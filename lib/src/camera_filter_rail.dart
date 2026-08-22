import 'config/story_editor_filters.dart';

/// Unified, stable ordering for the camera's legacy looks and live AR effects.
class CameraFilterRailCatalog {
  const CameraFilterRailCatalog._();

  static const StoryFilterPreset glasses = StoryFilterPreset(
    id: 'ar_glasses',
    name: 'Glasses',
  );

  static List<StoryFilterPreset> get presets => <StoryFilterPreset>[
    ...StoryEditorFilters.presets,
    ...StoryEditorFilters.arPresets,
    glasses,
  ];

  static bool isArIndex(int index) =>
      index >= StoryEditorFilters.presets.length &&
      index <
          StoryEditorFilters.presets.length +
              StoryEditorFilters.arPresets.length;

  static bool isGlassesIndex(int index) => index == presets.length - 1;
}
