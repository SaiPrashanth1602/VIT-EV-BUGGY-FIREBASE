import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/ev_location_provider.dart';
import '../../services/ev_simulation_provider.dart';
import '../../services/ev_tracking_service.dart';
import '../../services/notification_service.dart';

class FacultySimulationScreen extends StatefulWidget {
  const FacultySimulationScreen({super.key});

  @override
  State<FacultySimulationScreen> createState() =>
      _FacultySimulationScreenState();
}

class _FacultySimulationScreenState extends State<FacultySimulationScreen> {
  static const Color vitBlue = Color(0xFF123C69);
  static const Color vitGreen = Color(0xFF18864B);
  static const Color routeYellow = Color(0xFFFFD600);

  static const LatLng vitChennai = LatLng(12.8406, 80.1534);

  // TEMPORARY SIMULATION FACULTY LOCATION.
  // Remove this simulation screen and this value
  // when the pilot is handed over to SDC.
  static const LatLng facultySimulationPosition = LatLng(12.84435, 80.15518);

  static const LatLng ab1 = LatLng(12.84391293192312, 80.15342317676296);

  static const LatLng ab2 = LatLng(12.843120555928554, 80.15645139066287);

  static const LatLng ab3 = LatLng(12.844043686792524, 80.15474014135296);

  static const LatLng ab4 = LatLng(12.843127357629559, 80.1554401593973);

  static const LatLng adb = LatLng(12.840719876775859, 80.15393816088053);

  final MapController _mapController = MapController();

  late final EvSimulationProvider _evProvider;

  StreamSubscription<EvLocation>? _evLocationSubscription;

  LatLng _evPosition = EvTrackingService.adbPickup;

  bool _evIsMoving = false;

  String? _evWaitingBlock;

  String? _notificationMessage;

  bool _evInsideFacultyBlock = false;

  CampusStop? _facultyBlock;

  @override
  void initState() {
    super.initState();

    _evProvider = EvSimulationProvider(trackingService: EvTrackingService());

    _facultyBlock = EvTrackingService().findFacultyBlock(
      facultySimulationPosition,
    );

    _evLocationSubscription = _evProvider.locationStream.listen(
      _handleEvLocation,
    );

    _evProvider.start();
  }

  @override
  void dispose() {
    _evLocationSubscription?.cancel();

    _evProvider.stop();

    NotificationService.instance.cancelEvArrival();

    super.dispose();
  }

  void _handleEvLocation(EvLocation location) {
    if (!mounted) {
      return;
    }

    final evPosition = location.position;

    final isMoving = location.speed > 0;

    String? waitingBlock;

    if (!isMoving) {
      waitingBlock = _findNearestPickupBlock(evPosition);
    }

    setState(() {
      _evPosition = evPosition;
      _evIsMoving = isMoving;
      _evWaitingBlock = waitingBlock;
    });

    _checkFacultyNotification();
  }

  String? _findNearestPickupBlock(LatLng evPosition) {
    final trackingService = EvTrackingService();

    CampusStop? nearestStop;

    double nearestDistance = double.infinity;

    for (final stop in EvTrackingService.campusStops) {
      final pickupDistance = trackingService.distanceBetween(
        evPosition,
        stop.pickupPosition,
      );

      final blockDistance = trackingService.distanceBetween(
        evPosition,
        stop.blockPosition,
      );

      final distance = pickupDistance < blockDistance
          ? pickupDistance
          : blockDistance;

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestStop = stop;
      }
    }

    if (nearestStop != null &&
        nearestDistance <= EvTrackingService.evTriggerRadiusMeters) {
      return nearestStop.name;
    }

    return null;
  }

  void _checkFacultyNotification() {
    final facultyBlock = _facultyBlock;

    if (facultyBlock == null) {
      return;
    }

    final isNearBlock = EvTrackingService().isEvNearStop(
      _evPosition,
      facultyBlock,
    );

    if (isNearBlock && !_evInsideFacultyBlock) {
      _evInsideFacultyBlock = true;

      final message =
          'EV1 is arriving at '
          '${facultyBlock.name}';

      setState(() {
        _notificationMessage = message;
      });

      NotificationService.instance.showEvArrival(blockName: facultyBlock.name);
    } else if (!isNearBlock) {
      _evInsideFacultyBlock = false;

      if (_notificationMessage != null) {
        setState(() {
          _notificationMessage = null;
        });
      }

      NotificationService.instance.cancelEvArrival();
    }
  }

  @override
  Widget build(BuildContext context) {
    final facultyBlockName = _facultyBlock?.name ?? 'Unknown';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: vitBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'EV SIMULATION',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.4),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14, top: 13, bottom: 13),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'DEMO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
          ),
        ],
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
                  _buildPickupMarker(EvTrackingService.adbPickup),

                  _buildPickupMarker(EvTrackingService.ab2Pickup),

                  _buildPickupMarker(EvTrackingService.ab4Pickup),

                  _buildPickupMarker(EvTrackingService.ab3Pickup),

                  _buildPickupMarker(EvTrackingService.ab1Pickup),

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

          Positioned(left: 16, top: 16, child: _buildSimulationBadge()),

          Positioned(left: 16, top: 60, child: _buildPickupLegend()),

          Positioned(right: 16, top: 16, child: _buildMapControl()),

          if (_notificationMessage != null)
            Positioned(
              left: 16,
              right: 16,
              top: 70,
              child: _buildNotificationBanner(),
            ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: _buildSimulationCard(facultyBlockName),
          ),
        ],
      ),
    );
  }

  Marker _buildPickupMarker(LatLng position) {
    return Marker(
      point: position,
      width: 70,
      height: 70,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: vitGreen.withValues(alpha: 0.12),
              boxShadow: [
                BoxShadow(
                  color: vitGreen.withValues(alpha: 0.45),
                  blurRadius: 16,
                  spreadRadius: 6,
                ),
              ],
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: vitGreen,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: vitGreen.withValues(alpha: 0.65),
                  blurRadius: 9,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupLegend() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: vitGreen,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: vitGreen.withValues(alpha: 0.60),
                    blurRadius: 7,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            const Text(
              'PICKUP POINTS',
              style: TextStyle(
                color: vitBlue,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.orange[800],
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_rounded, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text(
            'SIMULATION MODE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
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
        scale: _evIsMoving ? 1.0 : 1.08,
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
      point: facultySimulationPosition,
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
                  color: Colors.black.withValues(alpha: 0.30),
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

                NotificationService.instance.cancelEvArrival();
              },
              icon: const Icon(Icons.close_rounded, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationCard(String facultyBlockName) {
    final String statusText;

    if (_evIsMoving) {
      statusText = 'EV1 is moving';
    } else if (_evWaitingBlock != null) {
      statusText = 'EV1 is waiting at $_evWaitingBlock';
    } else {
      statusText = 'EV1 is waiting';
    }

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
                      'Simulated live location',
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
              const Icon(
                Icons.person_pin_circle_rounded,
                color: vitGreen,
                size: 21,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Waiting at: '
                  '$facultyBlockName',
                  style: const TextStyle(
                    color: vitBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.directions_bus_rounded,
                color: vitGreen,
                size: 21,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: const TextStyle(
                    color: vitBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
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
        color: _evIsMoving
            ? vitGreen.withValues(alpha: 0.12)
            : Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _evIsMoving ? 'MOVING' : 'STOPPED',
        style: TextStyle(
          color: _evIsMoving ? vitGreen : Colors.orange[800],
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
          _mapController.move(facultySimulationPosition, 17.0);
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
