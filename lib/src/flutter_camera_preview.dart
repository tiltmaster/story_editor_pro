import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'flutter_camera_controller.dart';

/// Fullscreen camera preview widget with Flutter camera package.
///
/// Provides Instagram quality, distortion-free fullscreen preview.
class FlutterCameraPreview extends StatelessWidget {
  final FlutterCameraController controller;

  const FlutterCameraPreview({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.isInitialized || controller.controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final cameraController = controller.controller!;

    // Fullscreen, distortion-free preview
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.of(context).size;
        final screenAspectRatio = screenSize.width / screenSize.height;
        final cameraAspectRatio = cameraController.value.aspectRatio;

        // Scale calculation: fit image to screen and crop
        // Short edge fits screen, long edge overflows (no distortion)
        var scale = screenAspectRatio * cameraAspectRatio;
        if (scale < 1) scale = 1 / scale;

        return ClipRect(
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Center(
              child: CameraPreview(cameraController),
            ),
          ),
        );
      },
    );
  }
}
