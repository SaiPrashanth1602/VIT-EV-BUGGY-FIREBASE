import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  bool _isTracking = false;
  String? _vehicleId;
  String? _lastErrorMessage;

  String? get lastErrorMessage => _lastErrorMessage;
  Position? _lastValidPosition;
  Timer? _heartbeatTimer;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;
  void Function(bool connected)? onConnectionChanged;

  static const String _deviceIdKey = 'ev_shuttle_driver_device_id';
  String? _resolvedDriverId;

  Future<String> _getDriverId() async {
    if (_resolvedDriverId != null) return _resolvedDriverId!;
    final preferences = await SharedPreferences.getInstance();
    var savedId = preferences.getString(_deviceIdKey);
    if (savedId == null || savedId.isEmpty) {
      savedId =
          'driver_${DateTime.now().microsecondsSinceEpoch}_${Object().hashCode}';
      await preferences.setString(_deviceIdKey, savedId);
    }
    _resolvedDriverId = savedId;
    return savedId;
  }

  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration networkTimeout = Duration(seconds: 8);

  bool get isTracking => _isTracking;
  String? get vehicleId => _vehicleId;

  static const List<String> vehicleIds = ['EV1', 'EV2'];
  static const Duration normalUpdateInterval = Duration(seconds: 1);

  static const double maxAcceptableAccuracy = 25.0;
  static const double minMovementThreshold = 3.0;
  static const double maxBuggySpeedMetersPerSecond = 12.0;

  final DatabaseReference _vehiclesReference = FirebaseDatabase.instance.ref(
    'evShuttle/vehicles',
  );

  Future<bool> checkAndRequestPermission() async {
    _lastErrorMessage = null;

    if (!await Geolocator.isLocationServiceEnabled()) {
      _lastErrorMessage =
          'Location is turned off. Please enable GPS and try again.';
      print('LOCATION SERVICE IS DISABLED');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _lastErrorMessage = permission == LocationPermission.deniedForever
          ? 'Location permission is permanently denied. Please enable it from App Settings.'
          : 'Location permission is required to track your EV. Please allow permission in Settings.';
      print('LOCATION PERMISSION DENIED: $permission');
      return false;
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<bool> claimVehicle(String selectedVehicleId) async {
    if (!vehicleIds.contains(selectedVehicleId)) return false;

    final reference = _vehiclesReference.child(selectedVehicleId);
    final currentDriverId = await _getDriverId();
    try {
      final result = await reference
          .runTransaction((Object? currentData) {
            final data = currentData is Map
                ? Map<String, dynamic>.from(currentData)
                : <String, dynamic>{};

            final active = data['active'] == true;

            // An active EV cannot be claimed by another shift until END SHIFT.
            // Closing the app or clearing Recents must not release the vehicle.
            if (active) {
              return Transaction.abort();
            }

            data.addAll({
              'vehicleId': selectedVehicleId,
              'active': true,
              'status': 'STARTED',
              'driverId': currentDriverId,
              'shiftStartedAt': DateTime.now().toUtc().toIso8601String(),
              'lastSeen': DateTime.now().toUtc().toIso8601String(),
              'connectionState': 'CONNECTED',
            });

            return Transaction.success(data);
          }, applyLocally: false)
          .timeout(networkTimeout);

      if (!result.committed) {
        _lastErrorMessage =
            'This EV is currently assigned to another driver. Please choose another EV.';
      }
      return result.committed;
    } catch (error) {
      _lastErrorMessage =
          'Unable to connect to the server. Please check your internet connection and try again.';
      print('CLAIM VEHICLE ERROR: $error');
      return false;
    }
  }

  Future<bool> startTracking(String selectedVehicleId) async {
    return _activateTracking(selectedVehicleId, claim: true);
  }

  Future<bool> restoreTracking(String existingVehicleId) async {
    if (_isTracking) return true;
    return _activateTracking(existingVehicleId, claim: false);
  }

  Future<bool> _activateTracking(
    String selectedVehicleId, {
    required bool claim,
  }) async {
    if (_isTracking) return true;

    if (!await checkAndRequestPermission()) {
      return false;
    }

    if (claim) {
      final claimed = await claimVehicle(selectedVehicleId);
      if (!claimed) return false;
    }

    _vehicleId = selectedVehicleId;
    _isTracking = true;
    _lastValidPosition = null;

    try {
      final currentDriverId = await _getDriverId();
      if (claim) {
        await sendShiftEvent(vehicleId: _vehicleId!, status: 'STARTED');
      } else {
        // Reconnect an already active shift without creating a new STARTED event
        // or changing the existing shift state.
        await _vehiclesReference
            .child(_vehicleId!)
            .update({
              'vehicleId': _vehicleId,
              'active': true,
              'status': 'ACTIVE',
              'driverId': currentDriverId,
              'connectionState': 'CONNECTED',
              'lastSeen': DateTime.now().toUtc().toIso8601String(),
            })
            .timeout(networkTimeout);
      }

      await _registerDisconnectHandler(_vehicleId!);
      _startConnectionMonitor();
      _startHeartbeat();

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
      _lastErrorMessage ??=
          'Unable to connect to the server. Please check your internet connection and try again.';
      print('START TRACKING ERROR: $error');
      // Never end an existing shift just because reconnecting failed.
      // Only a deliberate END SHIFT should release the vehicle.
      if (claim) {
        await releaseVehicleSlot(_vehicleId);
      }
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

  void _startConnectionMonitor() {
    _connectionSubscription?.cancel();
    _connectionSubscription = FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen(
          (event) {
            final connected = event.snapshot.value == true;
            onConnectionChanged?.call(connected);
            if (!connected) {
              print('NETWORK DISCONNECTED DURING ACTIVE SHIFT');
            } else {
              print('NETWORK CONNECTED DURING ACTIVE SHIFT');
            }
          },
          onError: (Object error) {
            onConnectionChanged?.call(false);
            print('CONNECTION MONITOR ERROR: $error');
          },
        );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) async {
      final vehicleId = _vehicleId;
      if (!_isTracking || vehicleId == null) return;
      final currentDriverId = await _getDriverId();
      await _vehiclesReference.child(vehicleId).update({
        'lastSeen': DateTime.now().toUtc().toIso8601String(),
        'connectionState': 'CONNECTED',
        'driverId': currentDriverId,
      });
    });
  }

  Future<void> _registerDisconnectHandler(String vehicleId) async {
    await _vehiclesReference
        .child(vehicleId)
        .onDisconnect()
        .update({'connectionState': 'DISCONNECTED'})
        .timeout(networkTimeout);
  }

  Future<String?> findExistingShift() async {
    final currentDriverId = await _getDriverId();
    for (final vehicleId in vehicleIds) {
      final snapshot = await _vehiclesReference
          .child(vehicleId)
          .get()
          .timeout(networkTimeout);
      if (!snapshot.exists || snapshot.value is! Map) continue;

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final active = data['active'] == true;
      final status = data['status']?.toString().toUpperCase();

      print(
        'SHIFT CHECK $vehicleId: active=$active, status=$status, '
        'driverId=${data['driverId']}',
      );

      // Firebase data shown by your app contains active=true and status=ACTIVE.
      // Accept ACTIVE and STARTED so reopening works during either phase.
      final recordDriverId = data['driverId']?.toString();
      final belongsToThisPhone = recordDriverId == currentDriverId;

      if (active && status != 'ENDED' && belongsToThisPhone) {
        print('EXISTING SHIFT FOUND: $vehicleId');
        return vehicleId;
      }
    }

    print('NO EXISTING ACTIVE SHIFT FOUND');
    return null;
  }

  Future<void> stopTracking() async {
    if (!_isTracking) return;

    final vehicleId = _vehicleId;

    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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

    await _vehiclesReference
        .child(vehicleId)
        .update({
          'active': false,
          'status': 'ENDED',
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        })
        .timeout(networkTimeout);
  }

  Future<void> sendLocation({
    required String vehicleId,
    required Position position,
  }) async {
    final currentDriverId = await _getDriverId();
    await _vehiclesReference
        .child(vehicleId)
        .update({
          'vehicleId': vehicleId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'speed': position.speed,
          'heading': position.heading,
          'accuracy': position.accuracy,
          'active': true,
          'status': 'ACTIVE',
          'driverId': currentDriverId,
          'lastSeen': DateTime.now().toUtc().toIso8601String(),
          'connectionState': 'CONNECTED',
        })
        .timeout(networkTimeout);
  }

  Future<void> sendShiftEvent({
    required String vehicleId,
    required String status,
  }) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final currentDriverId = await _getDriverId();

    await _vehiclesReference.child(vehicleId).update({
      'vehicleId': vehicleId,
      'status': status,
      'active': status == 'STARTED',
      'driverId': status == 'ENDED' ? null : currentDriverId,
      'lastSeen': timestamp,
      'connectionState': status == 'ENDED' ? 'DISCONNECTED' : 'CONNECTED',
      'updatedAt': timestamp,
    });

    await FirebaseDatabase.instance.ref('evShuttle/shiftEvents').push().set({
      'vehicleId': vehicleId,
      'status': status,
      'timestamp': timestamp,
    });
  }
}
