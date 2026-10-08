import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Handles faculty GPS location updates and reduces GPS noise before sending
/// positions to the faculty screen.
class FacultyLocationService {
  /// Keeps the active GPS listener so it can be stopped safely.
  StreamSubscription<Position>? _positionSubscription;

  /// Sends cleaned location updates to the rest of the app.
  final StreamController<Position> _locationStreamController =
      StreamController<Position>.broadcast();

  /// Other screens listen here for cleaned faculty GPS updates.
  Stream<Position> get locationStream => _locationStreamController.stream;

  /// Stores recent valid GPS readings to reduce map-marker jumping.
  final List<Position> _recentFixes = [];

  /// Number of recent GPS readings used for smoothing.
  static const int _smoothingWindow = 4;

  /// Ignore very inaccurate GPS readings.
  static const double _hardRejectAccuracyMeters = 80.0;

  /// Ignore tiny location changes caused by normal GPS drift.
  static const double _minMovementMeters = 5.0;

  /// Last cleaned location sent to the UI. Used to avoid repeated small updates.
  Position? _lastEmittedPosition;

  /// Simple location and permission helpers used by the faculty screen.
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  Future<LocationPermission> getPermissionStatus() async {
    return await Geolocator.checkPermission();
  }

  Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Gets the first current location quickly. Returns null if GPS is unavailable.
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      return null;
    }
  }

  /// Starts live location tracking and clears old GPS data before a new session.
  Future<bool> startTracking() async {
    await stopTracking();
    _recentFixes.clear();
    _lastEmittedPosition = null;

    late final LocationSettings locationSettings;

    // Ask the device for updates only after small real movement.
    const int driftFilterMeters = 3;

    // Use the best available location settings for each platform.
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: driftFilterMeters,
        intervalDuration: const Duration(seconds: 2),
        forceLocationManager: false,
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: driftFilterMeters,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
      );
    } else {
      locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: driftFilterMeters,
      );
    }

    try {
      // Clean each raw GPS reading before sending it to the faculty screen.
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (Position position) => _handleRawFix(position),
            onError: (error) {},
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Filters inaccurate GPS readings, smooths valid readings, and sends updates
  /// only after meaningful movement.
  void _handleRawFix(Position position) {
    // Ignore this reading if GPS accuracy is too poor.
    if (position.accuracy > _hardRejectAccuracyMeters) {
      return;
    }

    // Keep only the latest readings needed for smoothing.
    _recentFixes.add(position);
    if (_recentFixes.length > _smoothingWindow) {
      _recentFixes.removeAt(0);
    }

    final smoothed = _smoothedPosition(position);

    // Send the first valid location immediately.
    if (_lastEmittedPosition == null) {
      _lastEmittedPosition = smoothed;
      if (!_locationStreamController.isClosed) {
        _locationStreamController.add(smoothed);
      }
      return;
    }

    // Do not send tiny GPS changes when the user is likely standing still.
    final movedMeters = Geolocator.distanceBetween(
      _lastEmittedPosition!.latitude,
      _lastEmittedPosition!.longitude,
      smoothed.latitude,
      smoothed.longitude,
    );

    // Use GPS accuracy to keep the movement filter practical.
    final effectiveThreshold = _minMovementMeters.clamp(
      3.0,
      smoothed.accuracy.clamp(3.0, 15.0),
    );

    if (movedMeters >= effectiveThreshold) {
      _lastEmittedPosition = smoothed;
      if (!_locationStreamController.isClosed) {
        _locationStreamController.add(smoothed);
      }
    }
  }

  /// Combines recent GPS readings to reduce map-marker jumping.
  Position _smoothedPosition(Position latest) {
    if (_recentFixes.length == 1) {
      return latest;
    }

    double weightSum = 0;
    double latSum = 0;
    double lngSum = 0;

    for (final fix in _recentFixes) {
      final effectiveAccuracy = fix.accuracy.clamp(3.0, 100.0);
      // More accurate readings have more influence on the final location.
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

  /// Stops GPS tracking and clears old readings for the next session.
  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _recentFixes.clear();
    _lastEmittedPosition = null;
  }

  /// Closes GPS tracking and the location stream when this service is no longer used.
  void dispose() {
    stopTracking();
    _locationStreamController.close();
  }
}
