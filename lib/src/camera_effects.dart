import 'dart:math' as math;
import 'place_identity.dart';
import 'models/story_capture_metadata.dart';
export 'place_identity.dart';
import 'place_sticker_geometry.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

import 'camera_nearby_places.dart';
export 'camera_effects_session.dart';
export 'camera_nearby_places.dart';

/// Independent camera layers. Selecting a look never clears beauty or a lens.
@immutable
class CameraEffects {
  const CameraEffects({
    this.beauty = 0,
    this.beautyEyes = 0,
    this.beautySlim = 0,
    this.backgroundStyle = 0,
    this.backgroundPath = '',
    this.backgroundIsVideo = false,
    this.faceLens = 'none',
    this.placeStyle = 'none',
    this.placeName = '',
    this.placeVariant = 0,
    this.placeX = .5,
    this.placeY = .68,
    this.placeScale = 1,
    this.placeRotation = 0,
    this.placeIdentity = const CameraPlaceIdentity(),
    this.nearbyPlace,
  });

  final double beauty;
  final double beautyEyes;
  final double beautySlim;

  /// 0: original, 1: studio, 2: sunset, 3: night, 4: background blur.
  final int backgroundStyle;
  final String backgroundPath;
  final bool backgroundIsVideo;
  final String faceLens;
  final String placeStyle;
  final String placeName;
  final int placeVariant;
  final double placeX, placeY, placeScale, placeRotation;
  final CameraPlaceIdentity placeIdentity;
  final CameraNearbyPlace? nearbyPlace;

  StoryCaptureMetadata? get captureMetadata {
    if (placeStyle == 'none' || placeName.isEmpty) return null;
    final venue = nearbyPlace;
    return StoryCaptureMetadata(
      place: StoryCapturePlace(
        source: venue == null ? 'camera_city' : 'camera_nearby',
        label: placeName, id: venue?.id, latitude: venue?.latitude,
        longitude: venue?.longitude, legacyPlaceId: venue?.legacyPlaceId),
      stickers: [StoryCaptureSticker(type: 'place', variant: placeVariant, value: placeName)],
    );
  }

  int get layerCount =>
      (beauty > 0 || beautyEyes > 0 || beautySlim > 0 ? 1 : 0) +
      (backgroundStyle != 0 ? 1 : 0) +
      (faceLens != 'none' ? 1 : 0) +
      (placeStyle != 'none' && placeName.isNotEmpty ? 1 : 0);

  CameraEffects copyWith({
    double? beauty,
    double? beautyEyes,
    double? beautySlim,
    int? backgroundStyle,
    String? backgroundPath,
    bool? backgroundIsVideo,
    String? faceLens,
    String? placeStyle,
    String? placeName,
    int? placeVariant,
    double? placeX,
    double? placeY,
    double? placeScale,
    double? placeRotation,
    CameraPlaceIdentity? placeIdentity,
    CameraNearbyPlace? nearbyPlace,
  }) {
    final nextStyle = placeStyle ?? this.placeStyle;
    final angle = placeRotation ?? this.placeRotation;
    final rotation = angle.isFinite
        ? (angle + math.pi) % (2 * math.pi) - math.pi
        : 0.0;
    final requestedScale = placeScale ?? this.placeScale;
    final fittedScale = (requestedScale.isFinite ? requestedScale : 1.0).clamp(
      .6,
      placeStickerMaxScale(nextStyle, rotation),
    );
    final size = rotatedPlaceStickerSize(nextStyle, rotation) * fittedScale;
    final marginX = nextStyle == 'none' ? 0.0 : size.width / 2160 + .015;
    final marginY = nextStyle == 'none' ? 0.0 : size.height / 3840 + .015;
    return CameraEffects(
      beauty: _amount(beauty, this.beauty),
      beautyEyes: _amount(beautyEyes, this.beautyEyes),
      beautySlim: _amount(beautySlim, this.beautySlim),
      backgroundStyle: backgroundStyle?.clamp(0, 5) ?? this.backgroundStyle,
      backgroundPath: backgroundPath ?? this.backgroundPath,
      backgroundIsVideo: backgroundIsVideo ?? this.backgroundIsVideo,
      faceLens: faceLens ?? this.faceLens,
      placeStyle: placeStyle ?? this.placeStyle,
      placeVariant: (placeVariant ?? this.placeVariant) % 3,
      placeX: _amount(placeX, this.placeX).clamp(marginX, 1 - marginX),
      placeY: _amount(placeY, this.placeY).clamp(marginY, 1 - marginY),
      placeScale: fittedScale,
      placeRotation: rotation,
      placeIdentity: placeIdentity ?? this.placeIdentity,
      nearbyPlace: nextStyle == 'none' ? null : nearbyPlace ??
          (placeName != null ? null : this.nearbyPlace),
      placeName: placeName == null
          ? this.placeName
          : String.fromCharCodes(placeName.trim().runes.take(64)),
    );
  }

