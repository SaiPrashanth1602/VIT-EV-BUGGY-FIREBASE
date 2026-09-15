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

    _databaseSubscription = _vehiclesReference.onValue.listen((event) {
      if (!_started || _locationController.isClosed) {
        return;
      }

      final data = event.snapshot.value;

      if (data is! Map) {
        return;
      }

      for (final entry in data.entries) {
        final vehicleId = entry.key.toString();
        final vehicleData = entry.value;

        if (vehicleData is! Map) {
          continue;
        }

        final active = vehicleData['active'] == true;

        if (!active) {
          continue;
        }

        final latitude = _toDouble(vehicleData['latitude']);

        final longitude = _toDouble(vehicleData['longitude']);

        if (latitude == null || longitude == null) {
          continue;
        }

        final timestamp = _parseTimestamp(vehicleData['timestamp']);

        final speed = _toDouble(vehicleData['speed']) ?? 0.0;

        final heading = _toDouble(vehicleData['heading']) ?? 0.0;

        final location = EvLocation(
          vehicleId: vehicleId,
          position: LatLng(latitude, longitude),
          timestamp: timestamp,
          speed: speed,
          heading: heading,
        );

        _locationController.add(location);
      }
    });
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
      final vehicleData = entry.value;

      if (vehicleData is! Map) {
        continue;
      }

      if (vehicleData['active'] != true) {
        continue;
      }

      final latitude = _toDouble(vehicleData['latitude']);

      final longitude = _toDouble(vehicleData['longitude']);

      if (latitude == null || longitude == null) {
        continue;
      }

      final timestamp = _parseTimestamp(vehicleData['timestamp']);

      locations.add(
        EvLocation(
          vehicleId: vehicleId,
          position: LatLng(latitude, longitude),
          timestamp: timestamp,
          speed: _toDouble(vehicleData['speed']) ?? 0.0,
          heading: _toDouble(vehicleData['heading']) ?? 0.0,
        ),
      );
    }

    return locations;
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
}
