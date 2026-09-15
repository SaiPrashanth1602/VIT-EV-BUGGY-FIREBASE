import 'dart:async';

import 'package:geolocator/geolocator.dart';

class FacultyLocationService {
  StreamSubscription<Position>? _positionSubscription;

  final StreamController<Position> _locationController =
      StreamController<Position>.broadcast();

  bool _isTracking = false;

  bool get isTracking => _isTracking;

  Stream<Position> get locationStream => _locationController.stream;

  Future<LocationPermission> getPermissionStatus() async {
    return Geolocator.checkPermission();
  }

  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  Future<LocationPermission> requestPermission() async {
    return Geolocator.requestPermission();
  }

  Future<bool> startTracking() async {
    if (_isTracking) {
      return true;
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return false;
      }

      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return false;
      }

      _isTracking = true;

      final locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 4),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'VIT EV BUGGY',
          notificationText: 'Faculty location tracking is active',
          enableWakeLock: true,
          enableWifiLock: true,
        ),
      );

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (position) {
              if (!_locationController.isClosed) {
                _locationController.add(position);
              }
            },
            onError: (Object error) {
              // Ignore runtime stream errors. The screen should keep rendering.
            },
          );

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();

    _positionSubscription = null;

    _isTracking = false;
  }

  Future<Position?> getCurrentPosition() async {
    final permission = await Geolocator.checkPermission();

    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> dispose() async {
    await stopTracking();
    await _locationController.close();
  }
}
