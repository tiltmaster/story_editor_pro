import 'package:flutter/material.dart';

/// Configuration for a single font style
class FontStyleConfig {
  /// Display name for this font style
  final String name;

  /// TextStyle for this font (user provides this from their app)
  final TextStyle textStyle;

  const FontStyleConfig({
    required this.name,
    required this.textStyle,
  });

  /// Convert to TextStyle with overrides
  TextStyle toTextStyle({
    double? fontSize,
    Color? color,
    List<Shadow>? shadows,
  }) {
    return textStyle.copyWith(
      fontSize: fontSize,
      color: color,
      shadows: shadows,
    );
  }
}

/// Font configuration for Story Editor Pro
class StoryEditorFonts {
  /// Available font styles for text editor
  final List<FontStyleConfig> fontStyles;

  /// Default font style index
  final int defaultFontIndex;

  /// Default font size
  final double defaultFontSize;

  /// Minimum font size
  final double minFontSize;

  /// Maximum font size
  final double maxFontSize;

  const StoryEditorFonts({
    this.fontStyles = _defaultFontStyles,
    this.defaultFontIndex = 0,
    this.defaultFontSize = 32,
    this.minFontSize = 12,
    this.maxFontSize = 72,
  });

  /// Default font styles (system fonts)
  static const List<FontStyleConfig> _defaultFontStyles = [
    FontStyleConfig(
      name: 'Bold',
      textStyle: TextStyle(fontWeight: FontWeight.bold),
    ),
  ];

  /// Get font style at index (with bounds checking)
  FontStyleConfig getFontStyle(int index) {
    if (index < 0 || index >= fontStyles.length) {
      return fontStyles[0];
    }
    return fontStyles[index];
  }
}
