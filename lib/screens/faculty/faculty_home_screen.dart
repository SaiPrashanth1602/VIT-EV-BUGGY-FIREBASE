import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../services/ev_api_provider.dart';
import '../../services/ev_location_provider.dart';
import '../../services/ev_tracking_service.dart';
import '../../services/faculty_location_service.dart';
import '../../services/notification_service.dart';

class FacultyHomeScreen extends StatefulWidget {
  const FacultyHomeScreen({super.key});

  @override
  State<FacultyHomeScreen> createState() => _FacultyHomeScreenState();
}

class _FacultyHomeScreenState extends State<FacultyHomeScreen> {
  final MapController _mapController = MapController();

  late final EvLocationProvider _evProvider =
      (Platform.isAndroid || Platform.isIOS) && Firebase.apps.isNotEmpty
      ? EvApiProvider()
      : const NoopEvLocationProvider();

  late final FacultyLocationService _facultyLocationService;

  StreamSubscription<EvLocation>? _evSubscription;
  StreamSubscription<Position>? _facultyLocationSubscription;

  Timer? _evAvailabilityTimer;

  LatLng? _facultyPosition;
  LatLng? _evPosition;

  String? _facultyBlockName;
  String? _notificationMessage;

  bool _locationAvailable = false;
  bool _evLocationAvailable = false;
  bool _evIsMoving = false;
  bool _evInsideFacultyBlock = false;

  @override
  void initState() {
    super.initState();

    _facultyLocationService = FacultyLocationService();

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _evProvider.start();
    } catch (_) {
      // Firebase or platform services may be unavailable during tests or setup.
    }

    try {
      _evSubscription = _evProvider.locationStream.listen(
        _handleEvLocation,
        onError: (_) {},
      );
    } catch (_) {
      // Ignore provider stream startup failures.
    }

    _startEvAvailabilityCheck();

