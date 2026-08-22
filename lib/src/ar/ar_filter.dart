import 'package:flutter/material.dart';

enum ArCameraFilterId {
  none,
  goldenHour,
  polarFrost,
  neonPulse,
  filmNoir,
  prismPop,
  retroScan,
  stargaze,
}

enum ArCameraQuality { low, balanced, high }

enum ArCameraPlatform { android, ios, other }

@immutable
class ArCameraFilter {
  const ArCameraFilter({
    required this.id,
    required this.presetId,
    required this.nameEn,
    required this.nameAr,
    required this.shaderMode,
    required this.fallbackPresetId,
    required this.icon,
    required this.previewColors,
    this.defaultIntensity = 0.82,
    this.animated = false,
    this.multiSample = false,
  }) : assert(shaderMode >= 0 && shaderMode <= 7),
       assert(defaultIntensity >= 0 && defaultIntensity <= 1);

  final ArCameraFilterId id;

  /// Stable ID used by host localization, analytics, and capture hand-off.
  final String presetId;
  final String nameEn;
  final String nameAr;
  final int shaderMode;
  final String fallbackPresetId;
  final IconData icon;
  final List<Color> previewColors;
  final double defaultIntensity;
  final bool animated;
  final bool multiSample;

  /// Existing color-matrix preset used for photo/video export parity when the
  /// screen-space runtime shader cannot be burned into the capture pipeline.
  String get exportPresetId => fallbackPresetId;

  String localizedName(Locale locale) =>
      locale.languageCode.toLowerCase() == 'ar' ? nameAr : nameEn;
}

@immutable
class ResolvedArCameraFilter {
  const ResolvedArCameraFilter({
    required this.filter,
    required this.useShader,
    required this.animate,
    required this.quality,
  });
  final ArCameraFilter filter;
  final bool useShader;
  final bool animate;
  final ArCameraQuality quality;
}
