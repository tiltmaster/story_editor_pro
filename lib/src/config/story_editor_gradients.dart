import 'package:flutter/material.dart';

/// A gradient preset with colors and optional name
class GradientPreset {
  /// The colors for this gradient (2 colors for linear gradient)
  final List<Color> colors;

  /// Optional name for this gradient
  final String? name;

  const GradientPreset({
    required this.colors,
    this.name,
  });

  /// Whether this is a solid color (both colors are the same)
  bool get isSolid => colors.length >= 2 && colors[0] == colors[1];

  /// Create a LinearGradient from this preset
  LinearGradient toLinearGradient({
    Alignment begin = Alignment.topLeft,
    Alignment end = Alignment.bottomRight,
    List<double>? stops,
  }) {
    return LinearGradient(
      colors: colors,
      begin: begin,
      end: end,
      stops: stops,
    );
  }
}

/// Gradient presets configuration for Story Editor Pro
class StoryEditorGradients {
  /// List of gradient presets for the gradient text editor
  final List<GradientPreset> presets;

  const StoryEditorGradients({
    this.presets = defaultPresets,
  });

  /// Default gradient presets (15 gradients + 3 solid colors)
  static const List<GradientPreset> defaultPresets = [
    // Gradients
    GradientPreset(colors: [Color(0xFF667EEA), Color(0xFF764BA2)], name: 'Purple-Blue'),
    GradientPreset(colors: [Color(0xFFf093fb), Color(0xFFf5576c)], name: 'Pink'),
    GradientPreset(colors: [Color(0xFF4facfe), Color(0xFF00f2fe)], name: 'Blue-Cyan'),
    GradientPreset(colors: [Color(0xFF43e97b), Color(0xFF38f9d7)], name: 'Green-Teal'),
    GradientPreset(colors: [Color(0xFFfa709a), Color(0xFFfee140)], name: 'Pink-Yellow'),
    GradientPreset(colors: [Color(0xFFa8edea), Color(0xFFfed6e3)], name: 'Pastel'),
    GradientPreset(colors: [Color(0xFF667eea), Color(0xFF764ba2)], name: 'Indigo'),
    GradientPreset(colors: [Color(0xFFff9a9e), Color(0xFFfecfef)], name: 'Soft Pink'),
    GradientPreset(colors: [Color(0xFFffecd2), Color(0xFFfcb69f)], name: 'Peach'),
    GradientPreset(colors: [Color(0xFF89f7fe), Color(0xFF66a6ff)], name: 'Sky'),
    GradientPreset(colors: [Color(0xFFa18cd1), Color(0xFFfbc2eb)], name: 'Lavender'),
    GradientPreset(colors: [Color(0xFFfad0c4), Color(0xFFffd1ff)], name: 'Soft Rose'),
    GradientPreset(colors: [Color(0xFFff8177), Color(0xFFcf556c)], name: 'Red'),
    GradientPreset(colors: [Color(0xFFFFB347), Color(0xFFFFCC33)], name: 'Orange'),
    GradientPreset(colors: [Color(0xFF11998e), Color(0xFF38ef7d)], name: 'Green'),
    // Solid colors
    GradientPreset(colors: [Color(0xFF000000), Color(0xFF000000)], name: 'Black'),
    GradientPreset(colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)], name: 'White'),
    GradientPreset(colors: [Color(0xFF1a1a2e), Color(0xFF1a1a2e)], name: 'Dark Navy'),
  ];
}
