import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'glasses_mesh.dart';
import 'glasses_pose.dart';

typedef GlassesOutputDirectoryProvider = Future<Directory> Function();

/// Bakes the exact tracked 3D glasses pose into a captured still before the
/// editor opens. Failure is non-destructive: the original capture is returned.
class GlassesCaptureCompositor {
  static const String outputPrefix = 'story_glasses_';

  GlassesCaptureCompositor({
    GlassesMeshRepository? repository,
    GlassesOutputDirectoryProvider? outputDirectoryProvider,
  }) : _repository = repository ?? GlassesMeshRepository(),
       _outputDirectoryProvider =
           outputDirectoryProvider ?? getTemporaryDirectory;

  final GlassesMeshRepository _repository;
  final GlassesOutputDirectoryProvider _outputDirectoryProvider;

  Future<String> composite({
    required String imagePath,
    required GlassesPose pose,
    required Size previewViewport,
  }) async {
    ui.Codec? codec;
    ui.Image? source;
    ui.Image? result;
    try {
      final mesh = await _repository.load();
      if (mesh == null || !mesh.isRenderable) return imagePath;
      final bytes = await File(imagePath).readAsBytes();
      codec = await ui.instantiateImageCodec(bytes);
      source = (await codec.getNextFrame()).image;
      final imageSize = Size(source.width.toDouble(), source.height.toDouble());
      final capturePose = GlassesCaptureTransform(
        viewportSize: previewViewport,
        imageSize: imageSize,
        previewMirrored: pose.mirrored,
      ).poseToImage(pose);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(source, Offset.zero, Paint());
      GlassesMeshPainter.paintMesh(
        canvas,
        imageSize,
        mesh,
        capturePose,
        normalizedCoordinates: false,
      );
      final picture = recorder.endRecording();
      result = await picture.toImage(source.width, source.height);
      picture.dispose();
      final encoded = await result.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null) return imagePath;
      final output = await _outputFile();
      await output.writeAsBytes(
        encoded.buffer.asUint8List(
          encoded.offsetInBytes,
          encoded.lengthInBytes,
        ),
        flush: true,
      );
      return output.path;
    } catch (error) {
      assert(() {
        debugPrint('Glasses capture compositing unavailable: $error');
        return true;
      }());
      return imagePath;
    } finally {
      result?.dispose();
      source?.dispose();
      codec?.dispose();
    }
  }

  Future<File> _outputFile() async {
    final directory = await _outputDirectoryProvider();
    return File(
      '${directory.path}${Platform.pathSeparator}'
      '$outputPrefix${DateTime.now().microsecondsSinceEpoch}.png',
    );
  }

  /// Deletes only compositor-owned cache output. Original camera files are
  /// never eligible, even when a caller accidentally passes their path.
  Future<bool> deleteManagedOutput(String path) async {
    final directory = await _outputDirectoryProvider();
    final file = File(path);
    final parent = file.parent.absolute.path.toLowerCase();
    final expectedParent = directory.absolute.path.toLowerCase();
    final name = file.uri.pathSegments.last;
    if (parent != expectedParent ||
        !name.startsWith(outputPrefix) ||
        !name.endsWith('.png')) {
      return false;
    }
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }
}
