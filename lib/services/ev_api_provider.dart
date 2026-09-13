import 'dart:async';

import 'ev_location_provider.dart';

class EvApiProvider implements EvLocationProvider {
  EvApiProvider();

  final StreamController<EvLocation> _locationController =
      StreamController<EvLocation>.broadcast();

  bool _started = false;

  @override
  Stream<EvLocation> get locationStream => _locationController.stream;

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }

    _started = true;

    // PILOT API INTEGRATION POINT
    //
    // The Java backend will provide the current
    // EV locations here.
    //
    // Expected EV location data:
    // - vehicleId
    // - latitude
    // - longitude
    // - timestamp
    // - speed
    // - heading
    //
    // No simulated location is generated here.
    //
    // Example future flow:
    //
    // final locations = await _fetchFromApi();
    //
    // for (final location in locations) {
    //   _locationController.add(location);
    // }
  }

  @override
  Future<List<EvLocation>> fetchCurrentLocations() async {
    // PILOT API INTEGRATION POINT
    //
    // Replace this method with the Java backend
    // API call when the backend is available.
    //
    // Until then, no EV location is returned.

    return [];
  }

  @override
  Future<void> stop() async {
    if (!_started) {
      return;
    }

    _started = false;

    // Stop API polling / socket / stream here
    // when the real backend integration is added.
  }

  Future<void> dispose() async {
    await stop();

    await _locationController.close();
  }
}
