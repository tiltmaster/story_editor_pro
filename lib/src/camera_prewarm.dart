import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'face_ar/face_ar_camera_tracker.dart';

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
  static Stopwatch? _warmupStopwatch;
  static Duration? _lastWarmupDuration;
  static int _generation = 0;

  static List<CameraDescription>? get cameras => _cameras;
  static int get cameraIndex => _cameraIndex;

  /// Begin initializing a controller in the background. No-op if already
  /// warm/warming, or if camera permission isn't granted yet (so it never
  /// triggers an early permission prompt before the camera screen).
  static Future<void> prewarm({bool front = false}) {
    if (_controller != null) return Future<void>.value();
    final warming = _warming;
    if (warming != null) return warming;

    final generation = ++_generation;
    _warmupStopwatch = Stopwatch()..start();
    final future = _doWarm(front, generation);
    _warming = future.whenComplete(() {
      _warmupStopwatch?.stop();
      _lastWarmupDuration = _warmupStopwatch?.elapsed;
      _warmupStopwatch = null;
      _warming = null;
    });
    return _warming!;
  }

  static Future<void> _doWarm(bool front, int generation) async {
    CameraController? pendingController;
    try {
      if (!await Permission.camera.isGranted) return;
      if (generation != _generation) return;
      // Camera enumeration is stable for the process lifetime on mobile and is
      // a measurable platform-channel cost. Reuse the last successful list.
      final cachedCameras = _cameras;
      final cams = cachedCameras != null && cachedCameras.isNotEmpty
          ? cachedCameras
          : await availableCameras();
      if (cams.isEmpty || generation != _generation) return;
      final dir = front ? CameraLensDirection.front : CameraLensDirection.back;
      var idx = cams.indexWhere((c) => c.lensDirection == dir);
      if (idx == -1) idx = 0;

      final controller = CameraController(
        cams[idx],
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: FaceArCameraTracker.requiredImageFormat,
      );
      pendingController = controller;
      await controller.initialize();
      if (generation != _generation) {
        await controller.dispose();
        return;
      }

      _cameras = cams;
      _cameraIndex = idx;
      _controller = controller;
      pendingController = null;

      // Orientation locking is a secondary platform round-trip. The preview is
      // already usable after initialize(), so do not hold first-frame readiness
      // behind it. The screen repeats this best-effort configuration after it
      // adopts the controller.
      unawaited(
        controller
            .lockCaptureOrientation(DeviceOrientation.portraitUp)
            .catchError((_) {}),
      );

      // Safety: if the screen never claims it, don't hold the camera forever.
      _discardTimer?.cancel();
      _discardTimer = Timer(const Duration(seconds: 12), discard);
    } catch (_) {
      await pendingController?.dispose();
      _controller = null;
    }
  }

  /// Hand the ready controller to the caller (which now owns and disposes it).
  /// Awaits an in-flight warm-up. Returns null if none is available.
  static Future<CameraController?> take() async {
    final prepared = await takePrepared();
    return prepared?.controller;
  }

  /// Hands a warmed controller and its startup timing to the camera screen.
  ///
  /// This is separate from [take] to preserve compatibility for existing hosts.
  static Future<PrewarmedCamera?> takePrepared() async {
    final waitStopwatch = Stopwatch()..start();
    final warming = _warming;
    if (warming != null) {
      try {
        await warming;
      } catch (_) {}
    }
    waitStopwatch.stop();
    _discardTimer?.cancel();
    _discardTimer = null;
    final controller = _controller;
    _controller = null;
    if (controller == null) return null;
    return PrewarmedCamera(
      controller: controller,
      cameras: List<CameraDescription>.unmodifiable(_cameras ?? const []),
      cameraIndex: _cameraIndex,
      warmupDuration: _lastWarmupDuration ?? Duration.zero,
      screenWaitDuration: waitStopwatch.elapsed,
    );
  }

  /// Dispose an unclaimed warm controller.
  static Future<void> discard() async {
    _generation++;
    _discardTimer?.cancel();
    _discardTimer = null;
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

/// A camera prepared before the capture route became visible.
class PrewarmedCamera {
  const PrewarmedCamera({
    required this.controller,
    required this.cameras,
    required this.cameraIndex,
    required this.warmupDuration,
    required this.screenWaitDuration,
  });

  final CameraController controller;
  final List<CameraDescription> cameras;
  final int cameraIndex;
  final Duration warmupDuration;

  /// Time the camera screen still had to wait for an in-flight warm-up.
  final Duration screenWaitDuration;
}

/// First-preview performance data. Hosts can forward this to their existing
/// analytics sink without the camera package collecting user or media data.
class CameraStartupMetrics {
  const CameraStartupMetrics({
    required this.usedPrewarm,
    required this.controllerInitialization,
    required this.screenWaitForController,
    required this.routeToPreviewReady,
  });

  final bool usedPrewarm;
  final Duration controllerInitialization;
  final Duration screenWaitForController;
  final Duration routeToPreviewReady;

  bool get metWarmTarget =>
      routeToPreviewReady <= const Duration(milliseconds: 700);
}
