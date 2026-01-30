import 'package:shared_preferences/shared_preferences.dart';

/// Settings storage for Story Editor Pro
/// Uses SharedPreferences internally - no external configuration needed
class StoryEditorSettings {
  /// Initial value for front camera default setting
  final bool initialFrontCameraDefault;

  /// Initial value for tools on left setting
  final bool initialToolsOnLeft;

  const StoryEditorSettings({
    this.initialFrontCameraDefault = false,
    this.initialToolsOnLeft = false,
  });

  // ============ Setting Keys ============
  static const String _keyFrontCameraDefault = 'story_editor_front_camera_default';
  static const String _keyCameraToolsOnLeft = 'story_editor_camera_tools_on_left';

  // ============ Front Camera Default ============

  /// Get front camera default setting
  Future<bool> getFrontCameraDefault() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFrontCameraDefault) ?? initialFrontCameraDefault;
  }

  /// Set front camera default setting
  Future<void> setFrontCameraDefault(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFrontCameraDefault, value);
  }

  // ============ Tools Position ============

  /// Get tools on left setting
  Future<bool> getToolsOnLeft() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCameraToolsOnLeft) ?? initialToolsOnLeft;
  }

  /// Set tools on left setting
  Future<void> setToolsOnLeft(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCameraToolsOnLeft, value);
  }
}
