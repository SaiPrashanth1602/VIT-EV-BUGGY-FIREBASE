// VIT EV BUGGY Driver location service.
// Handles GPS tracking, EV allocation, Firebase updates and shift lifecycle.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_core/firebase_core.dart';
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
  Timer? _shiftExpiryTimer;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;
  void Function(bool connected)? onConnectionChanged;
  void Function()? onShiftAutoEnded;

  static const String _deviceIdKey = 'ev_shuttle_driver_device_id';
  String? _resolvedDriverId;

  // Stores a persistent device-specific driver ID using SharedPreferences.
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

  // Driver configuration: EV1/EV2, 30-minute shifts and Firebase heartbeat.
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration maximumShiftDuration = Duration(minutes: 30);
  static const Duration networkTimeout = Duration(seconds: 8);

  bool get isTracking => _isTracking;
  String? get vehicleId => _vehicleId;

  static const List<String> vehicleIds = ['EV1', 'EV2'];
  static const Duration normalUpdateInterval = Duration(seconds: 1);

  static const double maxAcceptableAccuracy = 25.0;
  static const double minMovementThreshold = 3.0;
  static const double maxBuggySpeedMetersPerSecond = 12.0;

  FirebaseDatabase? _databaseInstance;

  FirebaseDatabase get _database {
    final app = Firebase.apps.isNotEmpty ? Firebase.app() : null;
    if (app == null) {
      throw FirebaseException(
        plugin: 'firebase_database',
        code: 'no-app',
        message: 'Firebase has not been initialized for this app instance.',
      );
    }

    // Firebase Realtime Database shared by Driver, Faculty and Admin apps.
    _databaseInstance ??= FirebaseDatabase.instanceFor(
      app: app,
      databaseURL:
          'https://vit-ev-buggy-demo-default-rtdb.asia-southeast1.firebasedatabase.app',
    );

    return _databaseInstance!;
  }

  // evShuttle/vehicles stores the live state and location of EV1 and EV2.
  DatabaseReference get _vehiclesReference =>
      _database.ref('evShuttle/vehicles');

  // Uses Firebase .info/connected to monitor Realtime Database connectivity.
  Future<bool> _isRealtimeDatabaseConnected() async {
    if (Firebase.apps.isEmpty) {
      return false;
    }

    try {
      final snapshot = await _database
          .ref('.info/connected')
          .get()
          .timeout(const Duration(seconds: 2));
      return snapshot.value == true || snapshot.value == null;
    } catch (_) {
      return true;
    }
  }

  // Reads Firebase with a timeout to avoid waiting indefinitely on network failure.
  Future<DataSnapshot?> _safeReadSnapshot(
    DatabaseReference reference, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (Firebase.apps.isEmpty) {
      return null;
    }

    try {
      return await reference.get().timeout(timeout);
    } catch (error) {
      try {
        final event = await reference.once().timeout(
          const Duration(seconds: 2),
        );
        return event.snapshot;
      } catch (_) {
        debugPrint('RTDB READ FAILED FOR ${reference.path}: $error');
        return null;
      }
    }
  }

  // Checks that device location services and required GPS permissions are available.
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

  // Recovers stale Firebase shifts that have exceeded the 30-minute limit.
  Future<bool> _endExpiredShiftIfNeeded(String selectedVehicleId) async {
    final reference = _vehiclesReference.child(selectedVehicleId);

    try {
      final snapshot = await reference.get().timeout(networkTimeout);

      if (!snapshot.exists || snapshot.value is! Map) {
        return true;
      }

      final data = Map<String, dynamic>.from(snapshot.value as Map);

      if (data['active'] != true) {
        return true;
      }

      final startedAt = DateTime.tryParse(
        data['shiftStartedAt']?.toString() ?? '',
      )?.toUtc();

      if (startedAt == null) {
        return true;
      }

      final now = DateTime.now().toUtc();
      if (now.difference(startedAt) < maximumShiftDuration) {
        return true;
      }

      final expectedStartedAt = startedAt.toIso8601String();

      // Transaction safely updates the EV only if the existing shift is still unchanged.
      final result = await reference
          .runTransaction((Object? currentData) {
            if (currentData is! Map) {
              return Transaction.abort();
            }

            final current = Map<String, dynamic>.from(currentData);

            if (current['active'] != true) {
              return Transaction.success(current);
            }

            final currentStartedAt = DateTime.tryParse(
              current['shiftStartedAt']?.toString() ?? '',
            )?.toUtc();

            if (currentStartedAt == null ||
                currentStartedAt.toIso8601String() != expectedStartedAt) {
              return Transaction.abort();
            }

            final transactionNow = DateTime.now().toUtc();
            if (transactionNow.difference(currentStartedAt) <
                maximumShiftDuration) {
              return Transaction.abort();
            }

            current.addAll({
              'active': false,
              'status': 'ENDED',
              'driverId': null,
              'connectionState': 'DISCONNECTED',
              'updatedAt': transactionNow.toIso8601String(),
            });

            return Transaction.success(current);
          }, applyLocally: false)
          .timeout(networkTimeout);

      if (result.committed) {
        try {
          await _database
              .ref('evShuttle/shiftEvents')
              .push()
              .set({
                'vehicleId': selectedVehicleId,
                'status': 'ENDED',
                'reason': 'AUTO_EXPIRED',
                'timestamp': now.toIso8601String(),
              })
              .timeout(networkTimeout);
        } catch (eventError) {
          print('EXPIRED SHIFT EVENT ERROR: $eventError');
        }
      }

      return result.committed;
    } catch (error) {
      print('EXPIRED SHIFT CHECK ERROR: $error');
      return false;
    }
  }

  // Atomically claims EV1 or EV2 so two drivers cannot claim the same EV.
  Future<bool> claimVehicle(String selectedVehicleId) async {
    if (!vehicleIds.contains(selectedVehicleId)) return false;

    final reference = _vehiclesReference.child(selectedVehicleId);
    final currentDriverId = await _getDriverId();

    try {
      final expiredCheck = await _endExpiredShiftIfNeeded(selectedVehicleId);
      if (!expiredCheck) {
        _lastErrorMessage =
            'Unable to verify the EV shift status. Please check your internet connection and try again.';
        return false;
      }

      final result = await reference
          .runTransaction((Object? currentData) {
            final data = currentData is Map
                ? Map<String, dynamic>.from(currentData)
                : <String, dynamic>{};

            final active = data['active'] == true;

            if (active) {
              return Transaction.abort();
            }

            final now = DateTime.now().toUtc().toIso8601String();
            data.addAll({
              'vehicleId': selectedVehicleId,
              'active': true,
              'status': 'STARTED',
              'driverId': currentDriverId,
              'shiftStartedAt': now,
              'lastSeen': now,
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

  // Starts a new driver shift and claims the selected EV.
  Future<bool> startTracking(String selectedVehicleId) async {
    return _activateTracking(selectedVehicleId, claim: true);
  }

  // Restores an existing active shift belonging to this device.
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
        // Records the shift start for Admin shift history.
        await sendShiftEvent(vehicleId: _vehicleId!, status: 'STARTED');
      } else {
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
      await _scheduleShiftExpiry(_vehicleId!);
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

      // Configures continuous GPS tracking for the active EV.
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
      if (claim) {
        await releaseVehicleSlot(_vehicleId);
      }
      _vehicleId = null;
      _isTracking = false;
      _lastValidPosition = null;
      return false;
    }
  }

  // Validates GPS data before accepting and sending a vehicle position.
  Future<void> _handlePosition(Position position) async {
    if (!_isTracking || _vehicleId == null) return;

    final vehicleId = _vehicleId!;

    // Rejects inaccurate GPS readings.
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

      // Ignores tiny movements caused by GPS jitter.
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

        // Rejects unrealistic GPS speed spikes.
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

  // Monitors Firebase connectivity while the driver shift is active.
  void _startConnectionMonitor() {
    _connectionSubscription?.cancel();
    _connectionSubscription = _database
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

  // Schedules automatic shift termination from the Firebase shift start time.
  Future<void> _scheduleShiftExpiry(String vehicleId) async {
    _shiftExpiryTimer?.cancel();

    final snapshot = await _safeReadSnapshot(
      _vehiclesReference.child(vehicleId),
      timeout: const Duration(seconds: 3),
    );
    if (snapshot == null || !snapshot.exists || snapshot.value is! Map) return;

    final data = Map<String, dynamic>.from(snapshot.value as Map);
    final startedAtText = data['shiftStartedAt']?.toString();
    final startedAt = DateTime.tryParse(startedAtText ?? '')?.toUtc();
    if (startedAt == null) return;

    final expiryTime = startedAt.add(maximumShiftDuration);
    final remaining = expiryTime.difference(DateTime.now().toUtc());

    if (remaining <= Duration.zero) {
      await stopTracking();
      onShiftAutoEnded?.call();
      return;
    }

    _shiftExpiryTimer = Timer(remaining, () async {
      if (!_isTracking || _vehicleId != vehicleId) return;
      print('30-MINUTE SHIFT LIMIT REACHED. ENDING SHIFT.');
      await stopTracking();
      onShiftAutoEnded?.call();
    });
  }

  // Periodically refreshes lastSeen and connection state while the shift is active.
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

  // Firebase onDisconnect marks the vehicle disconnected after unexpected loss.
  Future<void> _registerDisconnectHandler(String vehicleId) async {
    await _vehiclesReference
        .child(vehicleId)
        .onDisconnect()
        .update({'connectionState': 'DISCONNECTED'})
        .timeout(networkTimeout);
  }

  // Finds an active EV shift belonging to this device for shift restoration.
  Future<String?> findExistingShift() async {
    final currentDriverId = await _getDriverId();
    for (final vehicleId in vehicleIds) {
      final snapshot = await _safeReadSnapshot(
        _vehiclesReference.child(vehicleId),
        timeout: const Duration(seconds: 3),
      );
      if (snapshot == null || !snapshot.exists || snapshot.value is! Map) {
        continue;
      }

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final active = data['active'] == true;
      final status = data['status']?.toString().toUpperCase();

      print(
        'SHIFT CHECK $vehicleId: active=$active, status=$status, '
        'driverId=${data['driverId']}',
      );

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

  // Ends the shift, stops local tracking and records the END event.
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    final vehicleId = _vehicleId;

    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _shiftExpiryTimer?.cancel();
    _shiftExpiryTimer = null;
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

  // Releases the EV so it can be allocated to another driver.
  Future<void> releaseVehicleSlot(String? vehicleId) async {
    if (vehicleId == null) return;

    await _vehiclesReference
        .child(vehicleId)
        .update({
          'active': false,
          'status': 'ENDED',
          'connectionState': 'DISCONNECTED',
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        })
        .timeout(networkTimeout);
  }

  // Sends validated live EV location and operational state to Firebase.
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

  // Stores STARTED/ENDED shift events used by the Admin application.
  Future<void> sendShiftEvent({
    required String vehicleId,
    required String status,
  }) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final currentDriverId = await _getDriverId();

    await _vehiclesReference.child(vehicleId).update({
      'vehicleId': vehicleId,
      'status': status,
      'active': status != 'ENDED',
      'driverId': status == 'ENDED' ? null : currentDriverId,
      'lastSeen': timestamp,
      'connectionState': status == 'ENDED' ? 'DISCONNECTED' : 'CONNECTED',
      'updatedAt': timestamp,
    });

    await _database.ref('evShuttle/shiftEvents').push().set({
      'vehicleId': vehicleId,
      'status': status,
      'timestamp': timestamp,
    });
  }
}
