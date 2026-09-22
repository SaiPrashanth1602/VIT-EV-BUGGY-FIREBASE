import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
    'AB2, AB4 Junction': [472, 527, 582, 637, 692, 747, 832, 887, 942],
    'MAB3': [475, 530, 585, 640, 695, 750, 835, 890, 945],
    'MAB4': [475, 530, 585, 640, 695, 750, 835, 890, 945],
  };

  static const Map<String, List<int>> _ev2OutboundByBlock = {
    'AB3': [473, 527, 583, 637, 693, 747, 833, 887, 943],
    'AB2, AB4 Junction': [475, 529, 585, 639, 695, 750, 835, 889, 945],
    'MAB3': [477, 532, 587, 642, 707, 752, 837, 892, 947],
    'MAB4': [477, 532, 587, 642, 707, 752, 837, 892, 947],
    'AB5': [482, 537, 592, 647, 702, 757, 842, 898, 952],
  };

  static const Map<String, List<int>> _ev1ReturnByBlock = {
    'MAB3': [540, 595, 650, 705, 760, 900, 955],
    'MAB4': [540, 595, 650, 705, 760, 900, 955],
    'AB2, AB4 Junction': [543, 598, 653, 708, 763, 903, 958],
    'AB3': [545, 600, 655, 710, 765, 905, 960],
    'AB1': [547, 602, 657, 712, 767, 907, 962],
  };

  static const Map<String, List<int>> _ev2ReturnByBlock = {
    'AB5': [538, 593, 648, 703, 758, 898, 953],
    'MAB3': [543, 598, 653, 708, 763, 903, 957],
    'MAB4': [543, 598, 653, 708, 763, 903, 957],
    'AB2, AB4 Junction': [546, 601, 656, 711, 766, 906, 960],
    'AB3': [548, 603, 658, 713, 768, 908, 962],
  };

  // ── Metro-style route order per vehicle — FULL round trip ────────────────
  // Real routes are there-and-back: the EV drives out to the turnaround
  // stop, then drives the SAME stops in reverse back to the start. This
  // list spells out every stop in both legs (turnaround appears once), so
  // the progress line can correctly show the return leg instead of going
  // blank after the last outbound stop. Purely a UI concept for the
  // progress-line indicator below — does not affect scheduling, arrival
  // notifications, or any Firebase/location logic elsewhere.
  static const List<String> _ev1RouteOrder = [
    'AB1',
    'AB3',
    'AB2, AB4 Junction',
    'MAB3',
    'MAB4', // turnaround
    'MAB3',
    'AB2, AB4 Junction',
    'AB3',
    'AB1',
  ];

  static const List<String> _ev2RouteOrder = [
    'AB3',
    'AB2, AB4 Junction',
    'MAB3',
    'MAB4',
    'AB5', // turnaround
    'MAB4',
    'MAB3',
    'AB2, AB4 Junction',
    'AB3',
  ];

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

  // Multi-vehicle state: every currently-active/online EV, keyed by its
  // vehicleId (e.g. "EV1", "EV2"). Each EvLocation already carries its own
  // `heading` field straight from Firebase, which the direction arrows
  // below read directly — no changes to this logic.
  final Map<String, EvLocation> _evLocations = {};

  // Tracks per-block "arrival" state per vehicle, so EV1 and EV2 arriving
  // at the same block independently trigger their own notifications.
  final Set<String> _evInsideFacultyBlockIds = {};

  // UI-only debounce: smooths the moving/idle flag used purely for the
  // direction-arrow animation, so GPS speed jitter right at the threshold
  // doesn't flicker the arrows on/off. Does NOT affect any EV location,
  // arrival, or notification logic elsewhere in this file.
  final Map<String, bool> _evMovingStable = {};

  // UI-only: remembers the last stop genuinely reached by each EV.
  // This is used only for route continuity; the metro line itself glows
  // ONLY when the EV is physically inside the current pickup-point radius.
  final Map<String, int> _evLastRouteIndex = {};

  // True only while the EV is physically inside its currently confirmed
  // pickup-point radius. A 5-second departure debounce prevents GPS jitter
  // from immediately changing the stop from green to yellow.
  final Map<String, bool> _evAtPickupStop = {};

  // Per-EV departure debounce timers.
  final Map<String, Timer> _evDepartureTimers = {};

  // Horizontal controllers for the two permanent metro strips.
  final Map<String, ScrollController> _metroScrollControllers = {};

  String? _facultyBlockName;
  String? _notificationMessage;

  bool _locationAvailable = false;
  bool _hasInitialMapCentered = false;

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

    _facultyLocationService = FacultyLocationService();
    _initialize();
  }

  Future<void> _refreshEvStatus() async {
    try {
      final locations = await _evProvider.fetchCurrentLocations();
      for (final location in locations) {
        _handleEvLocation(location);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Live EV status refreshed')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to refresh EV status')),
      );
    }
  }

  Future<void> _initialize() async {
    await NotificationService.instance.initialize();

    try {
      // IMPORTANT:
      // Subscribe BEFORE starting the provider.
      _evSubscription = _evProvider.locationStream.listen(
        _handleEvLocation,
        onError: (error) {
          debugPrint('❌ FACULTY EV STREAM ERROR: $error');
        },
      );

      await _evProvider.start();
    } catch (error, stackTrace) {
      debugPrint('❌ EV PROVIDER START ERROR: $error');
      debugPrint('$stackTrace');
    }

    _startEvAvailabilityCheck();

    try {
      await _startFacultyLocation();
    } catch (error, stackTrace) {
      debugPrint('❌ FACULTY LOCATION ERROR: $error');
      debugPrint('$stackTrace');
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

      final initialPosition = await _facultyLocationService
          .getCurrentPosition();
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
  // (UNCHANGED — same logic as before)
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

    _evMovingStable.remove(vehicleId);
    _evDepartureTimers.remove(vehicleId)?.cancel();
    _evAtPickupStop.remove(vehicleId);

    // Vehicle went offline (shift ended) — drop its remembered route
    // position so the NEXT time it comes online (new shift), the metro
    // line starts a completely fresh lap from index 0 instead of
    // carrying over wherever it left off last time.
    _evLastRouteIndex.remove(vehicleId);

    if (_evInsideFacultyBlockIds.remove(vehicleId) &&
        _evInsideFacultyBlockIds.isEmpty) {
      if (mounted) {
        setState(() {
          _notificationMessage = null;
        });
      }
      NotificationService.instance.cancelEvArrival();
    }
  }

  // ---------------------------------------------------------------------------
  // EV AVAILABILITY CHECK (UNCHANGED)
  // ---------------------------------------------------------------------------

  void _startEvAvailabilityCheck() {
    for (final controller in _metroScrollControllers.values) {
      controller.dispose();
    }

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
            _handleEvLocation(loc);
          }
        }

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
    });

    _evMovingStable.clear();
    _evLastRouteIndex.clear();
    _evAtPickupStop.clear();
    for (final timer in _evDepartureTimers.values) {
      timer.cancel();
    }
    _evDepartureTimers.clear();
    _evInsideFacultyBlockIds.clear();

    NotificationService.instance.cancelEvArrival();
  }

  // ---------------------------------------------------------------------------
  // EV ARRIVAL / GEOFENCING
  //
  // IMPORTANT:
  // A faculty member must ONLY be notified by a vehicle that actually serves
  // their pickup block.
  //
  // Example:
  //   Faculty at AB1 + EV1 inside AB1 radius -> NOTIFY
  //   Faculty at AB1 + EV2 inside AB1 radius -> DO NOT NOTIFY
  //
  // The physical 35 m geofence is still checked by EvTrackingService.
  // ---------------------------------------------------------------------------

  bool _vehicleServesFacultyBlock(String vehicleId, String blockName) {
    switch (vehicleId) {
      case 'EV1':
        return _ev1OutboundByBlock.containsKey(blockName) ||
            _ev1ReturnByBlock.containsKey(blockName);

      case 'EV2':
        return _ev2OutboundByBlock.containsKey(blockName) ||
            _ev2ReturnByBlock.containsKey(blockName);

      default:
        // Only EV1 and EV2 are valid shuttle vehicles in this project.
        return false;
    }
  }

  void _checkEvArrival(
    LatLng facultyPosition,
    CampusStop facultyStop,
    EvLocation evLocation,
  ) {
    final trackingService = EvTrackingService();
    final vehicleId = evLocation.vehicleId;
    final blockName = facultyStop.name;

    // First enforce the route assignment.
    //
    // This prevents an EV from another route from notifying a faculty member
    // simply because both vehicles can physically pass through/near the same
    // pickup coordinate.
    final vehicleServesBlock = _vehicleServesFacultyBlock(vehicleId, blockName);

    if (!vehicleServesBlock) {
      // If this vehicle was previously considered inside the faculty block,
      // clear only its arrival state. It must never create a notification.
      if (_evInsideFacultyBlockIds.remove(vehicleId) &&
          _evInsideFacultyBlockIds.isEmpty) {
        if (mounted) {
          setState(() {
            _notificationMessage = null;
          });
        }

        NotificationService.instance.cancelEvArrival();
      }

      return;
    }

    // Route is valid, now perform the exact physical pickup-point geofence.
    final evNear = trackingService.isEvNearStop(
      evLocation.position,
      facultyStop,
    );

    if (evNear) {
      if (!_evInsideFacultyBlockIds.contains(vehicleId)) {
        _evInsideFacultyBlockIds.add(vehicleId);

        if (mounted) {
          setState(() {
            _notificationMessage =
                '$vehicleId arrived at $blockName pickup point';
          });
        }

        NotificationService.instance.showEvArrival(blockName: blockName);
      }
    } else {
      if (_evInsideFacultyBlockIds.remove(vehicleId)) {
        if (mounted) {
          setState(() {
            // Only clear the banner if no other valid vehicle is still inside.
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
  // METRO-STYLE ROUTE PROGRESS — pure UI, read-only, computed on every build
  // ---------------------------------------------------------------------------
  //
  // Finds which stop (by index into the FULL round-trip route list) the
  // given EV is currently nearest/at, reusing the exact same `isEvNearStop`
  // geofence check already used for arrival notifications.
  //
  // IMPORTANT: this only ever returns an index when a REAL match happens.
  // If the EV isn't near ANY stop right now (e.g. still driving from its
  // depot, or — as in testing — nowhere near campus at all), this returns
  // whatever was last genuinely confirmed (or null if nothing ever was).
  // It never guesses/defaults to index 0 — that was the earlier bug that
  // made a stop show green before the EV had actually reached it.
  //
  // Because the round-trip list repeats stop names (e.g. MAB3 appears once
  // outbound and once on the return leg), matching searches forward from
  // the last confirmed index first, so later matches correctly resolve to
  // the RETURN-leg occurrence instead of snapping back to the outbound one.

  // ---------------------------------------------------------------------------
  // ROUTE PROGRESS STATE
  //
  // There are two different states:
  //
  //   _evLastRouteIndex = the last stop the EV has genuinely reached.
  //   _evAtPickupStop   = whether it is still physically at that stop.
  //
  // The EV must remain outside the 35 m pickup radius for 5 continuous
  // seconds before _evAtPickupStop becomes false. This prevents GPS jitter
  // from instantly changing GREEN -> YELLOW.
  //
  // Route indices are always resolved FORWARD from the last confirmed index.
  // This is critical because MAB3, AB2/4 and AB3 occur twice on the round
  // trip. We must never jump back to the outbound occurrence on the return.
  // ---------------------------------------------------------------------------

  CampusStop _routeStopFor(String name) {
    final normalizedName = name == 'AB2, AB4 Junction' ? 'AB2-4' : name;

    return EvTrackingService.campusStops.firstWhere(
      (s) => s.name == normalizedName,
      orElse: () => throw StateError('Unknown metro stop: $name'),
    );
  }

  int? _findForwardRouteMatch(
    String vehicleId,
    EvLocation location,
    List<String> routeOrder,
  ) {
    final trackingService = EvTrackingService();
    final lastIndex = _evLastRouteIndex[vehicleId];

    // Once progress exists, never search earlier route occurrences.
    final startIndex = lastIndex ?? 0;

    for (int i = startIndex; i < routeOrder.length; i++) {
      final stop = _routeStopFor(routeOrder[i]);

      if (trackingService.isEvNearStop(location.position, stop)) {
        return i;
      }
    }

    return null;
  }

  void _updateRouteState(
    String vehicleId,
    EvLocation location,
    List<String> routeOrder,
  ) {
    final matchedIndex = _findForwardRouteMatch(
      vehicleId,
      location,
      routeOrder,
    );

    if (matchedIndex != null) {
      final previousIndex = _evLastRouteIndex[vehicleId];

      // Never move backwards. If the EV is still at the same stop, keep the
      // same route occurrence. If it reaches a later occurrence, advance.
      if (previousIndex == null || matchedIndex > previousIndex) {
        _evLastRouteIndex[vehicleId] = matchedIndex;
      }

      // The EV is physically at a pickup point again, so cancel any pending
      // 5-second departure confirmation.
      _evDepartureTimers.remove(vehicleId)?.cancel();

      _evAtPickupStop[vehicleId] = true;
      return;
    }

    final lastIndex = _evLastRouteIndex[vehicleId];
    if (lastIndex == null) return;

    // We are outside the current pickup radius. Do not immediately turn the
    // stop yellow; wait 5 seconds in case this is GPS jitter.
    if (_evAtPickupStop[vehicleId] != true) return;
    if (_evDepartureTimers.containsKey(vehicleId)) return;

    _evDepartureTimers[vehicleId] = Timer(const Duration(seconds: 5), () {
      _evDepartureTimers.remove(vehicleId);

      if (!mounted) return;

      final latestLocation = _evLocations[vehicleId];
      if (latestLocation == null) return;

      final currentIndex = _evLastRouteIndex[vehicleId];
      if (currentIndex == null ||
          currentIndex < 0 ||
          currentIndex >= routeOrder.length) {
        return;
      }

      final currentStop = _routeStopFor(routeOrder[currentIndex]);
      final stillAtStop = EvTrackingService().isEvNearStop(
        latestLocation.position,
        currentStop,
      );

      if (stillAtStop) {
        // GPS came back into the radius during the debounce window.
        _evAtPickupStop[vehicleId] = true;
        return;
      }

      // Confirmed departure: current stop is now yellow/passed and the
      // arrow moves to currentIndex + 1.
      _evAtPickupStop[vehicleId] = false;
      setState(() {});
    });
  }

  // Returns the last confirmed route occurrence. The UI separately checks
  // _evAtPickupStop to decide whether that occurrence is GREEN (still there)
  // or YELLOW (departed).
  int? _currentRouteIndex(
    String vehicleId,
    EvLocation location,
    List<String> routeOrder,
  ) {
    _updateRouteState(vehicleId, location, routeOrder);
    return _evLastRouteIndex[vehicleId];
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
    final anyEvAvailable = _evLocations.isNotEmpty;

    final ev1Location = _evLocations['EV1'];
    final ev2Location = _evLocations['EV2'];

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

            // ── Metro-style route progress strips — top free space ───────────
            // One permanent row per EV, showing its fixed round-trip stop
            // sequence with passed/current/next/upcoming states. Purely
            // additive, reads only from _evLocations (already-existing
            // state) plus the isEvNearStop geofence check (already-
            // existing logic).
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.of(context).padding.top + 6,
              child: Column(
                children: [
                  _buildMetroLine(
                    vehicleId: 'EV1',
                    routeOrder: _ev1RouteOrder,
                    currentIndex: ev1Location == null
                        ? null
                        : _currentRouteIndex(
                            'EV1',
                            ev1Location,
                            _ev1RouteOrder,
                          ),
                  ),
                  const SizedBox(height: 6),
                  _buildMetroLine(
                    vehicleId: 'EV2',
                    routeOrder: _ev2RouteOrder,
                    currentIndex: ev2Location == null
                        ? null
                        : _currentRouteIndex(
                            'EV2',
                            ev2Location,
                            _ev2RouteOrder,
                          ),
                  ),
                ],
              ),
            ),

            // ── Personal Arrival Notification Banner ─────────────────────────
            if (_notificationMessage != null)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 360,
                      minWidth: 300,
                    ),
                    child: _buildNotificationBanner(),
                  ),
                ),
              ),

            // ── Pickup legend ───────────────────────────────────────────────
            Positioned(
              left: 16,
              top:
                  MediaQuery.of(context).padding.top +
                  12 +
                  _metroAreaHeight(ev1Location, ev2Location) +
                  28,
              child: _buildPickupLegend(),
            ),

            // ── Map controls ─────────────────────────────────────────────────
            Positioned(
              right: 16,
              top:
                  MediaQuery.of(context).padding.top +
                  12 +
                  _metroAreaHeight(ev1Location, ev2Location) +
                  28,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildRefreshControl(),
                  const SizedBox(width: 8),
                  _buildMapControl(),
                ],
              ),
            ),

            // ── Fixed Shuttle Information Panel ──────────────────────────────
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              height: (MediaQuery.of(context).size.height * 0.245)
                  .clamp(235.0, 255.0)
                  .toDouble(),
              child: _buildPilotCard(facultyBlockName, anyEvAvailable),
            ),
          ],
        ),
      ),
    );
  }

  // Approximates how tall the metro-line area currently is, so the warning/
  // notification banners below it shift down instead of overlapping it.
  // Pure layout math — does not touch any EV state.
  double _metroAreaHeight(EvLocation? ev1, EvLocation? ev2) {
    // Both metro strips are permanently rendered, including when an EV is
    // offline. Keep overlays below the same fixed two-row area at all times.
    const lineHeight = 54.0;
    const gap = 6.0;
    return (lineHeight * 2) + gap;
  }

  // ---------------------------------------------------------------------------
  // METRO-STYLE ROUTE PROGRESS WIDGET
  // ---------------------------------------------------------------------------
  //
  // Renders one horizontal line for a single EV's full round-trip route:
  //   - Stops before `currentIndex`  -> passed (dull yellow/orange)
  //   - Stop at `currentIndex`       -> current/at pickup (solid green)
  //                                      ONLY while physically there
  //   - Stop at `currentIndex + 1`   -> next / approaching (blinking)
  //   - After a 5-second confirmed departure, the former current becomes
  //     yellow and the next stop becomes the route focus.
  //   - Everything after that        -> upcoming (neutral grey)
  //   - If `currentIndex` is null (EV online but hasn't reached its first
  //     stop yet, or nowhere near any stop at all), NOTHING is green —
  //     only stop 0 blinks as "waiting to start," rest stay grey.
  //
  // Auto-scrolls horizontally to keep the current/next stop visible as
  // progress advances, so the user doesn't have to manually swipe to see
  // where the EV currently is on a 9-stop route.

  Widget _buildMetroLine({
    required String vehicleId,
    required List<String> routeOrder,
    required int? currentIndex,
  }) {
    final nextIndex = (currentIndex ?? -1) + 1;
    final isAtPickupStop = _evAtPickupStop[vehicleId] ?? false;

    final controller = _metroScrollControllers.putIfAbsent(
      vehicleId,
      () => ScrollController(),
    );

    // Auto-scroll to bring the focus stop (current, or next if nothing
    // is current yet) into view, without fighting the user if they're
    // actively scrolling it themselves.
    final focusIndex = isAtPickupStop ? (currentIndex ?? nextIndex) : nextIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      const segmentWidth = 64.0; // 46 label width + 18 connector width
      final targetOffset = (focusIndex * segmentWidth - 60).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      if ((controller.offset - targetOffset).abs() > 4) {
        controller.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: _buildGlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: vitGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                vehicleId,
                style: const TextStyle(
                  color: vitGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: List.generate(routeOrder.length, (i) {
                    final isCurrent = isAtPickupStop && i == currentIndex;
                    final isPassed = currentIndex != null && i < currentIndex;
                    final isNext = currentIndex != null && i == nextIndex;

                    final dot = _buildMetroDot(
                      isPassed: isPassed,
                      isCurrent: isCurrent,
                      isNext: isNext,
                    );

                    final stopLabel = Text(
                      routeOrder[i],
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: isCurrent
                            ? FontWeight.w900
                            : FontWeight.w700,
                        color: isCurrent
                            ? vitGreen
                            : (isPassed
                                  ? Colors.orange.shade800
                                  : Colors.grey.shade500),
                      ),
                    );

                    final segment = SizedBox(
                      width: 46,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [dot, const SizedBox(height: 3), stopLabel],
                      ),
                    );

                    if (i == routeOrder.length - 1) {
                      return segment;
                    }

                    final connectorPassed =
                        currentIndex != null && i < currentIndex;

                    final isActiveConnector =
                        currentIndex != null &&
                        i == currentIndex &&
                        currentIndex + 1 < routeOrder.length;
                    return Row(
                      children: [
                        segment,
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 18,
                                height: 2.5,
                                color: connectorPassed
                                    ? Colors.orange.shade400
                                    : Colors.grey.withValues(alpha: 0.25),
                              ),
                              if (isActiveConnector)
                                AnimatedBuilder(
                                  animation: _glowController,
                                  builder: (context, child) {
                                    return Align(
                                      alignment: Alignment(
                                        -0.65 + (_glowController.value * 1.3),
                                        0,
                                      ),
                                      child: const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 16,
                                        color: vitGreen,
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(width: 4),
            AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset((_glowController.value * 4) - 2, 0),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: vitGreen,
                    size: 16,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetroDot({
    required bool isPassed,
    required bool isCurrent,
    required bool isNext,
  }) {
    if (isCurrent) {
      return AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final glow = 8.0 + (_glowController.value * 8.0);
          final alpha = 0.35 + (_glowController.value * 0.30);
          return Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              color: vitGreen,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: vitGreen.withValues(alpha: alpha),
                  blurRadius: glow,
                  spreadRadius: 1.5,
                ),
              ],
            ),
          );
        },
      );
    }

    // The next stop stays neutral until the EV physically reaches it.
    if (isNext) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: Colors.grey.shade400,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      );
    }

    if (isPassed) {
      return Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: Colors.orange.shade400,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      );
    }

    // Upcoming / not yet relevant.
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.35),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
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

  Widget _buildRefreshControl() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _refreshEvStatus,
        child: _buildGlassContainer(
          padding: const EdgeInsets.all(8),
          child: const Icon(Icons.refresh_rounded, color: vitBlue, size: 22),
        ),
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
      markers.add(_buildCampusMarker(position: block.value, label: block.key));
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
  bool _isEvNearPickupPoint(LatLng pickupPosition) {
    const radiusMeters = 35.0;

    for (final location in _evLocations.values) {
      final distance = Geolocator.distanceBetween(
        location.position.latitude,
        location.position.longitude,
        pickupPosition.latitude,
        pickupPosition.longitude,
      );

      if (distance <= radiusMeters) return true;
    }

    return false;
  }

  // Pickup pin glows ONLY while an active EV is physically inside this
  // pickup point's radius. Every pickup point is checked independently.
  Marker _buildPickupMarker(LatLng position) {
    const pinSize = 40.0;
    final evInsideRadius = _isEvNearPickupPoint(position);

    return Marker(
      point: position,
      width: pinSize,
      height: pinSize,
      alignment: Alignment.topCenter,
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final glow = evInsideRadius
              ? 0.35 + (_glowController.value * 0.30)
              : 0.0;

          return Stack(
            alignment: Alignment.topCenter,
            children: [
              if (evInsideRadius)
                Positioned(
                  top: 2,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: pickupPinColor.withValues(alpha: glow),
                          blurRadius: 15,
                          spreadRadius: 2,
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

  // ---------------------------------------------------------------------------
  // VEHICLE MARKER — EV icon + radial direction-flow chevrons
  // (UNCHANGED FROM YOUR CURRENT VERSION — including your size/opacity edits)
  // ---------------------------------------------------------------------------

  Marker _buildVehicleMarker(EvLocation location) {
    final vehicleId = location.vehicleId;
    final rawMoving = location.speed >= 1.0;
    final wasMoving = _evMovingStable[vehicleId] ?? rawMoving;

    // Hysteresis purely for the arrow's visual on/off state: once moving,
    // only flips back to "stopped" below a lower threshold, so GPS speed
    // jitter right around 1.0 m/s can't flicker the arrows.
    final isMoving = wasMoving ? (location.speed >= 0.6) : rawMoving;
    _evMovingStable[vehicleId] = isMoving;

    final headingRad = location.heading * (math.pi / 180);

    return Marker(
      point: location.position,
      width: 92,
      height: 92,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _glowController]),
        builder: (context, child) {
          final scale = isMoving ? 1.0 : 1.0 + (_pulseController.value * 0.07);

          return Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // ── Direction chevrons — radially placed around the icon
                //    along the heading line, animating outward on a loop.
                if (isMoving)
                  ..._buildDirectionChevrons(
                    headingRad: headingRad,
                    animationValue: _glowController.value,
                  ),

                // ── EV icon — perfectly centered, untouched ─────────────
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

                // ── Vehicle label — pinned below the icon ────────────────
                Positioned(
                  bottom: -22,
                  child: Container(
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
                      vehicleId,
                      style: const TextStyle(
                        color: vitBlue,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
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

  // Builds small chevrons along the heading direction from the icon's
  // center, spaced at increasing radius with decreasing opacity, staggered
  // in phase so together they read as a continuous outward flow — a subtle
  // trailing pulse in the travel direction, always tucked right next to
  // the icon. (UNCHANGED — retains your bigger size/opacity/radius edits.)
  List<Widget> _buildDirectionChevrons({
    required double headingRad,
    required double animationValue,
  }) {
    const chevronCount = 3;
    const baseRadius = 38.0;
    const radiusSpread = 20.0;
    const chevronSize = 22.0;

    final dx = math.sin(headingRad);
    final dy = -math.cos(headingRad);

    return List.generate(chevronCount, (i) {
      final phase = (animationValue + (i / chevronCount)) % 1.0;
      final radius = baseRadius + (phase * radiusSpread);
      final opacity = (0.85 * (1.0 - phase)).clamp(0.0, 0.85);

      return Transform.translate(
        offset: Offset(dx * radius, dy * radius),
        child: Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: headingRad,
            child: Icon(
              Icons.navigation_rounded,
              color: vitGreen,
              size: chevronSize,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ),
      );
    });
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
      child: Material(
        color: Colors.transparent,
        child: _buildGlassContainer(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: vitGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: vitGreen,
                  size: 27,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Ready for pickup',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: vitBlue,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _notificationMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _notificationMessage = null);
                      NotificationService.instance.cancelEvArrival();
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: vitBlue,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Text(
                        'CLOSE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEvStatusCard(
    String vehicleId,
    EvLocation? location,
    List<String> routeOrder,
  ) {
    final online = location != null;
    final index = online
        ? (_currentRouteIndex(vehicleId, location, routeOrder) ?? -1)
        : -1;
    final current = online && index >= 0 && index < routeOrder.length
        ? routeOrder[index]
        : '—';
    final next = online && index >= 0 && index + 1 < routeOrder.length
        ? routeOrder[index + 1]
        : '—';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: online
            ? vitGreen.withValues(alpha: 0.07)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: online
              ? vitGreen.withValues(alpha: 0.25)
              : Colors.grey.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.electric_rickshaw_rounded,
                size: 18,
                color: online ? vitGreen : Colors.grey,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  vehicleId,
                  style: const TextStyle(
                    color: vitBlue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  online ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    color: online ? vitGreen : Colors.grey.shade600,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Current: $current',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: vitBlue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Next: $next',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTTOM DRAGGABLE CARD
  // ---------------------------------------------------------------------------

  // Fixed, non-scrollable bottom panel. The panel height is controlled by
  // the Positioned widget in build(), so the map remains stable and the
  // information stays visible without dragging or inner scrolling.
  Widget _buildPilotCard(String facultyBlockName, bool anyEvAvailable) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.75),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          6,
          16,
          MediaQuery.of(context).padding.bottom + 6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [vitGreenSoft, vitGreen],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: vitGreen.withValues(alpha: 0.28),
                        blurRadius: 9,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.electric_rickshaw_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VIT EV Shuttle',
                        style: TextStyle(
                          color: vitBlue,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        facultyBlockName == 'Not assigned'
                            ? 'Your pickup point: Not assigned'
                            : 'Your pickup point: $facultyBlockName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                const SizedBox(width: 8),
                _buildStatusBadge(anyEvAvailable),
              ],
            ),
            const SizedBox(height: 7),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildEvStatusCard(
                      'EV1',
                      _evLocations['EV1'],
                      _ev1RouteOrder,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildEvStatusCard(
                      'EV2',
                      _evLocations['EV2'],
                      _ev2RouteOrder,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
