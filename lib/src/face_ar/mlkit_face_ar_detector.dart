import 'dart:ui' show Offset, Size;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_ar_detector.dart';
import 'face_ar_models.dart';

/// ML Kit-backed detector. Processing is entirely on-device on Android/iOS.
class MlKitFaceArDetector implements FaceArDetector {
  MlKitFaceArDetector()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            enableLandmarks: true,
            enableTracking: true,
            performanceMode: FaceDetectorMode.fast,
            minFaceSize: 0.12,
          ),
        );

  final FaceDetector _detector;
  bool _closed = false;

  @override
  Future<List<FaceArRawDetection>> detect(FaceArFrame frame) async {
    if (_closed) return const [];
    final rotation = InputImageRotationValue.fromRawValue(
      frame.rotationDegrees,
    );
    if (rotation == null) return const [];
    final format = switch (frame.format) {
      FaceArPixelFormat.nv21 => InputImageFormat.nv21,
      FaceArPixelFormat.bgra8888 => InputImageFormat.bgra8888,
    };
    final image = InputImage.fromBytes(
      bytes: frame.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: frame.bytesPerRow,
      ),
    );
    final faces = await _detector.processImage(image);
    return faces.map(_mapFace).toList(growable: false);
  }

  FaceArRawDetection _mapFace(Face face) {
    final landmarks = <FaceArLandmark, Offset>{};
    void add(FaceArLandmark target, FaceLandmarkType source) {
      final point = face.landmarks[source]?.position;
      if (point != null) {
        landmarks[target] = Offset(point.x.toDouble(), point.y.toDouble());
      }
    }

    add(FaceArLandmark.leftEye, FaceLandmarkType.leftEye);
    add(FaceArLandmark.rightEye, FaceLandmarkType.rightEye);
    add(FaceArLandmark.noseBase, FaceLandmarkType.noseBase);
    add(FaceArLandmark.leftEar, FaceLandmarkType.leftEar);
    add(FaceArLandmark.rightEar, FaceLandmarkType.rightEar);
    add(FaceArLandmark.leftMouth, FaceLandmarkType.leftMouth);
    add(FaceArLandmark.rightMouth, FaceLandmarkType.rightMouth);
    add(FaceArLandmark.bottomMouth, FaceLandmarkType.bottomMouth);
    add(FaceArLandmark.leftCheek, FaceLandmarkType.leftCheek);
    add(FaceArLandmark.rightCheek, FaceLandmarkType.rightCheek);

    return FaceArRawDetection(
      trackingId: face.trackingId,
      bounds: face.boundingBox,
      landmarks: landmarks,
      yawDegrees: face.headEulerAngleY ?? 0,
      pitchDegrees: face.headEulerAngleX ?? 0,
      rollDegrees: face.headEulerAngleZ ?? 0,
      // ML Kit's face API has no scalar detection probability. 1 means the
      // result passed ML Kit's detector threshold, not a fabricated score.
      confidence: 1,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _detector.close();
  }
}
