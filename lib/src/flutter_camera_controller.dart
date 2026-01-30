import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

/// Flash modu
enum StoryFlashMode { off, on, auto, torch }

/// Kamera yönü
enum StoryCameraFacing { back, front }

/// Flutter camera paketi ile yüksek kaliteli kamera controller.
///
/// Instagram kalitesinde 1080p önizleme ve çekim sağlar.
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

  /// Kamera hazır mı?
  bool get isInitialized => _isInitialized;

  /// Video kaydı yapılıyor mu?
  bool get isRecording => _isRecording;

  /// Mevcut kamera yönü
  StoryCameraFacing get currentFacing =>
      _cameras.isNotEmpty &&
          _cameras[_currentCameraIndex].lensDirection ==
              CameraLensDirection.front
      ? StoryCameraFacing.front
      : StoryCameraFacing.back;

  /// Kamera controller (preview için)
  CameraController? get controller => _controller;

  /// Önizleme aspect ratio
  double get aspectRatio {
    if (_controller == null || !_isInitialized) return 9 / 16;
    return _controller!.value.aspectRatio;
  }

  /// Önizleme genişliği
  int get previewWidth {
    if (_controller == null || !_isInitialized) return 1080;
    return _controller!.value.previewSize?.width.toInt() ?? 1080;
  }

  /// Önizleme yüksekliği
  int get previewHeight {
    if (_controller == null || !_isInitialized) return 1920;
    return _controller!.value.previewSize?.height.toInt() ?? 1920;
  }

  /// Mevcut zoom seviyesi
  double get currentZoom => _currentZoom;

  /// Minimum zoom
  double get minZoom => _minZoom;

  /// Maximum zoom
  double get maxZoom => _maxZoom;

  /// Kamerayı başlat
  Future<bool> initialize({
    StoryCameraFacing facing = StoryCameraFacing.back,
  }) async {
    try {
      // Kameraları al
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('FlutterCameraController: No cameras available');
        return false;
      }

      // İstenen yöndeki kamerayı bul
      final targetDirection = facing == StoryCameraFacing.front
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      _currentCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == targetDirection,
      );
      if (_currentCameraIndex == -1) _currentCameraIndex = 0;

      // Controller oluştur ve başlat
      await _setupController(_cameras[_currentCameraIndex]);

      return _isInitialized;
    } catch (e) {
      debugPrint('FlutterCameraController: Initialize error: $e');
      return false;
    }
  }

  /// Controller'ı kur
  Future<void> _setupController(CameraDescription camera) async {
    // Eski controller'ı temizle
    await _controller?.dispose();

    // Yeni controller - YÜKSEK KALİTE (1080p)
    _controller = CameraController(
      camera,
      ResolutionPreset.ultraHigh, // 1080p
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();

      // Orientation kilitle
      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);

      // Zoom limitlerini al
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _currentZoom = _minZoom;

      // Flash modunu ayarla
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

  /// Fotoğraf çek
  Future<String?> takePicture() async {
    if (_controller == null || !_isInitialized || _isRecording) {
      return null;
    }

    try {
      // Çekim sırasında flash
      if (_flashMode == StoryFlashMode.on ||
          _flashMode == StoryFlashMode.auto) {
        await _controller!.setFlashMode(
          _flashMode == StoryFlashMode.on ? FlashMode.always : FlashMode.auto,
        );
      }

      final XFile file = await _controller!.takePicture();

      // Ön kamera ise mirror düzeltmesi gerekebilir
      // (Flutter camera paketi bunu otomatik yapıyor)

      debugPrint('FlutterCameraController: Photo captured: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('FlutterCameraController: Take picture error: $e');
      return null;
    }
  }

  /// Video kaydını başlat
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

  /// Video kaydını durdur
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

  /// Kamera değiştir (ön/arka)
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

  /// Flash modunu ayarla
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

  /// Zoom seviyesini ayarla
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

  /// Odak noktası ayarla
  Future<void> setFocusPoint(Offset point) async {
    if (_controller == null || !_isInitialized) return;

    try {
      await _controller!.setFocusPoint(point);
      await _controller!.setExposurePoint(point);
    } catch (e) {
      debugPrint('FlutterCameraController: Set focus error: $e');
    }
  }

  /// Kaynakları temizle
  Future<void> dispose() async {
    _isInitialized = false;
    _isRecording = false;
    await _controller?.dispose();
    _controller = null;
  }
}
