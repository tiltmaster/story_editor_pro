import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import XCTest
@testable import story_editor_pro

final class PersonBackgroundTests: XCTestCase {
    private let context = CIContext(options: [.useSoftwareRenderer: true])

    func testDelayedOrFailedInferenceKeepsSceneButDoesNotAllowStaleCapture() {
        var cache = PersonBackgroundMaskCache()
        let size = CGSize(width: 100, height: 200)
        let mask = CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        cache.update(mask, sourceSize: size, capturedAt: 10)
        XCTAssertTrue(cache.isReady(now: 10.8))
        XCTAssertFalse(cache.isReady(now: 12))
        XCTAssertTrue(cache.current(sourceSize: size) === mask)
        cache.update(nil, sourceSize: size, capturedAt: 12)
        XCTAssertTrue(cache.current(sourceSize: size) === mask)
        XCTAssertFalse(cache.isReady(now: 12))
        cache.update(mask, sourceSize: size, capturedAt: 12)
        XCTAssertTrue(cache.isReady(now: 12.1))
        XCTAssertFalse(cache.isReady(now: 11.9))
        XCTAssertNil(cache.current(sourceSize: CGSize(width: 200, height: 100)))
        cache = PersonBackgroundMaskCache()
        XCTAssertNil(cache.current(sourceSize: size))
        XCTAssertFalse(cache.isReady(now: 12.1))
    }

