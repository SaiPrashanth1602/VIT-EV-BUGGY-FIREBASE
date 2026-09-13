import 'dart:async';

import 'package:geolocator/geolocator.dart';

class FacultyLocationService {
  StreamSubscription<Position>? _positionSubscription;

  final StreamController<Position> _locationController =
      StreamController<Position>.broadcast();

  bool _isTracking = false;

  bool get isTracking => _isTracking;

  Stream<Position> get locationStream => _locationController.stream;

  Future<bool> checkAndRequestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<bool> startTracking() async {
    if (_isTracking) {
      return true;
    }

    if (!await checkAndRequestPermission()) {
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
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (position) {
            if (!_locationController.isClosed) {
              _locationController.add(position);
            }
          },
          onError: (Object error) {
            print('FACULTY LOCATION STREAM ERROR: $error');
          },
        );

    return true;
  }

  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();

    _positionSubscription = null;

    _isTracking = false;
  }

  Future<Position?> getCurrentPosition() async {
    if (!await checkAndRequestPermission()) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> dispose() async {
    await stopTracking();
    await _locationController.close();
  }
}
