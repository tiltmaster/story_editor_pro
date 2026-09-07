import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'native_story_camera_controller.dart';

/// Warms up the camera *before* the camera screen is shown so the live preview is
/// ready on arrival, instead of the user staring at a ~0.7s black/spinner while
/// the controller initializes on-screen.
///
/// Call [prewarm] right before navigating to [StoryCameraScreen]; the screen then
/// adopts the ready native controller via [takeNativePrepared]. If nothing was
/// warmed (e.g. permission not yet granted), the screen initializes normally.
class CameraPrewarm {
  CameraPrewarm._();

  static NativeStoryCameraController? _nativeController;
  static NativeStoryCameraSession? _nativeSession;
  static NativeStoryCameraFacing? _nativeFacing;
  static const List<CameraDescription>? _cameras = null;
  static const int _cameraIndex = 0;
  static Future<void> _operationTail = Future<void>.value();
  static bool _claiming = false;
  static NativeStoryCameraController? _leasedController;
  static final Set<int> _routeLeaseIds = <int>{};
  static int _nextRouteLeaseId = 0;
  static Timer? _discardTimer;
  static Duration? _lastWarmupDuration;
  static bool _lastNativeInitializationFailed = false;

  static List<CameraDescription>? get cameras => _cameras;
  static int get cameraIndex => _cameraIndex;

  /// Begin initializing a controller in the background. No-op if already
  /// warm/warming, or if camera permission isn't granted yet (so it never
  /// triggers an early permission prompt before the camera screen).
  static Future<void> prewarm({
    bool front = false,
    @visibleForTesting bool? cameraPermissionGranted,
  }) {
    if (_claiming || _leasedController != null || _routeLeaseIds.isNotEmpty) {
      return Future<void>.value();
    }
    final requestedFacing = front
        ? NativeStoryCameraFacing.front
        : NativeStoryCameraFacing.back;
    return _enqueue<void>(
      () => _warm(
        requestedFacing,
        cameraPermissionGranted: cameraPermissionGranted,
      ),
    );
  }

  static Future<void> _warm(
    NativeStoryCameraFacing facing, {
    required bool? cameraPermissionGranted,
  }) async {
    if (_nativeController != null && _nativeFacing == facing) return;
    final previousController = _detachNativeController();
    NativeStoryCameraController? pendingController;
    final stopwatch = Stopwatch()..start();
    _lastNativeInitializationFailed = false;
    try {
      await previousController?.dispose();
      final permissionGranted =
          cameraPermissionGranted ?? await Permission.camera.isGranted;
      if (!permissionGranted) return;
      late final NativeStoryCameraController controller;
      controller = NativeStoryCameraController(
        onDisposed: () {
          if (identical(_leasedController, controller)) {
            _leasedController = null;
          }
        },
      );
      pendingController = controller;
      final session = await controller.initialize(facing);

      _nativeController = controller;
      _nativeSession = session;
      _nativeFacing = facing;
      _lastNativeInitializationFailed = false;
      pendingController = null;

      // Safety: if the screen never claims it, don't hold the camera forever.
      _discardTimer?.cancel();
      _discardTimer = Timer(const Duration(seconds: 12), discard);
    } catch (_) {
      await pendingController?.dispose();
      _nativeController = null;
      _nativeSession = null;
      _nativeFacing = null;
      _lastNativeInitializationFailed = true;
    } finally {
      stopwatch.stop();
      _lastWarmupDuration = stopwatch.elapsed;
    }
  }

  static Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    final previous = _operationTail;
    _operationTail = previous.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static NativeStoryCameraController? _detachNativeController() {
    _discardTimer?.cancel();
    _discardTimer = null;
    final controller = _nativeController;
    _nativeController = null;
    _nativeSession = null;
    _nativeFacing = null;
    return controller;
  }

  /// Blocks background prewarming while a visible camera route owns hardware.
  static CameraPrewarmRouteLease acquireRouteLease() {
    final id = ++_nextRouteLeaseId;
    _routeLeaseIds.add(id);
    return CameraPrewarmRouteLease._(id);
  }

  static void _releaseRouteLease(int id) {
    _routeLeaseIds.remove(id);
  }

  /// Legacy package-camera adoption is no longer used by the native-primary
  /// camera screen. The signature remains for source compatibility.
  @Deprecated('Use takeNativePrepared for the native-primary camera pipeline.')
  static Future<CameraController?> take() async {
    final prepared = await takeNativePrepared();
    await prepared?.controller.dispose();
    return null;
  }

  /// Legacy package-camera adoption retained for source compatibility.
  @Deprecated('Use takeNativePrepared for the native-primary camera pipeline.')
  static Future<PrewarmedCamera?> takePrepared() async {
    final prepared = await takeNativePrepared();
    await prepared?.controller.dispose();
    return null;
  }

  /// Transfers the already-open native camera session to the camera route.
  static Future<NativePrewarmedCamera?> takeNativePrepared() {
    if (_claiming || _leasedController != null) {
      return Future<NativePrewarmedCamera?>.value();
    }
    _claiming = true;
    final waitStopwatch = Stopwatch()..start();
    return _enqueue<NativePrewarmedCamera?>(() async {
      waitStopwatch.stop();
      _discardTimer?.cancel();
      _discardTimer = null;
      final controller = _nativeController;
      final session = _nativeSession;
      final facing = _nativeFacing;
      _nativeController = null;
      _nativeSession = null;
      _nativeFacing = null;
      if (controller == null || session == null || facing == null) return null;
      _leasedController = controller;
      return NativePrewarmedCamera(
        controller: controller,
        session: session,
        facing: facing,
        warmupDuration: _lastWarmupDuration ?? Duration.zero,
        screenWaitDuration: waitStopwatch.elapsed,
      );
    }).whenComplete(() {
      _claiming = false;
    });
  }

  /// Returns and clears a failed native warmup signal. The visible route uses
  /// this to avoid retrying the same failed native initialization immediately.
  static bool takeNativeInitializationFailure() {
    final failed = _lastNativeInitializationFailed;
    _lastNativeInitializationFailed = false;
    return failed;
  }

  /// Dispose an unclaimed warm controller.
  static Future<void> discard() {
    return _enqueue<void>(() async {
      _lastNativeInitializationFailed = false;
      _discardTimer?.cancel();
      _discardTimer = null;
      final controller = _detachNativeController();
      await controller?.dispose();
    });
  }
}

/// A route-lifetime camera ownership token.
class CameraPrewarmRouteLease {
  CameraPrewarmRouteLease._(this._id);

  final int _id;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    CameraPrewarm._releaseRouteLease(_id);
  }
}

/// A native session prepared before the camera route became visible.
class NativePrewarmedCamera {
  const NativePrewarmedCamera({
    required this.controller,
    required this.session,
    required this.facing,
    required this.warmupDuration,
    required this.screenWaitDuration,
  });

  final NativeStoryCameraController controller;
  final NativeStoryCameraSession session;
  final NativeStoryCameraFacing facing;
  final Duration warmupDuration;
  final Duration screenWaitDuration;
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