    func testPhotographicSceneUsesCoverFramingAndPreservesPersonPixels() {
        let extent = CGRect(x: 10, y: 20, width: 100, height: 200)
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: extent)
        let scene = CIImage(color: CIColor(red: 0, green: 0, blue: 1))
            .cropped(to: CGRect(x: 30, y: 40, width: 300, height: 200))
        let backgroundMask = CIImage(color: .black).cropped(to: extent)
        let personMask = CIImage(color: .white).cropped(to: extent)
        for style in [2, 3, 5] {
            let replaced = PersonBackgroundCompositor.composite(source: source, mask: backgroundMask, style: style, scene: scene)
            XCTAssertEqual(replaced.extent, extent)
            XCTAssertEqual(pixel(replaced, x: 11, y: 21), [0, 0, 255, 255])
            XCTAssertEqual(pixel(replaced, x: 108, y: 218), [0, 0, 255, 255])
            let preserved = PersonBackgroundCompositor.composite(source: source, mask: personMask, style: style, scene: scene)
            XCTAssertEqual(pixel(preserved, x: 50, y: 100), [255, 0, 0, 255])
        }
    }

    private func pixel(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: 4,
                           bounds: CGRect(x: x, y: y, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        }
        return bytes
    }

    func testUnloadedCustomSceneNeverSubstitutesAnUnrelatedBackground() {
        let source = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 30))
        let mask = CIImage(color: .black).cropped(to: source.extent)
        XCTAssertTrue(PersonBackgroundCompositor.composite(source: source, mask: mask, style: 5) === source)
    }

    func testCustomMediaMirrorCompensationDoesNotMirrorThePersonMask() {
        let extent = CGRect(x: 0, y: 0, width: 20, height: 20)
        let source = CIImage(color: .green).cropped(to: extent)
        let scene = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 10, height: 20))
            .composited(over: CIImage(color: .blue).cropped(to: extent))
        let mask = CIImage(color: .black).cropped(to: extent)
        let result = PersonBackgroundCompositor.composite(source: source, mask: mask, style: 5, scene: scene, mirrorScene: true)
        XCTAssertEqual(pixel(result, x: 2, y: 10), [0, 0, 255, 255])
        XCTAssertEqual(pixel(result, x: 18, y: 10), [255, 0, 0, 255])
        let person = PersonBackgroundCompositor.composite(source: source, mask: CIImage(color: .white).cropped(to: extent), style: 5, scene: scene, mirrorScene: true)
        XCTAssertEqual(pixel(person, x: 2, y: 10), [0, 255, 0, 255])
    }

    func testBackgroundConfigurationDoesNotRequireFaceModelAndRejectsUnknownStyles() throws {
        let coordinator = FaceARCoordinator(modelPath: nil)
        XCTAssertEqual(coordinator.capabilities["backgrounds"] as? Bool, true)
        coordinator.setEnabled(true)
        for style in 0...4 {
            try coordinator.setLens(id: "none", intensity: 1, backgroundStyle: style)
            XCTAssertEqual(coordinator.runtimeState, style == 0 ? "ready" : "active")
            XCTAssertEqual(coordinator.hasActiveEffect, style != 0)
            XCTAssertFalse(coordinator.faceReady, "Background selection must not initialize face tracking")
            XCTAssertFalse(coordinator.backgroundReady, "Selection alone is not a real Vision mask")
        }
        XCTAssertThrowsError(try coordinator.setLens(id: "none", intensity: 1, backgroundStyle: -1))
        XCTAssertThrowsError(try coordinator.setLens(id: "none", intensity: 1, backgroundStyle: 5))
        coordinator.dispose()
    }

    func testOffReturnsCameraBufferWithoutRenderingOrPreparingVision() throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 32, 48, kCVPixelFormatType_32BGRA,
                                           nil, &buffer), kCVReturnSuccess)
        let input = try XCTUnwrap(buffer)
        let coordinator = FaceARCoordinator(modelPath: nil)
        coordinator.setEnabled(true)
        try coordinator.setLens(id: "none", intensity: 1, backgroundStyle: 0)
        XCTAssertTrue(coordinator.process(pixelBuffer: input, timestamp: .zero) === input)
        XCTAssertFalse(coordinator.faceReady)
        XCTAssertFalse(coordinator.backgroundReady)
    }

    func testMaskScalesFullCanvasWithoutMirroringOrCroppingTopLeftPerson() throws {
        // Vision produces a lower-resolution mask in the same upright image
        // coordinates. Nonzero extents exercise both normalization steps.
        let extent = CGRect(x: 100, y: 200, width: 40, height: 80)
        let maskExtent = CGRect(x: 9, y: 15, width: 10, height: 20)
        let black = CIImage(color: .black).cropped(to: maskExtent)
        let white = CIImage(color: .white).cropped(to: CGRect(x: 9, y: 25, width: 5, height: 10))
        let mask = white.composited(over: black)
        let source = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: extent)
        let result = PersonBackgroundCompositor.composite(source: source, mask: mask, style: 3)
        XCTAssertEqual(result.extent, extent)
        XCTAssertEqual(pixel(result, x: 105, y: 270), [0, 255, 0, 255])
        XCTAssertNotEqual(pixel(result, x: 135, y: 270), [0, 255, 0, 255])
        XCTAssertNotEqual(pixel(result, x: 105, y: 210), [0, 255, 0, 255])
        XCTAssertEqual(try XCTUnwrap(PersonBackgroundCompositor.alignedMask(mask, to: extent)).extent, extent)
    }

    func testEveryStylePreservesWhitePersonAndProducesDistinctRealBackgroundPixels() {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 200)
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: extent)
        let person = CIImage(color: .white).cropped(to: extent)
        let noPerson = CIImage(color: .black).cropped(to: extent)
        var backgrounds: Set<[UInt8]> = []
        for style in 1...4 {
            let preserved = PersonBackgroundCompositor.composite(source: source, mask: person, style: style)
            XCTAssertEqual(pixel(preserved, x: 50, y: 100), [255, 0, 0, 255])
            let replaced = PersonBackgroundCompositor.composite(source: source, mask: noPerson, style: style)
            backgrounds.insert(pixel(replaced, x: 50, y: 100))
        }
        XCTAssertEqual(backgrounds.count, 4)
        for style in [0, -1, 6] {
            XCTAssertEqual(pixel(PersonBackgroundCompositor.composite(source: source, mask: noPerson, style: style),
                                 x: 50, y: 100), [255, 0, 0, 255])
        }
    }

    func testGradientIsBrightAtTopAndCoversWholePortraitFrameWithoutAFace() throws {
        let extent = CGRect(x: 0, y: 0, width: 120, height: 240)
        let source = CIImage(color: .black).cropped(to: extent)
        let result = PersonBackgroundCompositor.composite(source: source, mask: source, style: 2)
        let top = pixel(result, x: 60, y: 225)
        let bottom = pixel(result, x: 60, y: 15)
        XCTAssertGreaterThan(top[0], bottom[0])
        XCTAssertGreaterThan(top[1], bottom[1])
        let output = try XCTUnwrap(CreativeLensFrameRenderer().render(source: result, lensId: "none",
            intensity: 1, lensContext: CreativeLensContext(), pose: nil))
        XCTAssertEqual(CVPixelBufferGetWidth(output), 120)
        XCTAssertEqual(CVPixelBufferGetHeight(output), 240)
        XCTAssertEqual(pixel(CIImage(cvPixelBuffer: output), x: 110, y: 10)[3], 255)
    }

    func testBlurChangesCameraBackgroundAndKeepsPersonSharp() throws {
        let extent = CGRect(x: 0, y: 0, width: 120, height: 200)
        let source = try XCTUnwrap(CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputWidth": 9, "inputSharpness": 1,
            "inputColor0": CIColor.black, "inputColor1": CIColor.white
        ])?.outputImage).cropped(to: extent)
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 200))
            .composited(over: CIImage(color: .black).cropped(to: extent))
        let result = PersonBackgroundCompositor.composite(source: source, mask: mask, style: 4)
        for y in [20, 35, 50, 65] {
            XCTAssertEqual(pixel(result, x: 15, y: y), pixel(source, x: 15, y: y))
            XCTAssertNotEqual(pixel(result, x: 90, y: y), pixel(source, x: 90, y: y))
        }
    }

    func testFinalPresentationMirrorMovesPersonAndMaskTogether() {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 200)
        let source = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: extent)
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 100, width: 40, height: 100))
            .composited(over: CIImage(color: .black).cropped(to: extent))
        let composed = PersonBackgroundCompositor.composite(source: source, mask: mask, style: 3)
        let mirrored = composed.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100, ty: 0))
        XCTAssertEqual(pixel(mirrored, x: 85, y: 170), [0, 255, 0, 255])
        XCTAssertNotEqual(pixel(mirrored, x: 15, y: 170), [0, 255, 0, 255])
        XCTAssertNotEqual(pixel(mirrored, x: 85, y: 30), [0, 255, 0, 255])
    }
}
