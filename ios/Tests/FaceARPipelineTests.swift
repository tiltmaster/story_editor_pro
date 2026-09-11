import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import XCTest
@testable import story_editor_pro

final class FaceARPipelineTests: XCTestCase {
    func testTrackedArtworkChangesActualPixelsAndAnimates() throws {
        let extent = CGRect(x: 0, y: 0, width: 360, height: 640)
        let source = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(to: extent)
        let compositor = FaceAdornmentCompositor()
        let contour = (0..<36).map { index -> CGPoint in
            let angle = CGFloat(index) * .pi * 2 / 36
            return CGPoint(x: 0.5 + cos(angle) * 0.28, y: 0.52 + sin(angle) * 0.21)
        }
        let pose = FaceARPose(center: CGPoint(x: 0.5, y: 0.55), eyeDistance: 0.25, rollRadians: 0, contour: contour)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        func pixels(_ image: CIImage) throws -> Data {
            let result = try XCTUnwrap(context.createCGImage(image, from: extent))
            return try XCTUnwrap(result.dataProvider?.data) as Data
        }
        let baseline = try pixels(source)
        for lens in CreativeLensFrameRenderer.adornmentIds {
            let first = compositor.composite(over: source, pose: pose, lensId: lens, time: 0, intensity: 1)
            XCTAssertNotEqual(try pixels(first), baseline, "Artwork must change camera pixels: \(lens)")
            if lens != "face_freckles" {
                let next = compositor.composite(over: source, pose: pose, lensId: lens, time: 1, intensity: 1)
                XCTAssertNotEqual(try pixels(first), try pixels(next), "Animation must change frames: \(lens)")
            }
        }
    }

    func testNeonRequiresDetectedContourAndFollowsItsShape() throws {
        let extent = CGRect(x: 0, y: 0, width: 360, height: 640)
        let source = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(to: extent)
        let compositor = FaceAdornmentCompositor()
        let context = CIContext(options: [.useSoftwareRenderer: true])
        func pixels(_ image: CIImage) throws -> Data {
            let result = try XCTUnwrap(context.createCGImage(image, from: extent))
            return try XCTUnwrap(result.dataProvider?.data) as Data
        }
        let absent = FaceARPose(center: CGPoint(x: 0.5, y: 0.55), eyeDistance: 0.25, rollRadians: 0)
        let baseline = try pixels(source)
        XCTAssertEqual(try pixels(compositor.composite(over: source, pose: absent, lensId: "face_neon", time: 0, intensity: 1)), baseline)
        func jaw(width: CGFloat) -> [CGPoint] {
            (0..<17).map { index in
                let angle = CGFloat(index) * .pi / 16
                return CGPoint(x: 0.5 + cos(angle) * width, y: 0.58 - sin(angle) * 0.21)
            }
        }
        let narrow = FaceARPose(center: absent.center, eyeDistance: absent.eyeDistance, rollRadians: 0,
                                contour: jaw(width: 0.2), contourClosed: false)
        let wide = FaceARPose(center: absent.center, eyeDistance: absent.eyeDistance, rollRadians: 0,
                              contour: jaw(width: 0.3), contourClosed: false)
        let narrowPixels = try pixels(compositor.composite(over: source, pose: narrow, lensId: "face_neon", time: 0, intensity: 1))
        let widePixels = try pixels(compositor.composite(over: source, pose: wide, lensId: "face_neon", time: 0, intensity: 1))
        XCTAssertNotEqual(narrowPixels, baseline)
        XCTAssertNotEqual(narrowPixels, widePixels)
        let smoothed = narrow.smoothed(toward: wide, alpha: 0.5)
        XCTAssertEqual(smoothed.contour[0].x, 0.75, accuracy: 0.000001)
        XCTAssertFalse(smoothed.contourClosed)
    }

