import 'package:latlong2/latlong.dart';

/// Stores the latest location details for one EV.
class EvLocation {
  const EvLocation({
    required this.vehicleId,
    required this.position,
    required this.timestamp,
    this.speed = 0.0,
    this.heading = 0.0,
  });

  /// EV name or ID, such as EV1 or EV2.
  final String vehicleId;

  /// Current GPS location of the EV.
  final LatLng position;

  /// Time when this location update was received or saved.
  final DateTime timestamp;

  /// Current EV speed. Uses 0 if speed is not available.
  final double speed;

  /// Direction the EV is facing. Uses 0 if heading is not available.
  final double heading;
}

/// Common interface used to get live EV location updates.
abstract class EvLocationProvider {
  /// Sends live location updates for individual EVs.
  Stream<EvLocation> get locationStream;

  /// Starts live EV tracking.
  Future<void> start();

  /// Stops live EV tracking.
  Future<void> stop();

  /// Gets the latest EV locations for refresh or first load.
  Future<List<EvLocation>> fetchCurrentLocations();
}

/// Safe fallback used when live EV tracking is not available.
class NoopEvLocationProvider implements EvLocationProvider {
  const NoopEvLocationProvider();

  // Return empty data so the app can continue safely without live tracking.
  @override
  Stream<EvLocation> get locationStream => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<List<EvLocation>> fetchCurrentLocations() async => const [];
}
