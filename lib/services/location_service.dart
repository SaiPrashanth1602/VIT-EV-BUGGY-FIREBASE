import 'dart:async';
import 'dart:math' as math; // Added for distance calculations

import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  bool _isTracking = false;
  String? _vehicleId;

  // Track the last valid position to perform delta filtering
  Position? _lastValidPosition;

  bool get isTracking => _isTracking;
  String? get vehicleId => _vehicleId;

  static const List<String> vehicleIds = ['EV1', 'EV2', 'EV3', 'EV4'];
  static const Duration normalUpdateInterval = Duration(seconds: 1);

  // --- TUNING METRICS FOR HIGHER ACCURACY ---
  // Reject updates where the GPS margin of error is too wide (in metres)
  static const double maxAcceptableAccuracy = 25.0; 
  
  // Ignore tiny micro-movements (jitter) when the buggy is completely stopped (in metres)
  static const double minMovementThreshold = 3.0; 
  
  // Maximum realistic speed for a campus EV buggy (e.g., 40 km/h converted to m/s is ~11.1)
  static const double maxBuggySpeedMetersPerSecond = 12.0;

  final DatabaseReference _vehiclesReference = FirebaseDatabase.instance.ref(
    'evShuttle/vehicles',
  );

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

    // CRITICAL FIX: For accurate background tracking, you should ideally request .always
    // This allows the OS to give high-accuracy updates even when the driver's phone screen locks.
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<String?> allocateVehicleSlot() async {
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
    _lastValidPosition = null; // Reset history

    await sendShiftEvent(vehicleId: _vehicleId!, status: 'STARTED');

    // Android configuration
    final androidSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation, // Upgraded from 'best' to navigation mode
      distanceFilter: 2, // Only trigger stream if the driver moves at least 2 metres
      intervalDuration: normalUpdateInterval,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'VIT EV BUGGY',
        notificationText: 'EV shift tracking is active',
        enableWakeLock: true,
        enableWifiLock: true,
      ),
    );

    // iOS configuration (Added to match your Android performance)
    final appleSettings = AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
      activityType: ActivityType.otherNavigation,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );

    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
      timeLimit: const Duration(seconds: 10),
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: GetPlatformLocationSettings(
        androidSettings: androidSettings,
        appleSettings: appleSettings,
        defaultSettings: locationSettings,
      ),
    ).listen(
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

    // FILTER 1: Reject mathematically noisy fixes
    if (position.accuracy > maxAcceptableAccuracy) {
      print('REJECTED: Low accuracy fix (${position.accuracy}m)');
      return;
    }

    if (_lastValidPosition != null) {
      // Calculate real distance shifted since the last approved coordinate
      double distanceMoved = Geolocator.distanceBetween(
        _lastValidPosition!.latitude,
        _lastValidPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // FILTER 2: Static Jitter Protection
      // If the buggy is parked or waiting for faculty, don't update Firebase with ghost movements
      if (distanceMoved < minMovementThreshold) {
        return;
      }

      // FILTER 3: Sanity Check / Teleportation Prevention
      // Calculate how much time passed since the last coordinate
      final double timeDeltaSeconds = (position.timestamp.difference(_lastValidPosition!.timestamp)).inMilliseconds / 1000.0;
      
      if (timeDeltaSeconds > 0) {
        double calculatedSpeed = distanceMoved / timeDeltaSeconds;
        // If calculated speed implies the buggy broke campus speed limits drastically, it's a GPS bounce.
        if (calculatedSpeed > maxBuggySpeedMetersPerSecond) {
          print('REJECTED: Impossible speed spike ($calculatedSpeed m/s)');
          return;
        }
      }
    }

    // Clean data approved! Cache it and save to cloud.
    _lastValidPosition = position;
    sendLocation(vehicleId: _vehicleId!, position: position);
  }

  // Helper helper method to choose cross-platform configuration setup
  LocationSettings GetPlatformLocationSettings({
    required AndroidSettings androidSettings,
    required AppleSettings appleSettings,
    required LocationSettings defaultSettings,
  }) {
    // Packages automatically select platform rules under the hood
    return androidSettings;
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
    _lastValidPosition = null;

    if (vehicleId != null) {
      await sendShiftEvent(vehicleId: vehicleId, status: 'ENDED');
      await releaseVehicleSlot(vehicleId);
    }
  }

  Future<void> releaseVehicleSlot(String? vehicleId) async {
    if (vehicleId == null) {
      return;
    }

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
    final locationPayload = {
      'vehicleId': vehicleId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'speed': position.speed,
      'heading': position.heading,
      'accuracy': position.accuracy, // Good to log this to debug campus dead zones
      'active': true,
      'status': 'ACTIVE',
    };

    await _vehiclesReference.child(vehicleId).set(locationPayload);
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
