import 'package:flutter/material.dart';
import 'ar_filter.dart';

class ArCameraFilterCatalog {
  const ArCameraFilterCatalog._();
  static const String shaderAsset =
      'packages/story_editor_pro/shaders/ar_camera_filter.frag';
  static const String packageRootShaderAsset = 'shaders/ar_camera_filter.frag';

  /// Seven GPU effects plus a no-effect entry. No effect inspects or retains frames.
  static const List<ArCameraFilter> filters = <ArCameraFilter>[
    ArCameraFilter(
      id: ArCameraFilterId.none,
      presetId: 'none',
      nameEn: 'Original',
      nameAr: 'طبيعي',
      shaderMode: 0,
      fallbackPresetId: 'none',
      icon: Icons.block,
      previewColors: <Color>[Color(0xFF777777), Color(0xFF333333)],
      defaultIntensity: 0,
    ),
    ArCameraFilter(
      id: ArCameraFilterId.goldenHour,
      presetId: 'ar_golden',
      nameEn: 'Golden',
      nameAr: 'ذهبي',
      shaderMode: 1,
      fallbackPresetId: 'goldenhour',
      icon: Icons.wb_sunny_outlined,
      previewColors: <Color>[Color(0xFFFFD27A), Color(0xFFE85D3F)],
      animated: true,
    ),
    ArCameraFilter(
      id: ArCameraFilterId.polarFrost,
      presetId: 'ar_frost',
      nameEn: 'Frost',
      nameAr: 'صقيع',
      shaderMode: 2,
      fallbackPresetId: 'arctic',
      icon: Icons.ac_unit,
      previewColors: <Color>[Color(0xFFE7FAFF), Color(0xFF4EA5E8)],
      defaultIntensity: 0.76,
    ),
    ArCameraFilter(
      id: ArCameraFilterId.neonPulse,
      presetId: 'ar_neon',
      nameEn: 'Neon',
      nameAr: 'نيون',
      shaderMode: 3,
      fallbackPresetId: 'nightneon',
      icon: Icons.bolt,
      previewColors: <Color>[Color(0xFF00F0FF), Color(0xFFFF2BD6)],
      animated: true,
    ),
    ArCameraFilter(
      id: ArCameraFilterId.filmNoir,
      presetId: 'ar_noir',
      nameEn: 'Noir',
      nameAr: 'أبيض وأسود',
      shaderMode: 4,
      fallbackPresetId: 'noir',
      icon: Icons.movie_filter_outlined,
      previewColors: <Color>[Color(0xFFE8E8E8), Color(0xFF161616)],
      animated: true,
      defaultIntensity: 0.72,
    ),
    ArCameraFilter(
      id: ArCameraFilterId.prismPop,
      presetId: 'ar_prism',
      nameEn: 'Prism',
      nameAr: 'طيف',
      shaderMode: 5,
      fallbackPresetId: 'velvet',
      icon: Icons.change_history,
      previewColors: <Color>[Color(0xFF56E0FF), Color(0xFFFF4DB8)],
      animated: true,
      multiSample: true,
    ),
    ArCameraFilter(
      id: ArCameraFilterId.retroScan,
      presetId: 'ar_retro',
      nameEn: 'Retro',
      nameAr: 'ريترو',
      shaderMode: 6,
      fallbackPresetId: 'retro2044',
      icon: Icons.tv,
      previewColors: <Color>[Color(0xFFFFA34E), Color(0xFF542B80)],
      animated: true,
      defaultIntensity: 0.68,
    ),
    ArCameraFilter(
      id: ArCameraFilterId.stargaze,
      presetId: 'ar_stargaze',
      nameEn: 'Stargaze',
      nameAr: 'نجوم',
      shaderMode: 7,
      fallbackPresetId: 'dream',
      icon: Icons.auto_awesome,
      previewColors: <Color>[Color(0xFFBFAAFF), Color(0xFF241450)],
      animated: true,
      defaultIntensity: 0.78,
    ),
  ];

  static ArCameraFilter byId(ArCameraFilterId id) => filters.firstWhere(
    (filter) => filter.id == id,
    orElse: () => filters.first,
  );

  static ArCameraFilter byPresetId(String presetId) => filters.firstWhere(
    (filter) => filter.presetId == presetId,
    orElse: () => filters.first,
  );
}
