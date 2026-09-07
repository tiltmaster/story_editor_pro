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

  test(
    'retired glasses never appear even when a host reports old capabilities',
    () {
      final unsupported = StoryEditorFilters.cameraPresetsFor();
      final legacyHost = StoryEditorFilters.cameraPresetsFor(
        supportedNativeLensIds: {NativeArLensIds.classicGlasses},
      );
      expect(unsupported, same(StoryEditorFilters.presets));
      expect(legacyHost, orderedEquals(StoryEditorFilters.presets));
      expect(
        legacyHost.map((preset) => preset.id),
        isNot(contains(NativeArLensIds.classicGlasses)),
      );
      expect(
        StoryEditorFilters.isNativeLens(NativeArLensIds.classicGlasses),
        isFalse,
      );
      expect(
        NativeArLensIds.all,
        isNot(contains(NativeArLensIds.classicGlasses)),
      );
    },
  );

  test('legacy glasses flag cannot re-enable the removed lens', () {
    final supported = StoryEditorFilters.cameraPresetsFor(
      supportsClassicGlasses: true,
    );
    expect(supported, orderedEquals(StoryEditorFilters.presets));
    expect(StoryEditorFilters.nativeLensPresets, isEmpty);
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

  test('authored effect labels are available without lens placeholders', () {
    const strings = StoryEditorStrings();

    expect(strings.filterNameForPreset('daytime'), 'Golden Bloom');
    expect(strings.filterNameForPreset('timefocus'), 'Studio Glow');
    expect(strings.filterNameForPreset('retrodate'), 'Film Aura');
  });
}
