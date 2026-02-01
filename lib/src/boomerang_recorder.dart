import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';

class BoomerangRecorder {
  static const MethodChannel _channel = MethodChannel('story_editor_pro');

  final CameraController _cameraController;
  final List<String> _capturedFrames = [];
  bool _isCapturing = false;
  Timer? _captureTimer;
  Timer? _maxDurationTimer;

  static const int _targetFps = 10; // Instagram style: 10 FPS
  static const Duration _maxDuration = Duration(seconds: 4);

  BoomerangRecorder(this._cameraController);

  bool get isCapturing => _isCapturing;
  int get capturedFrameCount => _capturedFrames.length;

  /// Capture first frame immediately
  Future<void> _captureFirstFrame() async {
    try {
      final XFile photo = await _cameraController.takePicture();
      if (_isCapturing) {
        _capturedFrames.add(photo.path);
        debugPrint('BoomerangRecorder: Frame 1 captured (immediate)');
      }
    } catch (e) {
      debugPrint('BoomerangRecorder: First frame capture error: $e');
    }
  }

  /// Start boomerang capture
  void startCapturing() {
    if (_isCapturing || !_cameraController.value.isInitialized) {
      return;
    }

    _isCapturing = true;
    _capturedFrames.clear();

    debugPrint('BoomerangRecorder: Starting capture at $_targetFps FPS');

    final frameInterval = Duration(milliseconds: 1000 ~/ _targetFps);

    // Capture first frame IMMEDIATELY (Timer.periodic delays first frame)
    _captureFirstFrame();

    // Frame capture timer
    _captureTimer = Timer.periodic(frameInterval, (timer) async {
      if (!_isCapturing) {
        timer.cancel();
        return;
      }

      try {
        final XFile photo = await _cameraController.takePicture();
        if (_isCapturing) {
          _capturedFrames.add(photo.path);
          debugPrint('BoomerangRecorder: Frame ${_capturedFrames.length} captured');
        }
      } catch (e) {
        debugPrint('BoomerangRecorder: Frame capture error: $e');
      }
    });

    // Maximum duration timer
    _maxDurationTimer = Timer(_maxDuration, () {
      if (_isCapturing) {
        stopCapturing();
      }
    });
  }

  /// Stop capture and create video
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
      final boomerangPath = await _createBoomerangNative();
      return boomerangPath;
    } catch (e) {
      debugPrint('Boomerang creation error: $e');
      await _cleanup();
      return null;
    }
  }

  /// Create boomerang video with native (from frames)
  Future<String?> _createBoomerangNative() async {
    // Use the application's cache directory
    final cacheDir = await getTemporaryDirectory();
    final tempDir = cacheDir.path;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Boomerang frame order: forward + backward
    final List<String> boomerangFrames;
    if (_capturedFrames.length == 1) {
      boomerangFrames = [..._capturedFrames];
    } else {
      boomerangFrames = [
        ..._capturedFrames,
        ..._capturedFrames.reversed.skip(1),
      ];
    }

    // Copy frames with sequential names
    final frameDir = Directory('$tempDir/boomerang_frames_$timestamp');
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
      await _cleanupFrameDir(frameDir);
      return null;
    }

    final outputPath = '$tempDir/boomerang_output_$timestamp.mp4';

    try {
      // Create video from frames with native method
      final result = await _channel.invokeMethod<String>('createBoomerangFromFrames', {
        'frameDir': frameDir.path,
        'outputPath': outputPath,
        'fps': _targetFps,
        'loopCount': 3,
      });

      await _cleanupFrameDir(frameDir);
      await _cleanup();

      if (result != null) {
        final outputFile = File(result);
        if (await outputFile.exists()) {
          final size = await outputFile.length();
          debugPrint('Boomerang created: $result ($size bytes)');
          return result;
        }
      }

      // If native method not available or failed, try simple approach
      debugPrint('Native frame method not available, using simple approach');
      return await _createSimpleBoomerang(frameDir, outputPath);
    } on MissingPluginException {
      debugPrint('createBoomerangFromFrames not implemented, using simple approach');
      final simpleResult = await _createSimpleBoomerang(frameDir, outputPath);
      await _cleanupFrameDir(frameDir);
      await _cleanup();
      return simpleResult;
    } catch (e) {
      debugPrint('Boomerang creation failed: $e');
      await _cleanupFrameDir(frameDir);
      await _cleanup();
      return null;
    }
  }

  /// Simple boomerang creation (return frames without creating video)
  Future<String?> _createSimpleBoomerang(Directory frameDir, String outputPath) async {
    // In this case, return first frame (video could not be created)
    final frames = frameDir.listSync().whereType<File>().toList();
    if (frames.isNotEmpty) {
      // Return first frame (at least something to return)
      return frames.first.path;
    }
    return null;
  }

  /// Clean up frame directory
  Future<void> _cleanupFrameDir(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Frame dir cleanup error: $e');
    }
  }

  /// Clean up temp files
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
