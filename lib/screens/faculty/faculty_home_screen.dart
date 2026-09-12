import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/ev_tracking_service.dart';

class FacultyHomeScreen extends StatefulWidget {
  const FacultyHomeScreen({super.key});

  @override
  State<FacultyHomeScreen> createState() => _FacultyHomeScreenState();
}

class _FacultyHomeScreenState extends State<FacultyHomeScreen> {
  static const Color vitBlue = Color(0xFF123C69);
  static const Color vitGreen = Color(0xFF18864B);
  static const Color routeYellow = Color(0xFFFFD600);

  static const LatLng vitChennai = LatLng(12.8406, 80.1534);

  static const LatLng ab1 = LatLng(12.84391293192312, 80.15342317676296);

  static const LatLng ab2 = LatLng(12.843120555928554, 80.15645139066287);

  static const LatLng ab3 = LatLng(12.844043686792524, 80.15474014135296);

  static const LatLng ab4 = LatLng(12.843127357629559, 80.1554401593973);

  static const LatLng adb = LatLng(12.840719876775859, 80.15393816088053);

  // Simulation-only Faculty position near AB3 pickup.
  static const LatLng facultyPosition = LatLng(12.84435, 80.15518);

  final MapController _mapController = MapController();

  final EvTrackingService _evService = EvTrackingService();

  late final List<LatLng> _simulationRoute;

  Timer? _simulationTimer;

  LatLng _evPosition = EvTrackingService.adbPickup;

  int _routeSegmentIndex = 0;

  double _segmentProgress = 0.0;

  int _currentPickupIndex = 0;

  int _stopRemainingSeconds = EvTrackingService.stopDurationSeconds;

  bool _isMoving = false;

  DateTime? _stopStartedAt;

  CampusStop? _facultyBlock;

  String? _notificationMessage;

  bool _evInsideFacultyBlock = false;

  @override
  void initState() {
    super.initState();

    _simulationRoute = _evService.buildSimulationRoute();

    _facultyBlock = _evService.findFacultyBlock(facultyPosition);

    _stopStartedAt = DateTime.now();

    _startSimulation();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }

