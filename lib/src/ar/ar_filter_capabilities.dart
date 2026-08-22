import 'package:flutter/foundation.dart';
import 'ar_filter.dart';

@immutable
class ArCameraCapabilities {
  const ArCameraCapabilities({
    required this.platform,
    this.quality = ArCameraQuality.balanced,
    this.fragmentShadersAvailable = true,
    this.reduceMotion = false,
    this.liveEffectsEnabled = true,
  });

  factory ArCameraCapabilities.current({
    ArCameraQuality quality = ArCameraQuality.balanced,
    bool fragmentShadersAvailable = true,
    bool reduceMotion = false,
    bool liveEffectsEnabled = true,
  }) {
    final family = switch (defaultTargetPlatform) {
      TargetPlatform.android => ArCameraPlatform.android,
      TargetPlatform.iOS => ArCameraPlatform.ios,
      _ => ArCameraPlatform.other,
    };
    return ArCameraCapabilities(
      platform: kIsWeb ? ArCameraPlatform.other : family,
      quality: quality,
      fragmentShadersAvailable: fragmentShadersAvailable,
      reduceMotion: reduceMotion,
      liveEffectsEnabled: liveEffectsEnabled,
    );
  }

  final ArCameraPlatform platform;
  final ArCameraQuality quality;
  final bool fragmentShadersAvailable;
  final bool reduceMotion;
  final bool liveEffectsEnabled;
  bool get isSupportedMobilePlatform =>
      platform == ArCameraPlatform.android || platform == ArCameraPlatform.ios;
}

class ArCameraCapabilityPolicy {
  const ArCameraCapabilityPolicy._();
  static ResolvedArCameraFilter resolve(
    ArCameraFilter filter,
    ArCameraCapabilities capabilities,
  ) {
    final useShader =
        filter.id != ArCameraFilterId.none &&
        capabilities.liveEffectsEnabled &&
        capabilities.fragmentShadersAvailable &&
        capabilities.isSupportedMobilePlatform &&
        capabilities.quality != ArCameraQuality.low &&
        !(filter.multiSample &&
            capabilities.quality == ArCameraQuality.balanced);
    return ResolvedArCameraFilter(
      filter: filter,
      useShader: useShader,
      animate: useShader && filter.animated && !capabilities.reduceMotion,
      quality: capabilities.quality,
    );
  }
}
