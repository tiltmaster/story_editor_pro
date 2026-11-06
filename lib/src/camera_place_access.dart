import 'package:geolocator/geolocator.dart';

enum CameraPlaceRecovery { permission, appSettings, services }

class CameraPlaceAccessException implements Exception {
  const CameraPlaceAccessException(this.recovery);
  final CameraPlaceRecovery recovery;
}

/// Checks never launch Settings. Only the labelled recovery action does.
class CameraPlaceAccess {
  CameraPlaceAccess({
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<bool> Function()? serviceEnabled,
    Future<bool> Function()? openAppSettings,
    Future<bool> Function()? openLocationSettings,
  }) : _check = checkPermission ?? Geolocator.checkPermission,
       _request = requestPermission ?? Geolocator.requestPermission,
       _enabled = serviceEnabled ?? Geolocator.isLocationServiceEnabled,
       _appSettings = openAppSettings ?? Geolocator.openAppSettings,
       _locationSettings =
           openLocationSettings ?? Geolocator.openLocationSettings;
  final Future<LocationPermission> Function() _check, _request;
  final Future<bool> Function() _enabled, _appSettings, _locationSettings;
  Future<void>? _pending;
  Future<void> prepare({required bool userInitiated}) => _pending ??= _prepare(
    userInitiated,
  ).timeout(const Duration(seconds: 15)).whenComplete(() => _pending = null);
  Future<void> _prepare(bool userInitiated) async {
    var permission = await _check();
    if (permission == LocationPermission.denied && userInitiated) {
      permission = await _request();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const CameraPlaceAccessException(CameraPlaceRecovery.appSettings);
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const CameraPlaceAccessException(CameraPlaceRecovery.permission);
    }
    if (!await _enabled()) {
      throw const CameraPlaceAccessException(CameraPlaceRecovery.services);
    }
  }

  Future<bool> openSettings(CameraPlaceRecovery recovery) => switch (recovery) {
    CameraPlaceRecovery.appSettings => _appSettings(),
    CameraPlaceRecovery.services => _locationSettings(),
    _ => Future.value(false),
  };
}