    func testStackKeepsFaceArtworkAndLocationIndependent() throws {
        let coordinator = FaceARCoordinator(modelPath: nil)
        for id in CreativeLensFrameRenderer.adornmentIds {
            XCTAssertNoThrow(try coordinator.setLens(id: id, intensity: 0.8,
                compositionId: "daytime", placeStyle: "postcard", placeName: "Kyoto"))
        }
        XCTAssertThrowsError(try coordinator.setLens(id: "none", intensity: .nan))
        XCTAssertThrowsError(try coordinator.setLens(id: "none", intensity: 1, placeStyle: "unknown"))
        XCTAssertFalse(CreativeLensContext(countryCode: "KW", placeStyle: "postcard").hasOverlay)
        XCTAssertTrue(CreativeLensContext(placeStyle: "postcard", placeName: "Kyoto").hasOverlay)
    }

    func testLocationOnlyBecomesActiveWithoutFacePreparation() throws {
        let coordinator = FaceARCoordinator(modelPath: nil)
        try coordinator.setLens(id: "none", intensity: 1, placeStyle: "editorial", placeName: "Paris")
        coordinator.setEnabled(true)
        XCTAssertTrue(coordinator.hasActiveEffect)
        XCTAssertFalse(coordinator.faceReady)
    }

    func testNativeSessionReuseRequiresAnActiveSameFacingSession() {
        XCTAssertTrue(NativeCameraSessionReuseContract.shouldReuse(
            isActive: true,
            existingFacing: "front",
            requestedFacing: "front"
        ))
        XCTAssertTrue(NativeCameraSessionReuseContract.shouldReuse(
            isActive: true,
            existingFacing: "back",
            requestedFacing: "back"
        ))
        XCTAssertFalse(NativeCameraSessionReuseContract.shouldReuse(
            isActive: false,
            existingFacing: "front",
            requestedFacing: "front"
        ))
        XCTAssertFalse(NativeCameraSessionReuseContract.shouldReuse(
            isActive: true,
            existingFacing: "front",
            requestedFacing: "back"
        ))
    }

    func testPoseSmoothingMovesWithoutOvershoot() {
        let previous = FaceARPose(
            center: CGPoint(x: 0.2, y: 0.4),
            eyeDistance: 0.1,
            rollRadians: 0,
            yawNormalized: -0.4
        )
        let next = FaceARPose(
            center: CGPoint(x: 0.8, y: 0.6),
            eyeDistance: 0.3,
            rollRadians: .pi / 2,
            yawNormalized: 0.4
        )
        let result = previous.smoothed(toward: next, alpha: 0.25)
        XCTAssertEqual(result.center.x, 0.35, accuracy: 0.0001)
        XCTAssertEqual(result.center.y, 0.45, accuracy: 0.0001)
        XCTAssertEqual(result.eyeDistance, 0.15, accuracy: 0.0001)
        XCTAssertEqual(result.rollRadians, .pi / 8, accuracy: 0.0001)
        XCTAssertEqual(result.yawNormalized, -0.2, accuracy: 0.0001)
    }

    func testPoseGeometryIsStableWhenDetectorEyeLabelsReverse() {
        let left = CGPoint(x: 0.25, y: 0.40)
        let right = CGPoint(x: 0.75, y: 0.48)
        let nose = CGPoint(x: 0.53, y: 0.60)
        let forward = FaceARPoseGeometry.make(firstEye: left, secondEye: right, nose: nose)
        let reversed = FaceARPoseGeometry.make(firstEye: right, secondEye: left, nose: nose)

        XCTAssertNotNil(forward)
        XCTAssertEqual(forward, reversed)
        XCTAssertLessThan(abs(forward!.rollRadians), .pi / 2)
    }

    func testPoseGeometryProjectsYawAlongRolledEyeAxis() {
        let pose = FaceARPoseGeometry.make(
            firstEye: CGPoint(x: 0.30, y: 0.35),
            secondEye: CGPoint(x: 0.70, y: 0.55),
            nose: CGPoint(x: 0.54, y: 0.56)
        )

        XCTAssertNotNil(pose)
        XCTAssertGreaterThan(pose!.yawNormalized, 0)
        XCTAssertLessThanOrEqual(abs(pose!.yawNormalized), 1)
    }

