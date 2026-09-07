import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import story_editor_pro

final class FaceExpressionTests: XCTestCase {
    private let neutral = FaceExpressionMetrics(mouthOpenRatio: 0.10, leftEyeOpenRatio: 0.26, rightEyeOpenRatio: 0.26)
    private let mouth = FaceExpressionMetrics(mouthOpenRatio: 0.30, leftEyeOpenRatio: 0.26, rightEyeOpenRatio: 0.26)
    private let wink = FaceExpressionMetrics(mouthOpenRatio: 0.10, leftEyeOpenRatio: 0.10, rightEyeOpenRatio: 0.26)

    func testLandmarkRatioUsesPixelsAndIsInvariantToRotation() throws {
        let size = CGSize(width: 100, height: 200)
        let first = CGPoint(x: 0.2, y: 0.5), second = CGPoint(x: 0.6, y: 0.5)
        let pairs = [(CGPoint(x: 0.3, y: 0.47), CGPoint(x: 0.3, y: 0.53)),
                     (CGPoint(x: 0.5, y: 0.475), CGPoint(x: 0.5, y: 0.525))]
        // Mean height 11 pixels / width 40 pixels. Normalized XY alone would
        // incorrectly halve this ratio and report ordinary eyes as closed.
        let ratio = try XCTUnwrap(FaceExpressionGeometry.ratio(widthFrom: first, widthTo: second,
                                                              heightPairs: pairs, imageSize: size))
        XCTAssertEqual(ratio, 0.275, accuracy: 0.000001)
        func rotate(_ point: CGPoint) -> CGPoint {
            let x = point.x * size.width, y = point.y * size.height
            let angle: CGFloat = 0.7
            return CGPoint(x: (x * cos(angle) - y * sin(angle)) / size.width,
                           y: (x * sin(angle) + y * cos(angle)) / size.height)
        }
        let rotated = try XCTUnwrap(FaceExpressionGeometry.ratio(widthFrom: rotate(first), widthTo: rotate(second),
            heightPairs: pairs.map { (rotate($0.0), rotate($0.1)) }, imageSize: size))
        XCTAssertEqual(rotated, ratio, accuracy: 0.000001)
    }

    func testVisionContourRatioUsesRolledEyeAxisAndRejectsAbsentRegions() throws {
        let size = CGSize(width: 100, height: 200)
        let region = [CGPoint(x: 0.2, y: 0.47), CGPoint(x: 0.6, y: 0.47),
                      CGPoint(x: 0.6, y: 0.53), CGPoint(x: 0.2, y: 0.53)]
        let first = CGPoint(x: 0.2, y: 0.5), second = CGPoint(x: 0.6, y: 0.5)
        func rotate(_ point: CGPoint) -> CGPoint {
            let x = point.x * size.width, y = point.y * size.height
            let angle: CGFloat = 0.8
            return CGPoint(x: (x * cos(angle) - y * sin(angle)) / size.width,
                           y: (x * sin(angle) + y * cos(angle)) / size.height)
        }
        let value = try XCTUnwrap(FaceExpressionGeometry.contourRatio(heightPoints: region.map(rotate), widthPoints: region.map(rotate),
            firstEye: rotate(first), secondEye: rotate(second), imageSize: size))
        XCTAssertEqual(value, 0.30, accuracy: 0.000001)
        XCTAssertNil(FaceExpressionGeometry.contourRatio(heightPoints: [], widthPoints: region,
            firstEye: first, secondEye: second, imageSize: size))
        XCTAssertNil(FaceExpressionGeometry.ratio(widthFrom: first, widthTo: first,
            heightPairs: [(first, second)], imageSize: size))
    }

    func testMissingInvalidOrBothClosedEyesCannotTriggerAWink() {
        for metrics in [FaceExpressionMetrics(),
                        FaceExpressionMetrics(leftEyeOpenRatio: .nan, rightEyeOpenRatio: 0.26),
                        FaceExpressionMetrics(leftEyeOpenRatio: -1, rightEyeOpenRatio: 0.26),
                        FaceExpressionMetrics(leftEyeOpenRatio: 0.10, rightEyeOpenRatio: 0.10)] {
            XCTAssertFalse(metrics.isWink)
            XCTAssertEqual(FaceExpressionReactions.still(metrics).butterflies, 0)
        }
        XCTAssertTrue(wink.isWink)
        XCTAssertTrue(FaceExpressionMetrics(leftEyeOpenRatio: 0.26, rightEyeOpenRatio: 0.13).isWink)
    }

