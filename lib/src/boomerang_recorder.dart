import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'camera_controller.dart';

class BoomerangRecorder {
  final CameraController _cameraController;
  final List<String> _capturedFrames = [];
  bool _isCapturing = false;
  Timer? _captureTimer;
  Timer? _maxDurationTimer;

  static const int _targetFps = 8; // Daha az frame = daha az bellek
  static const Duration _maxDuration = Duration(seconds: 7);

  BoomerangRecorder(this._cameraController);

  bool get isCapturing => _isCapturing;
  int get capturedFrameCount => _capturedFrames.length;

  /// İlk frame'i hemen yakala
  Future<void> _captureFirstFrame() async {
    try {
      final framePath = await _cameraController.takePicture();
      if (framePath != null && _isCapturing) {
        _capturedFrames.add(framePath);
        debugPrint('Frame 1 captured (immediate)');
      }
    } catch (e) {
      debugPrint('First frame capture error: $e');
    }
  }

  /// Boomerang yakalamayı başlat
  void startCapturing() {
    if (_isCapturing || !_cameraController.isInitialized) {
      return;
    }

    _isCapturing = true;
    _capturedFrames.clear();

    final frameInterval = Duration(milliseconds: 1000 ~/ _targetFps);

    // İlk frame'i HEMEN yakala (Timer.periodic ilk frame'i geciktiriyor)
    _captureFirstFrame();

    // Frame yakalama timer'ı
    _captureTimer = Timer.periodic(frameInterval, (timer) async {
      if (!_isCapturing) {
        timer.cancel();
        return;
      }

      try {
        final framePath = await _cameraController.takePicture();
        if (framePath != null && _isCapturing) {
          _capturedFrames.add(framePath);
          debugPrint('Frame ${_capturedFrames.length} captured');
        }
      } catch (e) {
        debugPrint('Frame capture error: $e');
      }
    });

    // Maksimum süre timer'ı
    _maxDurationTimer = Timer(_maxDuration, () {
      if (_isCapturing) {
        stopCapturing();
      }
    });
  }

  /// Yakalamayı durdur ve video oluştur
  Future<String?> stopCapturing() async {
    if (!_isCapturing) {
      return null;
    }

    _isCapturing = false;
    _captureTimer?.cancel();
    _maxDurationTimer?.cancel();

    if (_capturedFrames.isEmpty) {
      debugPrint('No frames captured');
      await _cleanup();
      return null;
    }

    debugPrint('Total captured: ${_capturedFrames.length} frames');

    try {
      final boomerangPath = await _createBoomerangWithFFmpeg();
      return boomerangPath;
    } catch (e) {
      debugPrint('Boomerang creation error: $e');
      await _cleanup();
      return null;
    }
  }

  /// FFmpeg ile boomerang video oluştur
  Future<String?> _createBoomerangWithFFmpeg() async {
    // Uygulamanın cache dizinini kullan
    final cacheDir = await getTemporaryDirectory();
    final tempDir = cacheDir.path;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Boomerang frame sırası: ileri + geri
    final List<String> boomerangFrames;
    if (_capturedFrames.length == 1) {
      boomerangFrames = [..._capturedFrames];
    } else {
      boomerangFrames = [
        ..._capturedFrames,
        ..._capturedFrames.reversed.skip(1),
      ];
    }

    // Frame'leri sıralı isimlerle kopyala
    final frameDir = Directory('$tempDir/boomerang_$timestamp');
    await frameDir.create(recursive: true);

    debugPrint('Frame dir: ${frameDir.path}');

    int copiedCount = 0;
    for (int i = 0; i < boomerangFrames.length; i++) {
      final srcFile = File(boomerangFrames[i]);
      if (await srcFile.exists()) {
        final destPath = '${frameDir.path}/frame_${i.toString().padLeft(4, '0')}.jpg';
        await srcFile.copy(destPath);
        copiedCount++;
      }
    }

    debugPrint('Copied $copiedCount frames');

    if (copiedCount == 0) {
      debugPrint('No frames copied!');
      await _cleanup();
      return null;
    }

    final outputPath = '$tempDir/boomerang_output_$timestamp.mp4';

    // FFmpeg: image sequence'den video oluştur
    // -vf scale ile boyutu küçült (bellek tasarrufu)
    final command = '-framerate $_targetFps -i "${frameDir.path}/frame_%04d.jpg" -vf "scale=720:-2" -c:v libx264 -pix_fmt yuv420p -preset ultrafast -crf 28 -y "$outputPath"';

    debugPrint('FFmpeg command: $command');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    // Frame klasörünü temizle
    try {
      await frameDir.delete(recursive: true);
    } catch (e) {
      debugPrint('Frame dir delete error: $e');
    }

    if (ReturnCode.isSuccess(returnCode)) {
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        final size = await outputFile.length();
        debugPrint('Boomerang created: $outputPath ($size bytes)');
        await _cleanup();
        return outputPath;
      } else {
        debugPrint('Output file not found!');
        await _cleanup();
        return null;
      }
    } else {
      debugPrint('FFmpeg failed: $returnCode');
      final logs = await session.getLogs();
      for (final log in logs) {
        debugPrint('FFmpeg: ${log.getMessage()}');
      }
      await _cleanup();
      return null;
    }
  }

  /// Temp dosyaları temizle
  Future<void> _cleanup() async {
    for (final frame in _capturedFrames) {
      try {
        final file = File(frame);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Cleanup error: $e');
      }
    }
    _capturedFrames.clear();
  }

  void cancel() {
    _captureTimer?.cancel();
    _maxDurationTimer?.cancel();
    _isCapturing = false;
    _cleanup();
  }

  void dispose() {
    cancel();
  }
}