    func testPoseSmoothingUsesShortestAngleAcrossPiBoundary() {
        let previous = FaceARPose(center: .zero, eyeDistance: 0.1, rollRadians: .pi - 0.1)
        let next = FaceARPose(center: .zero, eyeDistance: 0.1, rollRadians: -.pi + 0.1)
        let result = previous.smoothed(toward: next, alpha: 0.5)
        XCTAssertEqual(abs(result.rollRadians), .pi, accuracy: 0.0001)
    }

    func testPoseSmoothingClampsAlpha() {
        let previous = FaceARPose(center: .zero, eyeDistance: 0.1, rollRadians: 0, yawNormalized: -0.5)
        let next = FaceARPose(center: CGPoint(x: 1, y: 1), eyeDistance: 0.3,
                              rollRadians: 1, yawNormalized: 0.5)
        XCTAssertEqual(previous.smoothed(toward: next, alpha: -2), previous)
        XCTAssertEqual(previous.smoothed(toward: next, alpha: 2), next)
    }

    func testOperationalStateContract() {
        XCTAssertEqual(FaceARCoordinator.operationalState(
            enabled: false, lensId: "face_neon", trackerAvailable: true
        ), .disabled)
        XCTAssertEqual(FaceARCoordinator.operationalState(
            enabled: true, lensId: "face_neon", trackerAvailable: false
        ), .preparing)
        XCTAssertEqual(FaceARCoordinator.operationalState(
            enabled: true, lensId: "none", trackerAvailable: true
        ), .ready)
        XCTAssertEqual(FaceARCoordinator.operationalState(
            enabled: true, lensId: "face_neon", trackerAvailable: true
        ), .active)
    }

    func testAllAuthoredLensIdentifiersAreAcceptedAndAdvertised() throws {
        let coordinator = FaceARCoordinator(modelPath: nil)
        for lensId in CreativeLensFrameRenderer.adornmentIds {
            XCTAssertNoThrow(try coordinator.setLens(id: lensId, intensity: 1))
        }
        XCTAssertThrowsError(try coordinator.setLens(id: "glasses_classic", intensity: 1))
        for lensId in CreativeLensFrameRenderer.lensIds {
            XCTAssertNoThrow(try coordinator.setLens(id: lensId, intensity: 1))
        }
        XCTAssertThrowsError(try coordinator.setLens(id: "fake_color_preset", intensity: 1))
        XCTAssertEqual(
            coordinator.capabilities["lensIds"] as? [String],
            Array(CreativeLensFrameRenderer.lensIds.union(CreativeLensFrameRenderer.adornmentIds)).sorted()
        )
    }

    func testEyeCentersAreBetweenCornersRatherThanAtTemples() throws {
        let left = FaceARPoseGeometry.eyeCenter(outer: CGPoint(x: 0.2, y: 0.6), inner: CGPoint(x: 0.4, y: 0.62))
        let right = FaceARPoseGeometry.eyeCenter(outer: CGPoint(x: 0.8, y: 0.58), inner: CGPoint(x: 0.6, y: 0.6))
        let pose = try XCTUnwrap(FaceARPoseGeometry.make(firstEye: left, secondEye: right, nose: nil))
        XCTAssertEqual(left.x, 0.3, accuracy: 0.000001)
        XCTAssertEqual(right.x, 0.7, accuracy: 0.000001)
        XCTAssertEqual(pose.eyeDistance, hypot(0.4, 0.02), accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(pose.normalizedTopLeftEyes["leftY"]), 0.39, accuracy: 0.000001)
    }

