import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  test('front camera defaults to a selfie-mirrored live preview', () {
    expect(const StoryEditorConfig().mirrorFrontCameraPreview, isTrue);
  });

  test('selfie mirroring is presentation-only, not applied to saved media', () {
    final source = File('lib/src/story_camera_screen.dart').readAsStringSync();

    expect(
      RegExp(
        r'isFrontCamera && config\.mirrorFrontCameraPreview',
      ).allMatches(source).length,
      2,
    );
    expect(source, isNot(contains('!config.mirrorFrontCameraPreview')));
    expect(
      RegExp(r'flipHorizontally: false').allMatches(source).length,
      greaterThanOrEqualTo(4),
    );
  });

  test(
    'denied camera permission exits pushed route and retry requests again',
    () {
      final source = File(
        'lib/src/story_camera_screen.dart',
      ).readAsStringSync();

      expect(source, contains('await Permission.camera.request()'));
      expect(source, contains('Navigator.of(context).maybePop()'));
      expect(source, contains('onPressed: _requestPermissionsAndInitialize'));
    },
  );
}
