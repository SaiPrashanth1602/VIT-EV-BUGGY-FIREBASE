import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';

import 'ev_location_provider.dart';

/// Reads live EV locations from Firebase for the faculty app.
/// It sends active and online vehicle updates to the rest of the app.
class EvApiProvider implements EvLocationProvider {
  EvApiProvider();

  // Sends EV updates to all listeners, such as the faculty map screen.
  final StreamController<EvLocation> _locationController =
      StreamController<EvLocation>.broadcast();

  // Firebase path where EV1, EV2, and other vehicle data is stored.
  final DatabaseReference _vehiclesReference = FirebaseDatabase.instance.ref(
    'evShuttle/vehicles',
  );

  // Keeps the Firebase listener so it can be stopped safely.
  StreamSubscription<DatabaseEvent>? _databaseSubscription;

  // Prevents the app from starting the same Firebase listener more than once.
  bool _started = false;

  // Other parts of the app listen here for live EV location updates.
  @override
  Stream<EvLocation> get locationStream => _locationController.stream;

  @override
  Future<void> start() async {
    // Do not start another Firebase listener if tracking is already running.
    if (_started) return;

    _started = true;

    try {
      _databaseSubscription = _vehiclesReference.onValue.listen(
        (event) {
          // Stop sending updates if this provider has been stopped or closed.
          if (!_started || _locationController.isClosed) return;

          // Read all current vehicle records from Firebase.
          final locations = _parseLocations(event.snapshot.value);

          // Send each active EV update to the faculty screen.
          for (final location in locations) {
            _locationController.add(location);
          }

          print(
            '📡 FACULTY RECEIVED ${locations.length} ACTIVE EV LOCATION(S)',
          );
        },
        onError: (error) {
          print('❌ FIREBASE EV STREAM ERROR: $error');
        },
      );

      // Read the latest EV data once when the app starts.
      final snapshot = await _vehiclesReference.get();

      // Do not add updates after the provider has been stopped.
      if (!_started || _locationController.isClosed) return;

      // Read all current vehicle records from Firebase.
      final locations = _parseLocations(snapshot.value);

      // Send each active EV update to the faculty screen.
      for (final location in locations) {
        _locationController.add(location);
      }

      print('✅ INITIAL EV FETCH: ${locations.length} ACTIVE EV LOCATION(S)');
    } catch (error) {
      // Keep the faculty screen running even if Firebase is temporarily unavailable.
      print('❌ EV PROVIDER START ERROR: $error');
    }
  }

  /// Gets the latest active EV locations for refresh or status checks.
  @override
  Future<List<EvLocation>> fetchCurrentLocations() async {
    try {
      // Read the current data from Firebase.
      final snapshot = await _vehiclesReference.get();

      final locations = _parseLocations(snapshot.value);

      locations.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return locations;
    } catch (error) {
      // Return an empty list if Firebase cannot be reached.
      print('❌ FETCH CURRENT EV LOCATIONS ERROR: $error');
      return [];
    }
  }

  // Converts Firebase vehicle data into `EvLocation` objects.
  List<EvLocation> _parseLocations(dynamic data) {
    final locations = <EvLocation>[];

    // Return no locations if Firebase has no vehicle data.
    if (data is! Map) {
      return locations;
    }

    for (final entry in data.entries) {
      final vehicleId = entry.key.toString();
      final vehicleData = entry.value;

      // Skip this EV if its saved data is not valid.
      if (vehicleData is! Map) {
        continue;
      }

      // Only show vehicles that are active and connected.
      final active = vehicleData['active'] == true;

      final connectionState = vehicleData['connectionState']
          ?.toString()
          .toUpperCase()
          .trim();

      final isOnline = vehicleData['isOnline'] == true;

      // Some driver versions use `connectionState`; others use `isOnline`.
      final online = connectionState == 'CONNECTED' || isOnline;

      if (!active || !online) {
        print(
          '⏭️ SKIPPING $vehicleId | active=$active | '
          'connectionState=$connectionState | isOnline=$isOnline',
        );
        continue;
      }

      // Support different field names used for latitude and longitude.
      final latitude = _toDouble(vehicleData['latitude'] ?? vehicleData['lat']);

      final longitude = _toDouble(
        vehicleData['longitude'] ?? vehicleData['lng'] ?? vehicleData['lon'],
      );

      // Skip this EV if its location is missing or invalid.
      if (latitude == null || longitude == null) {
        print('⚠️ INVALID LOCATION FOR $vehicleId');
        continue;
      }

      // Support different timestamp field names from older data.
      final timestamp = _parseTimestamp(
        vehicleData['timestamp'] ??
            vehicleData['lastUpdated'] ??
            vehicleData['updatedAt'],
      );

      // Speed and heading are optional. Use zero if Firebase does not send them.
      final speed = _toDouble(vehicleData['speed']) ?? 0.0;

      final heading = _toDouble(vehicleData['heading']) ?? 0.0;

      locations.add(
        EvLocation(
          vehicleId: vehicleId,
          position: LatLng(latitude, longitude),
          timestamp: timestamp,
          speed: speed,
          heading: heading,
        ),
      );

      print(
        '✅ EV LOCATION PARSED: $vehicleId | '
        '$latitude, $longitude | $connectionState',
      );
    }

    return locations;
  }

  @override
  Future<void> stop() async {
    // Stop only if Firebase tracking is currently running.
    if (!_started) return;

    // Mark it stopped before canceling the Firebase listener.
    _started = false;

    // Stop receiving live updates from Firebase.
    await _databaseSubscription?.cancel();

    _databaseSubscription = null;

    print('🛑 EV PROVIDER STOPPED');
  }

  Future<void> dispose() async {
    // Close Firebase tracking and the stream when this provider is no longer used.
    await stop();

    await _locationController.close();
  }

  // Converts Firebase values safely because they may be numbers or text.
  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  // Converts Firebase timestamps into UTC time for the rest of the app.
  DateTime _parseTimestamp(dynamic value) {
    // Firebase may store Unix time in seconds or milliseconds.
    if (value is num) {
      final raw = value.toInt();

      final milliseconds = raw < 100000000000 ? raw * 1000 : raw;

      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }

    final parsed = DateTime.tryParse(value?.toString() ?? '');

    // Use the current UTC time if Firebase has no valid timestamp.
    return parsed?.toUtc() ?? DateTime.now().toUtc();
  }
}
