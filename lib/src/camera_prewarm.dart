import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Warms up the camera *before* the camera screen is shown so the live preview is
/// ready on arrival, instead of the user staring at a ~0.7s black/spinner while
/// the controller initializes on-screen.
///
/// Call [prewarm] right before navigating to [StoryCameraScreen]; the screen then
/// adopts the ready controller via [take]. If nothing was warmed (e.g. permission
/// not yet granted), [take] returns null and the screen initializes normally.
class CameraPrewarm {
  CameraPrewarm._();

  static CameraController? _controller;
  static List<CameraDescription>? _cameras;
  static int _cameraIndex = 0;
  static Future<void>? _warming;
  static Timer? _discardTimer;

  static List<CameraDescription>? get cameras => _cameras;
  static int get cameraIndex => _cameraIndex;

  /// Begin initializing a controller in the background. No-op if already
  /// warm/warming, or if camera permission isn't granted yet (so it never
  /// triggers an early permission prompt before the camera screen).
  static void prewarm({bool front = false}) {
    if (_controller != null || _warming != null) return;
    _warming = _doWarm(front).whenComplete(() => _warming = null);
  }

  static Future<void> _doWarm(bool front) async {
    try {
      if (!await Permission.camera.isGranted) return;
      final cams = await availableCameras();
      if (cams.isEmpty) return;
      final dir = front ? CameraLensDirection.front : CameraLensDirection.back;
      var idx = cams.indexWhere((c) => c.lensDirection == dir);
      if (idx == -1) idx = 0;

      final controller = CameraController(
        cams[idx],
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      _cameras = cams;
      _cameraIndex = idx;
      _controller = controller;

      // Safety: if the screen never claims it, don't hold the camera forever.
      _discardTimer?.cancel();
      _discardTimer = Timer(const Duration(seconds: 12), discard);
    } catch (_) {
      _controller = null;
    }
  }

  /// Hand the ready controller to the caller (which now owns and disposes it).
  /// Awaits an in-flight warm-up. Returns null if none is available.
  static Future<CameraController?> take() async {
    final warming = _warming;
    if (warming != null) {
      try {
        await warming;
      } catch (_) {}
    }
    _discardTimer?.cancel();
    _discardTimer = null;
    final controller = _controller;
    _controller = null;
    return controller;
  }

  /// Dispose an unclaimed warm controller.
  static Future<void> discard() async {
    _discardTimer?.cancel();
    _discardTimer = null;
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