    func testEyeEventsUseUprightUnmirroredTopLeftCoordinates() throws {
        let pose = try XCTUnwrap(FaceARPoseGeometry.make(
            firstEye: CGPoint(x: 0.25, y: 0.6), secondEye: CGPoint(x: 0.75, y: 0.4), nose: nil))
        let points = pose.normalizedTopLeftEyes
        XCTAssertEqual(try XCTUnwrap(points["leftX"]), 0.25, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(points["leftY"]), 0.4, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(points["rightX"]), 0.75, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(points["rightY"]), 0.6, accuracy: 0.000001)
        let axis = pose.pixelEyeAxis(in: CGSize(width: 360, height: 640))
        XCTAssertEqual(axis.x, 180, accuracy: 0.000001)
        XCTAssertEqual(axis.y, -128, accuracy: 0.000001)
    }

    func testBeautyTrackingSettingsRejectNonfiniteValuesAndAllowNoLens() {
        let coordinator = FaceARCoordinator(modelPath: nil)
        XCTAssertNoThrow(try coordinator.setLens(id: "none", intensity: 1, beautyEyes: 0.4, beautySlim: 0.5))
        XCTAssertThrowsError(try coordinator.setLens(id: "none", intensity: 1, beautyEyes: .infinity))
        XCTAssertThrowsError(try coordinator.setLens(id: "none", intensity: 1, beautySlim: .nan))
    }

