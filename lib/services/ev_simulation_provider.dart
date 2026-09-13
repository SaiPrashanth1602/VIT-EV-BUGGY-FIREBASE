import 'dart:async';

import 'package:latlong2/latlong.dart';

import 'ev_location_provider.dart';
import 'ev_tracking_service.dart';

class EvSimulationProvider implements EvLocationProvider {
  EvSimulationProvider({required EvTrackingService trackingService})
    : _trackingService = trackingService;

  final EvTrackingService _trackingService;

  final StreamController<EvLocation> _locationController =
      StreamController<EvLocation>.broadcast();

  final Distance _distance = const Distance();

  Timer? _timer;

  late final List<LatLng> _route;

  LatLng _position = EvTrackingService.adbPickup;

  int _routeSegmentIndex = 0;

  double _segmentProgress = 0.0;

  int _currentPickupIndex = 0;

  DateTime? _stopStartedAt;

  bool _isMoving = false;

  bool _started = false;

  static const double speedMetersPerSecond = 8.0;

  static const Duration tickDuration = Duration(milliseconds: 250);

  @override
  Stream<EvLocation> get locationStream => _locationController.stream;

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }

    _started = true;

    _route = _buildSimulationRoute();

    _position = EvTrackingService.adbPickup;

    _routeSegmentIndex = 0;

    _segmentProgress = 0.0;

    _currentPickupIndex = 0;

    _isMoving = false;

    _stopStartedAt = DateTime.now();

    _emitLocation();

    _timer = Timer.periodic(tickDuration, (_) => _update());
  }

  void _update() {
    if (!_started) {
      return;
    }

    if (!_isMoving) {
      final stopStartedAt = _stopStartedAt;

      if (stopStartedAt != null) {
        final elapsedSeconds = DateTime.now()
            .difference(stopStartedAt)
            .inSeconds;

        if (elapsedSeconds >= _simulationStopDurationSeconds) {
          _isMoving = true;

          _stopStartedAt = null;

          _segmentProgress = 0.0;
        }
      }

      _emitLocation();

      return;
    }

    final start = _route[_routeSegmentIndex];

    final endIndex = (_routeSegmentIndex + 1) % _route.length;

    final end = _route[endIndex];

    final segmentDistance = _distance.as(LengthUnit.Meter, start, end);

    if (segmentDistance < 0.5) {
      _routeSegmentIndex = endIndex;

      _segmentProgress = 0.0;

      return;
    }

    final progressIncrement =
        (speedMetersPerSecond * tickDuration.inMilliseconds / 1000) /
        segmentDistance;

    _segmentProgress += progressIncrement;

    if (_segmentProgress >= 1.0) {
      _position = end;

      _routeSegmentIndex = endIndex;

      _segmentProgress = 0.0;

      _checkPickupStop();

      _emitLocation();

      return;
    }

    _position = _interpolate(start, end, _segmentProgress);

    _emitLocation();
  }

  void _checkPickupStop() {
    final nextPickupIndex =
        (_currentPickupIndex + 1) % EvTrackingService.pickupPoints.length;

    final targetPickup = EvTrackingService.pickupPoints[nextPickupIndex];

    final distance = _trackingService.distanceBetween(_position, targetPickup);

    if (distance <= EvTrackingService.evTriggerRadiusMeters) {
      _position = targetPickup;

      _currentPickupIndex = nextPickupIndex;

      _isMoving = false;

      _stopStartedAt = DateTime.now();
    }
  }

  void _emitLocation() {
    if (_locationController.isClosed) {
      return;
    }

    _locationController.add(
      EvLocation(
        vehicleId: 'EV1',
        position: _position,
        timestamp: DateTime.now().toUtc(),
        speed: _isMoving ? speedMetersPerSecond : 0.0,
      ),
    );
  }

  @override
  Future<List<EvLocation>> fetchCurrentLocations() async {
    return [
      EvLocation(
        vehicleId: 'EV1',
        position: _position,
        timestamp: DateTime.now().toUtc(),
        speed: _isMoving ? speedMetersPerSecond : 0.0,
      ),
    ];
  }

  @override
  Future<void> stop() async {
    _started = false;

    _timer?.cancel();

    _timer = null;

    await _locationController.close();
  }

  List<LatLng> _buildSimulationRoute() {
    final route = <LatLng>[];

    final pickupRoadIndices = EvTrackingService.campusStops
        .map((stop) => _nearestRoadIndex(stop.pickupPosition))
        .toList();

    for (int i = 0; i < EvTrackingService.campusStops.length; i++) {
      final currentIndex = pickupRoadIndices[i];

      final nextIndex = i == EvTrackingService.campusStops.length - 1
          ? pickupRoadIndices[0]
          : pickupRoadIndices[i + 1];

      route.add(EvTrackingService.campusStops[i].pickupPosition);

      int index = currentIndex;

      while (index != nextIndex) {
        route.add(EvTrackingService.buggyRoad[index]);

        index = (index + 1) % EvTrackingService.buggyRoad.length;
      }

      route.add(
        EvTrackingService
            .campusStops[i == EvTrackingService.campusStops.length - 1
                ? 0
                : i + 1]
            .pickupPosition,
      );
    }

    return _removeDuplicatePoints(route);
  }

  int _nearestRoadIndex(LatLng point) {
    int nearestIndex = 0;

    double nearestDistance = double.infinity;

    for (int i = 0; i < EvTrackingService.buggyRoad.length; i++) {
      final distance = _distance.as(
        LengthUnit.Meter,
        point,
        EvTrackingService.buggyRoad[i],
      );

      if (distance < nearestDistance) {
        nearestDistance = distance;

        nearestIndex = i;
      }
    }

    return nearestIndex;
  }

  List<LatLng> _removeDuplicatePoints(List<LatLng> points) {
    final result = <LatLng>[];

    for (final point in points) {
      if (result.isEmpty || result.last != point) {
        result.add(point);
      }
    }

    return result;
  }

  LatLng _interpolate(LatLng start, LatLng end, double progress) {
    final clampedProgress = progress.clamp(0.0, 1.0);

    return LatLng(
      start.latitude + (end.latitude - start.latitude) * clampedProgress,
      start.longitude + (end.longitude - start.longitude) * clampedProgress,
    );
  }

  static const int _simulationStopDurationSeconds = 10;
}