  void _startSimulation() {
    _simulationTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _updateSimulation(),
    );
  }

  void _updateSimulation() {
    if (!mounted) {
      return;
    }

    if (!_isMoving) {
      final stopStartedAt = _stopStartedAt;

      if (stopStartedAt != null) {
        final elapsedSeconds = DateTime.now()
            .difference(stopStartedAt)
            .inSeconds;

        _stopRemainingSeconds =
            EvTrackingService.stopDurationSeconds - elapsedSeconds;

        if (_stopRemainingSeconds <= 0) {
          _isMoving = true;
          _stopRemainingSeconds = 0;
          _stopStartedAt = null;
          _segmentProgress = 0.0;
        }
      }

      _checkFacultyNotification();

      setState(() {});
      return;
    }

    final start = _simulationRoute[_routeSegmentIndex];

    final endIndex = (_routeSegmentIndex + 1) % _simulationRoute.length;

    final end = _simulationRoute[endIndex];

    final segmentDistance = _evService.distanceBetween(start, end);

    if (segmentDistance < 0.5) {
      _advanceToNextSegment();
      return;
    }

    const double tickSeconds = 0.25;

    final progressIncrement =
        (EvTrackingService.simulationSpeedMetersPerSecond * tickSeconds) /
        segmentDistance;

    _segmentProgress += progressIncrement;

    if (_segmentProgress >= 1.0) {
      _evPosition = end;

      _checkFacultyNotification();

      _routeSegmentIndex = endIndex;

      _segmentProgress = 0.0;

      _checkPickupStop();

      setState(() {});
      return;
    }

    _evPosition = _evService.interpolate(start, end, _segmentProgress);

    _checkFacultyNotification();

    setState(() {});
  }

  void _advanceToNextSegment() {
    _routeSegmentIndex = (_routeSegmentIndex + 1) % _simulationRoute.length;

    _segmentProgress = 0.0;

    setState(() {});
  }

  void _checkPickupStop() {
    final nextPickupIndex =
        (_currentPickupIndex + 1) % EvTrackingService.pickupPoints.length;

    final targetPickup = EvTrackingService.pickupPoints[nextPickupIndex];

    final distance = _evService.distanceBetween(_evPosition, targetPickup);

    if (distance <= EvTrackingService.evTriggerRadiusMeters) {
      _evPosition = targetPickup;

      _currentPickupIndex = nextPickupIndex;

      _isMoving = false;

      _stopStartedAt = DateTime.now();

      _stopRemainingSeconds = EvTrackingService.stopDurationSeconds;
    }
  }

  void _checkFacultyNotification() {
    final facultyBlock = _facultyBlock;

    if (facultyBlock == null) {
      return;
    }

    final isNearBlock = _evService.isEvNearStop(_evPosition, facultyBlock);

    if (isNearBlock && !_evInsideFacultyBlock) {
      _evInsideFacultyBlock = true;

      setState(() {
        _notificationMessage =
            'EV1 is arriving at '
            '${facultyBlock.name}';
      });
    }

    if (!isNearBlock) {
      _evInsideFacultyBlock = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPickup = EvTrackingService.pickupNames[_currentPickupIndex];

    final nextPickupIndex =
        (_currentPickupIndex + 1) % EvTrackingService.pickupNames.length;

    final nextPickup = EvTrackingService.pickupNames[nextPickupIndex];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: vitBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'VIT EV BUGGY',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.4),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: vitChennai,
              initialZoom: 16.2,
              minZoom: 13,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.vit.evbuggy',
              ),

              PolylineLayer(
                polylines: [
                  Polyline(
                    points: EvTrackingService.buggyRoad,
                    strokeWidth: 6,
                    color: routeYellow,
                  ),
                ],
              ),

              MarkerLayer(
                markers: [
                  _buildFacultyMarker(),

                  _buildVehicleMarker(),

                  _buildCampusMarker(position: ab1, label: 'AB1'),

                  _buildCampusMarker(position: ab2, label: 'AB2'),

                  _buildCampusMarker(position: ab3, label: 'AB3'),

                  _buildCampusMarker(position: ab4, label: 'AB4'),

                  _buildCampusMarker(position: adb, label: 'ADB'),
                ],
              ),
            ],
          ),

          Positioned(right: 16, top: 16, child: _buildMapControl()),

          if (_notificationMessage != null)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: _buildNotificationBanner(),
            ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: _buildSimulationCard(currentPickup, nextPickup),
          ),
        ],
      ),
    );
  }

  Marker _buildVehicleMarker() {
    return Marker(
      point: _evPosition,
      width: 82,
      height: 82,
      child: AnimatedScale(
        scale: _isMoving ? 1.0 : 1.08,
        duration: const Duration(milliseconds: 250),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: vitGreen,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 9,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_bus_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(7),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: const Text(
                'EV1',
                style: TextStyle(
                  color: vitBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _buildFacultyMarker() {
    return Marker(
      point: facultyPosition,
      width: 90,
      height: 75,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: vitBlue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 4,
                ),
              ],
            ),
            child: const Text(
              'Faculty',
              style: TextStyle(
                color: vitBlue,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Marker _buildCampusMarker({required LatLng position, required String label}) {
    return Marker(
      point: position,
      width: 90,
      height: 70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: vitBlue,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          CustomPaint(
            size: const Size(14, 10),
            painter: _MarkerArrowPainter(vitBlue),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: vitGreen,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBanner() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: vitGreen.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: vitGreen,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: Colors.white,
                size: 23,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EV ARRIVAL',
                    style: TextStyle(
                      color: vitGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _notificationMessage!,
                    style: const TextStyle(
                      color: vitBlue,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _notificationMessage = null;
                });
              },
              icon: const Icon(Icons.close_rounded, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationCard(String currentPickup, String nextPickup) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: vitGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.electric_rickshaw_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EV1',
                      style: TextStyle(
                        color: vitBlue,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Live simulation',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.place_rounded, color: vitGreen, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isMoving
                      ? 'Heading to $nextPickup'
                      : 'Stopped at $currentPickup',
                  style: const TextStyle(
                    color: vitBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!_isMoving)
                Text(
                  '${_stopRemainingSeconds}s',
                  style: const TextStyle(
                    color: vitGreen,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _isMoving
            ? vitGreen.withValues(alpha: 0.12)
            : Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _isMoving ? 'MOVING' : 'STOPPED',
        style: TextStyle(
          color: _isMoving ? vitGreen : Colors.orange[800],
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildMapControl() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          _mapController.move(vitChennai, 16.2);
        },
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.my_location_rounded, color: vitBlue, size: 24),
        ),
      ),
    );
  }
}

class _MarkerArrowPainter extends CustomPainter {
  const _MarkerArrowPainter(this.color);

  final Color color;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final paint = ui.Paint()..color = color;

    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MarkerArrowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
