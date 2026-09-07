import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Service that simulates Instagram Boomerang algorithm (Native - without FFmpeg).
///
/// Pipeline:
/// 1. Decode video to frames (native)
/// 2. Reverse sort frames (forward + backward)
/// 3. Encode new video from frames (native)
/// 4. Apply loop
///
/// Android: MediaCodec + MediaMuxer
/// iOS: AVAssetReader + AVAssetWriter
class AdvancedBoomerangService {
  static const MethodChannel _channel = MethodChannel('story_editor_pro');

  /// Progress callback for boomerang operation
  final void Function(double progress)? onProgress;

  /// Loop count (3 = forward-backward sequence repeated 3 times)
  final int loopCount;

  /// Output FPS
  final int outputFps;

  AdvancedBoomerangService({
    this.onProgress,
    this.loopCount = 3,
    this.outputFps = 30,
  });

  /// Creates Instagram-style Boomerang video (Native).
  ///
  /// [inputVideo]: Source video file (max 1 second recommended)
  ///
  /// Returns: Processed boomerang video file or null on error
  Future<File?> generateBoomerang(File inputVideo) async {
    if (!await inputVideo.exists()) {
      debugPrint('AdvancedBoomerangService: Input video does not exist');
      return null;
    }

    try {
      // Create output file path
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/boomerang_native_$timestamp.mp4';

      debugPrint(
        'AdvancedBoomerangService: Starting native boomerang creation',
      );

      onProgress?.call(0.1);

      final result = await _channel.invokeMethod<String>('createBoomerang', {
        'inputPath': inputVideo.path,
        'outputPath': outputPath,
        'loopCount': loopCount,
        'fps': outputFps,
      });

      onProgress?.call(1.0);

      if (result != null) {
        final outputFile = File(result);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          debugPrint(
            'AdvancedBoomerangService: Success! Output size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
          );
          return outputFile;
        }
      }

      debugPrint('AdvancedBoomerangService: Native boomerang creation failed');
      return null;
    } on PlatformException catch (e) {
      debugPrint('AdvancedBoomerangService: Platform error: ${e.message}');
      return null;
    } catch (e, stackTrace) {
      debugPrint('AdvancedBoomerangService: Exception occurred');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
      return null;
    }
  }

  /// Simple boomerang (only forward-backward, no loop)
  /// Can be used for faster processing
  Future<File?> generateSimpleBoomerang(File inputVideo) async {
    // Use loopCount=1 for simple version
    final tempService = AdvancedBoomerangService(
      onProgress: onProgress,
      loopCount: 1,
      outputFps: outputFps,
    );
    return tempService.generateBoomerang(inputVideo);
  }

  /// Cleans up previously created boomerang files
  Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();

      for (final file in files) {
        if (file is File && file.path.contains('boomerang_')) {
          await file.delete();
          debugPrint('AdvancedBoomerangService: Deleted temp file');
        }
      }
    } catch (e) {
      debugPrint('Cleanup error: $e');
    }
  }
}
