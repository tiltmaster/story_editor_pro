import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Face features exposed to AR renderers.
enum FaceArLandmark {
  leftEye,
  rightEye,
  noseBase,
  leftEar,
  rightEar,
  leftMouth,
  rightMouth,
  bottomMouth,
  leftCheek,
  rightCheek,
}

/// Camera pixel formats accepted by the on-device detector.
enum FaceArPixelFormat { nv21, bgra8888 }

/// Ephemeral camera frame passed directly to the detector.
///
/// Consumers must not retain [bytes]. The pipeline owns at most the frame being
/// processed and one replaceable pending frame; neither is written or uploaded.
class FaceArFrame {
  const FaceArFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.rotationDegrees,
    required this.format,
    required this.timestamp,
    required this.mirrored,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int rotationDegrees;
  final FaceArPixelFormat format;
  final DateTime timestamp;
  final bool mirrored;
}

/// Detector-space result, expressed in unrotated source-image pixels.
class FaceArRawDetection {
  const FaceArRawDetection({
    required this.bounds,
    required this.landmarks,
    required this.yawDegrees,
    required this.pitchDegrees,
    required this.rollDegrees,
    required this.confidence,
    this.trackingId,
  });

  final int? trackingId;
  final Rect bounds;
  final Map<FaceArLandmark, Offset> landmarks;
  final double yawDegrees;
  final double pitchDegrees;
  final double rollDegrees;
  final double confidence;
}

/// A face transformed into displayed-preview coordinates.
///
/// Bounds and landmarks use normalized viewport coordinates. Rotation,
/// BoxFit.cover cropping and front-camera mirroring have already been applied.
class FaceArObservation {
  const FaceArObservation({
    required this.bounds,
    required this.landmarks,
    required this.yawRadians,
    required this.pitchRadians,
    required this.rollRadians,
    required this.interocularDistance,
    required this.confidence,
    required this.timestamp,
    required this.mirrored,
    this.trackingId,
  });

  final int? trackingId;
  final Rect bounds;
  final Map<FaceArLandmark, Offset> landmarks;
  final double yawRadians;
  final double pitchRadians;
  final double rollRadians;
  final double interocularDistance;
  final double confidence;
  final DateTime timestamp;
  final bool mirrored;
}

class FaceArTrackingState {
  const FaceArTrackingState({
    required this.observations,
    required this.faceLost,
    required this.timestamp,
  });

  final List<FaceArObservation> observations;
  final bool faceLost;
  final DateTime timestamp;

  FaceArObservation? get primary =>
      observations.isEmpty ? null : observations.first;
}
