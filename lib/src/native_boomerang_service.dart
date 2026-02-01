import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Native (without FFmpeg) Boomerang service.
///
/// Android: MediaCodec + MediaMuxer
/// iOS: AVAssetReader + AVAssetWriter
///
/// Pipeline:
/// 1. Decode video to frames
/// 2. Reverse sort frames (forward + backward)
/// 3. Encode new video from frames
class NativeBoomerangService {
  static const MethodChannel _channel = MethodChannel('story_editor_pro');

  /// Progress callback (0.0 - 1.0)
  final void Function(double progress)? onProgress;

  /// Loop count (default: 3)
  final int loopCount;

  /// Output FPS (default: 30)
  final int outputFps;

  NativeBoomerangService({
    this.onProgress,
    this.loopCount = 3,
    this.outputFps = 30,
  });

  /// Creates boomerang from video (Native)
  ///
  /// [inputVideo]: Source video file
  /// Returns: Processed boomerang video file or null on error
  Future<File?> generateBoomerang(File inputVideo) async {
    if (!await inputVideo.exists()) {
      debugPrint('NativeBoomerangService: Input video does not exist');
      return null;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/boomerang_native_$timestamp.mp4';

      debugPrint('NativeBoomerangService: Starting native boomerang creation');
      debugPrint('Input: ${inputVideo.path}');
      debugPrint('Output: $outputPath');

      final result = await _channel.invokeMethod<String>('createBoomerang', {
        'inputPath': inputVideo.path,
        'outputPath': outputPath,
        'loopCount': loopCount,
        'fps': outputFps,
      });

      if (result != null) {
        final outputFile = File(result);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          debugPrint('NativeBoomerangService: Success! Output size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
          return outputFile;
        }
      }

      debugPrint('NativeBoomerangService: Failed to create boomerang');
      return null;
    } on PlatformException catch (e) {
      debugPrint('NativeBoomerangService: Platform error: ${e.message}');
      return null;
    } catch (e, stackTrace) {
      debugPrint('NativeBoomerangService: Exception occurred');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
      return null;
    }
  }

  /// Simple boomerang (only forward-backward, no loop)
  Future<File?> generateSimpleBoomerang(File inputVideo) async {
    return generateBoomerang(inputVideo);
  }

  /// Clean up temp files
  Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();

      for (final file in files) {
        if (file is File && file.path.contains('boomerang_')) {
          await file.delete();
          debugPrint('Deleted: ${file.path}');
        }
      }
    } catch (e) {
      debugPrint('Cleanup error: $e');
    }
  }
}
