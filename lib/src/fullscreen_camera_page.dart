import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'camera_controller.dart';
import 'camera_preview.dart';
import 'smart_shutter_button.dart';
import 'advanced_boomerang_service.dart';

/// Kamera çekim modu
enum CaptureMode {
  /// Fotoğraf modu
  photo,

  /// Video modu
  video,

  /// Boomerang modu (kısa video + ileri-geri efekt)
  boomerang,
}

/// Instagram tarzı tam ekran kamera sayfası.
///
/// Özellikler:
/// - Tam ekran önizleme (sıkıştırma/bozulma yok)
/// - 1080p yüksek kalite
/// - Fotoğraf, Video ve Boomerang desteği
/// - SmartShutterButton ile sıfır gecikmeli çekim
class FullscreenCameraPage extends StatefulWidget {
  /// Fotoğraf çekildiğinde
  final void Function(String path)? onPhotoCaptured;

  /// Video kaydedildiğinde
  final void Function(String path)? onVideoCaptured;

  /// Boomerang oluşturulduğunda
  final void Function(String path)? onBoomerangCreated;

  /// Tema rengi
  final Color primaryColor;

  /// Başlangıç modu
  final CaptureMode initialMode;

  /// Flash varsayılan durumu
  final FlashMode initialFlashMode;

  const FullscreenCameraPage({
    super.key,
    this.onPhotoCaptured,
    this.onVideoCaptured,
    this.onBoomerangCreated,
    this.primaryColor = const Color(0xFFC13584),
    this.initialMode = CaptureMode.photo,
    this.initialFlashMode = FlashMode.off,
  });

  @override
  State<FullscreenCameraPage> createState() => _FullscreenCameraPageState();
}

