import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Handles high-accuracy faculty location tracking for the VIT EV Buggy app.
///
/// Pipeline for every raw GPS fix from the OS:
///   1. Hard-reject only genuinely broken fixes (accuracy > 80m).
///   2. Weighted-average the last few accepted fixes (tighter fixes count
///      more) to smooth out normal GPS jitter.
///   3. Only emit the smoothed position if it moved far enough from the
///      last emitted position to be real movement, not noise. The
///      required distance adapts to fix quality (3-15m).
class FacultyLocationService {
  StreamSubscription<Position>? _positionSubscription;
  final StreamController<Position> _locationStreamController =
      StreamController<Position>.broadcast();

  Stream<Position> get locationStream => _locationStreamController.stream;

  final List<Position> _recentFixes = [];
  static const int _smoothingWindow = 4;

  // Only reject fixes the OS itself admits are badly broken. Real phones
  // commonly report 15-40m accuracy even outdoors near buildings/trees;
  // rejecting those outright freezes the marker entirely.
  static const double _hardRejectAccuracyMeters = 80.0;

  // Base minimum displacement (meters) required before a new smoothed fix
  // is treated as real movement. 5m is the tested sweet spot for
  // walking-speed pedestrian tracking: 3m barely filters GPS noise, 10m+
  // makes the marker feel laggy/broken during normal walking or a demo.
  static const double _minMovementMeters = 5.0;

  Position? _lastEmittedPosition;

  /// Checks if location services are enabled on the device.
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Gets current location permission status.
  Future<LocationPermission> getPermissionStatus() async {
    return await Geolocator.checkPermission();
  }

  /// Requests location permission from the user.
  Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  /// Opens location settings.
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Opens app settings.
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Fetches current position immediately, at the highest accuracy tier.
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

  /// Starts high-precision location tracking, filtered for GPS drift.
  Future<bool> startTracking() async {
    await stopTracking();
    _recentFixes.clear();
    _lastEmittedPosition = null;

    late final LocationSettings locationSettings;

    // OS-level distance filter (separate from our own smoothing above).
    // 3m here just stops the OS from firing callbacks for sub-3m twitches
    // before the fix even reaches our code.
    const int driftFilterMeters = 3;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        // best == bestForNavigation on Android; there's no extra tier.
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
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (Position position) => _handleRawFix(position),
            onError: (error) {
              // Handle stream location errors gracefully
            },
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleRawFix(Position position) {
    if (position.accuracy > _hardRejectAccuracyMeters) {
      return;
    }

    _recentFixes.add(position);
    if (_recentFixes.length > _smoothingWindow) {
      _recentFixes.removeAt(0);
    }

    final smoothed = _smoothedPosition(position);

    // First-ever fix: emit immediately so the marker appears right away
    // instead of waiting for "movement" measured from nothing.
    if (_lastEmittedPosition == null) {
      _lastEmittedPosition = smoothed;
      if (!_locationStreamController.isClosed) {
        _locationStreamController.add(smoothed);
      }
      return;
    }

    final movedMeters = Geolocator.distanceBetween(
      _lastEmittedPosition!.latitude,
      _lastEmittedPosition!.longitude,
      smoothed.latitude,
      smoothed.longitude,
    );

    // Adapt the required displacement to fix quality: tighter fixes need
    // less movement to be believed, noisy fixes need more.
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
    // else: treated as jitter, last emitted position stands.
  }

  /// Weighted average of recent fixes; tighter (lower-accuracy-number)
  /// fixes count more. Prevents one noisy sample from yanking the marker.
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

  /// Stops tracking updates.
  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _recentFixes.clear();
    _lastEmittedPosition = null;
  }

  /// Disposes of stream controller resources.
  void dispose() {
    stopTracking();
    _locationStreamController.close();
  }
}
