import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'config/story_editor_config.dart';
import 'config/story_editor_strings.dart';
import 'config/story_editor_theme.dart';

/// Camera settings screen
class CameraSettingsScreen extends StatefulWidget {
  const CameraSettingsScreen({super.key});

  @override
  State<CameraSettingsScreen> createState() => _CameraSettingsScreenState();
}

class _CameraSettingsScreenState extends State<CameraSettingsScreen> {
  bool _frontCameraDefault = false;
  bool _toolsOnLeft = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  Future<void> _loadSettings() async {
    final config = context.storyEditorConfig;
    final frontCamera = await config.settings.getFrontCameraDefault();
    final toolsOnLeft = await config.settings.getToolsOnLeft();
    if (mounted) {
      setState(() {
        _frontCameraDefault = frontCamera;
        _toolsOnLeft = toolsOnLeft;
      });
    }
  }

  Future<void> _saveFrontCameraDefault(bool value) async {
    final config = context.storyEditorConfig;
    await config.settings.setFrontCameraDefault(value);
    setState(() {
      _frontCameraDefault = value;
    });
  }

  Future<void> _saveToolsPosition(bool onLeft) async {
    final config = context.storyEditorConfig;
    await config.settings.setToolsOnLeft(onLeft);
    setState(() {
      _toolsOnLeft = onLeft;
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = context.storyEditorConfig;
    final strings = config.strings;
    final theme = config.theme;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
        title: Text(
          strings.settingsTitle,
          style: TextStyle(
            color: theme.textColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            theme.icons.arrowBackIcon,
            color: theme.textColor,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Controls Section
          _buildSectionHeader(strings.settingsControlsSection, theme),
          const SizedBox(height: 12),
          _buildSwitchTile(
            title: strings.settingsFrontCameraTitle,
            subtitle: strings.settingsFrontCameraSubtitle,
            value: _frontCameraDefault,
            onChanged: _saveFrontCameraDefault,
            theme: theme,
          ),

          const SizedBox(height: 32),

          // Camera Tools Section
          _buildSectionHeader(strings.settingsToolsSection, theme),
          const SizedBox(height: 12),
          _buildToolsPositionSelector(strings, theme),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, StoryEditorTheme theme) {
    return Text(
      title,
      style: TextStyle(
        color: theme.textSecondaryColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required StoryEditorTheme theme,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.hintColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: theme.switchActiveColor,
          ),
        ],
      ),
    );
  }

  Widget _buildToolsPositionSelector(StoryEditorStrings strings, StoryEditorTheme theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.settingsToolbarPositionTitle,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings.settingsToolbarPositionSubtitle,
            style: TextStyle(
              color: theme.hintColor,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildPositionOption(
                  title: strings.settingsLeftSide,
                  isSelected: _toolsOnLeft,
                  onTap: () => _saveToolsPosition(true),
                  theme: theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPositionOption(
                  title: strings.settingsRightSide,
                  isSelected: !_toolsOnLeft,
                  onTap: () => _saveToolsPosition(false),
                  theme: theme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPositionOption({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    required StoryEditorTheme theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.switchActiveColor.withValues(alpha: 0.2)
              : theme.overlayColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? theme.switchActiveColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? theme.switchActiveColor : Colors.white38,
                  width: 2,
                ),
                color: isSelected ? theme.switchActiveColor : Colors.transparent,
              ),
              child: isSelected
                  ? Icon(
                      theme.icons.checkIcon,
                      size: 14,
                      color: theme.textColor,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? theme.textColor : theme.textSecondaryColor,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper class to load camera settings
/// Deprecated: Use StoryEditorConfigProvider.of(context).settings instead
class CameraSettings {
  static Future<bool> getFrontCameraDefault() async {
    // This is now a fallback - users should use config.settings
    return false;
  }

  static Future<bool> getToolsOnLeft() async {
    // This is now a fallback - users should use config.settings
    return false;
  }
}
