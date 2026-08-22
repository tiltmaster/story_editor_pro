import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'face_ar_models.dart';

/// Stable, viewport-normalized pose consumed by the glasses renderers.
@immutable
class GlassesPose {
  const GlassesPose({
    required this.center,
    required this.interocularDistance,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.opacity,
    required this.timestamp,
    required this.mirrored,
  });

  final Offset center;
  final double interocularDistance;
  final double yaw;
  final double pitch;
  final double roll;
  final double opacity;
  final DateTime timestamp;

  /// Whether the displayed preview is mirrored. Live rendering must not mirror
  /// again; capture compositing uses this to map back to the camera file.
  final bool mirrored;

  GlassesPose copyWith({
    Offset? center,
    double? interocularDistance,
    double? yaw,
    double? pitch,
    double? roll,
    double? opacity,
    DateTime? timestamp,
    bool? mirrored,
  }) => GlassesPose(
    center: center ?? this.center,
    interocularDistance: interocularDistance ?? this.interocularDistance,
    yaw: yaw ?? this.yaw,
    pitch: pitch ?? this.pitch,
    roll: roll ?? this.roll,
    opacity: opacity ?? this.opacity,
    timestamp: timestamp ?? this.timestamp,
    mirrored: mirrored ?? this.mirrored,
  );
}

/// Adaptive low-pass tracker with short velocity prediction and loss
/// hysteresis. It intentionally contains no timers, making camera lifecycle
/// ownership explicit and its behavior deterministic in tests.
class GlassesPoseTracker {
  GlassesPoseTracker({
    this.minimumConfidence = 0.55,
    this.holdDuration = const Duration(milliseconds: 150),
    this.fadeDuration = const Duration(milliseconds: 180),
    this.maximumPrediction = const Duration(milliseconds: 34),
  });

  final double minimumConfidence;
  final Duration holdDuration;
  final Duration fadeDuration;
  final Duration maximumPrediction;

  GlassesPose? _pose;
  Offset _centerVelocity = Offset.zero;
  double _scaleVelocity = 0;
  DateTime? _lastMeasurementAt;
  int? _trackingId;

  GlassesPose? get lastPose => _pose;

  void reset() {
    _pose = null;
    _centerVelocity = Offset.zero;
    _scaleVelocity = 0;
    _lastMeasurementAt = null;
    _trackingId = null;
  }

  /// Ingests a detector observation. Null/low-confidence measurements are
  /// handled by [poseAt], which holds briefly before fading instead of popping.
  GlassesPose? update(FaceArObservation? observation, DateTime now) {
    if (observation == null ||
        observation.confidence < minimumConfidence ||
        observation.interocularDistance <= 0.01) {
      return poseAt(now);
    }

    final left = observation.landmarks[FaceArLandmark.leftEye];
    final right = observation.landmarks[FaceArLandmark.rightEye];
    final measuredCenter = left != null && right != null
        ? Offset((left.dx + right.dx) / 2, (left.dy + right.dy) / 2)
        : observation.bounds.center;
    final measured = GlassesPose(
      center: measuredCenter,
      interocularDistance: observation.interocularDistance,
      yaw: observation.yawRadians.clamp(-1.25, 1.25),
      pitch: observation.pitchRadians.clamp(-0.9, 0.9),
      roll: _wrapAngle(observation.rollRadians),
      opacity: 1,
      timestamp: now,
      mirrored: observation.mirrored,
    );

    final previous = _pose;
    final previousAt = _lastMeasurementAt;
    final identityChanged =
        previous != null &&
        observation.trackingId != null &&
        _trackingId != null &&
        observation.trackingId != _trackingId;
    final largeJump =
        previous != null &&
        (previous.center - measured.center).distance >
            math.max(0.16, previous.interocularDistance * 1.3);
    if (previous == null ||
        previousAt == null ||
        identityChanged ||
        largeJump) {
      _pose = measured;
      _centerVelocity = Offset.zero;
      _scaleVelocity = 0;
    } else {
      final elapsedSeconds = math.max(
        1 / 120,
        now.difference(previousAt).inMicroseconds /
            Duration.microsecondsPerSecond,
      );
      final motion =
          (previous.center - measured.center).distance /
          math.max(previous.interocularDistance, 0.03);
      final confidence = observation.confidence.clamp(0.0, 1.0);
      final centerAlpha = (0.30 + motion * 0.24 + confidence * 0.16).clamp(
        0.28,
        0.78,
      );
      final scaleAlpha = (0.24 + motion * 0.12 + confidence * 0.12).clamp(
        0.24,
        0.62,
      );
      final rotationAlpha = (0.28 + motion * 0.20 + confidence * 0.12).clamp(
        0.26,
        0.70,
      );

      final center = Offset.lerp(
        previous.center,
        measured.center,
        centerAlpha,
      )!;
      final scale = _lerp(
        previous.interocularDistance,
        measured.interocularDistance,
        scaleAlpha,
      );
      _centerVelocity =
          (_centerVelocity * 0.45) +
          ((center - previous.center) / elapsedSeconds) * 0.55;
      _scaleVelocity =
          _scaleVelocity * 0.5 +
          ((scale - previous.interocularDistance) / elapsedSeconds) * 0.5;
      _pose = GlassesPose(
        center: center,
        interocularDistance: scale,
        yaw: _lerpAngle(previous.yaw, measured.yaw, rotationAlpha),
        pitch: _lerpAngle(previous.pitch, measured.pitch, rotationAlpha),
        roll: _lerpAngle(previous.roll, measured.roll, rotationAlpha),
        opacity: 1,
        timestamp: now,
        mirrored: observation.mirrored,
      );
    }
    _lastMeasurementAt = now;
    _trackingId = observation.trackingId;
    return poseAt(now);
  }