    func testLocationMirroringCompensatesOnlyForFinalTextureFlip() throws {
        let extent = CGRect(x: 0, y: 0, width: 360, height: 640)
        let source = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(to: extent)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        func pixels(_ image: CIImage) throws -> Data {
            let result = try XCTUnwrap(context.createCGImage(image, from: extent))
            return try XCTUnwrap(result.dataProvider?.data) as Data
        }
        let artwork = UIGraphicsImageRenderer(size: CGSize(width: 340, height: 410)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0,y: 0,width: 340,height: 410))
            UIColor.red.setFill(); ctx.fill(CGRect(x: 20,y: 20,width: 80,height: 180))
            ("الكويت" as NSString).draw(at: CGPoint(x: 30,y: 250), withAttributes: [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.black])
        }
        for style in ["postcard", "editorial", "stamp"] {
          for angle in [CGFloat(0), CGFloat(0.45), CGFloat(-0.8)] {
            let renderer = CreativeLensFrameRenderer()
            let normal = try XCTUnwrap(renderer.render(source: source, lensId: "none", intensity: 1,
                lensContext: CreativeLensContext(languageCode: "ar", placeStyle: style, placeName: "الكويت", placeX: 0.3, placeY: 0.6, placeRotation: angle, placeArtwork: artwork)))
            let mirrored = try XCTUnwrap(renderer.render(source: source, lensId: "none", intensity: 1,
                lensContext: CreativeLensContext(languageCode: "ar", mirrorOutput: true, placeStyle: style, placeName: "الكويت", placeX: 0.3, placeY: 0.6, placeRotation: angle, placeArtwork: artwork)))
            XCTAssertEqual(CVPixelBufferGetWidth(normal), 360)
            XCTAssertEqual(CVPixelBufferGetHeight(normal), 640)
            let restored = CIImage(cvPixelBuffer: mirrored).transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 360, ty: 0))
            // Rasterizing text under a mirrored CGContext can round glyph edges
            // differently. Compare with a tiny tolerance using actual pixels.
            let normalBytes = Array(try pixels(CIImage(cvPixelBuffer: normal)))
            XCTAssertNotEqual(normalBytes, Array(try pixels(source)), "Native artwork must be present")
            if angle != 0 {
                let upright = try XCTUnwrap(renderer.render(source: source, lensId: "none", intensity: 1,
                    lensContext: CreativeLensContext(languageCode: "ar", placeStyle: style, placeName: "الكويت",
                        placeX: 0.3, placeY: 0.6, placeArtwork: artwork)))
                XCTAssertNotEqual(normalBytes, Array(try pixels(CIImage(cvPixelBuffer: upright))),
                    "Rotation must change native pixels, not just the Flutter hit target")
            }
            let moved = try XCTUnwrap(renderer.render(source: source, lensId: "none", intensity: 1,
                lensContext: CreativeLensContext(placeStyle: style, placeName: "الكويت",
                    placeX: 0.65, placeY: 0.4, placeScale: 0.8, placeArtwork: artwork)))
            XCTAssertNotEqual(normalBytes, Array(try pixels(CIImage(cvPixelBuffer: moved))),
                "Position and scale changes must update pixels without regenerating artwork")

            let restoredBytes = Array(try pixels(restored))
            XCTAssertEqual(normalBytes.count, restoredBytes.count)
            let difference = zip(normalBytes, restoredBytes).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            XCTAssertLessThan(Double(difference) / Double(normalBytes.count), 1.0)
          }
        }
    }

    func testFaceOnlyLensWithoutFacePreservesInputPixels() throws {
        let extent = CGRect(x: 0, y: 0, width: 360, height: 640)
        let source = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(to: extent)
        let renderer = CreativeLensFrameRenderer()
        let input = try XCTUnwrap(renderer.render(source: source, lensId: "none", intensity: 1,
                                                 lensContext: CreativeLensContext()))
        for lens in CreativeLensFrameRenderer.adornmentIds {
            let output = try XCTUnwrap(renderer.render(input: input, lensId: lens, intensity: 1,
                                                      lensContext: CreativeLensContext(), pose: nil))
            XCTAssertTrue(output === input)
        }
    }

    func testPoseTimelineUsesAbsoluteSourceTimeAndClearsLostOrStaleFaces() throws {
        let eye: [String: Any] = ["timeMs": 2000, "leftX": 0.3, "leftY": 0.4, "rightX": 0.7, "rightY": 0.4]
        let timeline = FacePoseTimeline([eye, ["timeMs": 2150]])
        XCTAssertNil(timeline.eyes(at: 0))
        XCTAssertNil(timeline.eyes(at: 1999))
        XCTAssertEqual(try XCTUnwrap(timeline.eyes(at: 2100)).x, 0.3, accuracy: 0.000001)
        XCTAssertNil(timeline.eyes(at: 2150))
        let stale = FacePoseTimeline([eye])
        XCTAssertNotNil(stale.eyes(at: 2250))
        XCTAssertNil(stale.eyes(at: 2251))
        XCTAssertNil(stale.eyes(at: .nan))
        // Last input entry wins at equal timestamps, including a loss marker.
        XCTAssertNil(FacePoseTimeline([eye, ["timeMs": 2000]]).eyes(at: 2000))
        XCTAssertNotNil(FacePoseTimeline([["timeMs": 2000], eye]).eyes(at: 2000))
    }

    func testFaceWarpChangesEyeAndJawPixelsAndZeroControlsPassThrough() throws {
        let extent = CGRect(x: 0, y: 0, width: 360, height: 640)
        let source = try XCTUnwrap(CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputWidth": 11, "inputSharpness": 1,
            "inputColor0": CIColor(red: 0.15, green: 0.2, blue: 0.25),
            "inputColor1": CIColor(red: 0.8, green: 0.75, blue: 0.7)
        ])?.outputImage).cropped(to: extent)
        let processor = VideoOverlayProcessor()
        let eyes = CIVector(x: 0.32, y: 0.35, z: 0.68, w: 0.36)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        func pixels(_ image: CIImage) throws -> Data {
            let result = try XCTUnwrap(context.createCGImage(image, from: extent))
            return try XCTUnwrap(result.dataProvider?.data) as Data
        }
        let baseline = try pixels(source)
        let neutral = try XCTUnwrap(processor.applyFaceWarp(to: source, eyes: eyes, eyeAmount: 0, slimAmount: 0))
        XCTAssertEqual(try pixels(neutral), baseline)
        let eyeResult = try XCTUnwrap(processor.applyFaceWarp(to: source, eyes: eyes, eyeAmount: 1, slimAmount: 0))
        let jawResult = try XCTUnwrap(processor.applyFaceWarp(to: source, eyes: eyes, eyeAmount: 0, slimAmount: 1))
        XCTAssertNotEqual(try pixels(eyeResult), baseline)
        XCTAssertNotEqual(try pixels(jawResult), baseline)
        XCTAssertNotEqual(try pixels(eyeResult), try pixels(jawResult))
    }

    func testPhotoExifOrientationDeterminesFullFrameCanvas() throws {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 640, height: 360))
        let input = try XCTUnwrap(CreativeLensFrameRenderer().render(source: source,
            lensId: "none", intensity: 1, lensContext: CreativeLensContext()))
        let coordinator = FaceARCoordinator(modelPath: nil)
        try coordinator.setLens(id: "none", intensity: 1, placeStyle: "editorial", placeName: "Paris")
        coordinator.setEnabled(true)
        let photo = try XCTUnwrap(coordinator.processPhoto(pixelBuffer: input, metadata: ["Orientation": 6]))
        XCTAssertEqual(CVPixelBufferGetWidth(photo), 360)
        XCTAssertEqual(CVPixelBufferGetHeight(photo), 640)
    }

    func testRecorderReportsFirstFrameTimestampExactlyOnce() throws {
        let recorder = FaceARVideoRecorder()
        let path = NSTemporaryDirectory() + UUID().uuidString + ".mp4"
        defer { recorder.cancel(); try? FileManager.default.removeItem(atPath: path) }
        var timestamps: [CMTime] = []
        let error = recorder.start(outputPath: path, width: 320, height: 240, onStarted: { timestamps.append($0) })
        XCTAssertNil(error)
        var rawBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        XCTAssertEqual(CVPixelBufferCreate(nil, 320, 240, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &rawBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(rawBuffer)
        let first = CMTime(value: 1234567, timescale: 1000)
        recorder.appendVideo(pixelBuffer: buffer, presentationTime: first)
        recorder.appendVideo(pixelBuffer: buffer, presentationTime: CMTimeAdd(first, CMTime(value: 1, timescale: 30)))
        XCTAssertEqual(timestamps.count, 1)
        XCTAssertEqual(timestamps.first, first)
    }

    func testFocusPointRemovesVisibleCropBeforeSensorRotation() throws {
        let point = CGPoint(x: 0.25, y: 0.75)
        let portrait = try XCTUnwrap(NativeCameraControlGeometry.focusPoint(point,
            sourceSize: CGSize(width: 1080, height: 1920), orientation: .portrait))
        XCTAssertEqual(portrait.x, 0.75, accuracy: 0.000001)
        XCTAssertEqual(portrait.y, 0.75, accuracy: 0.000001)
        let cropped = try XCTUnwrap(NativeCameraControlGeometry.focusPoint(point,
            sourceSize: CGSize(width: 1080, height: 1440), orientation: .portrait))
        XCTAssertEqual(cropped.x, 0.75, accuracy: 0.000001)
        XCTAssertEqual(cropped.y, 0.6875, accuracy: 0.000001)
        let inverted = try XCTUnwrap(NativeCameraControlGeometry.focusPoint(point,
            sourceSize: CGSize(width: 1080, height: 1440), orientation: .portraitUpsideDown))
        XCTAssertEqual(inverted.x, 0.25, accuracy: 0.000001)
        XCTAssertEqual(inverted.y, 0.3125, accuracy: 0.000001)
        let landscape = try XCTUnwrap(NativeCameraControlGeometry.focusPoint(CGPoint(x: 0, y: 0.25),
            sourceSize: CGSize(width: 1920, height: 1080), orientation: .landscapeRight))
        XCTAssertEqual(landscape.x, (1 - (9.0 / 16) / (16.0 / 9)) / 2, accuracy: 0.000001)
        XCTAssertEqual(landscape.y, 0.25, accuracy: 0.000001)
        let opposite = try XCTUnwrap(NativeCameraControlGeometry.focusPoint(CGPoint(x: 0, y: 0.25),
            sourceSize: CGSize(width: 1920, height: 1080), orientation: .landscapeLeft))
        XCTAssertEqual(opposite.x, 1 - landscape.x, accuracy: 0.000001)
        XCTAssertEqual(opposite.y, 0.75, accuracy: 0.000001)
    }

    func testCameraControlsRejectNonfiniteInputsAndUseReportedDeviceBounds() {
        XCTAssertNil(NativeCameraControlGeometry.focusPoint(CGPoint(x: CGFloat.nan, y: 0), sourceSize: CGSize(width: 1080, height: 1920), orientation: .portrait))
        XCTAssertNil(NativeCameraControlGeometry.focusPoint(.zero, sourceSize: .zero, orientation: .portrait))
        XCTAssertNil(NativeCameraControlGeometry.bounded(.infinity, minimum: -3, maximum: 3))
        XCTAssertEqual(NativeCameraControlGeometry.bounded(20, minimum: 1, maximum: 8), 8)
        XCTAssertEqual(NativeCameraControlGeometry.bounded(-1, minimum: 0.5, maximum: 8), 0.5)
        XCTAssertEqual(NativeCameraControlGeometry.bounded(-4, minimum: -2, maximum: 3), -2)
        XCTAssertEqual(NativeCameraControlGeometry.bounded(1.25, minimum: -2, maximum: 3), 1.25)
    }

    func testMediaTransformMatchesCenteredScaleThenScreenTranslation() throws {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 100)
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let transformed = VideoOverlayProcessor.applyMediaTransform(to: source, extent: extent,
                                                                   scale: 0.5, offsetX: 0.1, offsetY: 0.2)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        func pixel(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes.withUnsafeMutableBytes { buffer in
                context.render(image, toBitmap: buffer.baseAddress!, rowBytes: 4,
                               bounds: CGRect(x: x, y: y, width: 1, height: 1),
                               format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            }
            return bytes
        }
        // Half-size image is x35...85, y5...55 in Core Image coordinates;
        // positive editor Y moves it down, not up.
        XCTAssertEqual(pixel(transformed, x: 50, y: 20), [255, 0, 0, 255])
        XCTAssertEqual(pixel(transformed, x: 20, y: 20), [0, 0, 0, 255])
        XCTAssertEqual(pixel(transformed, x: 50, y: 80), [0, 0, 0, 255])
        let neutral = VideoOverlayProcessor.applyMediaTransform(to: source, extent: extent,
                                                               scale: .nan, offsetX: .infinity, offsetY: .nan)
        XCTAssertEqual(pixel(neutral, x: 50, y: 50), [255, 0, 0, 255])
    }

    func testRecordingEncodingContract() {
        XCTAssertEqual(FaceARRecordingContract.framesPerSecond, 30)
        XCTAssertEqual(FaceARRecordingContract.audioSampleRate, 44_100)
        XCTAssertEqual(FaceARRecordingContract.audioChannelCount, 1)
        XCTAssertEqual(FaceARRecordingContract.audioBitRate, 96_000)
        XCTAssertEqual(FaceARRecordingContract.videoBitRate(width: 320, height: 240), 2_500_000)
        XCTAssertEqual(FaceARRecordingContract.videoBitRate(width: 1_920, height: 1_080), 10_000_000)
        XCTAssertTrue(FaceARRecordingContract.dimensionsAreValid(width: 1_080, height: 1_920))
        XCTAssertFalse(FaceARRecordingContract.dimensionsAreValid(width: 0, height: 1_920))
        XCTAssertFalse(FaceARRecordingContract.dimensionsAreValid(width: 1_081, height: 1_920))
    }

    func testRecorderRejectsInvalidDimensionsWithoutArming() {
        let recorder = FaceARVideoRecorder()
        let error = recorder.start(outputPath: NSTemporaryDirectory() + "invalid.mp4", width: 0, height: 1_080)
        XCTAssertEqual((error as? NSError)?.code, 7)
        XCTAssertFalse(recorder.isRecording)
    }

    func testStoppingIdleRecorderReturnsContractError() {
        let recorder = FaceARVideoRecorder()
        var returnedError: Error?
        recorder.stop { _, error in returnedError = error }
        XCTAssertEqual((returnedError as? NSError)?.code, 3)
        XCTAssertFalse(recorder.isRecording)
    }
}
