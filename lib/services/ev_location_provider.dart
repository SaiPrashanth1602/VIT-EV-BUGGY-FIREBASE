import 'package:latlong2/latlong.dart';

class EvLocation {
  const EvLocation({
    required this.vehicleId,
    required this.position,
    required this.timestamp,
    this.speed = 0.0,
    this.heading = 0.0,
  });

  final String vehicleId;
  final LatLng position;
  final DateTime timestamp;
  final double speed;
  final double heading;
}

abstract class EvLocationProvider {
  Stream<EvLocation> get locationStream;

  Future<void> start();

  Future<void> stop();

  Future<List<EvLocation>> fetchCurrentLocations();
}

class NoopEvLocationProvider implements EvLocationProvider {
  const NoopEvLocationProvider();

  @override
  Stream<EvLocation> get locationStream => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<List<EvLocation>> fetchCurrentLocations() async => const [];
}
