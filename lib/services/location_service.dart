import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  bool _isTracking = false;
  bool _isStreaming = false;

  String? _vehicleId;
  DateTime? _lastMovementTime;
  Position? _lastPosition;

  // Rolling buffer for accuracy-weighted smoothing, same approach used in
  // the faculty app's FacultyLocationService. Prevents a single noisy GPS
  // fix from making the EV marker jump or from being pushed to Firebase
  // and shown wrong on every faculty device watching the stream.
  final List<Position> _recentFixes = [];
  static const int _smoothingWindow = 4;

  bool get isTracking => _isTracking;
  String? get vehicleId => _vehicleId;

  static const List<String> vehicleIds = ['EV1', 'EV2', 'EV3', 'EV4'];

  static const Duration normalUpdateInterval = Duration(seconds: 1);

  static const Duration stationaryTimeout = Duration(seconds: 120);

  // Base minimum displacement required to count as real movement. Same
  // value tuned for the faculty app; works for vehicle speed too since
  // it's evaluated per fix, not per second.
  static const double movementThresholdMeters = 5.0;

  // Reject only fixes the OS itself admits are badly broken (GPS
  // cold-start spikes). Do NOT set this low — real phones routinely
  // report 15-40m accuracy outdoors near buildings, and rejecting those
  // would silently stop the EV from broadcasting its location at all.
  static const double hardRejectAccuracyMeters = 80.0;

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

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<String?> allocateVehicleSlot() async {
    /*
     * DEMO SLOT ALLOCATION
     *
     * For the Transport Manager demo we use EV1.
     *
     * In the final Java backend:
     * the server will atomically allocate the
     * first available slot from EV1-EV4.
     */

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
    _recentFixes.clear();

    await sendShiftEvent(vehicleId: _vehicleId!, status: 'STARTED');

    final locationSettings = AndroidSettings(
      // `best` requests the tightest GNSS fix tier available (same as
      // `bestForNavigation` on Android — there is no separate tier).
      accuracy: LocationAccuracy.best,
      // OS-level distance filter left at 0 intentionally: the vehicle is
      // always moving during a shift, and our own smoothing + movement
      // gate below (in _handlePosition) does the real filtering. Setting
      // this above 0 would also suppress the stationary-timeout fixes we
      // need to detect that the EV has actually stopped.
      distanceFilter: 0,
      intervalDuration: normalUpdateInterval,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
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

  void _handlePosition(Position rawPosition) {
    if (!_isTracking || _vehicleId == null) {
      return;
    }

    // Drop only genuinely broken fixes (cold-start spikes). Everything
    // else is used, weighted by quality, so the vehicle never goes
    // "silent" on Firebase just because signal briefly got noisy.
    if (rawPosition.accuracy > hardRejectAccuracyMeters) {
      return;
    }

    _recentFixes.add(rawPosition);
    if (_recentFixes.length > _smoothingWindow) {
      _recentFixes.removeAt(0);
    }

    final position = _smoothedPosition(rawPosition);

    final now = DateTime.now();

    bool hasMoved = false;

    if (_lastPosition != null) {
      final distance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // Adapt required displacement to fix quality, same logic as the
      // faculty app: tighter fixes need less movement to be believed,
      // noisy fixes need more, so jitter never reads as "moving."
      final effectiveThreshold = movementThresholdMeters.clamp(
        3.0,
        position.accuracy.clamp(3.0, 15.0),
      );

      hasMoved = distance >= effectiveThreshold || position.speed >= 1.0;
    } else {
      // First-ever fix for this shift: treat as movement so the vehicle
      // appears on the faculty map immediately.
      hasMoved = true;
    }

    if (hasMoved) {
      _lastMovementTime = now;
      _lastPosition = position;

      _isStreaming = true;
    } else if (_lastMovementTime != null &&
        now.difference(_lastMovementTime!) >= stationaryTimeout) {
      _isStreaming = false;
    }

    if (_isStreaming) {
      sendLocation(vehicleId: _vehicleId!, position: position);
    }

    if (_lastPosition == null) {
      _lastPosition = position;
    }
  }

  /// Weighted average of recent fixes; tighter (lower-accuracy-number)
  /// fixes count more. Smooths jitter before it ever reaches Firebase,
  /// so every faculty device watching the stream sees the same clean
  /// position instead of raw GPS noise.
  Position _smoothedPosition(Position latest) {
    if (_recentFixes.length == 1) {
      return latest;
    }

    double weightSum = 0;
    double latSum = 0;
    double lngSum = 0;

    for (final fix in _recentFixes) {
      final effectiveAccuracy = fix.accuracy.clamp(3.0, 100.0);
      final weight = 1 / (effectiveAccuracy * effectiveAccuracy);
      weightSum += weight;
      latSum += fix.latitude * weight;
      lngSum += fix.longitude * weight;
    }

    return Position(
      latitude: latSum / weightSum,
      longitude: lngSum / weightSum,
      timestamp: latest.timestamp,
      accuracy: latest.accuracy,
      altitude: latest.altitude,
      altitudeAccuracy: latest.altitudeAccuracy,
      heading: latest.heading,
      headingAccuracy: latest.headingAccuracy,
      speed: latest.speed,
      speedAccuracy: latest.speedAccuracy,
      floor: latest.floor,
      isMocked: latest.isMocked,
    );
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
    _recentFixes.clear();

    if (vehicleId != null) {
      await sendShiftEvent(vehicleId: vehicleId, status: 'ENDED');

      await releaseVehicleSlot(vehicleId);
    }
  }

  Future<void> releaseVehicleSlot(String? vehicleId) async {
    if (vehicleId == null) {
      return;
    }

    /*
     * The tracking node remains available so Faculty
     * can see that the vehicle is no longer active.
     *
     * Final Java backend will handle actual slot
     * allocation and release.
     */

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
