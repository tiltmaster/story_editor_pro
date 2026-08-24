import 'package:flutter_test/flutter_test.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  test('camera slider geometry and snapping scale contract stay fixed', () {
    expect(CameraFilterSliderContract.viewportFraction, 0.18);
    expect(CameraFilterSliderContract.pageSnapping, isTrue);
    expect(CameraFilterSliderContract.integratedControlHeight, 126);
    expect(CameraFilterSliderContract.selectorHeight, 108);
    expect(CameraFilterSliderContract.bubbleSize, 52);
    expect(CameraFilterSliderContract.itemHeight, 96);
    expect(CameraFilterSliderContract.itemHorizontalPadding, 7);
    expect(CameraFilterSliderContract.scaleForDistance(0), 1.04);
    expect(CameraFilterSliderContract.scaleForDistance(1), 0.82);
    expect(CameraFilterSliderContract.isSelected(0.49), isTrue);
    expect(CameraFilterSliderContract.isSelected(0.5), isFalse);
    expect(
      CameraFilterSliderContract.swipeAnimationDuration,
      const Duration(milliseconds: 180),
    );
  });

  test('glasses append without changing any existing filter index', () {
    final unsupported = StoryEditorFilters.cameraPresetsFor(
      supportsClassicGlasses: false,
    );
    final supported = StoryEditorFilters.cameraPresetsFor(
      supportedNativeLensIds: NativeArLensIds.glasses,
    );

    expect(unsupported, same(StoryEditorFilters.presets));
    expect(supported.length, StoryEditorFilters.presets.length + 3);
    expect(
      supported.take(StoryEditorFilters.presets.length),
      orderedEquals(StoryEditorFilters.presets),
    );
    expect(
      supported
          .skip(StoryEditorFilters.presets.length)
          .map((preset) => preset.id),
      orderedEquals(<String>[
        NativeArLensIds.classicGlasses,
        NativeArLensIds.aviatorGold,
        NativeArLensIds.visorCyan,
      ]),
    );
  });

  test('legacy capability flag exposes only classic glasses', () {
    final supported = StoryEditorFilters.cameraPresetsFor(
      supportsClassicGlasses: true,
    );

    expect(supported.length, StoryEditorFilters.presets.length + 1);
    expect(supported.last.id, NativeArLensIds.classicGlasses);
  });

  test('classic glasses label is localized for English and Arabic', () {
    const strings = StoryEditorStrings();

    expect(
      strings.filterNameForPreset(
        NativeArLensIds.classicGlasses,
        languageCode: 'en',
      ),
      'Classic Glasses',
    );
    expect(
      strings.filterNameForPreset(
        NativeArLensIds.classicGlasses,
        languageCode: 'ar',
      ),
      'نظارات كلاسيكية',
    );
  });

  test('new authored glasses labels are localized for English and Arabic', () {
    const strings = StoryEditorStrings();

    expect(
      strings.filterNameForPreset(NativeArLensIds.aviatorGold),
      'Aviator Gold',
    );
    expect(
      strings.filterNameForPreset(
        NativeArLensIds.aviatorGold,
        languageCode: 'ar',
      ),
      'نظارات طيار ذهبية',
    );
    expect(
      strings.filterNameForPreset(NativeArLensIds.visorCyan),
      'Cyan Visor',
    );
    expect(
      strings.filterNameForPreset(
        NativeArLensIds.visorCyan,
        languageCode: 'ar',
      ),
      'قناع سماوي',
    );
  });
}
