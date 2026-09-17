import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _FacultyHomeScreenState extends State<FacultyHomeScreen>
    with TickerProviderStateMixin {
  // ── Official shuttle schedule (VIT Chennai timetable) ──────────────────────
  static const Map<String, List<int>> _ev1OutboundByBlock = {
    'AB1': [468, 523, 578, 633, 688, 743, 828, 883, 938],
    'AB3': [470, 525, 580, 635, 690, 745, 830, 885, 940],
    'AB2-4': [472, 527, 582, 637, 692, 747, 832, 887, 942],
    'MAB3': [475, 530, 585, 640, 695, 750, 835, 890, 945],
    'MAB4': [475, 530, 585, 640, 695, 750, 835, 890, 945],
  };

  static const Map<String, List<int>> _ev2OutboundByBlock = {
    'AB3': [473, 527, 583, 637, 693, 747, 833, 887, 943],
    'AB2-4': [475, 529, 585, 639, 695, 750, 835, 889, 945],
    'MAB3': [477, 532, 587, 642, 707, 752, 837, 892, 947],
    'MAB4': [477, 532, 587, 642, 707, 752, 837, 892, 947],
    'AB5': [482, 537, 592, 647, 702, 757, 842, 898, 952],
  };

  static const Map<String, List<int>> _ev1ReturnByBlock = {
    'MAB3': [540, 595, 650, 705, 760, 900, 955],
    'MAB4': [540, 595, 650, 705, 760, 900, 955],
    'AB2-4': [543, 598, 653, 708, 763, 903, 958],
    'AB3': [545, 600, 655, 710, 765, 905, 960],
    'AB1': [547, 602, 657, 712, 767, 907, 962],
  };

  static const Map<String, List<int>> _ev2ReturnByBlock = {
    'AB5': [538, 593, 648, 703, 758, 898, 953],
    'MAB3': [543, 598, 653, 708, 763, 903, 957],
    'MAB4': [543, 598, 653, 708, 763, 903, 957],
    'AB2-4': [546, 601, 656, 711, 766, 906, 960],
    'AB3': [548, 603, 658, 713, 768, 908, 962],
  };

  // ── Brand Colors & Map Constants ──────────────────────────────────────────
  static const Color vitBlue = Color(0xFF0F2C56);
  static const Color vitBlueLight = Color(0xFF1A4A7A);
  static const Color vitGreen = Color(0xFF16A34A);
  static const Color vitGreenSoft = Color(0xFF22C55E);
  static const Color routeYellow = Color(0xFFFACC15);
  static const LatLng vitChennai = LatLng(12.8406, 80.1534);

  // Muted/dull red for pickup pins — less saturated than Colors.red so it
  // doesn't overpower the map visually.
  static const Color pickupPinColor = Color(0xFFB33A3A);

  // Draggable sheet size fractions — reused by both the sheet and the
  // floating controls so they can compute their offset in sync.
  static const double _sheetMinSize = 0.235;
  static const double _sheetMaxSize = 0.66;

  final MapController _mapController = MapController();

  // Controls the draggable schedule sheet AND lets the floating controls
  // (GPS button, pickup legend) read its live size so they can move up
  // together with it as the user drags.
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  late final EvLocationProvider _evProvider =
      (Platform.isAndroid || Platform.isIOS) && Firebase.apps.isNotEmpty
          ? EvApiProvider()
          : const NoopEvLocationProvider();

  late final FacultyLocationService _facultyLocationService;

  StreamSubscription<EvLocation>? _evSubscription;
  StreamSubscription<Position>? _facultyLocationSubscription;

  Timer? _evAvailabilityTimer;

  LatLng? _facultyPosition;

  // Multi-vehicle state: every currently-active/online EV, keyed by its
  // vehicleId (e.g. "EV1", "EV2"). Replaces the old single _evPosition /
  // _evLocationAvailable / _evIsMoving fields, which could only ever hold
  // one vehicle at a time — a second vehicle's updates were silently
  // overwriting the first's.
  final Map<String, EvLocation> _evLocations = {};

  // Tracks per-block "arrival" state per vehicle, so EV1 and EV2 arriving
  // at the same block independently trigger their own notifications.
  final Set<String> _evInsideFacultyBlockIds = {};

  String? _facultyBlockName;
  String? _notificationMessage;

  // General "EV is at {block} pickup point" indicator — shows for EVERY
  // faculty user regardless of their own assigned block, updates live to
  // whichever block ANY EV currently sits near. Independent of the
  // personal arrival notification below.
  String? _evAtBlockName;

  bool _locationAvailable = false;
  bool _hasInitialMapCentered = false;

  // Live fraction (0.0-1.0) of how far the sheet is dragged, used to push
  // the bottom controls upward in sync with the sheet's drag.
  double _sheetExtent = _sheetMinSize;

  late AnimationController _pulseController;
  late AnimationController _glowController;

  // Named campus blocks, reused for both the map markers and the
  // "EV at any block" pickup-point check below.
  static final List<MapEntry<String, LatLng>> _campusBlocks = [
    MapEntry('AB1', EvTrackingService.ab1Block),
    MapEntry('AB2', EvTrackingService.ab2Block),
    MapEntry('AB3', EvTrackingService.ab3Block),
    MapEntry('AB4', EvTrackingService.ab4Block),
    MapEntry('ADB', EvTrackingService.adbBlock),
    MapEntry('MAB3', EvTrackingService.mab3Block),
    MapEntry('MAB4', EvTrackingService.mab4Block),
    MapEntry('AB5', EvTrackingService.ab5Block),
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _sheetController.addListener(_handleSheetDrag);

    _facultyLocationService = FacultyLocationService();
    _initialize();
  }

  void _handleSheetDrag() {
    if (!_sheetController.isAttached) return;
    setState(() {
      _sheetExtent = _sheetController.size;
    });
  }

  Future<void> _initialize() async {
    await NotificationService.instance.initialize();

    try {
      await _evProvider.start();
    } catch (_) {
      // Firebase or platform services may be unavailable during setup.
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

  // ── Timetable Logic Functions ──────────────────────────────────────────────
  String _formatScheduleTime(int minutes) {
    final hour24 = minutes ~/ 60;
    final minute = minutes % 60;
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $suffix';
  }

  int _currentMinutes() {
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
  }

  // Direction label is now blank for outbound trips ('TO CLASS' removed).
  // 'RETURN' trips keep their label so the two directions stay distinct.
  static const String _outboundDirectionLabel = '';

  _ScheduleEntry? _nextScheduledShuttle(String blockName) {
    final now = _currentMinutes();
    final candidates = <_ScheduleEntry>[];

    final ev1Outbound = _ev1OutboundByBlock[blockName] ?? const <int>[];
    final ev2Outbound = _ev2OutboundByBlock[blockName] ?? const <int>[];
    final ev1Return = _ev1ReturnByBlock[blockName] ?? const <int>[];
    final ev2Return = _ev2ReturnByBlock[blockName] ?? const <int>[];

    for (final time in ev1Outbound) {
      if (time >= now) {
        candidates.add(_ScheduleEntry('EV1', time, _outboundDirectionLabel));
      }
    }
    for (final time in ev2Outbound) {
      if (time >= now) {
        candidates.add(_ScheduleEntry('EV2', time, _outboundDirectionLabel));
      }
    }
    for (final time in ev1Return) {
      if (time >= now) {
        candidates.add(_ScheduleEntry('EV1', time, 'RETURN'));
      }
    }
    for (final time in ev2Return) {
      if (time >= now) {
        candidates.add(_ScheduleEntry('EV2', time, 'RETURN'));
      }
    }

    if (candidates.isEmpty) {
      final tomorrowEv1 = ev1Outbound.isNotEmpty ? ev1Outbound.first : null;
      final tomorrowEv2 = ev2Outbound.isNotEmpty ? ev2Outbound.first : null;

      if (tomorrowEv1 != null) {
        candidates.add(
          _ScheduleEntry(
            'EV1',
            tomorrowEv1,
            _outboundDirectionLabel,
            tomorrow: true,
          ),
        );
      }
      if (tomorrowEv2 != null) {
        candidates.add(
          _ScheduleEntry(
            'EV2',
            tomorrowEv2,
            _outboundDirectionLabel,
            tomorrow: true,
          ),
        );
      }
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => a.time.compareTo(b.time));
    return candidates.first;
  }

  List<_ScheduleEntry> _upcomingSchedule(String blockName) {
    final now = _currentMinutes();
    final entries = <_ScheduleEntry>[];

    void addEntries(
      String vehicle,
      Map<String, List<int>> source,
      String direction,
    ) {
      for (final time in source[blockName] ?? const <int>[]) {
        if (time >= now) {
          entries.add(_ScheduleEntry(vehicle, time, direction));
        }
      }
    }

    addEntries('EV1', _ev1OutboundByBlock, _outboundDirectionLabel);
    addEntries('EV2', _ev2OutboundByBlock, _outboundDirectionLabel);
    addEntries('EV1', _ev1ReturnByBlock, 'RETURN');
    addEntries('EV2', _ev2ReturnByBlock, 'RETURN');

    entries.sort((a, b) {
      final timeCompare = a.time.compareTo(b.time);
      if (timeCompare != 0) return timeCompare;
      return a.vehicle.compareTo(b.vehicle);
    });

    return entries.take(5).toList();
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
          setState(() => _locationAvailable = false);
          await _showLocationRequiredDialog(
            title: 'Location services required',
            message:
                'VIT EV Buggy needs your device location to identify your nearby '
                'campus block and provide EV arrival notifications when the buggy '
                'approaches your pickup point.',
            actionText: 'Open Settings',
            onAction: () => _facultyLocationService.openLocationSettings(),
          );
        }
        return;
      }

      var permission = await _facultyLocationService.getPermissionStatus();

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
          setState(() => _locationAvailable = false);
          await _showLocationRequiredDialog(
            title: 'Location permission blocked',
            message:
                'Location access has been permanently denied for VIT EV Buggy. '
                'Please enable location permission from your device settings '
                'to use block detection and EV arrival notifications.',
            actionText: 'Open Settings',
            onAction: () => _facultyLocationService.openAppSettings(),
          );
        }
        return;
      }

      if (updatedPermission == LocationPermission.denied) {
        if (mounted) setState(() => _locationAvailable = false);
        return;
      }

      final started = await _facultyLocationService.startTracking();

      if (!started) {
        if (mounted) setState(() => _locationAvailable = false);
        return;
      }

      if (mounted) setState(() => _locationAvailable = true);

      final initialPosition = await _facultyLocationService.getCurrentPosition();
      if (initialPosition != null) {
        _handleFacultyPosition(initialPosition);
      }

      _facultyLocationSubscription ??= _facultyLocationService.locationStream
          .listen(_handleFacultyPosition, onError: (_) {});
    } catch (_) {
      // Location plugin fallback logic.
    }
  }

  void _handleFacultyPosition(Position position) {
    final facultyPosition = LatLng(position.latitude, position.longitude);
    final facultyStop = EvTrackingService().findFacultyBlock(facultyPosition);

    if (!mounted) return;

    setState(() {
      _facultyPosition = facultyPosition;
      _locationAvailable = true;
      _facultyBlockName = facultyStop?.name;
    });

    if (!_hasInitialMapCentered) {
      _hasInitialMapCentered = true;
      _mapController.move(facultyPosition, 16.8);
    }

    if (facultyStop != null) {
      for (final location in _evLocations.values) {
        _checkEvArrival(facultyPosition, facultyStop, location);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // EV LOCATION (FIREBASE REALTIME STREAM) — MULTI-VEHICLE
  // ---------------------------------------------------------------------------

  void _handleEvLocation(EvLocation location) {
    if (!mounted) return;

    final now = DateTime.now().toUtc();
    final isStale = now.difference(location.timestamp).inSeconds > 180;

    // A stale update for THIS vehicle only removes that vehicle, not the
    // others — e.g. if EV2 goes quiet, EV1's marker must stay untouched.
    if (isStale) {
      _removeEvLocation(location.vehicleId);
      return;
    }

    setState(() {
      _evLocations[location.vehicleId] = location;
    });

    // Runs for every faculty user regardless of their own block, checked
    // against every currently known vehicle.
    _checkEvNearAnyBlock();

    if (_facultyPosition == null) return;

    final facultyStop = EvTrackingService().findFacultyBlock(_facultyPosition!);
    if (facultyStop == null) return;

    _checkEvArrival(_facultyPosition!, facultyStop, location);
  }

  void _removeEvLocation(String vehicleId) {
    if (!mounted) return;

    setState(() {
      _evLocations.remove(vehicleId);
    });

    if (_evInsideFacultyBlockIds.remove(vehicleId) &&
        _evInsideFacultyBlockIds.isEmpty) {
      if (mounted) {
        setState(() {
          _notificationMessage = null;
        });
      }
      NotificationService.instance.cancelEvArrival();
    }

    _checkEvNearAnyBlock();
  }

  // ---------------------------------------------------------------------------
  // EV AVAILABILITY CHECK
  // ---------------------------------------------------------------------------

  void _startEvAvailabilityCheck() {
    _evAvailabilityTimer?.cancel();

    _evAvailabilityTimer = Timer.periodic(const Duration(seconds: 2), (
      _,
    ) async {
      try {
        final locations = await _evProvider.fetchCurrentLocations();

        if (!mounted) return;

        if (locations.isEmpty) {
          _clearAllEvLocations();
          return;
        }

        final now = DateTime.now().toUtc();
        final activeIds = <String>{};

        for (final loc in locations) {
          if (now.difference(loc.timestamp).inSeconds <= 180) {
            activeIds.add(loc.vehicleId);
          }
        }

        // Drop any vehicle we're currently showing that isn't in the
        // fresh active list anymore (per-vehicle offline detection).
        final staleIds = _evLocations.keys
            .where((id) => !activeIds.contains(id))
            .toList();

        for (final id in staleIds) {
          _removeEvLocation(id);
        }
      } catch (_) {
        // Soft fail protection
      }
    });
  }

  void _clearAllEvLocations() {
    if (!mounted) return;

    setState(() {
      _evLocations.clear();
      _notificationMessage = null;
      _evAtBlockName = null;
    });

    _evInsideFacultyBlockIds.clear();

    NotificationService.instance.cancelEvArrival();
  }

  // ---------------------------------------------------------------------------
  // EV ARRIVAL / GEOFENCING (personal — only for the viewer's own block)
  // ---------------------------------------------------------------------------

  void _checkEvArrival(
    LatLng facultyPosition,
    CampusStop facultyStop,
    EvLocation evLocation,
  ) {
    final trackingService = EvTrackingService();
    final evNear = trackingService.isEvNearStop(
      evLocation.position,
      facultyStop,
    );

    final vehicleId = evLocation.vehicleId;

    if (evNear) {
      if (!_evInsideFacultyBlockIds.contains(vehicleId)) {
        _evInsideFacultyBlockIds.add(vehicleId);

        if (mounted) {
          setState(() {
            _notificationMessage =
                '$vehicleId is arriving at ${facultyStop.name}';
          });
        }

        NotificationService.instance.showEvArrival(blockName: facultyStop.name);
      }
    } else {
      if (_evInsideFacultyBlockIds.remove(vehicleId)) {
        if (mounted) {
          setState(() {
            // Only clear the banner if no other vehicle is still inside.
            if (_evInsideFacultyBlockIds.isEmpty) {
              _notificationMessage = null;
            }
          });
        }

        if (_evInsideFacultyBlockIds.isEmpty) {
          NotificationService.instance.cancelEvArrival();
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // EV AT ANY BLOCK — general pickup-point indicator (shown to ALL users)
  // ---------------------------------------------------------------------------

  void _checkEvNearAnyBlock() {
    final trackingService = EvTrackingService();

    String? matchedBlockName;

    for (final location in _evLocations.values) {
      for (final stop in EvTrackingService.campusStops) {
        if (trackingService.isEvNearStop(location.position, stop)) {
          matchedBlockName = stop.name;
          break;
        }
      }
      if (matchedBlockName != null) break;
    }

    if (matchedBlockName != _evAtBlockName && mounted) {
      setState(() {
        _evAtBlockName = matchedBlockName;
      });
    }
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
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AlertDialog(
            backgroundColor: Colors.white.withValues(alpha: 0.95),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        vitGreen.withValues(alpha: 0.15),
                        vitGreen.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: vitGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: vitBlue,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              message,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 14.5,
                height: 1.55,
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    actionText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _glowController.dispose();
    _sheetController.removeListener(_handleSheetDrag);
    _sheetController.dispose();

    _evAvailabilityTimer?.cancel();
    _evSubscription?.cancel();
    _facultyLocationSubscription?.cancel();

    _facultyLocationService.stopTracking();
    _facultyLocationService.dispose();

    _evProvider.stop();
    NotificationService.instance.cancelEvArrival();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUILD METHOD & UI COMPONENTS
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final facultyBlockName = _facultyBlockName ?? 'Not assigned';
    final screenHeight = MediaQuery.of(context).size.height;

    // How far above the bottom of the screen the sheet's visible top edge
    // currently sits, in logical pixels — used to float the GPS button
    // and pickup legend just above the sheet, moving with it as dragged.
    final sheetTopOffset = (screenHeight * _sheetExtent) + 14;

    final anyEvAvailable = _evLocations.isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(0),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
        ),
        body: Stack(
          children: [
            // ── Map ─────────────────────────────────────────────────────────
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
                Container(color: Colors.black.withValues(alpha: 0.18)),
                // ── Glowing thin route lines ──────────────────────────────
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: EvTrackingService.buggyRoadYellow,
                      color: routeYellow.withValues(alpha: 0.35),
                      strokeWidth: 9,
                    ),
                    Polyline(
                      points: EvTrackingService.buggyRoadOrange,
                      color: Colors.orange.shade400.withValues(alpha: 0.35),
                      strokeWidth: 9,
                    ),
                  ],
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: EvTrackingService.buggyRoadYellow,
                      color: routeYellow,
                      strokeWidth: 2.6,
                    ),
                    Polyline(
                      points: EvTrackingService.buggyRoadOrange,
                      color: Colors.orange.shade400,
                      strokeWidth: 2.6,
                    ),
                  ],
                ),
                MarkerLayer(markers: _buildMarkers()),
              ],
            ),

            // ── Location Warning ────────────────────────────────────────────
            if (!_locationAvailable)
              Positioned(
                left: 16,
                right: 16,
                top: MediaQuery.of(context).padding.top + 12,
                child: _buildLocationWarning(),
              ),

            // ── EV At {Block} Pickup Point — shown to everyone, live ─────────
            if (_evAtBlockName != null)
              Positioned(
                left: 16,
                right: 16,
                top: MediaQuery.of(context).padding.top + 12,
                child: _buildEvAtBlockBanner(_evAtBlockName!),
              ),

            // ── Personal Arrival Notification Banner ─────────────────────────
            if (_notificationMessage != null)
              Positioned(
                left: 16,
                right: 16,
                top:
                    MediaQuery.of(context).padding.top +
                    (_evAtBlockName != null
                        ? 88
                        : (_locationAvailable ? 12 : 92)),
                child: _buildNotificationBanner(),
              ),

            // ── Bottom-left: Pickup legend — floats just above the sheet,
            //     and rides up with it as the sheet is dragged ─────────────
            Positioned(
              left: 16,
              bottom: sheetTopOffset,
              child: _buildPickupLegend(),
            ),

            // ── Bottom-right: GPS recenter button — same behavior ────────────
            Positioned(
              right: 16,
              bottom: sheetTopOffset,
              child: _buildMapControl(),
            ),

            // ── Draggable Shuttle Schedule Sheet ─────────────────────────────
            Positioned.fill(
              child: _buildPilotCard(facultyBlockName, anyEvAvailable),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GLASSMORPHISM & CONTROLS
  // ---------------------------------------------------------------------------

  Widget _buildGlassContainer({
    required Widget child,
    EdgeInsetsGeometry? padding,
    BorderRadius? borderRadius,
  }) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: borderRadius ?? BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.55),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildPickupLegend() {
    return _buildGlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              final glow = 0.25 + (_glowController.value * 0.15);
              return Icon(
                Icons.location_on_rounded,
                color: pickupPinColor,
                size: 18,
                shadows: [
                  Shadow(
                    color: pickupPinColor.withValues(alpha: glow),
                    blurRadius: 8,
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 6),
          const Text(
            'PICKUP POINTS',
            style: TextStyle(
              color: vitBlue,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapControl() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final pos = _facultyPosition;
          if (pos != null) {
            _mapController.move(pos, 17.0);
          } else {
            _mapController.move(vitChennai, 16.2);
          }
        },
        child: _buildGlassContainer(
          padding: const EdgeInsets.all(12),
          child: const Icon(
            Icons.my_location_rounded,
            color: vitBlue,
            size: 22,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAP MARKERS BUILDER
  // ---------------------------------------------------------------------------

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Pickup points
    for (int i = 0; i < EvTrackingService.pickupPoints.length; i++) {
      markers.add(_buildPickupMarker(EvTrackingService.pickupPoints[i]));
    }

    // Block markers
    for (final block in _campusBlocks) {
      markers.add(
        _buildCampusMarker(
          position: block.value,
          label: block.key,
        ),
      );
    }

    // Faculty Marker (Blue User Pin)
    if (_facultyPosition != null) {
      markers.add(_buildFacultyMarker());
    }

    // EV Buggy Markers — one per currently active vehicle (EV1, EV2, ...).
    // If a vehicle goes offline, it's removed from _evLocations and its
    // marker simply stops being added here; other vehicles are untouched.
    for (final location in _evLocations.values) {
      markers.add(_buildVehicleMarker(location));
    }

    return markers;
  }

  // Standard Google-Maps-style pin using Flutter's built-in Material icon,
  // in a muted/dulled red so it doesn't overpower the map visually.
  Marker _buildPickupMarker(LatLng position) {
    const pinSize = 40.0;

    return Marker(
      point: position,
      width: pinSize,
      height: pinSize,
      alignment: Alignment.topCenter,
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final glow = 0.20 + (_glowController.value * 0.15);

          return Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: 2,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: pickupPinColor.withValues(alpha: glow),
                        blurRadius: 12,
                        spreadRadius: 1.5,
                      ),
                    ],
                  ),
                ),
              ),
              Icon(
                Icons.location_on_rounded,
                color: pickupPinColor,
                size: pinSize,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    offset: const Offset(0, 2),
                    blurRadius: 3,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // Now takes the specific EvLocation it represents, so each vehicle gets
  // its own marker with its own label and its own moving/stationary state.
  Marker _buildVehicleMarker(EvLocation location) {
    final isMoving = location.speed >= 1.0;

    return Marker(
      point: location.position,
      width: 92,
      height: 92,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = isMoving ? 1.0 : 1.0 + (_pulseController.value * 0.07);
          return Transform.scale(
            scale: scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [vitGreenSoft, vitGreen],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3.2),
                    boxShadow: [
                      BoxShadow(
                        color: vitGreen.withValues(alpha: 0.55),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.electric_rickshaw_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    location.vehicleId,
                    style: const TextStyle(
                      color: vitBlue,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Marker _buildFacultyMarker() {
    return Marker(
      point: _facultyPosition!,
      width: 88,
      height: 78,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [vitBlueLight, vitBlue],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: vitBlue.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
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
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 5,
                ),
              ],
            ),
            child: const Text(
              'You',
              style: TextStyle(
                color: vitBlue,
                fontSize: 11,
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
      width: 86,
      height: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: vitGreen,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.2),
              boxShadow: [
                BoxShadow(
                  color: vitGreen.withValues(alpha: 0.45),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          CustomPaint(
            size: const Size(13, 9),
            painter: _MarkerArrowPainter(vitBlue, flip: true),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [vitBlueLight, vitBlue]),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BANNERS & WARNINGS
  // ---------------------------------------------------------------------------

  Widget _buildEvAtBlockBanner(String blockName) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.95 + (0.05 * value),
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
      child: _buildGlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        borderRadius: BorderRadius.circular(22),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: vitBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.electric_rickshaw_rounded,
                color: vitBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'EV AT $blockName PICKUP POINT',
                style: const TextStyle(
                  color: vitBlue,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationBanner() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.95 + (0.05 * value),
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
      child: _buildGlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        borderRadius: BorderRadius.circular(22),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: vitGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: vitGreen,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: vitGreen,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ARRIVING',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Ready for pickup',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _notificationMessage!,
                    style: const TextStyle(
                      color: vitBlue,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() => _notificationMessage = null);
                NotificationService.instance.cancelEvArrival();
              },
              icon: Icon(
                Icons.close_rounded,
                color: Colors.grey.shade400,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationWarning() {
    return _buildGlassContainer(
      padding: const EdgeInsets.all(15),
      borderRadius: BorderRadius.circular(18),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.location_off_rounded,
              color: Colors.orange.shade800,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LOCATION REQUIRED',
                  style: TextStyle(
                    color: vitBlue,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Needed for block detection & arrival alerts',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _startFacultyLocation,
            style: TextButton.styleFrom(
              foregroundColor: vitGreen,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text(
              'ENABLE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTTOM DRAGGABLE CARD
  // ---------------------------------------------------------------------------

  Widget _buildPilotCard(String facultyBlockName, bool anyEvAvailable) {
    final nextShuttle = _nextScheduledShuttle(facultyBlockName);
    final upcoming = _upcomingSchedule(facultyBlockName);

    // Lists which vehicles are currently online, e.g. "EV1, EV2 online"
    // or "EV1 online" if only one is active.
    final String evStatus;
    if (!anyEvAvailable) {
      evStatus = 'Waiting for live shuttle location';
    } else {
      final ids = _evLocations.keys.toList()..sort();
      evStatus = '${ids.join(', ')} online';
    }

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _sheetMinSize,
      minChildSize: _sheetMinSize,
      maxChildSize: _sheetMaxSize,
      snap: true,
      snapSizes: const [_sheetMinSize, _sheetMaxSize],
      builder: (context, scrollController) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.7),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              MediaQuery.of(context).padding.bottom + 24,
            ),
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [vitGreenSoft, vitGreen],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: vitGreen.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.electric_rickshaw_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'VIT EV Shuttle',
                          style: TextStyle(
                            color: vitBlue,
                            fontSize: 17.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          facultyBlockName == 'Not assigned'
                              ? 'Your block: Not assigned'
                              : 'Your block: $facultyBlockName',
                          style: TextStyle(
                            color: facultyBlockName == 'Not assigned'
                                ? Colors.orange.shade800
                                : Colors.grey.shade600,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(anyEvAvailable),
                ],
              ),

              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
                decoration: BoxDecoration(
                  color: vitBlue.withValues(alpha: 0.045),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: vitBlue.withValues(alpha: 0.10)),
                ),
                child: nextShuttle == null
                    ? const Text(
                        'No scheduled shuttle for this block.',
                        style: TextStyle(
                          color: vitBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: vitGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              nextShuttle.vehicle,
                              style: const TextStyle(
                                color: vitGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'NEXT SCHEDULED SHUTTLE',
                                  style: TextStyle(
                                    color: vitBlue,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.45,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  nextShuttle.direction.isEmpty
                                      ? '${nextShuttle.tomorrow ? 'TOMORROW • ' : ''}${_formatScheduleTime(nextShuttle.time)}'
                                      : '${nextShuttle.tomorrow ? 'TOMORROW • ' : ''}${nextShuttle.direction} • ${_formatScheduleTime(nextShuttle.time)}',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: vitBlue,
                            size: 22,
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 12),

              _buildInfoRow(
                icon: Icons.alt_route_rounded,
                label: 'Live status',
                value: evStatus,
              ),

              const SizedBox(height: 18),

              const Text(
                'TODAY’S SCHEDULE',
                style: TextStyle(
                  color: vitBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.65,
                ),
              ),
              const SizedBox(height: 8),

              if (facultyBlockName == 'Not assigned')
                _buildScheduleEmpty(
                  'Move within a shuttle service area to see your block schedule.',
                )
              else if (upcoming.isEmpty)
                _buildScheduleEmpty(
                  'Today’s scheduled services have ended. The next service starts tomorrow.',
                )
              else
                ...upcoming.map(_buildScheduleRow),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScheduleRow(_ScheduleEntry entry) {
    final hasDirection = entry.direction.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              _formatScheduleTime(entry.time),
              style: const TextStyle(
                color: vitBlue,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            width: 1,
            height: 28,
            color: Colors.grey.withValues(alpha: 0.18),
          ),
          const SizedBox(width: 11),
          hasDirection
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: vitGreen.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    entry.vehicle,
                    style: const TextStyle(
                      color: vitGreen,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              : Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: vitGreen.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      entry.vehicle,
                      style: const TextStyle(
                        color: vitGreen,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
          if (hasDirection) const SizedBox(width: 9),
          if (hasDirection)
            Expanded(
              child: Text(
                entry.direction,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScheduleEmpty(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 12.5,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: vitGreen, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label  ',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: vitBlue,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Status badge: only ONLINE or OFFLINE. No MOVING/STOPPED distinction.
  Widget _buildStatusBadge(bool anyEvAvailable) {
    if (!anyEvAvailable) {
      return _statusChip(
        label: 'OFFLINE',
        color: Colors.orange.shade800,
        bg: Colors.orange.withValues(alpha: 0.12),
      );
    }

    return _statusChip(
      label: 'ONLINE',
      color: vitGreen,
      bg: vitGreen.withValues(alpha: 0.12),
    );
  }

  Widget _statusChip({
    required String label,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SCHEDULE ENTRY & PAINTER HELPERS
// ---------------------------------------------------------------------------

class _ScheduleEntry {
  const _ScheduleEntry(
    this.vehicle,
    this.time,
    this.direction, {
    this.tomorrow = false,
  });

  final String vehicle;
  final int time;
  final String direction;
  final bool tomorrow;
}

class _MarkerArrowPainter extends CustomPainter {
  const _MarkerArrowPainter(this.color, {this.flip = false});

  final Color color;
  final bool flip;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final paint = ui.Paint()..color = color;
    final path = ui.Path();

    if (flip) {
      path
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0)
        ..close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MarkerArrowPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.flip != flip;
  }
}