  /// Returns a short predicted pose, then holds and fades after tracking loss.
  GlassesPose? poseAt(DateTime now) {
    final pose = _pose;
    final lastAt = _lastMeasurementAt;
    if (pose == null || lastAt == null) return null;
    final age = now.difference(lastAt);
    if (age > holdDuration + fadeDuration) return null;

    final predictionUs = math.min(
      math.max(age.inMicroseconds, 0),
      maximumPrediction.inMicroseconds,
    );
    final predictionSeconds = predictionUs / Duration.microsecondsPerSecond;
    final predictedCenter = Offset(
      (pose.center.dx + _centerVelocity.dx * predictionSeconds).clamp(
        -0.1,
        1.1,
      ),
      (pose.center.dy + _centerVelocity.dy * predictionSeconds).clamp(
        -0.1,
        1.1,
      ),
    );
    final predictedScale =
        (pose.interocularDistance + _scaleVelocity * predictionSeconds).clamp(
          0.01,
          0.75,
        );
    final opacity = age <= holdDuration
        ? 1.0
        : (1 -
                  (age - holdDuration).inMicroseconds /
                      fadeDuration.inMicroseconds)
              .clamp(0.0, 1.0);
    return pose.copyWith(
      center: predictedCenter,
      interocularDistance: predictedScale,
      opacity: opacity,
      timestamp: now,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _wrapAngle(double value) =>
      math.atan2(math.sin(value), math.cos(value));

  static double _lerpAngle(double a, double b, double t) =>
      _wrapAngle(a + _wrapAngle(b - a) * t);
}

/// Inverse of the preview's BoxFit.cover mapping, used when the face pose must
/// be composited into an unmirrored captured image.
@immutable
class GlassesCaptureTransform {
  const GlassesCaptureTransform({
    required this.viewportSize,
    required this.imageSize,
    required this.previewMirrored,
  });

  final Size viewportSize;
  final Size imageSize;
  final bool previewMirrored;

  double get coverScale => math.max(
    viewportSize.width / imageSize.width,
    viewportSize.height / imageSize.height,
  );

  Offset viewportPointToImage(Offset normalized) {
    final scale = coverScale;
    final renderedWidth = imageSize.width * scale;
    final renderedHeight = imageSize.height * scale;
    final offsetX = (viewportSize.width - renderedWidth) / 2;
    final offsetY = (viewportSize.height - renderedHeight) / 2;
    final displayX =
        (previewMirrored ? 1 - normalized.dx : normalized.dx) *
        viewportSize.width;
    return Offset(
      (displayX - offsetX) / scale,
      (normalized.dy * viewportSize.height - offsetY) / scale,
    );
  }

  double viewportWidthToImage(double normalizedWidth) =>
      normalizedWidth * viewportSize.width / coverScale;

  GlassesPose poseToImage(GlassesPose pose) => pose.copyWith(
    center: viewportPointToImage(pose.center),
    interocularDistance: viewportWidthToImage(pose.interocularDistance),
    yaw: previewMirrored ? -pose.yaw : pose.yaw,
    roll: previewMirrored ? -pose.roll : pose.roll,
    mirrored: false,
  );
}
