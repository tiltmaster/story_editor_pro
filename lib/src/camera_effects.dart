import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

export 'camera_effects_session.dart';

/// Independent camera layers. Selecting a look never clears beauty or a lens.
@immutable
class CameraEffects {
  const CameraEffects({
    this.beauty = 0,
    this.beautyEyes = 0,
    this.beautySlim = 0,
    this.backgroundStyle = 0,
    this.faceLens = 'none',
    this.placeStyle = 'none',
    this.placeName = '',
  });

  final double beauty;
  final double beautyEyes;
  final double beautySlim;

  /// 0: original, 1: studio, 2: sunset, 3: night, 4: background blur.
  final int backgroundStyle;
  final String faceLens;
  final String placeStyle;
  final String placeName;

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
    String? faceLens,
    String? placeStyle,
    String? placeName,
  }) => CameraEffects(
    beauty: _amount(beauty, this.beauty),
    beautyEyes: _amount(beautyEyes, this.beautyEyes),
    beautySlim: _amount(beautySlim, this.beautySlim),
    backgroundStyle: backgroundStyle?.clamp(0, 4) ?? this.backgroundStyle,
    faceLens: faceLens ?? this.faceLens,
    placeStyle: placeStyle ?? this.placeStyle,
    placeName: placeName == null
        ? this.placeName
        : String.fromCharCodes(placeName.trim().runes.take(64)),
  );

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
  CameraPlaceSession({CameraPlaceResolver? resolver})
    : _resolver = resolver ?? _resolve;

  final CameraPlaceResolver _resolver;
  final Map<String, String> _names = {};
  final Map<String, Future<String>> _pending = {};

  static Future<String> _resolve(String locale) =>
      resolveCameraPlace(localeIdentifier: locale);

  Future<String> resolve({required String localeIdentifier}) async {
    final cached = _names[localeIdentifier];
    if (cached != null) return cached;
    final pending = _pending[localeIdentifier];
    if (pending != null) return pending;
    final request = _resolver(localeIdentifier).then((name) {
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
Future<String> resolveCameraPlace({String localeIdentifier = 'en'}) async {
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
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: Duration(seconds: 10),
    ),
  );
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
      if (name != null && name.trim().isNotEmpty) return name.trim();
    }
  }
  throw StateError('Could not find a city here. Please retry.');
}
