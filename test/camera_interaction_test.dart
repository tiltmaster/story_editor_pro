import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/src/camera_interaction.dart';
import 'package:story_editor_pro/src/native_story_camera_controller.dart';

void main() {
  test('recording locks toward the visible lock in each reading direction', () {
    for (final rtl in [false, true]) {
      final gesture = CameraRecordGesture()..begin(const Offset(150, 400));
      expect(gesture.stopOnRelease, isTrue);
      expect(
        gesture.move(const Offset(150, 250), rtl: rtl),
        isFalse,
        reason: 'Vertical zoom must not lock recording',
      );
      expect(gesture.move(Offset(rtl ? 220 : 80, 380), rtl: rtl), isTrue);
      expect(gesture.stopOnRelease, isFalse);
      expect(gesture.move(const Offset(150, 400), rtl: rtl), isFalse);
      expect(
        gesture.locked,
        isTrue,
        reason: 'Lock survives lifting the finger',
      );
      gesture.reset();
      expect(gesture.stopOnRelease, isTrue);
    }
  });

  test('focus removes cover scale before undoing front preview mirroring', () {
    expect(
      cameraFocusCoordinates(
        const Offset(.1, .8),
        coverScale: const Offset(2, 2),
        mirrored: false,
      ),
      const Offset(.3, .65),
    );
    expect(
      cameraFocusCoordinates(
        const Offset(.1, .8),
        coverScale: const Offset(2, 2),
        mirrored: true,
      ),
      const Offset(.7, .65),
    );
    expect(
      cameraFocusCoordinates(
        const Offset(.5, .5),
        coverScale: const Offset(3, 3),
        mirrored: true,
      ),
      const Offset(.5, .5),
    );
  });

  test(
    'cover fitting preserves aspect and clips only the overflowing axis',
    () {
      final wide = cameraPreviewCoverScale(
        const Size(320, 480),
        portraitAspect: 9 / 16,
      );
      expect(wide.dx, 1);
      expect(wide.dy, closeTo(32 / 27, .0001));
      final point = cameraFocusCoordinates(
        const Offset(.1, .8),
        coverScale: wide,
        mirrored: false,
      );
      expect(point.dx, closeTo(.1, .0001));
      expect(point.dy, closeTo(.753125, .0001));
      final tall = cameraPreviewCoverScale(
        const Size(320, 700),
        portraitAspect: 9 / 16,
      );
      expect(tall.dx, greaterThan(1));
      expect(tall.dy, 1);
    },
  );

  test('missing hardware controls do not invent zoom or exposure support', () {
    final controls = NativeCameraControls.fromMap({});
    expect(controls.minZoom, controls.maxZoom);
    expect(controls.exposure, isFalse);
    expect(controls.focus, isFalse);
    final invalid = NativeCameraControls.fromMap({
      'minZoom': double.nan,
      'maxZoom': double.infinity,
    });
    expect(invalid.minZoom, 1);
    expect(invalid.maxZoom, 1);
  });
}
