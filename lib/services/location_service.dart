import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  bool _isTracking = false;
  bool _isStreaming = false;

  String? _vehicleId;
  DateTime? _lastMovementTime;
  Position? _lastPosition;

  bool get isTracking => _isTracking;
  String? get vehicleId => _vehicleId;

  static const List<String> vehicleIds = ['EV1', 'EV2', 'EV3', 'EV4'];

  static const Duration normalUpdateInterval = Duration(seconds: 4);
  static const Duration stationaryTimeout = Duration(seconds: 120);

  // Ignore small GPS jitter when deciding whether the vehicle moved.
  static const double movementThresholdMeters = 5.0;

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

  Future<String?> allocateVehicleSlot() async {
    // PILOT PLACEHOLDER:
    // The final Java/PostgreSQL backend will atomically allocate the first
    // FREE slot from EV1-EV4. This is a temporary local implementation.
    return vehicleIds.first;
  }

  Future<bool> startTracking() async {
    if (_isTracking) {
      return true;
    }

    if (!await checkAndRequestPermission()) {
      return false;
    }

    final allocatedVehicleId = await allocateVehicleSlot();

    if (allocatedVehicleId == null) {
      return false;
    }

    _vehicleId = allocatedVehicleId;
    _isTracking = true;
    _isStreaming = true;
    _lastMovementTime = DateTime.now();
    _lastPosition = null;

    await sendShiftEvent(vehicleId: _vehicleId!, status: 'STARTED');

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: normalUpdateInterval,
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'VIT EV BUGGY',
        notificationText: 'EV shift tracking is active',
        enableWakeLock: true,
        enableWifiLock: true,
      ),
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          _handlePosition,
          onError: (Object error) {
            print('LOCATION STREAM ERROR: $error');
          },
        );

    return true;
  }

  void _handlePosition(Position position) {
    if (!_isTracking || _vehicleId == null) {
      return;
    }

    final now = DateTime.now();
    bool hasMoved = false;

    if (_lastPosition != null) {
      final distance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      hasMoved = distance >= movementThresholdMeters || position.speed >= 1.0;
    }

    if (hasMoved) {
      _lastMovementTime = now;
      _lastPosition = position;

      if (!_isStreaming) {
        _isStreaming = true;
        print('VEHICLE MOVED: location streaming resumed');
      }
    } else if (_lastMovementTime != null &&
        now.difference(_lastMovementTime!) >= stationaryTimeout) {
      if (_isStreaming) {
        _isStreaming = false;
        print(
          'VEHICLE STATIONARY: location streaming paused after 120 seconds',
        );
      }
    }

    // The local GPS listener stays alive so movement can be detected again.
    // Only backend/location updates are paused after 120 seconds stationary.
    if (_isStreaming) {
      sendLocation(vehicleId: _vehicleId!, position: position);
    }

    if (_lastPosition == null) {
      _lastPosition = position;
    }
  }

  Future<void> stopTracking() async {
    if (!_isTracking) {
      return;
    }

    final vehicleId = _vehicleId;

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _isTracking = false;
    _isStreaming = false;
    _vehicleId = null;
    _lastMovementTime = null;
    _lastPosition = null;

    if (vehicleId != null) {
      await sendShiftEvent(vehicleId: vehicleId, status: 'ENDED');
    }

    await releaseVehicleSlot(vehicleId);
  }

  Future<void> releaseVehicleSlot(String? vehicleId) async {
    if (vehicleId == null) {
      return;
    }

    // PILOT PLACEHOLDER:
    // Final backend will mark this slot FREE for reuse.
    print('VEHICLE SLOT RELEASED: $vehicleId');
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

    // Integration hook for the Java/PostgreSQL backend.
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

    // Integration hook for the Java/PostgreSQL backend.
    print('SHIFT EVENT: $shiftPayload');
  }
}
