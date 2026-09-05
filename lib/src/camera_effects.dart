import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

/// Independent camera layers. Selecting a look never clears beauty or a lens.
@immutable
class CameraEffects {
  const CameraEffects({
    this.beauty = 0,
    this.faceLens = 'none',
    this.placeStyle = 'none',
    this.placeName = '',
  });

  final double beauty;
  final String faceLens;
  final String placeStyle;
  final String placeName;

  int get layerCount =>
      (beauty > 0 ? 1 : 0) +
      (faceLens != 'none' ? 1 : 0) +
      (placeStyle != 'none' && placeName.isNotEmpty ? 1 : 0);

  CameraEffects copyWith({
    double? beauty,
    String? faceLens,
    String? placeStyle,
    String? placeName,
  }) => CameraEffects(
    beauty: beauty == null
        ? this.beauty
        : beauty.isFinite
        ? beauty.clamp(0, 1)
        : 0,
    faceLens: faceLens ?? this.faceLens,
    placeStyle: placeStyle ?? this.placeStyle,
    placeName: placeName == null
        ? this.placeName
        : String.fromCharCodes(placeName.trim().runes.take(64)),
  );
}

/// Only invoked by the user's location action, never camera initialization.
/// A city name is retained for the session; precise coordinates are discarded.
Future<String> resolveCameraPlace({String localeIdentifier = 'en'}) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw StateError('Turn on location services, or enter a place below.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    throw StateError('Location access is off. You can enter a place below.');
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
  throw StateError('Could not find a city here. Enter a place below.');
}
