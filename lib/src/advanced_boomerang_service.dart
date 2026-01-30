import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';

/// Instagram Boomerang algoritmasını birebir simüle eden servis.
///
/// Pipeline (Optimized):
/// 1. Input & Trim (max 1 saniye)
/// 2. Speed Manipulation (2x hızlandırma)
/// 3. Boomerang Logic (ileri + geri)
/// 4. Loop (3x tekrar) & Audio removal
///
/// NOT: Stabilizasyon kaldırıldı (performans için)
class AdvancedBoomerangService {
  /// Boomerang işlemi için progress callback
  final void Function(double progress)? onProgress;

  /// Hızlandırma faktörü (2.0 = 2x hız)
  final double speedFactor;

  /// Loop sayısı (3 = ileri-geri sekansı 3 kez tekrarlanır)
  final int loopCount;

  /// Maximum input süresi (saniye)
  final double maxInputDuration;

  /// Çıktı video kalitesi (CRF: 0-51, düşük = yüksek kalite)
  /// 23 = default, iyi denge
  final int outputQuality;

  /// Çıktı FPS
  final int outputFps;

  AdvancedBoomerangService({
    this.onProgress,
    this.speedFactor = 2.0,
    this.loopCount = 3,
    this.maxInputDuration = 1.0,
    this.outputQuality = 23,
    this.outputFps = 30,
  });

  /// Instagram tarzı Boomerang videosu oluşturur.
  ///
  /// [inputVideo]: Kaynak video dosyası (max 1 saniye önerilir)
  ///
  /// Returns: İşlenmiş boomerang video dosyası veya hata durumunda null
  Future<File?> generateBoomerang(File inputVideo) async {
    if (!await inputVideo.exists()) {
      debugPrint('AdvancedBoomerangService: Input video does not exist');
      return null;
    }

    try {
      // Çıktı dosya yolunu oluştur
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/boomerang_advanced_$timestamp.mp4';

      // Video bilgilerini al (boyut için)
      final probeResult = await _getVideoInfo(inputVideo.path);
      if (probeResult == null) {
        debugPrint('AdvancedBoomerangService: Failed to probe video');
        return null;
      }

      final int width = probeResult['width'] ?? 1080;
      final int height = probeResult['height'] ?? 1920;

      // Speed için PTS çarpanı (2x hız = 0.5 PTS)
      final double ptsFactor = 1.0 / speedFactor;

      // FFmpeg filter_complex komutunu oluştur (optimized - stabilizasyon yok)
      final filterComplex = _buildFilterComplex(
        width: width,
        height: height,
        ptsFactor: ptsFactor,
      );

      // FFmpeg komutunu oluştur
      final command = _buildFFmpegCommand(
        inputPath: inputVideo.path,
        outputPath: outputPath,
        filterComplex: filterComplex,
      );

      debugPrint('AdvancedBoomerangService: Executing FFmpeg command');
      debugPrint('Command: $command');

      // Progress callback ayarla
      if (onProgress != null) {
        FFmpegKitConfig.enableStatisticsCallback((Statistics statistics) {
          final time = statistics.getTime();
          // Tahmini toplam süre: (input/speed) * 2 (ileri-geri) * loopCount
          final estimatedTotal = (maxInputDuration / speedFactor) * 2 * loopCount * 1000;
          if (estimatedTotal > 0) {
            final progress = (time / estimatedTotal).clamp(0.0, 1.0);
            onProgress!(progress);
          }
        });
      }

      // FFmpeg'i çalıştır
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          debugPrint('AdvancedBoomerangService: Success! Output size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
          return outputFile;
        }
      }

      // Hata durumunda logları yazdır
      debugPrint('AdvancedBoomerangService: FFmpeg failed with code $returnCode');
      final logs = await session.getLogs();
      for (final log in logs) {
        debugPrint('FFmpeg Log: ${log.getMessage()}');
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('AdvancedBoomerangService: Exception occurred');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
      return null;
    }
  }

  /// Video bilgilerini (width, height, duration) alır
  Future<Map<String, dynamic>?> _getVideoInfo(String videoPath) async {
    try {
      final session = await FFmpegKit.execute(
        '-i "$videoPath" -hide_banner',
      );

      final output = await session.getOutput();
      if (output == null) return null;

      // Regex ile video boyutlarını çıkar
      // Örnek: "Stream #0:0: Video: h264, 1080x1920"
      final sizeRegex = RegExp(r'(\d{2,4})x(\d{2,4})');
      final sizeMatch = sizeRegex.firstMatch(output);

      if (sizeMatch != null) {
        return {
          'width': int.parse(sizeMatch.group(1)!),
          'height': int.parse(sizeMatch.group(2)!),
        };
      }

      // Varsayılan değerler
      return {'width': 1080, 'height': 1920};
    } catch (e) {
      debugPrint('Video probe error: $e');
      return {'width': 1080, 'height': 1920};
    }
  }

