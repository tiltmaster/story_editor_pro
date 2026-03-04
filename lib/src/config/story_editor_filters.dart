import 'dart:math' as math;

import 'package:flutter/material.dart';

class StoryFilterPreset {
  final String id;
  final String name;

  const StoryFilterPreset({
    required this.id,
    required this.name,
  });
}

class StoryFilterParams {
  final double brightness;
  final double contrast;
  final double saturation;
  final double red;
  final double green;
  final double blue;

  const StoryFilterParams({
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.red,
    required this.green,
    required this.blue,
  });

  static const neutral = StoryFilterParams(
    brightness: 0.0,
    contrast: 1.0,
    saturation: 1.0,
    red: 1.0,
    green: 1.0,
    blue: 1.0,
  );
}

class StoryEditorFilters {
  static const String none = 'none';

  static const List<StoryFilterPreset> presets = [
    StoryFilterPreset(id: 'none', name: 'Normal'),
    StoryFilterPreset(id: 'vivid', name: 'Vivid'),
    StoryFilterPreset(id: 'warm', name: 'Warm'),
    StoryFilterPreset(id: 'cool', name: 'Cool'),
    StoryFilterPreset(id: 'sunset', name: 'Sunset'),
    StoryFilterPreset(id: 'fade', name: 'Fade'),
    StoryFilterPreset(id: 'mono', name: 'Mono'),
    StoryFilterPreset(id: 'noir', name: 'Noir'),
    StoryFilterPreset(id: 'dream', name: 'Dream'),
    StoryFilterPreset(id: 'vignette', name: 'Vignette'),
    StoryFilterPreset(id: 'retro2044', name: '2044'),
    StoryFilterPreset(id: 'cinematic', name: 'Cinematic'),
    StoryFilterPreset(id: 'tealorange', name: 'Teal Orange'),
    StoryFilterPreset(id: 'portraitpop', name: 'Portrait Pop'),
    StoryFilterPreset(id: 'nightneon', name: 'Night Neon'),
    StoryFilterPreset(id: 'productcrisp', name: 'Product Crisp'),
    StoryFilterPreset(id: 'filmicfade', name: 'Filmic Fade'),
    StoryFilterPreset(id: 'pastelmist', name: 'Pastel Mist'),
  ];

  static StoryFilterParams resolve(String presetId, double strength) {
    final s = strength.clamp(0.0, 1.0);

    StoryFilterParams target;
    switch (presetId) {
      case 'vivid':
        target = const StoryFilterParams(
          brightness: 0.02,
          contrast: 1.15,
          saturation: 1.22,
          red: 1.02,
          green: 1.02,
          blue: 1.02,
        );
        break;
      case 'warm':
        target = const StoryFilterParams(
          brightness: 0.015,
          contrast: 1.08,
          saturation: 1.08,
          red: 1.11,
          green: 1.02,
          blue: 0.92,
        );
        break;
      case 'cool':
        target = const StoryFilterParams(
          brightness: 0.0,
          contrast: 1.06,
          saturation: 1.05,
          red: 0.94,
          green: 1.01,
          blue: 1.11,
        );
        break;
      case 'sunset':
        target = const StoryFilterParams(
          brightness: 0.03,
          contrast: 1.1,
          saturation: 1.16,
          red: 1.14,
          green: 1.0,
          blue: 0.9,
        );
        break;
      case 'fade':
        target = const StoryFilterParams(
          brightness: 0.03,
          contrast: 0.88,
          saturation: 0.86,
          red: 1.0,
          green: 1.0,
          blue: 1.0,
        );
        break;
      case 'mono':
        target = const StoryFilterParams(
          brightness: 0.01,
          contrast: 1.04,
          saturation: 0.0,
          red: 1.0,
          green: 1.0,
          blue: 1.0,
        );
        break;
      case 'noir':
        target = const StoryFilterParams(
          brightness: -0.02,
          contrast: 1.22,
          saturation: 0.18,
          red: 1.0,
          green: 1.0,
          blue: 1.0,
        );
        break;
      case 'dream':
        target = const StoryFilterParams(
          brightness: 0.04,
          contrast: 0.94,
          saturation: 1.08,
          red: 1.06,
          green: 1.0,
          blue: 1.05,
        );
        break;
      case 'vignette':
        target = const StoryFilterParams(
          brightness: -0.01,
          contrast: 1.12,
          saturation: 1.02,
          red: 1.01,
          green: 1.0,
          blue: 0.99,
        );
        break;
      case 'retro2044':
        target = const StoryFilterParams(
          brightness: 0.02,
          contrast: 1.18,
          saturation: 1.28,
          red: 1.12,
          green: 0.98,
          blue: 1.14,
        );
        break;
      case 'cinematic':
        target = const StoryFilterParams(
          brightness: -0.01,
          contrast: 1.16,
          saturation: 0.92,
          red: 1.03,
          green: 1.0,
          blue: 0.96,
        );
        break;
      case 'tealorange':
        target = const StoryFilterParams(
          brightness: 0.01,
          contrast: 1.2,
          saturation: 1.08,
          red: 1.12,
          green: 1.0,
          blue: 1.12,
        );
        break;
      case 'portraitpop':
        target = const StoryFilterParams(
          brightness: 0.03,
          contrast: 1.12,
          saturation: 1.08,
          red: 1.08,
          green: 1.02,
          blue: 0.96,
        );
        break;
      case 'nightneon':
        target = const StoryFilterParams(
          brightness: -0.02,
          contrast: 1.3,
          saturation: 1.24,
          red: 0.98,
          green: 1.08,
          blue: 1.2,
        );
        break;
      case 'productcrisp':
        target = const StoryFilterParams(
          brightness: 0.01,
          contrast: 1.25,
          saturation: 1.12,
          red: 1.03,
          green: 1.03,
          blue: 1.03,
        );
        break;
      case 'filmicfade':
        target = const StoryFilterParams(
          brightness: 0.005,
          contrast: 1.06,
          saturation: 0.78,
          red: 1.04,
          green: 1.0,
          blue: 0.93,
        );
        break;
      case 'pastelmist':
        target = const StoryFilterParams(
          brightness: 0.045,
          contrast: 0.86,
          saturation: 0.92,
          red: 1.04,
          green: 1.01,
          blue: 1.06,
        );
        break;
      case 'none':
      default:
        target = StoryFilterParams.neutral;
    }

    return StoryFilterParams(
      brightness: _lerp(StoryFilterParams.neutral.brightness, target.brightness, s),
      contrast: _lerp(StoryFilterParams.neutral.contrast, target.contrast, s),
      saturation: _lerp(StoryFilterParams.neutral.saturation, target.saturation, s),
      red: _lerp(StoryFilterParams.neutral.red, target.red, s),
      green: _lerp(StoryFilterParams.neutral.green, target.green, s),
      blue: _lerp(StoryFilterParams.neutral.blue, target.blue, s),
    );
  }

