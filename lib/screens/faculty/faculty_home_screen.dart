import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../services/ev_location_provider.dart';
import '../../services/ev_api_provider.dart';
import '../../services/ev_tracking_service.dart';
import '../../services/faculty_location_service.dart';
import '../../services/notification_service.dart';
import 'faculty_simulation_screen.dart';

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

  final MapController _mapController = MapController();

  final FacultyLocationService _facultyLocationService =
      FacultyLocationService();

  late final EvLocationProvider _evProvider;

  StreamSubscription<EvLocation>? _evLocationSubscription;

  StreamSubscription<Position>? _facultyLocationSubscription;

  LatLng? _evPosition;

  LatLng? _facultyPosition;

  bool _evIsMoving = false;

  bool _evLocationAvailable = false;

  bool _facultyLocationAvailable = false;

  String? _notificationMessage;

  bool _evInsideFacultyBlock = false;

  CampusStop? _facultyBlock;

  String? _evWaitingBlock;

  @override
  void initState() {
    super.initState();

    _evProvider = EvApiProvider();

    _evLocationSubscription = _evProvider.locationStream.listen(
      _handleEvLocation,
    );

    _evProvider.start();

    _startFacultyLocation();
  }

  Future<void> _startFacultyLocation() async {
    final serviceEnabled = await _facultyLocationService
        .isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _facultyLocationAvailable = false;
        });

        await _showLocationRequiredDialog(
          title: 'Location services required',
          message:
              'VIT EV Buggy needs your device location to identify your nearby '
              'campus block and provide EV arrival notifications when the buggy '
              'approaches your pickup point.',
          actionText: 'Open Settings',
          onAction: () {
            _facultyLocationService.openLocationSettings();
          },
        );
      }

      return;
    }

    final permission = await _facultyLocationService.getPermissionStatus();

    if (permission == LocationPermission.denied) {
      if (mounted) {
        await _showLocationRequiredDialog(
          title: 'Location access required',
          message:
              'VIT EV Buggy uses your location to identify your nearby campus '
              'block and provide EV arrival notifications when the buggy '
              'approaches your pickup point.\n\n'
              'Location access is required for this feature to work correctly.',
          actionText: 'Allow Location',
          onAction: () async {
            await _facultyLocationService.requestPermission();
          },
        );
      }
    }

    final updatedPermission = await _facultyLocationService
        .getPermissionStatus();

    if (updatedPermission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _facultyLocationAvailable = false;
        });

        await _showLocationRequiredDialog(
          title: 'Location permission blocked',
          message:
              'Location access has been permanently denied for VIT EV Buggy. '
              'Please enable location permission from your device settings '
              'to use block detection and EV arrival notifications.',
          actionText: 'Open Settings',
          onAction: () {
            _facultyLocationService.openAppSettings();
          },
        );
      }

      return;
    }

    if (updatedPermission == LocationPermission.denied) {
      if (mounted) {
        setState(() {
          _facultyLocationAvailable = false;
        });
      }

      return;
    }

    final started = await _facultyLocationService.startTracking();

    if (!started) {
      if (mounted) {
        setState(() {
          _facultyLocationAvailable = false;
        });
      }

      return;
    }

    if (mounted) {
      setState(() {
        _facultyLocationAvailable = true;
      });
    }

    final initialPosition = await _facultyLocationService.getCurrentPosition();

    if (initialPosition != null) {
      _updateFacultyPosition(initialPosition, moveMap: true);
    }

    _facultyLocationSubscription ??= _facultyLocationService.locationStream
        .listen(_updateFacultyPosition);
  }

  Future<void> _showLocationRequiredDialog({
    required String title,
    required String message,
    required String actionText,
    required VoidCallback onAction,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: vitGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_on_rounded, color: vitGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: vitBlue,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onAction();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: vitGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  actionText,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _updateFacultyPosition(Position position, {bool moveMap = false}) {
    if (!mounted) {
      return;
    }

    final newPosition = LatLng(position.latitude, position.longitude);

    final newFacultyBlock = EvTrackingService().findFacultyBlock(newPosition);

    setState(() {
      _facultyPosition = newPosition;
      _facultyBlock = newFacultyBlock;
      _facultyLocationAvailable = true;
    });

    if (moveMap) {
      _mapController.move(newPosition, 17.0);
    }

    _checkFacultyNotification();
  }

  @override
  void dispose() {
    _facultyLocationSubscription?.cancel();

    _facultyLocationService.dispose();

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
      _evLocationAvailable = true;
      _evWaitingBlock = waitingBlock;
    });

    _checkFacultyNotification();
  }

  String? _findNearestPickupBlock(LatLng evPosition) {
    final trackingService = EvTrackingService();

    CampusStop? nearestStop;
    double nearestDistance = double.infinity;

    for (final stop in EvTrackingService.campusStops) {
      final blockDistance = trackingService.distanceBetween(
        evPosition,
        stop.blockPosition,
      );

      final pickupDistance = trackingService.distanceBetween(
        evPosition,
        stop.pickupPosition,
      );

      final distance = blockDistance < pickupDistance
          ? blockDistance
          : pickupDistance;

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
    final evPosition = _evPosition;

    if (facultyBlock == null || evPosition == null) {
      if (_notificationMessage != null) {
        setState(() {
          _notificationMessage = null;
        });
      }

      if (_evInsideFacultyBlock) {
        _evInsideFacultyBlock = false;

        NotificationService.instance.cancelEvArrival();
      }

      return;
    }

    final isNearBlock = EvTrackingService().isEvNearStop(
      evPosition,
      facultyBlock,
    );

    if (isNearBlock && !_evInsideFacultyBlock) {
      _evInsideFacultyBlock = true;

      final message =
          '${_evVehicleName()} is arriving at '
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

  String _evVehicleName() {
    return 'EV';
  }

  void _openSimulation() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FacultySimulationScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final facultyBlockName = _facultyBlock?.name ?? 'Not assigned';

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
                  _buildPickupMarker(EvTrackingService.adbPickup),
                  _buildPickupMarker(EvTrackingService.ab2Pickup),
                  _buildPickupMarker(EvTrackingService.ab4Pickup),
                  _buildPickupMarker(EvTrackingService.ab3Pickup),
                  _buildPickupMarker(EvTrackingService.ab1Pickup),

                  if (_facultyPosition != null) _buildFacultyMarker(),

                  if (_evPosition != null) _buildVehicleMarker(),

                  _buildCampusMarker(position: ab1, label: 'AB1'),

                  _buildCampusMarker(position: ab2, label: 'AB2'),

                  _buildCampusMarker(position: ab3, label: 'AB3'),

                  _buildCampusMarker(position: ab4, label: 'AB4'),

                  _buildCampusMarker(position: adb, label: 'ADB'),
                ],
              ),
            ],
          ),

          Positioned(left: 16, top: 16, child: _buildPickupLegend()),

          Positioned(right: 68, top: 16, child: _buildSimulationButton()),

          Positioned(right: 16, top: 16, child: _buildMapControl()),

          if (!_facultyLocationAvailable)
            Positioned(
              left: 16,
              right: 16,
              top: 70,
              child: _buildLocationWarning(),
            ),

          if (_notificationMessage != null)
            Positioned(
              left: 16,
              right: 16,
              top: _facultyLocationAvailable ? 70 : 140,
              child: _buildNotificationBanner(),
            ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: _buildPilotCard(facultyBlockName),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _openSimulation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: vitGreen.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_fill_rounded, color: vitGreen, size: 20),
              SizedBox(width: 7),
              Text(
                'SIMULATE EV',
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

  Marker _buildVehicleMarker() {
    return Marker(
      point: _evPosition!,
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
                'EV',
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
      point: _facultyPosition!,
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

  Widget _buildLocationWarning() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.location_off_rounded,
                color: Colors.orange[800],
                size: 22,
              ),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LOCATION REQUIRED',
                    style: TextStyle(
                      color: vitBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Location is needed for block detection '
                    'and EV arrival alerts.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _startFacultyLocation,
              child: const Text(
                'ENABLE',
                style: TextStyle(
                  color: vitGreen,
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

  Widget _buildPilotCard(String facultyBlockName) {
    final String evStatus;

    if (!_evLocationAvailable) {
      evStatus = 'Waiting for EV location';
    } else if (_evIsMoving) {
      evStatus = 'EV is moving';
    } else if (_evWaitingBlock != null) {
      evStatus = 'EV is waiting at $_evWaitingBlock';
    } else {
      evStatus = 'EV is stopped';
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VIT EV BUGGY',
                      style: TextStyle(
                        color: vitBlue,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _evLocationAvailable
                          ? 'Live location'
                          : 'EV location unavailable',
                      style: TextStyle(
                        color: _evLocationAvailable
                            ? Colors.grey
                            : Colors.orange[800],
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
                  'Waiting at: $facultyBlockName',
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
                  evStatus,
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
    if (!_evLocationAvailable) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'OFFLINE',
          style: TextStyle(
            color: Colors.orange[800],
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

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
          final facultyPosition = _facultyPosition;

          if (facultyPosition != null) {
            _mapController.move(facultyPosition, 17.0);
          } else {
            _mapController.move(vitChennai, 16.2);
          }
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
