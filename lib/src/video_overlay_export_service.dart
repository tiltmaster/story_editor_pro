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

  static void validateTrimRange(int trimStartMs, int trimEndMs) {
    if (trimStartMs < 0 || trimEndMs < 0) {
      throw ArgumentError('Video trim values cannot be negative.');
    }
    if (trimEndMs > 0 && trimEndMs <= trimStartMs) {
      throw ArgumentError('Video trim end must be after its start.');
    }
  }

  /// Export video with overlay PNG baked in.
  ///
  /// [videoPath]: Original video file path
  /// [overlayPngBytes]: PNG image bytes (transparent background, only overlays)
  /// [animatedStickers]: Animated GIF layers composited natively per frame so
  /// they stay animated in the output. Each map: {path, left, top, width,
  /// height} — rect normalized (0..1) to the overlay PNG, top-left origin.
  /// Returns: Path to the exported MP4 file, or null on failure
  static Future<String?> exportVideoWithOverlay({
    required String videoPath,
    required Uint8List overlayPngBytes,
    List<Map<String, dynamic>> animatedStickers = const [],
    bool mirrorHorizontally = false,
    int? outputWidth,
    int? outputHeight,
    String filterPreset = 'none',
    double filterStrength = 1.0,
    double beautyStrength = 0,
    double beautyEyes = 0,
    double beautySlim = 0,
    List<Map<String, double>> faceTimeline = const [],
    double mediaScale = 1,
    double mediaOffsetX = 0,
    double mediaOffsetY = 0,
    bool shouldMuteAudio = false,
    int trimStartMs = 0,
    int trimEndMs = 0,
  }) async {
    validateTrimRange(trimStartMs, trimEndMs);
    _lastExportError = null;
    File? overlayFile;
    try {
      final sw = Stopwatch()..start();
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final overlayPath = '${tempDir.path}/overlay_$timestamp.png';
      final outputPath = '${tempDir.path}/story_video_$timestamp.mp4';

      overlayFile = File(overlayPath);
      await overlayFile.writeAsBytes(overlayPngBytes);
      debugPrint(
        'VideoOverlayProcessor: Overlay PNG written in ${sw.elapsedMilliseconds}ms (${(overlayPngBytes.length / 1024).toStringAsFixed(0)}KB)',
      );

      debugPrint('VideoOverlayProcessor: Starting native export...');

      final result = await _channel
          .invokeMethod<String>('exportVideoWithOverlay', {
            'videoPath': videoPath,
            'overlayImagePath': overlayPath,
            'outputPath': outputPath,
            'animatedStickers': animatedStickers,
            'mirrorHorizontally': mirrorHorizontally,
            'outputWidth': outputWidth,
            'outputHeight': outputHeight,
            'filterPreset': filterPreset,
            'filterStrength': filterStrength,
            'beautyStrength': beautyStrength.isFinite
                ? beautyStrength.clamp(0, 1)
                : 0,
            'beautyEyes': beautyEyes.isFinite ? beautyEyes.clamp(0, 1) : 0,
            'beautySlim': beautySlim.isFinite ? beautySlim.clamp(0, 1) : 0,
            'faceTimeline': faceTimeline,
            'mediaScale': mediaScale.isFinite ? mediaScale.clamp(.5, 5) : 1.0,
            'mediaOffsetX': mediaOffsetX.isFinite ? mediaOffsetX : 0.0,
            'mediaOffsetY': mediaOffsetY.isFinite ? mediaOffsetY : 0.0,
            'shouldMuteAudio': shouldMuteAudio,
            'trimStartMs': trimStartMs,
            'trimEndMs': trimEndMs,
          });

      if (result != null) {
        final outputFile = File(result);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          debugPrint(
            'VideoOverlayProcessor: Success! '
            'Size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
          );
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
      _lastExportError = details.isEmpty
          ? 'PlatformException with no details.'
          : details;
      debugPrint('VideoOverlayProcessor: Platform error: $_lastExportError');
      return null;
    } catch (_) {
      _lastExportError = 'Unexpected video export failure.';
      debugPrint('VideoOverlayProcessor: Error: $_lastExportError');
      return null;
    } finally {
      await _deleteTempFile(overlayFile);
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
    List<Map<String, dynamic>> animatedStickers = const [],
    bool mirrorHorizontally = false,
    int? outputWidth,
    int? outputHeight,
    String filterPreset = 'none',
    double filterStrength = 1.0,
    double beautyStrength = 0,
    double beautyEyes = 0,
    double beautySlim = 0,
    List<Map<String, double>> faceTimeline = const [],
    double mediaScale = 1,
    double mediaOffsetX = 0,
    double mediaOffsetY = 0,
    bool shouldMuteAudio = false,
    int trimStartMs = 0,
    int trimEndMs = 0,
  }) async {
    validateTrimRange(trimStartMs, trimEndMs);
    _lastExportError = null;
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final overlayPath = '${tempDir.path}/overlay_$timestamp.png';
    final outputPath = '${tempDir.path}/story_video_$timestamp.mp4';

    // Write overlay PNG synchronously before firing the native call (~5–15ms)
    await File(overlayPath).writeAsBytes(overlayPngBytes);
    debugPrint(
      'VideoOverlayProcessor: Overlay written; firing background export',
    );

    _pendingExportRawVideoPath =
        videoPath; // saved for instant preview in detail screens

    // Start native export and store the future — callers await pendingExportFuture
    _pendingExportFuture = _runNativeExport(
      videoPath: videoPath,
      overlayPath: overlayPath,
      outputPath: outputPath,
      animatedStickers: animatedStickers,
      mirrorHorizontally: mirrorHorizontally,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
      filterPreset: filterPreset,
      filterStrength: filterStrength,
      beautyStrength: beautyStrength,
      beautyEyes: beautyEyes,
      beautySlim: beautySlim,
      faceTimeline: faceTimeline,
      mediaScale: mediaScale,
      mediaOffsetX: mediaOffsetX,
      mediaOffsetY: mediaOffsetY,
      shouldMuteAudio: shouldMuteAudio,
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs,
    );

    return outputPath;
  }

  static Future<String?> _runNativeExport({
    required String videoPath,
    required String overlayPath,
    required String outputPath,
    List<Map<String, dynamic>> animatedStickers = const [],
    required bool mirrorHorizontally,
    int? outputWidth,
    int? outputHeight,
    required String filterPreset,
    required double filterStrength,
    required double beautyStrength,
    required double beautyEyes,
    required double beautySlim,
    required List<Map<String, double>> faceTimeline,
    required double mediaScale,
    required double mediaOffsetX,
    required double mediaOffsetY,
    required bool shouldMuteAudio,
    required int trimStartMs,
    required int trimEndMs,
  }) async {
    try {
      final result = await _channel
          .invokeMethod<String>('exportVideoWithOverlay', {
            'videoPath': videoPath,
            'overlayImagePath': overlayPath,
            'outputPath': outputPath,
            'animatedStickers': animatedStickers,
            'mirrorHorizontally': mirrorHorizontally,
            'outputWidth': outputWidth,
            'outputHeight': outputHeight,
            'filterPreset': filterPreset,
            'filterStrength': filterStrength,
            'beautyStrength': beautyStrength.isFinite
                ? beautyStrength.clamp(0, 1)
                : 0,
            'beautyEyes': beautyEyes.isFinite ? beautyEyes.clamp(0, 1) : 0,
            'beautySlim': beautySlim.isFinite ? beautySlim.clamp(0, 1) : 0,
            'faceTimeline': faceTimeline,
            'mediaScale': mediaScale.isFinite ? mediaScale.clamp(.5, 5) : 1.0,
            'mediaOffsetX': mediaOffsetX.isFinite ? mediaOffsetX : 0.0,
            'mediaOffsetY': mediaOffsetY.isFinite ? mediaOffsetY : 0.0,
            'shouldMuteAudio': shouldMuteAudio,
            'trimStartMs': trimStartMs,
            'trimEndMs': trimEndMs,
          });
      if (result != null && await File(result).exists()) {
        debugPrint('VideoOverlayProcessor: Background export completed');
        return result;
      }
      _lastExportError = 'Native export returned no output file path.';
      return null;
    } on PlatformException catch (e) {
      _lastExportError = e.message ?? 'PlatformException';
      debugPrint(
        'VideoOverlayProcessor: Background export failed: $_lastExportError',
      );
      return null;
    } catch (_) {
      _lastExportError = 'Unexpected video export failure.';
      debugPrint(
        'VideoOverlayProcessor: Background export error: $_lastExportError',
      );
      return null;
    } finally {
      await _deleteTempFile(File(overlayPath));
    }
  }

  static Future<void> _deleteTempFile(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The platform temp directory is OS-managed; a later cache sweep can
      // remove a file that was locked by the native exporter.
    }
  }
}