  /// FFmpeg filter_complex string'ini oluşturur (OPTIMIZED)
  ///
  /// Pipeline açıklaması:
  /// ```
  /// [0:v] Input video
  ///   ↓
  /// trim=0:1 → Max 1 saniye al
  ///   ↓
  /// setpts=0.5*PTS → 2x hızlandır
  ///   ↓
  /// scale+crop → 9:16 story formatına zorla
  ///   ↓
  /// fps=30 → FPS sabitle
  ///   ↓
  /// split → İki kopya oluştur
  ///   ↓
  /// [copy1] Normal | [copy2] reverse → Ters çevir
  ///   ↓
  /// concat → Birleştir (ileri + geri)
  ///   ↓
  /// loop=3 → 3 kez tekrarla
  ///   ↓
  /// [out] Final output
  /// ```
  String _buildFilterComplex({
    required int width,
    required int height,
    required double ptsFactor,
  }) {
    // Story formatı: 9:16 dikey (1080x1920)
    // Hedef boyut
    const int targetWidth = 1080;
    const int targetHeight = 1920;

    // Input video yatay mı dikey mi?
    final bool isLandscape = width > height;

    String scaleAndCrop;
    if (isLandscape) {
      // Yatay video -> dikeye çevir: önce yüksekliği hedef yüksekliğe scale et, sonra genişlikten crop
      // scale=-2:1920 -> yükseklik 1920, genişlik orantılı
      // crop=1080:1920 -> merkezden 1080x1920 kes
      scaleAndCrop = 'scale=-2:$targetHeight,crop=$targetWidth:$targetHeight';
    } else {
      // Dikey video -> boyutu koru veya 9:16'ya zorla
      // scale=1080:-2 -> genişlik 1080, yükseklik orantılı
      // crop=1080:1920 -> merkezden 1080x1920 kes
      scaleAndCrop = 'scale=$targetWidth:-2,crop=$targetWidth:$targetHeight';
    }

    return '''
[0:v]
trim=start=0:duration=$maxInputDuration,
setpts=$ptsFactor*PTS,
$scaleAndCrop,
fps=$outputFps,
split[fwd][rev];
[rev]reverse[reversed];
[fwd][reversed]concat=n=2:v=1:a=0[boomerang];
[boomerang]loop=loop=${loopCount - 1}:size=1000:start=0[out]
'''
        .replaceAll('\n', '')
        .replaceAll(RegExp(r'\s+'), '');
  }

  /// Tam FFmpeg komutunu oluşturur (OPTIMIZED for speed)
  String _buildFFmpegCommand({
    required String inputPath,
    required String outputPath,
    required String filterComplex,
  }) {
    return '''
-y
-i "$inputPath"
-filter_complex "$filterComplex"
-map "[out]"
-an
-c:v libx264
-preset ultrafast
-tune fastdecode
-crf $outputQuality
-pix_fmt yuv420p
-movflags +faststart
"$outputPath"
'''
        .replaceAll('\n', ' ')
        .trim();
  }

  /// Basit boomerang (sadece ileri-geri, loop yok)
  /// Daha hızlı işlem için kullanılabilir
  Future<File?> generateSimpleBoomerang(File inputVideo) async {
    if (!await inputVideo.exists()) {
      return null;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/boomerang_simple_$timestamp.mp4';

      // 9:16 story formatına zorla + ileri-geri
      // scale=-2:1920 -> yükseklik 1920'ye scale, genişlik orantılı
      // crop=1080:1920 -> merkezden 1080x1920 kes
      const filterComplex =
          '[0:v]setpts=0.5*PTS,scale=-2:1920,crop=1080:1920,split[fwd][rev];[rev]reverse[reversed];[fwd][reversed]concat=n=2:v=1:a=0[out]';

      final command =
          '-y -i "${inputVideo.path}" -filter_complex "$filterComplex" -map "[out]" -an -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p "$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          return outputFile;
        }
      }

      return null;
    } catch (e) {
      debugPrint('Simple boomerang error: $e');
      return null;
    }
  }

  /// Önceden oluşturulmuş boomerang dosyalarını temizler
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