    func testMouthTriggerHasHysteresisCooldownAndNoHeldOpenRetrigger() {
        var reactions = FaceExpressionReactions()
        XCTAssertEqual(reactions.sample(neutral, at: 0), .none)
        XCTAssertEqual(reactions.sample(mouth, at: 0.05).hearts, 0)
        XCTAssertGreaterThan(reactions.sample(mouth, at: 0.15).hearts, 0)
        _ = reactions.sample(neutral, at: 0.20)
        // A second rise during the refractory interval must not restart it.
        _ = reactions.sample(mouth, at: 0.25)
        for index in 3...9 { _ = reactions.sample(mouth, at: Double(index) / 10) }
        XCTAssertEqual(reactions.sample(mouth, at: 1.0).hearts, 0)
        _ = reactions.sample(neutral, at: 1.1)
        _ = reactions.sample(mouth, at: 1.2)
        XCTAssertGreaterThan(reactions.sample(mouth, at: 1.3).hearts, 0)
        XCTAssertEqual(reactions.sample(nil, at: 1.4), .none)
        XCTAssertEqual(reactions.sample(neutral, at: 1.5), .none)
    }

    func testWinkRequiresReopeningAndNoFaceClearsTheReaction() {
        var reactions = FaceExpressionReactions()
        _ = reactions.sample(neutral, at: 0)
        _ = reactions.sample(wink, at: 0.1)
        XCTAssertGreaterThan(reactions.sample(wink, at: 0.2).butterflies, 0)
        for index in 3...9 { _ = reactions.sample(wink, at: Double(index) / 10) }
        XCTAssertEqual(reactions.sample(wink, at: 1.0).butterflies, 0)
        _ = reactions.sample(neutral, at: 1.1)
        _ = reactions.sample(wink, at: 1.2)
        XCTAssertGreaterThan(reactions.sample(wink, at: 1.3).butterflies, 0)
        XCTAssertEqual(reactions.sample(nil, at: 1.4), .none)
    }

    func testRawExpressionsSurvivePoseSmoothingAndPhotosUseFreshExpression() {
        let previous = FaceARPose(center: .zero, eyeDistance: 0.3, rollRadians: 0, expressions: neutral)
        let next = FaceARPose(center: CGPoint(x: 0.5, y: 0.5), eyeDistance: 0.4, rollRadians: 0.1, expressions: wink)
        XCTAssertEqual(previous.smoothed(toward: next, alpha: 0.1).expressions, wink)
        XCTAssertEqual(FaceExpressionReactions.still(mouth), FaceExpressionReaction(hearts: 1, butterflies: 0))
        XCTAssertEqual(FaceExpressionReactions.still(wink), FaceExpressionReaction(hearts: 0, butterflies: 1))
        XCTAssertEqual(FaceExpressionReactions.still(neutral), .none)
    }

    func testActualExpressionChangesArtworkAtTheSameFrameTime() throws {
        let extent = CGRect(x: 0, y: 0, width: 360, height: 640)
        let source = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(to: extent)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        func pixels(_ image: CIImage) throws -> Data {
            let result = try XCTUnwrap(context.createCGImage(image, from: extent))
            return try XCTUnwrap(result.dataProvider?.data) as Data
        }
        func pose(_ metrics: FaceExpressionMetrics) -> FaceARPose {
            FaceARPose(center: CGPoint(x: 0.5, y: 0.52), eyeDistance: 0.25, rollRadians: 0, expressions: metrics)
        }
        for (lens, expression) in [("face_hearts", mouth), ("face_butterflies", wink)] {
            let neutralRenderer = FaceAdornmentCompositor(), activeRenderer = FaceAdornmentCompositor()
            _ = neutralRenderer.composite(over: source, pose: pose(neutral), lensId: lens, time: 0, intensity: 1)
            _ = activeRenderer.composite(over: source, pose: pose(expression), lensId: lens, time: 0, intensity: 1)
            let baseline = neutralRenderer.composite(over: source, pose: pose(neutral), lensId: lens, time: 0.25, intensity: 1)
            let reaction = activeRenderer.composite(over: source, pose: pose(expression), lensId: lens, time: 0.25, intensity: 1)
            XCTAssertNotEqual(try pixels(reaction), try pixels(baseline), "Real landmarks must change the effect: \(lens)")
            let stillNeutral = neutralRenderer.composite(over: source, pose: pose(neutral), lensId: lens, time: 1, intensity: 1, isPhoto: true)
            let stillActive = activeRenderer.composite(over: source, pose: pose(expression), lensId: lens, time: 1, intensity: 1, isPhoto: true)
            XCTAssertNotEqual(try pixels(stillActive), try pixels(stillNeutral))
        }
    }
}
