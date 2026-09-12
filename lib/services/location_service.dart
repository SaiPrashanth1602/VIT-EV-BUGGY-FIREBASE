import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  bool _isTracking = false;
  String? _vehicleId;

  bool get isTracking => _isTracking;

  Future<bool> checkAndRequestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
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

    return true;
  }

  Future<bool> startTracking({required String vehicleId}) async {
    if (_isTracking) {
      return true;
    }

    final permissionGranted = await checkAndRequestPermission();

    if (!permissionGranted) {
      return false;
    }

    _vehicleId = vehicleId;
    _isTracking = true;

    await sendShiftEvent(vehicleId: vehicleId, status: 'STARTED');

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 4),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'VIT EV BUGGY',
        notificationText: 'EV shift tracking is active',
        enableWakeLock: true,
        enableWifiLock: true,
      ),
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            if (_vehicleId == null) {
              return;
            }

            sendLocation(vehicleId: _vehicleId!, position: position);
          },
        );

    return true;
  }

  Future<void> stopTracking() async {
    if (!_isTracking) {
      return;
    }

    final vehicleId = _vehicleId;

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _isTracking = false;
    _vehicleId = null;

    if (vehicleId != null) {
      await sendShiftEvent(vehicleId: vehicleId, status: 'ENDED');
    }
  }

  Future<void> sendLocation({
    required String vehicleId,
    required Position position,
  }) async {
    final locationPayload = {
      'vehicleId': vehicleId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'speed': position.speed,
      'heading': position.heading,
    };

    // Integration hook.
    //
    // The Java/PostgreSQL backend team will replace this
    // with the actual API call during integration.
    print('LOCATION UPDATE: $locationPayload');
  }

  Future<void> sendShiftEvent({
    required String vehicleId,
    required String status,
  }) async {
    final shiftPayload = {
      'vehicleId': vehicleId,
      'status': status,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    // Integration hook.
    //
    // The Java/PostgreSQL backend team will replace this
    // with the actual API call during integration.
    print('SHIFT EVENT: $shiftPayload');
  }
}
