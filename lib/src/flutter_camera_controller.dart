import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

/// Flash mode
enum StoryFlashMode { off, on, auto, torch }

/// Camera direction
enum StoryCameraFacing { back, front }

/// High quality camera controller with Flutter camera package.
///
/// Provides Instagram quality 1080p preview and capture.
class FlutterCameraController {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;
  bool _isInitialized = false;
  bool _isRecording = false;

  StoryFlashMode _flashMode = StoryFlashMode.off;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  /// Is camera ready?
  bool get isInitialized => _isInitialized;

  /// Is video recording in progress?
  bool get isRecording => _isRecording;

  /// Current camera direction
  StoryCameraFacing get currentFacing =>
      _cameras.isNotEmpty &&
          _cameras[_currentCameraIndex].lensDirection ==
              CameraLensDirection.front
      ? StoryCameraFacing.front
      : StoryCameraFacing.back;

  /// Camera controller (for preview)
  CameraController? get controller => _controller;

  /// Preview aspect ratio
  double get aspectRatio {
    if (_controller == null || !_isInitialized) return 9 / 16;
    return _controller!.value.aspectRatio;
  }

  /// Preview width
  int get previewWidth {
    if (_controller == null || !_isInitialized) return 1080;
    return _controller!.value.previewSize?.width.toInt() ?? 1080;
  }

  /// Preview height
  int get previewHeight {
    if (_controller == null || !_isInitialized) return 1920;
    return _controller!.value.previewSize?.height.toInt() ?? 1920;
  }

  /// Current zoom level
  double get currentZoom => _currentZoom;

  /// Minimum zoom
  double get minZoom => _minZoom;

  /// Maximum zoom
  double get maxZoom => _maxZoom;

  /// Initialize camera
  Future<bool> initialize({
    StoryCameraFacing facing = StoryCameraFacing.back,
  }) async {
    try {
      // Get cameras
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('FlutterCameraController: No cameras available');
        return false;
      }

      // Find camera in requested direction
      final targetDirection = facing == StoryCameraFacing.front
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      _currentCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == targetDirection,
      );
      if (_currentCameraIndex == -1) _currentCameraIndex = 0;

      // Create and initialize controller
      await _setupController(_cameras[_currentCameraIndex]);

      return _isInitialized;
    } catch (e) {
      debugPrint('FlutterCameraController: Initialize error: $e');
      return false;
    }
  }

  /// Setup controller
  Future<void> _setupController(CameraDescription camera) async {
    // Clean up old controller
    await _controller?.dispose();

    // New controller - HIGH QUALITY (1080p)
    _controller = CameraController(
      camera,
      ResolutionPreset.ultraHigh, // 1080p
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();

      // Lock orientation
      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);

      // Get zoom limits
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _currentZoom = _minZoom;

      // Set flash mode
      await _setFlashModeInternal(_flashMode);

      _isInitialized = true;
      debugPrint(
        'FlutterCameraController: Initialized - ${_controller!.value.previewSize}',
      );
    } on CameraException catch (e) {
      debugPrint('FlutterCameraController: CameraException: ${e.description}');
      _isInitialized = false;
    }
  }

  /// Take photo
  Future<String?> takePicture() async {
    if (_controller == null || !_isInitialized || _isRecording) {
      return null;
    }

    try {
      // Flash during capture
      if (_flashMode == StoryFlashMode.on ||
          _flashMode == StoryFlashMode.auto) {
        await _controller!.setFlashMode(
          _flashMode == StoryFlashMode.on ? FlashMode.always : FlashMode.auto,
        );
      }

      final XFile file = await _controller!.takePicture();

      // Mirror correction may be needed for front camera
      // (Flutter camera package does this automatically)

      debugPrint('FlutterCameraController: Photo captured: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('FlutterCameraController: Take picture error: $e');
      return null;
    }
  }

  /// Start video recording
  Future<bool> startVideoRecording([String? outputPath]) async {
    if (_controller == null || !_isInitialized || _isRecording) {
      return false;
    }

    try {
      await _controller!.startVideoRecording();
      _isRecording = true;
      debugPrint('FlutterCameraController: Video recording started');
      return true;
    } catch (e) {
      debugPrint('FlutterCameraController: Start recording error: $e');
      return false;
    }
  }

  /// Stop video recording
  Future<String?> stopVideoRecording() async {
    if (_controller == null || !_isRecording) {
      return null;
    }

    try {
      final XFile file = await _controller!.stopVideoRecording();
      _isRecording = false;
      debugPrint('FlutterCameraController: Video saved: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('FlutterCameraController: Stop recording error: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Switch camera (front/back)
  Future<bool> switchCamera() async {
    if (_cameras.length < 2 || _isRecording) {
      return false;
    }

    try {
      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
      await _setupController(_cameras[_currentCameraIndex]);
      return true;
    } catch (e) {
      debugPrint('FlutterCameraController: Switch camera error: $e');
      return false;
    }
  }

  /// Set flash mode
  Future<void> setFlashMode(StoryFlashMode mode) async {
    _flashMode = mode;
    await _setFlashModeInternal(mode);
  }

  Future<void> _setFlashModeInternal(StoryFlashMode mode) async {
    if (_controller == null || !_isInitialized) return;

    try {
      FlashMode flashMode;
      switch (mode) {
        case StoryFlashMode.on:
          flashMode = FlashMode.always;
          break;
        case StoryFlashMode.auto:
          flashMode = FlashMode.auto;
          break;
        case StoryFlashMode.torch:
          flashMode = FlashMode.torch;
          break;
        default:
          flashMode = FlashMode.off;
      }
      await _controller!.setFlashMode(flashMode);
    } catch (e) {
      debugPrint('FlutterCameraController: Set flash error: $e');
    }
  }

  /// Set zoom level
  Future<void> setZoomLevel(double level) async {
    if (_controller == null || !_isInitialized) return;

    try {
      final clampedLevel = level.clamp(_minZoom, _maxZoom);
      await _controller!.setZoomLevel(clampedLevel);
      _currentZoom = clampedLevel;
    } catch (e) {
      debugPrint('FlutterCameraController: Set zoom error: $e');
    }
  }

  /// Set focus point
  Future<void> setFocusPoint(Offset point) async {
    if (_controller == null || !_isInitialized) return;

    try {
      await _controller!.setFocusPoint(point);
      await _controller!.setExposurePoint(point);
    } catch (e) {
      debugPrint('FlutterCameraController: Set focus error: $e');
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    _isInitialized = false;
    _isRecording = false;
    await _controller?.dispose();
    _controller = null;
  }
}
