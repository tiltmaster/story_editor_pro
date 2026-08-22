import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'face_ar_models.dart';

/// Converts sensor-image pixels into normalized, displayed preview coordinates.
class FaceArViewportTransform {
  const FaceArViewportTransform({
    required this.imageSize,
    required this.viewportSize,
    required this.rotationDegrees,
    required this.mirrored,
  }) : assert(rotationDegrees == 0 ||
            rotationDegrees == 90 ||
            rotationDegrees == 180 ||
            rotationDegrees == 270);

  final Size imageSize;
  final Size viewportSize;
  final int rotationDegrees;
  final bool mirrored;

  Size get orientedSize => rotationDegrees == 90 || rotationDegrees == 270
      ? Size(imageSize.height, imageSize.width)
      : imageSize;

  Offset mapPoint(Offset source) {
    final rotated = switch (rotationDegrees) {
      90 => Offset(imageSize.height - source.dy, source.dx),
      180 => Offset(
          imageSize.width - source.dx,
          imageSize.height - source.dy,
        ),
      270 => Offset(source.dy, imageSize.width - source.dx),
      _ => source,
    };
    final size = orientedSize;
    final scale = math.max(
      viewportSize.width / size.width,
      viewportSize.height / size.height,
    );
    final offsetX = (viewportSize.width - size.width * scale) / 2;
    final offsetY = (viewportSize.height - size.height * scale) / 2;
    var x = (rotated.dx * scale + offsetX) / viewportSize.width;
    final y = (rotated.dy * scale + offsetY) / viewportSize.height;
    if (mirrored) x = 1 - x;
    return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  }

  Rect mapRect(Rect source) {
    final points = <Offset>[
      mapPoint(source.topLeft),
      mapPoint(source.topRight),
      mapPoint(source.bottomLeft),
      mapPoint(source.bottomRight),
    ];
    return Rect.fromLTRB(
      points.map((p) => p.dx).reduce(math.min),
      points.map((p) => p.dy).reduce(math.min),
      points.map((p) => p.dx).reduce(math.max),
      points.map((p) => p.dy).reduce(math.max),
    );
  }

  FaceArObservation mapDetection(
    FaceArRawDetection detection,
    DateTime timestamp,
  ) {
    final landmarks = detection.landmarks.map(
      (key, point) => MapEntry(key, mapPoint(point)),
    );
    final left = landmarks[FaceArLandmark.leftEye];
    final right = landmarks[FaceArLandmark.rightEye];
    final eyeDistance = left == null || right == null
        ? mapRect(detection.bounds).width * 0.45
        : (left - right).distance;
    const radiansPerDegree = math.pi / 180;
    return FaceArObservation(
      trackingId: detection.trackingId,
      bounds: mapRect(detection.bounds),
      landmarks: Map.unmodifiable(landmarks),
      yawRadians:
          detection.yawDegrees * radiansPerDegree * (mirrored ? -1 : 1),
      pitchRadians: detection.pitchDegrees * radiansPerDegree,
      rollRadians:
          detection.rollDegrees * radiansPerDegree * (mirrored ? -1 : 1),
      interocularDistance: eyeDistance,
      confidence: detection.confidence.clamp(0.0, 1.0),
      timestamp: timestamp,
      mirrored: mirrored,
    );
  }
}
