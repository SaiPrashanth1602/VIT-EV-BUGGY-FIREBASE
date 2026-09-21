import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';

import 'ev_location_provider.dart';

class EvApiProvider implements EvLocationProvider {
  EvApiProvider();

  final StreamController<EvLocation> _locationController =
      StreamController<EvLocation>.broadcast();

  final DatabaseReference _vehiclesReference = FirebaseDatabase.instance.ref(
    'evShuttle/vehicles',
  );

  StreamSubscription<DatabaseEvent>? _databaseSubscription;

  bool _started = false;

  @override
  Stream<EvLocation> get locationStream => _locationController.stream;

  @override
  Future<void> start() async {
    if (_started) return;

    _started = true;

    try {
      // Listen for real-time updates
      _databaseSubscription = _vehiclesReference.onValue.listen(
        (event) {
          if (!_started || _locationController.isClosed) return;

          final locations = _parseLocations(event.snapshot.value);

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

      // Fetch current locations immediately
      final snapshot = await _vehiclesReference.get();

      if (!_started || _locationController.isClosed) return;

      final locations = _parseLocations(snapshot.value);

      for (final location in locations) {
        _locationController.add(location);
      }

      print('✅ INITIAL EV FETCH: ${locations.length} ACTIVE EV LOCATION(S)');
    } catch (error) {
      print('❌ EV PROVIDER START ERROR: $error');
    }
  }

  @override
  Future<List<EvLocation>> fetchCurrentLocations() async {
    try {
      final snapshot = await _vehiclesReference.get();

      final locations = _parseLocations(snapshot.value);

      locations.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return locations;
    } catch (error) {
      print('❌ FETCH CURRENT EV LOCATIONS ERROR: $error');
      return [];
    }
  }

  List<EvLocation> _parseLocations(dynamic data) {
    final locations = <EvLocation>[];

    if (data is! Map) {
      return locations;
    }

    for (final entry in data.entries) {
      final vehicleId = entry.key.toString();
      final vehicleData = entry.value;

      if (vehicleData is! Map) {
        continue;
      }

      final active = vehicleData['active'] == true;

      final connectionState = vehicleData['connectionState']
          ?.toString()
          .toUpperCase()
          .trim();

      final isOnline = vehicleData['isOnline'] == true;

      // Accept the driver's current connectionState field.
      // Also support isOnline for backward compatibility.
      final online = connectionState == 'CONNECTED' || isOnline;

      if (!active || !online) {
        print(
          '⏭️ SKIPPING $vehicleId | active=$active | '
          'connectionState=$connectionState | isOnline=$isOnline',
        );
        continue;
      }

      final latitude = _toDouble(vehicleData['latitude'] ?? vehicleData['lat']);

      final longitude = _toDouble(
        vehicleData['longitude'] ?? vehicleData['lng'] ?? vehicleData['lon'],
      );

      if (latitude == null || longitude == null) {
        print('⚠️ INVALID LOCATION FOR $vehicleId');
        continue;
      }

      final timestamp = _parseTimestamp(
        vehicleData['timestamp'] ??
            vehicleData['lastUpdated'] ??
            vehicleData['updatedAt'],
      );

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
    if (!_started) return;

    _started = false;

    await _databaseSubscription?.cancel();

    _databaseSubscription = null;

    print('🛑 EV PROVIDER STOPPED');
  }

  Future<void> dispose() async {
    await stop();

    await _locationController.close();
  }

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  DateTime _parseTimestamp(dynamic value) {
    if (value is num) {
      final raw = value.toInt();

      final milliseconds = raw < 100000000000 ? raw * 1000 : raw;

      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }

    final parsed = DateTime.tryParse(value?.toString() ?? '');

    return parsed?.toUtc() ?? DateTime.now().toUtc();
  }
}
