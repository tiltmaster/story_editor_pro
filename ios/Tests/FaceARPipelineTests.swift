import CoreGraphics
import Foundation
import XCTest
@testable import story_editor_pro

final class FaceARPipelineTests: XCTestCase {
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
            enabled: false, lensId: "glasses_classic", trackerAvailable: true
        ), .disabled)
        XCTAssertEqual(FaceARCoordinator.operationalState(
            enabled: true, lensId: "glasses_classic", trackerAvailable: false
        ), .preparing)
        XCTAssertEqual(FaceARCoordinator.operationalState(
            enabled: true, lensId: "none", trackerAvailable: true
        ), .ready)
        XCTAssertEqual(FaceARCoordinator.operationalState(
            enabled: true, lensId: "glasses_classic", trackerAvailable: true
        ), .active)
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