  static double _amount(double? value, double fallback) => value == null
      ? fallback
      : value.isFinite
      ? value.clamp(0, 1)
      : 0;
}

typedef CameraPlaceResolver = Future<String> Function(String localeIdentifier);

/// Keeps verified city names for one open camera session, including in-flight
/// requests. Closing and reopening the effects tray does not reacquire GPS.
class CameraPlaceSession {
  CameraPlaceSession({
    CameraPlaceResolver? resolver,
    CameraNearbyResolver? nearbyResolver,
  }) : _resolver = resolver,
       _nearbyResolver = nearbyResolver;

  final CameraPlaceResolver? _resolver;
  final Map<String, CameraPlaceIdentity> _identities = {};
  CameraPlaceIdentity identityFor(String name) =>
      _identities[name] ?? const CameraPlaceIdentity();
  final CameraNearbyResolver? _nearbyResolver;
  bool get supportsNearby => _nearbyResolver != null;
  final Map<String, (DateTime, List<CameraNearbyPlace>)> _nearby = {};
  final Map<String, Future<List<CameraNearbyPlace>>> _nearbyPending = {};
  final Map<String, String> stylesByPlace = {};

  Future<List<CameraNearbyPlace>> nearby({
    required String localeIdentifier,
  }) async {
    final cached = _nearby[localeIdentifier];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) {
      return cached.$2;
    }
    final pending = _nearbyPending[localeIdentifier];
    if (pending != null) return pending;
    final request = () async {
      final resolver = _nearbyResolver;
      if (resolver == null) {
        throw StateError("No nearby-place provider configured");
      }
      final position = await cameraPlacePosition();
      final places = normalizeNearbyCameraPlaces(
        await resolver(
          position.latitude,
          position.longitude,
          localeIdentifier,
        ).timeout(const Duration(seconds: 25)),
      );
      _nearby[localeIdentifier] = (DateTime.now(), places);
      return places;
    }();
    _nearbyPending[localeIdentifier] = request;
    try {
      return await request;
    } finally {
      _nearbyPending.remove(localeIdentifier);
    }
  }

  final Map<String, String> _names = {};
  final Map<String, Future<String>> _pending = {};

  Future<String> _resolve(String locale) async {
    if (_resolver != null) return _resolver(locale);
    final result = await _resolveCameraPlaceDetails(locale);
    _identities[String.fromCharCodes(result.$1.trim().runes.take(64))] =
        result.$2;
    return result.$1;
  }

  Future<String> resolve({required String localeIdentifier}) async {
    final cached = _names[localeIdentifier];
    if (cached != null) return cached;
    final pending = _pending[localeIdentifier];
    if (pending != null) return pending;
    final request = _resolve(localeIdentifier).then((name) {
      final city = String.fromCharCodes(name.trim().runes.take(64));
      if (city.isEmpty) throw StateError('No city was returned.');
      _names[localeIdentifier] = city;
      return city;
    });
    _pending[localeIdentifier] = request;
    try {
      return await request;
    } finally {
      _pending.remove(localeIdentifier);
    }
  }
}

/// Invoked when the user selects Places, never during camera initialization.
/// Precise coordinates are discarded after reverse geocoding.
Future<String> resolveCameraPlace({String localeIdentifier = 'en'}) async =>
    (await _resolveCameraPlaceDetails(localeIdentifier)).$1;

Future<(String, CameraPlaceIdentity)> _resolveCameraPlaceDetails(
  String localeIdentifier,
) async {
  final position = await cameraPlacePosition();
  await geo.setLocaleIdentifier(localeIdentifier);
  final places = await geo
      .placemarkFromCoordinates(position.latitude, position.longitude)
      .timeout(const Duration(seconds: 8));
  for (final place in places) {
    for (final name in [
      place.locality,
      place.subAdministrativeArea,
      place.administrativeArea,
      place.country,
    ]) {
      if (name != null && name.trim().isNotEmpty) {
        return (
          name.trim(),
          CameraPlaceIdentity(
            locality: place.locality ?? '',
            countryCode: place.isoCountryCode ?? '',
          ),
        );
      }
    }
  }
  throw StateError('Could not find a city here. Please retry.');
}

Future<Position> cameraPlacePosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw StateError('Turn on location services and retry.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    throw StateError('Allow location access in Settings and retry.');
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: Duration(seconds: 10),
    ),
  );
}
