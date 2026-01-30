import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'flutter_camera_controller.dart';

/// Flutter camera paketi ile tam ekran kamera önizleme widget'ı.
///
/// Instagram kalitesinde, bozulmasız tam ekran önizleme sağlar.
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

    // Tam ekran, bozulmasız önizleme
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.of(context).size;
        final screenAspectRatio = screenSize.width / screenSize.height;
        final cameraAspectRatio = cameraController.value.aspectRatio;

        // Scale hesaplama: görüntüyü ekrana sığdır ve crop yap
        // Kısa kenar ekrana oturur, uzun kenar taşar (bozulma olmaz)
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
