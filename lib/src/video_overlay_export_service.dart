import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Native video overlay export service.
/// Composites a transparent PNG overlay onto a video using native APIs.
///
/// iOS: AVMutableComposition + AVVideoCompositionCoreAnimationTool
/// Android: MediaCodec + Surface + Canvas
class VideoOverlayExportService {
  static const MethodChannel _channel = MethodChannel('story_editor_pro');
  static String? _lastExportError;
  static Future<String?>? _pendingExportFuture;
  static String? _pendingExportRawVideoPath;

  /// Last export error details (if any).
  static String? get lastExportError => _lastExportError;

  /// Future that resolves when the most recent background export completes.
  /// Returns the output path on success, or null on failure.
  static Future<String?>? get pendingExportFuture => _pendingExportFuture;

  /// The original (pre-filter) video path for use as an instant preview placeholder.
  static String? get pendingExportRawVideoPath => _pendingExportRawVideoPath;

  /// Export video with overlay PNG baked in.
  ///
  /// [videoPath]: Original video file path
  /// [overlayPngBytes]: PNG image bytes (transparent background, only overlays)
  /// Returns: Path to the exported MP4 file, or null on failure
  static Future<String?> exportVideoWithOverlay({
    required String videoPath,
    required Uint8List overlayPngBytes,
    bool mirrorHorizontally = false,
    int? outputWidth,
    int? outputHeight,
    String filterPreset = 'none',
    double filterStrength = 1.0,
  }) async {
    _lastExportError = null;
    try {
      final sw = Stopwatch()..start();
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final overlayPath = '${tempDir.path}/overlay_$timestamp.png';
      final outputPath = '${tempDir.path}/story_video_$timestamp.mp4';

      final overlayFile = File(overlayPath);
      await overlayFile.writeAsBytes(overlayPngBytes);
      debugPrint('VideoOverlayProcessor: Overlay PNG written in ${sw.elapsedMilliseconds}ms (${(overlayPngBytes.length / 1024).toStringAsFixed(0)}KB)');

      debugPrint('VideoOverlayProcessor: Starting native export...');
      debugPrint('  Video: $videoPath');
      debugPrint('  Output: $outputPath');

      final result = await _channel.invokeMethod<String>(
        'exportVideoWithOverlay',
        {
          'videoPath': videoPath,
          'overlayImagePath': overlayPath,
          'outputPath': outputPath,
          'mirrorHorizontally': mirrorHorizontally,
          'outputWidth': outputWidth,
          'outputHeight': outputHeight,
          'filterPreset': filterPreset,
          'filterStrength': filterStrength,
        },
      );

      // Clean up overlay temp file
      try {
        await overlayFile.delete();
      } catch (_) {}

      if (result != null) {
        final outputFile = File(result);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          debugPrint('VideoOverlayProcessor: Success! '
              'Size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
          return result;
        }
      }

      _lastExportError = 'Native export returned no output file path.';
      debugPrint('VideoOverlayProcessor: $_lastExportError');
      return null;
    } on PlatformException catch (e) {
      final details = [
        if (e.code.isNotEmpty) 'code=${e.code}',
        if (e.message != null && e.message!.isNotEmpty) 'message=${e.message}',
        if (e.details != null) 'details=${e.details}',
      ].join(', ');
      _lastExportError = details.isEmpty ? 'PlatformException with no details.' : details;
      debugPrint('VideoOverlayProcessor: Platform error: $_lastExportError');
      return null;
    } catch (e) {
      _lastExportError = e.toString();
      debugPrint('VideoOverlayProcessor: Error: $_lastExportError');
      return null;
    }
  }

  /// Starts a video export in the background and returns the predetermined output path
  /// immediately (~10ms for temp dir lookup + overlay PNG write).
  ///
  /// The native export runs asynchronously. Access [pendingExportFuture] to track completion.
  /// Callers can navigate away immediately and await [pendingExportFuture] before uploading.
  static Future<String> startExportInBackground({
    required String videoPath,
    required Uint8List overlayPngBytes,
    bool mirrorHorizontally = false,
    int? outputWidth,
    int? outputHeight,
    String filterPreset = 'none',
    double filterStrength = 1.0,
  }) async {
    _lastExportError = null;
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final overlayPath = '${tempDir.path}/overlay_$timestamp.png';
    final outputPath = '${tempDir.path}/story_video_$timestamp.mp4';

    // Write overlay PNG synchronously before firing the native call (~5–15ms)
    await File(overlayPath).writeAsBytes(overlayPngBytes);
    debugPrint('VideoOverlayProcessor: Overlay written, firing background export → $outputPath');

    _pendingExportRawVideoPath = videoPath; // saved for instant preview in detail screens

    // Start native export and store the future — callers await pendingExportFuture
    _pendingExportFuture = _runNativeExport(
      videoPath: videoPath,
      overlayPath: overlayPath,
      outputPath: outputPath,
      mirrorHorizontally: mirrorHorizontally,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
      filterPreset: filterPreset,
      filterStrength: filterStrength,
    );

    return outputPath;
  }

  static Future<String?> _runNativeExport({
    required String videoPath,
    required String overlayPath,
    required String outputPath,
    required bool mirrorHorizontally,
    int? outputWidth,
    int? outputHeight,
    required String filterPreset,
    required double filterStrength,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'exportVideoWithOverlay',
        {
          'videoPath': videoPath,
          'overlayImagePath': overlayPath,
          'outputPath': outputPath,
          'mirrorHorizontally': mirrorHorizontally,
          'outputWidth': outputWidth,
          'outputHeight': outputHeight,
          'filterPreset': filterPreset,
          'filterStrength': filterStrength,
        },
      );
      try { await File(overlayPath).delete(); } catch (_) {}
      if (result != null && await File(result).exists()) {
        debugPrint('VideoOverlayProcessor: Background export done → $result');
        return result;
      }
      _lastExportError = 'Native export returned no output file path.';
      return null;
    } on PlatformException catch (e) {
      _lastExportError = e.message ?? 'PlatformException';
      debugPrint('VideoOverlayProcessor: Background export failed: $_lastExportError');
      return null;
    } catch (e) {
      _lastExportError = e.toString();
      debugPrint('VideoOverlayProcessor: Background export error: $_lastExportError');
      return null;
    }
  }
}
