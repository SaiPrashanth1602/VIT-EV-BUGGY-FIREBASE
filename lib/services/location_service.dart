import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  bool _isTracking = false;
  String? _vehicleId;
  Position? _lastValidPosition;

  bool get isTracking => _isTracking;
  String? get vehicleId => _vehicleId;

  static const List<String> vehicleIds = ['EV1', 'EV2', 'EV3', 'EV4'];
  static const Duration normalUpdateInterval = Duration(seconds: 1);

  static const double maxAcceptableAccuracy = 25.0;
  static const double minMovementThreshold = 3.0;
  static const double maxBuggySpeedMetersPerSecond = 12.0;

  final DatabaseReference _vehiclesReference = FirebaseDatabase.instance.ref(
    'evShuttle/vehicles',
  );

  Future<bool> checkAndRequestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      print('LOCATION SERVICE IS DISABLED');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      print('LOCATION PERMISSION DENIED: $permission');
      return false;
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<String?> allocateVehicleSlot() async {
    for (final vehicleId in vehicleIds) {
      final reference = _vehiclesReference.child(vehicleId);

      final result = await reference.runTransaction((Object? currentData) {
        if (currentData is Map && currentData['active'] == true) {
          return Transaction.abort();
        }

        return Transaction.success({
          'vehicleId': vehicleId,
          'active': true,
          'status': 'STARTED',
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
      }, applyLocally: false);

      if (result.committed) {
        print('ALLOCATED VEHICLE: $vehicleId');
        return vehicleId;
      }
    }

    print('NO AVAILABLE EVS');
    return null;
  }

  Future<bool> startTracking() async {
    if (_isTracking) return true;

    if (!await checkAndRequestPermission()) {
      return false;
    }

    final allocatedVehicleId = await allocateVehicleSlot();
    if (allocatedVehicleId == null) return false;

    _vehicleId = allocatedVehicleId;
    _isTracking = true;
    _lastValidPosition = null;

    try {
      await sendShiftEvent(vehicleId: _vehicleId!, status: 'STARTED');

      final androidSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
        intervalDuration: normalUpdateInterval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'VIT EV BUGGY',
          notificationText: 'EV shift tracking is active',
          enableWakeLock: true,
          enableWifiLock: true,
        ),
      );

      final appleSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );

      final defaultSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
        timeLimit: const Duration(seconds: 10),
      );

      print('STARTING LOCATION STREAM FOR $_vehicleId');

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: _getPlatformLocationSettings(
              androidSettings: androidSettings,
              appleSettings: appleSettings,
              defaultSettings: defaultSettings,
            ),
          ).listen(
            _handlePosition,
            onError: (Object error) {
              print('LOCATION STREAM ERROR: $error');
            },
            onDone: () {
              print('LOCATION STREAM CLOSED');
            },
          );

      return true;
    } catch (error) {
      print('START TRACKING ERROR: $error');
      await releaseVehicleSlot(_vehicleId);
      _vehicleId = null;
      _isTracking = false;
      _lastValidPosition = null;
      return false;
    }
  }

  Future<void> _handlePosition(Position position) async {
    if (!_isTracking || _vehicleId == null) return;

    final vehicleId = _vehicleId!;

    if (position.accuracy > maxAcceptableAccuracy) {
      print('REJECTED: Low accuracy fix (${position.accuracy}m)');
      return;
    }

    if (_lastValidPosition != null) {
      final distanceMoved = Geolocator.distanceBetween(
        _lastValidPosition!.latitude,
        _lastValidPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (distanceMoved < minMovementThreshold) {
        return;
      }

      final timeDeltaSeconds =
          position.timestamp
              .difference(_lastValidPosition!.timestamp)
              .inMilliseconds /
          1000.0;

      if (timeDeltaSeconds > 0) {
        final calculatedSpeed = distanceMoved / timeDeltaSeconds;

        if (calculatedSpeed > maxBuggySpeedMetersPerSecond) {
          print('REJECTED: Impossible speed spike ($calculatedSpeed m/s)');
          return;
        }
      }
    }

    _lastValidPosition = position;

    try {
      await sendLocation(vehicleId: vehicleId, position: position);
      print('LOCATION UPDATED FOR $vehicleId');
    } catch (error) {
      print('SEND LOCATION ERROR FOR $vehicleId: $error');
    }
  }

  LocationSettings _getPlatformLocationSettings({
    required AndroidSettings androidSettings,
    required AppleSettings appleSettings,
    required LocationSettings defaultSettings,
  }) {
    if (Platform.isAndroid) return androidSettings;
    if (Platform.isIOS) return appleSettings;
    return defaultSettings;
  }

  Future<void> stopTracking() async {
    if (!_isTracking) return;

    final vehicleId = _vehicleId;

    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    _vehicleId = null;
    _lastValidPosition = null;

    if (vehicleId != null) {
      try {
        await sendShiftEvent(vehicleId: vehicleId, status: 'ENDED');
      } finally {
        await releaseVehicleSlot(vehicleId);
      }
    }
  }

  Future<void> releaseVehicleSlot(String? vehicleId) async {
    if (vehicleId == null) return;

    await _vehiclesReference.child(vehicleId).update({
      'active': false,
      'status': 'ENDED',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> sendLocation({
    required String vehicleId,
    required Position position,
  }) async {
    await _vehiclesReference.child(vehicleId).update({
      'vehicleId': vehicleId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'speed': position.speed,
      'heading': position.heading,
      'accuracy': position.accuracy,
      'active': true,
      'status': 'ACTIVE',
    });
  }

  Future<void> sendShiftEvent({
    required String vehicleId,
    required String status,
  }) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();

    await _vehiclesReference.child(vehicleId).update({
      'vehicleId': vehicleId,
      'status': status,
      'active': status == 'STARTED',
      'updatedAt': timestamp,
    });

    await FirebaseDatabase.instance.ref('evShuttle/shiftEvents').push().set({
      'vehicleId': vehicleId,
      'status': status,
      'timestamp': timestamp,
    });
  }
}
