import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  test('front camera defaults to unmirrored anatomical handedness', () {
    expect(const StoryEditorConfig().mirrorFrontCameraPreview, isFalse);
  });

  test('front handedness is backend-aware and preserved in saved media', () {
    final source = File('lib/src/story_camera_screen.dart').readAsStringSync();

    expect(source, contains('Transform.flip(flipX: true, child: preview)'));
    expect(source, contains('wantsMirroredPreview != backendAlreadyMirrored'));
    expect(
      RegExp(r'_presentCameraPreview\(').allMatches(source).length,
      greaterThanOrEqualTo(4),
    );
    expect(
      RegExp(
        r'flipHorizontally: capturedFlipHorizontally',
      ).allMatches(source).length,
      greaterThanOrEqualTo(4),
    );
    final switchCamera = source.substring(
      source.indexOf('Future<void> _switchCamera()'),
      source.indexOf('Future<void> _toggleFlash()'),
    );
    expect(switchCamera, contains('await _applyNativeArSelection()'));
    expect(
      RegExp(r'_finalizeVideoWithoutEditor\(').allMatches(source).length,
      greaterThanOrEqualTo(4),
    );
    expect(source, contains('mirrorHorizontally: flipHorizontally'));
    expect(source, contains('_finalizePhotoForRawConsumer('));
    expect(source, isNot(contains('onImageCaptured?.call(imagePath)')));
    expect(source, contains('bool get _filterSelectionLocked'));
    expect(source, contains('const NeverScrollableScrollPhysics()'));
    final takePicture = source.substring(
      source.indexOf('Future<void> _takePicture()'),
      source.indexOf('Future<void> _handleLayoutCapture('),
    );
    expect(takePicture, contains('await _applyNativeArSelection()'));
  });

  test('host-managed permission never auto-pops or requests twice', () {
    final source = File('lib/src/story_camera_screen.dart').readAsStringSync();

    expect(source, contains('await Permission.camera.request()'));
    expect(source, contains('config.cameraPermissionManagedByHost'));
    expect(source, contains('await openAppSettings()'));
    expect(source, isNot(contains('Navigator.of(context).maybePop()')));
  });
}
