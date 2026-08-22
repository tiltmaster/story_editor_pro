import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter/widgets.dart' show Size;

import 'face_ar_detector.dart';
import 'face_ar_models.dart';
import 'mlkit_face_ar_detector.dart';

/// Owns camera-frame ingestion while leaving camera permission and camera
/// lifecycle ownership with the host camera screen.
///
/// Call [pauseForStillCapture] before `takePicture()`. For video, call
/// [pauseForVideoRecording], then pass [onVideoFrame] to
/// `CameraController.startVideoRecording(onAvailable: tracker.onVideoFrame)`.
/// The last pose remains available to the renderer during transitions.
class FaceArCameraTracker {
  FaceArCameraTracker({
    required Size viewportSize,
    required FaceArStateListener onState,
    FaceArDetector? detector,
    double maxFramesPerSecond = 15,
    int missingFramesBeforeLost = 2,
    bool? previewMirrored,
  }) : _processor = FaceArStreamProcessor(
          detector: detector ?? MlKitFaceArDetector(),
          viewportSize: viewportSize,
          onState: onState,
          maxFramesPerSecond: maxFramesPerSecond,
          missingFramesBeforeLost: missingFramesBeforeLost,
        ),
       _previewMirrored = previewMirrored;

  final FaceArStreamProcessor _processor;
  CameraController? _controller;
  CameraDescription? _description;
  bool _started = false;
  bool _closed = false;
  bool? _previewMirrored;

  /// Stream format required by ML Kit for the active mobile platform.
  static ImageFormatGroup get requiredImageFormat =>
      switch (defaultTargetPlatform) {
        TargetPlatform.android => ImageFormatGroup.nv21,
        TargetPlatform.iOS => ImageFormatGroup.bgra8888,
        _ => ImageFormatGroup.jpeg,
      };

  bool get isStarted => _started;

  /// Starts a preview image stream. The controller must have been constructed
  /// with NV21 on Android or BGRA8888 on iOS.
  Future<void> start(
    CameraController controller,
    CameraDescription description, {
    bool? previewMirrored,
  }) async {
    if (_closed || _started || !controller.value.isInitialized) return;
    _controller = controller;
    _description = description;
    _previewMirrored = previewMirrored ??
        _previewMirrored ??
        description.lensDirection == CameraLensDirection.front;
    await controller.startImageStream(onCameraImage);
    _started = true;
  }

  /// Stops only the analysis stream; it never disposes the host camera.
  Future<void> stop() async {
    final controller = _controller;
    _started = false;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isStreamingImages &&
        !controller.value.isRecordingVideo) {
      await controller.stopImageStream();
    }
  }

  /// Safe still-capture wrapper. Face analysis cannot race `takePicture()`.
  Future<T> pauseForStillCapture<T>(Future<T> Function() capture) async {
    final shouldResume = _started;
    await stop();
    try {
      return await capture();
    } finally {
      final controller = _controller;
      final description = _description;
      if (!_closed &&
          shouldResume &&
          controller != null &&
          description != null &&
          controller.value.isInitialized &&
          !controller.value.isRecordingVideo) {
        await start(controller, description);
      }
    }
  }

  /// Stops preview streaming before video starts. Supply [onVideoFrame] as the
  /// camera package's recording frame callback to keep tracking during video.
  Future<void> pauseForVideoRecording() => stop();

  /// Camera image callback for preview or `startVideoRecording(onAvailable:)`.
  void onCameraImage(CameraImage image) {
    if (_closed) return;
    final description = _description;
    final controller = _controller;
    if (description == null || controller == null || image.planes.length != 1) {
      return;
    }
    final format = switch (image.format.group) {
      ImageFormatGroup.nv21 => FaceArPixelFormat.nv21,
      ImageFormatGroup.bgra8888 => FaceArPixelFormat.bgra8888,
      _ => null,
    };
    if (format == null) return;
    final rotation = _rotationDegrees(
      description,
      controller.value.deviceOrientation,
    );
    _processor.submit(FaceArFrame(
      // The camera plugin may reuse buffers after this callback returns.
      bytes: Uint8List.fromList(image.planes.first.bytes),
      width: image.width,
      height: image.height,
      bytesPerRow: image.planes.first.bytesPerRow,
      rotationDegrees: rotation,
      format: format,
      timestamp: DateTime.now(),
      mirrored: _previewMirrored ??
          description.lensDirection == CameraLensDirection.front,
    ));
  }

  /// Alias intended for CameraController.startVideoRecording(onAvailable: ...).
  void onVideoFrame(CameraImage image) => onCameraImage(image);

  int _rotationDegrees(
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    final deviceDegrees = switch (orientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    if (camera.lensDirection == CameraLensDirection.front) {
      return (camera.sensorOrientation + deviceDegrees) % 360;
    }
    return (camera.sensorOrientation - deviceDegrees + 360) % 360;
  }

  Future<void> close() async {
    if (_closed) return;
    await stop();
    _closed = true;
    _controller = null;
    _description = null;
    await _processor.close();
  }
}
