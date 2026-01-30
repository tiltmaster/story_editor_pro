import 'package:flutter/material.dart';
import 'story_editor_strings.dart';
import 'story_editor_theme.dart';
import 'story_editor_fonts.dart';
import 'story_editor_settings.dart';

/// Main configuration class for Story Editor Pro
/// Pass this to StoryEditorConfigProvider to customize the entire plugin
class StoryEditorConfig {
  /// Localization strings (English defaults)
  final StoryEditorStrings strings;

  /// Theme configuration (colors, icons, gradients)
  final StoryEditorTheme theme;

  /// Font configuration
  final StoryEditorFonts fonts;

  /// Settings callbacks (replaces SharedPreferences)
  final StoryEditorSettings settings;

  // ============ Hands-Free Configuration ============

  /// Available delay options for hands-free mode (in seconds)
  final List<int> handsFreeDelayOptions;

  /// Default hands-free delay in seconds
  final int defaultHandsFreeDelay;

  /// Maximum hands-free recording duration in seconds
  final int maxHandsFreeRecordingSeconds;

  // ============ Video Configuration ============

  /// Maximum video recording duration in seconds
  final int maxVideoRecordingSeconds;

  // ============ Boomerang Configuration ============

  /// Maximum boomerang recording duration in seconds
  final int maxBoomerangSeconds;

  // ============ Gradient Configuration ============

  /// Default gradient balance (0.0 to 1.0)
  /// 0.5 means 50%/50% color distribution
  final double defaultGradientBalance;

  const StoryEditorConfig({
    this.strings = const StoryEditorStrings(),
    this.theme = const StoryEditorTheme(),
    this.fonts = const StoryEditorFonts(),
    this.settings = const StoryEditorSettings(),
    this.handsFreeDelayOptions = const [3, 5, 10, 15],
    this.defaultHandsFreeDelay = 3,
    this.maxHandsFreeRecordingSeconds = 60,
    this.maxVideoRecordingSeconds = 60,
    this.maxBoomerangSeconds = 4,
    this.defaultGradientBalance = 0.5,
  });

  /// Create a copy with modified values
  StoryEditorConfig copyWith({
    StoryEditorStrings? strings,
    StoryEditorTheme? theme,
    StoryEditorFonts? fonts,
    StoryEditorSettings? settings,
    List<int>? handsFreeDelayOptions,
    int? defaultHandsFreeDelay,
    int? maxHandsFreeRecordingSeconds,
    int? maxVideoRecordingSeconds,
    int? maxBoomerangSeconds,
    double? defaultGradientBalance,
  }) {
    return StoryEditorConfig(
      strings: strings ?? this.strings,
      theme: theme ?? this.theme,
      fonts: fonts ?? this.fonts,
      settings: settings ?? this.settings,
      handsFreeDelayOptions: handsFreeDelayOptions ?? this.handsFreeDelayOptions,
      defaultHandsFreeDelay: defaultHandsFreeDelay ?? this.defaultHandsFreeDelay,
      maxHandsFreeRecordingSeconds: maxHandsFreeRecordingSeconds ?? this.maxHandsFreeRecordingSeconds,
      maxVideoRecordingSeconds: maxVideoRecordingSeconds ?? this.maxVideoRecordingSeconds,
      maxBoomerangSeconds: maxBoomerangSeconds ?? this.maxBoomerangSeconds,
      defaultGradientBalance: defaultGradientBalance ?? this.defaultGradientBalance,
    );
  }
}

/// InheritedWidget to provide StoryEditorConfig to the widget tree
class StoryEditorConfigProvider extends InheritedWidget {
  /// The configuration to provide
  final StoryEditorConfig config;

  const StoryEditorConfigProvider({
    super.key,
    required this.config,
    required super.child,
  });

  /// Get the config from context
  static StoryEditorConfig of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<StoryEditorConfigProvider>();
    return provider?.config ?? const StoryEditorConfig();
  }

  /// Get the config from context without listening to changes
  static StoryEditorConfig read(BuildContext context) {
    final provider = context.getInheritedWidgetOfExactType<StoryEditorConfigProvider>();
    return provider?.config ?? const StoryEditorConfig();
  }

  @override
  bool updateShouldNotify(StoryEditorConfigProvider oldWidget) {
    return config != oldWidget.config;
  }
}

/// Extension for easy access to config from BuildContext
extension StoryEditorConfigExtension on BuildContext {
  /// Get the full config
  StoryEditorConfig get storyEditorConfig => StoryEditorConfigProvider.of(this);

  /// Get localization strings
  StoryEditorStrings get storyStrings => storyEditorConfig.strings;

  /// Get theme configuration
  StoryEditorTheme get storyTheme => storyEditorConfig.theme;

  /// Get fonts configuration
  StoryEditorFonts get storyFonts => storyEditorConfig.fonts;

  /// Get settings callbacks
  StoryEditorSettings get storySettings => storyEditorConfig.settings;
}
