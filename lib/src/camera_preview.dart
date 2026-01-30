import 'package:flutter/material.dart';
import 'camera_controller.dart';

class CameraPreview extends StatelessWidget {
  final CameraController controller;
  final BoxFit fit;

  const CameraPreview({
    super.key,
    required this.controller,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.isInitialized || controller.textureId == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: FittedBox(
            fit: fit,
            child: SizedBox(
              width: controller.previewWidth?.toDouble() ?? constraints.maxWidth,
              height: controller.previewHeight?.toDouble() ?? constraints.maxHeight,
              child: Texture(textureId: controller.textureId!),
            ),
          ),
        );
      },
    );
  }
}