  static ColorFilter colorFilter(String presetId, double strength) {
    return ColorFilter.matrix(matrix(presetId, strength));
  }

  static Color previewColor(String presetId) {
    switch (presetId) {
      case 'vivid':
        return const Color(0xFFFF7A59);
      case 'warm':
        return const Color(0xFFFFB15E);
      case 'cool':
        return const Color(0xFF56B4FF);
      case 'sunset':
        return const Color(0xFFFF6A5B);
      case 'fade':
        return const Color(0xFFB3B3B3);
      case 'mono':
        return const Color(0xFFE5E5E5);
      case 'noir':
        return const Color(0xFF6E6E6E);
      case 'dream':
        return const Color(0xFFB58CFF);
      case 'vignette':
        return const Color(0xFF8B6A55);
      case 'retro2044':
        return const Color(0xFFFF5EA8);
      case 'cinematic':
        return const Color(0xFF4F7FA8);
      case 'tealorange':
        return const Color(0xFF1FA6A0);
      case 'portraitpop':
        return const Color(0xFFFFA38B);
      case 'nightneon':
        return const Color(0xFF4DD7FF);
      case 'productcrisp':
        return const Color(0xFFB6F06D);
      case 'filmicfade':
        return const Color(0xFFD8B79B);
      case 'pastelmist':
        return const Color(0xFFBFC7FF);
      case 'none':
      default:
        return const Color(0xFFFFFFFF);
    }
  }

  static List<double> matrix(String presetId, double strength) {
    final p = resolve(presetId, strength);

    final c = p.contrast;
    final bOffset = (p.brightness * 255.0) + ((1.0 - c) * 128.0);
    final s = p.saturation;

    const rLum = 0.2126;
    const gLum = 0.7152;
    const bLum = 0.0722;

    final sr = (1 - s) * rLum;
    final sg = (1 - s) * gLum;
    final sb = (1 - s) * bLum;

    double r0 = (sr + s) * c * p.red;
    double r1 = sg * c * p.red;
    double r2 = sb * c * p.red;
    double g0 = sr * c * p.green;
    double g1 = (sg + s) * c * p.green;
    double g2 = sb * c * p.green;
    double bl0 = sr * c * p.blue;
    double bl1 = sg * c * p.blue;
    double bl2 = (sb + s) * c * p.blue;

    r0 = _finite(r0);
    r1 = _finite(r1);
    r2 = _finite(r2);
    g0 = _finite(g0);
    g1 = _finite(g1);
    g2 = _finite(g2);
    bl0 = _finite(bl0);
    bl1 = _finite(bl1);
    bl2 = _finite(bl2);

    return [
      r0, r1, r2, 0, bOffset,
      g0, g1, g2, 0, bOffset,
      bl0, bl1, bl2, 0, bOffset,
      0, 0, 0, 1, 0,
    ];
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _finite(double v) => v.isFinite ? v : 0.0;

  static int nearestPresetIndex(double rawValue) {
    final v = rawValue.clamp(0.0, presets.length - 1.0);
    return math.max(0, math.min(presets.length - 1, v.round()));
  }
}
