import 'config/story_editor_filters.dart';

/// Unified, stable ordering for the camera's legacy looks and live AR effects.
class CameraFilterRailCatalog {
  const CameraFilterRailCatalog._();

  static List<StoryFilterPreset> get presets => <StoryFilterPreset>[
    ...StoryEditorFilters.presets,
    ...StoryEditorFilters.arPresets,
  ];

  static bool isArIndex(int index) =>
      index >= StoryEditorFilters.presets.length && index < presets.length;
}