    try {
      await _startFacultyLocation();
    } catch (_) {
      // Ignore location platform failures during startup.
    }
  }

  // ---------------------------------------------------------------------------
  // FACULTY LOCATION
  // ---------------------------------------------------------------------------

  Future<void> _startFacultyLocation() async {
    try {
      final serviceEnabled = await _facultyLocationService
          .isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (mounted) {
          await _showLocationServiceDialog();
        }
        return;
      }

      var permission = await _facultyLocationService.getPermissionStatus();

      if (permission == LocationPermission.denied) {
        if (mounted) {
          await _showPermissionExplanation();
        }

        permission = await _facultyLocationService.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          await _showPermissionDeniedForeverDialog();
        }
        return;
      }

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }

      final started = await _facultyLocationService.startTracking();

      if (!started) {
        return;
      }

      _facultyLocationSubscription = _facultyLocationService.locationStream
          .listen(_handleFacultyPosition, onError: (_) {});
    } catch (_) {
      // Some environments (such as widget tests) do not have the platform
      // location plugin registered, so startup should stay non-fatal.
    }
  }

  void _handleFacultyPosition(Position position) {
    final facultyPosition = LatLng(position.latitude, position.longitude);

    final facultyStop = EvTrackingService().findFacultyBlock(facultyPosition);

    if (!mounted) {
      return;
    }

    setState(() {
      _facultyPosition = facultyPosition;
      _locationAvailable = true;
      _facultyBlockName = facultyStop?.name;
    });

    if (facultyStop != null && _evPosition != null) {
      _checkEvArrival(facultyPosition, facultyStop, _evPosition!);
    }
  }

  // ---------------------------------------------------------------------------
  // EV LOCATION
  // ---------------------------------------------------------------------------

  void _handleEvLocation(EvLocation location) {
    if (!mounted) {
      return;
    }

    final position = location.position;

    final isMoving = location.speed >= 1.0;

    setState(() {
      _evPosition = position;
      _evLocationAvailable = true;
      _evIsMoving = isMoving;
    });

    if (_facultyPosition == null) {
      return;
    }

    final facultyStop = EvTrackingService().findFacultyBlock(_facultyPosition!);

    if (facultyStop == null) {
      return;
    }

    _checkEvArrival(_facultyPosition!, facultyStop, position);
  }

  // ---------------------------------------------------------------------------
  // EV AVAILABILITY
  //
  // Firebase provider emits active EV locations but does not emit a
  // "removed" event when the driver ends the shift.
  //
  // Therefore we periodically fetch the current active locations.
  // If there are none, the old EV marker is cleared.
  // ---------------------------------------------------------------------------

  void _startEvAvailabilityCheck() {
    _evAvailabilityTimer?.cancel();

    _evAvailabilityTimer = Timer.periodic(const Duration(seconds: 2), (
      _,
    ) async {
      try {
        final locations = await _evProvider.fetchCurrentLocations();

        if (!mounted) {
          return;
        }

        if (locations.isEmpty) {
          _clearEvLocation();
        }
      } catch (_) {
        // Keep the current UI state if a temporary read fails.
      }
    });
  }

  void _clearEvLocation() {
    if (!mounted) {
      return;
    }

    setState(() {
      _evPosition = null;
      _evIsMoving = false;
      _evLocationAvailable = false;

      _notificationMessage = null;
    });

    _evInsideFacultyBlock = false;

    NotificationService.instance.cancelEvArrival();
  }

  // ---------------------------------------------------------------------------
  // EV ARRIVAL / GEOFENCING
  // ---------------------------------------------------------------------------

  void _checkEvArrival(
    LatLng facultyPosition,
    CampusStop facultyStop,
    LatLng evPosition,
  ) {
    final trackingService = EvTrackingService();

    final facultyIsAssociated =
        trackingService.distanceBetween(
              facultyPosition,
              facultyStop.blockPosition,
            ) <=
            EvTrackingService.facultyEligibilityRadiusMeters ||
        trackingService.distanceBetween(
              facultyPosition,
              facultyStop.pickupPosition,
            ) <=
            EvTrackingService.facultyEligibilityRadiusMeters;

    if (!facultyIsAssociated) {
      if (_evInsideFacultyBlock) {
        _evInsideFacultyBlock = false;

        if (mounted) {
          setState(() {
            _notificationMessage = null;
          });
        }

        NotificationService.instance.cancelEvArrival();
      }

      return;
    }

    final evNear = trackingService.isEvNearStop(evPosition, facultyStop);

    if (evNear) {
      if (!_evInsideFacultyBlock) {
        _evInsideFacultyBlock = true;

        if (mounted) {
          setState(() {
            _notificationMessage = 'EV is arriving at ${facultyStop.name}';
          });
        }

        // Keep the existing notification service seam.
        NotificationService.instance.showEvArrival(blockName: facultyStop.name);
      }
    } else {
      if (_evInsideFacultyBlock) {
        _evInsideFacultyBlock = false;

        if (mounted) {
          setState(() {
            _notificationMessage = null;
          });
        }

        NotificationService.instance.cancelEvArrival();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // LOCATION PERMISSION UI
  // ---------------------------------------------------------------------------

  Future<void> _showPermissionExplanation() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Location Required'),
          content: const Text(
            'VIT EV BUGGY uses your location to associate '
            'you with the nearest campus block and notify '
            'you when the EV shuttle approaches your area.\n\n'
            'Location tracking can continue while the app '
            'is running in the background.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('CONTINUE'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLocationServiceDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Location Services Off'),
          content: const Text(
            'Please enable Location Services so VIT EV BUGGY '
            'can determine your campus block and track EV arrival.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await Geolocator.openLocationSettings();
              },
              child: const Text('OPEN SETTINGS'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPermissionDeniedForeverDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text(
            'Location permission has been permanently denied. '
            'Please enable it from Android Settings to use '
            'faculty shuttle tracking.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await Geolocator.openAppSettings();
              },
              child: const Text('OPEN SETTINGS'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MAP
  // ---------------------------------------------------------------------------

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Faculty location.
    if (_facultyPosition != null) {
      markers.add(
        Marker(
          point: _facultyPosition!,
          width: 44,
          height: 44,
          child: _buildFacultyMarker(),
        ),
      );
    }

    // Actual pickup points.
    for (int i = 0; i < EvTrackingService.pickupPoints.length; i++) {
      markers.add(
        Marker(
          point: EvTrackingService.pickupPoints[i],
          width: 38,
          height: 38,
          child: _buildPickupMarker(EvTrackingService.pickupNames[i]),
        ),
      );
    }

    // Block markers.
    final blocks = <MapEntry<String, LatLng>>[
      MapEntry('AB1', EvTrackingService.ab1Block),
      MapEntry('AB2', EvTrackingService.ab2Block),
      MapEntry('AB3', EvTrackingService.ab3Block),
      MapEntry('AB4', EvTrackingService.ab4Block),
      MapEntry('ADB', EvTrackingService.adbBlock),
      MapEntry('MAB3', EvTrackingService.mab3Block),
      MapEntry('MAB4', EvTrackingService.mab4Block),
      MapEntry('AB5', EvTrackingService.ab5Block),
    ];

    for (final block in blocks) {
      markers.add(
        Marker(
          point: block.value,
          width: 72,
          height: 34,
          child: _buildBlockMarker(block.key),
        ),
      );
    }

    // EV marker ONLY when an active EV location exists.
    if (_evLocationAvailable && _evPosition != null) {
      markers.add(
        Marker(
          point: _evPosition!,
          width: 58,
          height: 58,
          child: _buildVehicleMarker(),
        ),
      );
    }

    return markers;
  }

  Widget _buildFacultyMarker() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(blurRadius: 10, spreadRadius: 2, color: Colors.black26),
        ],
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 23),
    );
  }

  Widget _buildVehicleMarker() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.green.shade600,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.45),
            blurRadius: 16,
            spreadRadius: 5,
          ),
        ],
      ),
      child: const Icon(Icons.directions_bus, color: Colors.white, size: 28),
    );
  }

  Widget _buildPickupMarker(String name) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.greenAccent.shade400,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withOpacity(0.8),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          name,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildBlockMarker(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.black12),
        boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black12)],
      ),
      child: Text(
        name,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          _buildMap(),
          _buildTopCard(),
          _buildPilotCard(),
          if (_notificationMessage != null) _buildArrivalNotification(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(12.84355, 80.1557),
        initialZoom: 16.8,
        minZoom: 14,
        maxZoom: 20,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/'
              'World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.example.vit_ev_buggy',
        ),

        PolylineLayer(
          polylines: [
            Polyline(
              points: EvTrackingService.buggyRoad,
              strokeWidth: 4,
              color: Colors.yellow,
            ),
          ],
        ),

        MarkerLayer(markers: _buildMarkers()),
      ],
    );
  }

  Widget _buildTopCard() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            height: 78,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.electric_bolt,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'VIT EV BUGGY',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Faculty Shuttle Tracking',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildLocationBadge(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _locationAvailable ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _locationAvailable ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _locationAvailable ? 'GPS ON' : 'GPS OFF',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _locationAvailable
                  ? Colors.green.shade700
                  : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPilotCard() {
    final String evStatus;

    if (!_evLocationAvailable) {
      evStatus = 'LOCATION NOT AVAILABLE';
    } else if (_evIsMoving) {
      evStatus = 'EV IS MOVING';
    } else {
      evStatus = 'EV STATIONARY';
    }

    return Positioned(
      left: 16,
      right: 16,
      bottom: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.black12),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 20,
                  offset: Offset(0, 8),
                  color: Colors.black12,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _evLocationAvailable
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.electric_car,
                    color: _evLocationAvailable
                        ? Colors.green.shade700
                        : Colors.grey.shade500,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'EV SHUTTLE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        evStatus,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (_facultyBlockName != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Associated: $_facultyBlockName',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _evLocationAvailable
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _evLocationAvailable ? 'ONLINE' : 'OFFLINE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: _evLocationAvailable
                          ? Colors.green.shade700
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArrivalNotification() {
    return Positioned(
      left: 16,
      right: 16,
      top: 105,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                blurRadius: 14,
                offset: Offset(0, 5),
                color: Colors.black26,
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_active,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  _notificationMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _notificationMessage = null;
                  });
                },
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _evAvailabilityTimer?.cancel();

    _evSubscription?.cancel();
    _facultyLocationSubscription?.cancel();

    _facultyLocationService.stopTracking();

    _evProvider.stop();

    super.dispose();
  }
}
