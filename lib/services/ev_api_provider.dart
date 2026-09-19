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
    if (_started) {
      return;
    }

    _started = true;

    _databaseSubscription = _vehiclesReference.onValue.listen(
      (event) {
        if (!_started || _locationController.isClosed) {
          return;
        }

        final data = event.snapshot.value;

        if (data is! Map) {
          return;
        }

        bool foundActiveVehicle = false;

        for (final entry in data.entries) {
          final vehicleId = entry.key.toString();
          final rawVehicleData = entry.value;

          if (rawVehicleData is! Map) {
            continue;
          }

          final vehicleData = Map<String, dynamic>.from(rawVehicleData);

          // Only active and connected vehicles are displayed.
          if (!_isVehicleActive(vehicleData) ||
              !_isVehicleConnected(vehicleData)) {
            continue;
          }

          final location = _createLocation(vehicleId, vehicleData);

          if (location == null) {
            continue;
          }

          foundActiveVehicle = true;
          _locationController.add(location);
        }

        // Triggers a fresh read when no active vehicle is found.
        if (!foundActiveVehicle) {
          unawaited(fetchCurrentLocations());
        }
      },
      onError: (error) {
        // Prevents Firebase stream errors from crashing the app.
      },
    );
  }

  @override
  Future<List<EvLocation>> fetchCurrentLocations() async {
    final snapshot = await _vehiclesReference.get();

    final data = snapshot.value;

    if (data is! Map) {
      return [];
    }

    final locations = <EvLocation>[];

    for (final entry in data.entries) {
      final vehicleId = entry.key.toString();
      final rawVehicleData = entry.value;

      if (rawVehicleData is! Map) {
        continue;
      }

      final vehicleData = Map<String, dynamic>.from(rawVehicleData);

      // Only active and connected vehicles are returned.
      if (!_isVehicleActive(vehicleData) || !_isVehicleConnected(vehicleData)) {
        continue;
      }

      final location = _createLocation(vehicleId, vehicleData);

      if (location == null) {
        continue;
      }

      locations.add(location);
    }

    return locations;
  }

  bool _isVehicleActive(Map<String, dynamic> data) {
    final active = data['active'];

    if (active is bool) {
      return active;
    }

    if (active is num) {
      return active != 0;
    }

    return active?.toString().toLowerCase() == 'true';
  }

  bool _isVehicleConnected(Map<String, dynamic> data) {
    final connectionState = data['connectionState']
        ?.toString()
        .toUpperCase()
        .trim();

    return connectionState == 'CONNECTED';
  }

  EvLocation? _createLocation(
    String vehicleId,
    Map<String, dynamic> vehicleData,
  ) {
    final latitude = _toDouble(vehicleData['latitude'] ?? vehicleData['lat']);

    final longitude = _toDouble(
      vehicleData['longitude'] ?? vehicleData['lng'] ?? vehicleData['lon'],
    );

    if (latitude == null || longitude == null) {
      return null;
    }

    final timestamp = _parseTimestamp(vehicleData['timestamp']);

    final speed = _toDouble(vehicleData['speed']) ?? 0.0;

    final heading = _toDouble(vehicleData['heading']) ?? 0.0;

    return EvLocation(
      vehicleId: vehicleId,
      position: LatLng(latitude, longitude),
      timestamp: timestamp,
      speed: speed,
      heading: heading,
    );
  }

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  DateTime _parseTimestamp(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');

    return parsed ?? DateTime.now().toUtc();
  }

  @override
  Future<void> stop() async {
    if (!_started) {
      return;
    }

    _started = false;

    await _databaseSubscription?.cancel();

    _databaseSubscription = null;
  }

  Future<void> dispose() async {
    await stop();

    await _locationController.close();
  }
}