class _FullscreenCameraPageState extends State<FullscreenCameraPage>
    with WidgetsBindingObserver {
  // Kamera controller (projenin kendi controller'ı)
  final CameraController _cameraController = CameraController();
  bool _isInitialized = false;
  bool _hasPermission = false;
  String? _errorMessage;

  // Çekim durumu
  CaptureMode _currentMode = CaptureMode.photo;
  FlashMode _flashMode = FlashMode.off;
  bool _isCapturing = false;
  bool _isRecording = false;
  bool _isProcessing = false;

  // Zoom
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;

  // Video kayıt süresi
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  // Boomerang için max süre (saniye)
  static const int _boomerangMaxDuration = 1;
  static const int _videoMaxDuration = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentMode = widget.initialMode;
    _flashMode = widget.initialFlashMode;
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _cameraController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  /// Kamerayı başlat
  Future<void> _initializeCamera() async {
    setState(() {
      _isInitialized = false;
      _errorMessage = null;
    });

    try {
      // İzin kontrolü
      _hasPermission = await _cameraController.checkPermission();
      if (!_hasPermission) {
        _hasPermission = await _cameraController.requestPermission();
      }

      if (!_hasPermission) {
        setState(() {
          _errorMessage = 'Kamera izni verilmedi';
        });
        return;
      }

      // Kamerayı başlat
      await _cameraController.initialize(facing: CameraFacing.back);

      // Flash modunu ayarla
      await _cameraController.setFlashMode(_flashMode);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Kamera başlatılamadı: $e';
        });
      }
    }
  }

  /// Kamera değiştir (ön/arka)
  Future<void> _switchCamera() async {
    if (_isCapturing || _isRecording) return;

    HapticFeedback.lightImpact();

    try {
      await _cameraController.switchCamera();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera switch error: $e');
    }
  }

  /// Flash modunu değiştir
  Future<void> _toggleFlash() async {
    if (!_isInitialized) return;

    HapticFeedback.lightImpact();

    setState(() {
      if (_flashMode == FlashMode.off) {
        _flashMode = FlashMode.on;
      } else if (_flashMode == FlashMode.on) {
        _flashMode = FlashMode.auto;
      } else {
        _flashMode = FlashMode.off;
      }
    });

    await _cameraController.setFlashMode(_flashMode);
  }

  /// Fotoğraf çek
  Future<void> _takePhoto() async {
    if (!_isInitialized || _isCapturing || _isRecording) {
      return;
    }

    setState(() => _isCapturing = true);
    HapticFeedback.mediumImpact();

    try {
      final imagePath = await _cameraController.takePicture();

      if (imagePath != null && mounted) {
        widget.onPhotoCaptured?.call(imagePath);
        debugPrint('Photo captured: $imagePath');
      }
    } catch (e) {
      debugPrint('Photo capture error: $e');
      _showError('Fotoğraf çekilemedi');
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  /// Video kaydını başlat
  Future<void> _startVideoRecording() async {
    if (!_isInitialized || _isCapturing || _isRecording) {
      return;
    }

    HapticFeedback.heavyImpact();

    try {
      // Video dosya yolunu oluştur
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/video_$timestamp.mp4';

      final started = await _cameraController.startVideoRecording(outputPath);

      if (started && mounted) {
        setState(() {
          _isRecording = true;
          _recordingSeconds = 0;
        });

        // Kayıt süre sayacı
        final maxDuration = _currentMode == CaptureMode.boomerang
            ? _boomerangMaxDuration
            : _videoMaxDuration;

        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() => _recordingSeconds++);

            // Maksimum süreye ulaşıldı
            if (_recordingSeconds >= maxDuration) {
              _stopVideoRecording();
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Video start error: $e');
      _showError('Video başlatılamadı');
    }
  }

  /// Video kaydını durdur
  Future<void> _stopVideoRecording() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    HapticFeedback.mediumImpact();

    setState(() {
      _isRecording = false;
      _isProcessing = _currentMode == CaptureMode.boomerang;
    });

    try {
      final videoPath = await _cameraController.stopVideoRecording();

      if (videoPath != null && mounted) {
        if (_currentMode == CaptureMode.boomerang) {
          // Boomerang efekti uygula
          await _processBoomerang(videoPath);
        } else {
          // Normal video
          widget.onVideoCaptured?.call(videoPath);
          debugPrint('Video captured: $videoPath');
        }
      }
    } catch (e) {
      debugPrint('Video stop error: $e');
      _showError('Video kaydedilemedi');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _recordingSeconds = 0;
        });
      }
    }
  }

  /// Boomerang efekti uygula
  Future<void> _processBoomerang(String videoPath) async {
    try {
      final service = AdvancedBoomerangService(
        speedFactor: 2.0,
        loopCount: 3,
        maxInputDuration: 1.0,
        outputQuality: 23, // Daha hızlı encoding
        outputFps: 30,
      );

      final result = await service.generateBoomerang(File(videoPath));

      if (result != null && mounted) {
        widget.onBoomerangCreated?.call(result.path);
        debugPrint('Boomerang created: ${result.path}');

        // Orijinal videoyu sil
        try {
          await File(videoPath).delete();
        } catch (_) {}
      } else {
        _showError('Boomerang oluşturulamadı');
      }
    } catch (e) {
      debugPrint('Boomerang error: $e');
      _showError('Boomerang işlenirken hata oluştu');
    }
  }

  /// Zoom işlemleri
  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_isInitialized) return;

    final newZoom = (_baseZoom * details.scale).clamp(1.0, 5.0);

    if (newZoom != _currentZoom) {
      setState(() => _currentZoom = newZoom);
      _cameraController.setZoomLevel(newZoom);
    }
  }

  /// Hata mesajı göster
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Kamera önizleme
          _buildCameraPreview(),

          // Üst kontroller
          _buildTopControls(),

          // Mod seçici
          _buildModeSelector(),

          // Çekim butonu
          _buildCaptureButton(),

          // Alt kontroller
          _buildBottomControls(),

          // Zoom göstergesi
          if (_currentZoom > 1.0) _buildZoomIndicator(),

          // Kayıt süresi göstergesi
          if (_isRecording) _buildRecordingIndicator(),

          // İşleniyor göstergesi
          if (_isProcessing) _buildProcessingOverlay(),
        ],
      ),
    );
  }

  /// Kamera önizleme widget'ı - TAM EKRAN, BOZULMA YOK
  Widget _buildCameraPreview() {
    // Hata durumu
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.white54),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _initializeCamera,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.primaryColor,
                ),
                child: const Text(
                  'Tekrar Dene',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Yükleniyor
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // Tam ekran kamera önizleme
    // Transform.scale ile görüntüyü ekrana sığdır (crop ile bozulma yok)
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenSize = MediaQuery.of(context).size;
          final screenAspectRatio = screenSize.width / screenSize.height;
          final cameraAspectRatio = _cameraController.aspectRatio;

          // Scale hesaplama: görüntüyü ekrana sığdır ve crop yap
          // Bu formül kısa kenarı ekrana oturtur, uzun kenarı taşırır
          var scale = screenAspectRatio * cameraAspectRatio;
          if (scale < 1) scale = 1 / scale;

          return ClipRect(
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: Center(
                child: CameraPreview(
                  controller: _cameraController,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Üst kontroller
  Widget _buildTopControls() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Kapat butonu
              _buildIconButton(
                icon: Icons.close,
                onTap: () => Navigator.pop(context),
              ),

              // Flash butonu
              _buildIconButton(
                icon: _flashIcon,
                color: _flashMode == FlashMode.on
                    ? Colors.yellow
                    : (_flashMode == FlashMode.auto
                          ? Colors.yellowAccent
                          : Colors.white),
                onTap: _toggleFlash,
              ),

              // Kamera değiştir
              _buildIconButton(
                icon: Icons.flip_camera_ios,
                onTap: _switchCamera,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Flash ikonu
  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.on:
        return Icons.flash_on;
      case FlashMode.auto:
        return Icons.flash_auto;
      default:
        return Icons.flash_off;
    }
  }

  /// Mod seçici
  Widget _buildModeSelector() {
    return Positioned(
      bottom: 180,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildModeButton(CaptureMode.photo, 'Fotoğraf'),
          const SizedBox(width: 24),
          _buildModeButton(CaptureMode.video, 'Video'),
          const SizedBox(width: 24),
          _buildModeButton(CaptureMode.boomerang, 'Boomerang'),
        ],
      ),
    );
  }

  Widget _buildModeButton(CaptureMode mode, String label) {
    final isSelected = _currentMode == mode;

    return GestureDetector(
      onTap: () {
        if (_isRecording || _isCapturing) return;
        HapticFeedback.selectionClick();
        setState(() => _currentMode = mode);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontSize: isSelected ? 16 : 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (isSelected)
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  /// Çekim butonu
  Widget _buildCaptureButton() {
    // İşleniyor durumunda loading göster
    if (_isProcessing) {
      return Positioned(
        bottom: 80,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: const Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // SmartShutterButton - sıfır gecikmeli hibrit buton
    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Center(
        child: SmartShutterButton(
          size: 80,
          idleColor: _currentMode == CaptureMode.boomerang
              ? widget.primaryColor
              : Colors.white,
          recordingColor: const Color(0xFFFF3B30),
          longPressThreshold: _currentMode == CaptureMode.boomerang
              ? const Duration(milliseconds: 150)
              : const Duration(milliseconds: 300),
          onPhoto: () {
            if (_currentMode == CaptureMode.photo) {
              _takePhoto();
            }
          },
          onVideoStart: () {
            if (_currentMode == CaptureMode.video ||
                _currentMode == CaptureMode.boomerang) {
              _startVideoRecording();
            }
          },
          onVideoEnd: () {
            if (_isRecording) {
              _stopVideoRecording();
            }
          },
        ),
      ),
    );
  }

  /// Alt kontroller
  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Galeri butonu (placeholder)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white24,
                ),
                child: const Icon(Icons.photo_library, color: Colors.white),
              ),

              const Spacer(),

              // Boş alan (simetri için)
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  /// Zoom göstergesi
  Widget _buildZoomIndicator() {
    return Positioned(
      top: 120,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_currentZoom.toStringAsFixed(1)}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  /// Kayıt süresi göstergesi
  Widget _buildRecordingIndicator() {
    final minutes = (_recordingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordingSeconds % 60).toString().padLeft(2, '0');

    return Positioned(
      top: 100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$minutes:$seconds',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// İşleniyor overlay
  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _currentMode == CaptureMode.boomerang
                  ? 'Boomerang oluşturuluyor...'
                  : 'İşleniyor...',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  /// İkon buton
  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.black26,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}
