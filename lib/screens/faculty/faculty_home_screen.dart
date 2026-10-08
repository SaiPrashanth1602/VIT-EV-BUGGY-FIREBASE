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

/// Main faculty screen for viewing live EV locations, pickup alerts, and shuttle details.
class FacultyHomeScreen extends StatefulWidget {
  const FacultyHomeScreen({super.key});

  @override
  State<FacultyHomeScreen> createState() => _FacultyHomeScreenState();
}

class _FacultyHomeScreenState extends State<FacultyHomeScreen>
    with TickerProviderStateMixin {
  // Shuttle times in minutes after midnight, grouped by pickup block.
  static const Map<String, List<int>> _ev1OutboundByBlock = {
    'AB1': [468, 523, 578, 633, 688, 743, 828, 883, 938],
    'AB3': [470, 525, 580, 635, 690, 745, 830, 885, 940],
    'AB2, AB4 Junction': [472, 527, 582, 637, 692, 747, 832, 887, 942],
    'MAB3, MAB4': [475, 530, 585, 640, 695, 750, 835, 890, 945],
  };

  static const Map<String, List<int>> _ev2OutboundByBlock = {
    'AB3': [473, 527, 583, 637, 693, 747, 833, 887, 943],
    'AB2, AB4 Junction': [475, 529, 585, 639, 695, 750, 835, 889, 945],
    'MAB3, MAB4': [477, 532, 587, 642, 707, 752, 837, 892, 947],
    'AB5': [482, 537, 592, 647, 702, 757, 842, 898, 952],
  };

  static const Map<String, List<int>> _ev1ReturnByBlock = {
    'MAB3, MAB4': [540, 595, 650, 705, 760, 900, 955],
    'AB2, AB4 Junction': [543, 598, 653, 708, 763, 903, 958],
    'AB3': [545, 600, 655, 710, 765, 905, 960],
    'AB1': [547, 602, 657, 712, 767, 907, 962],
  };

  static const Map<String, List<int>> _ev2ReturnByBlock = {
    'AB5': [538, 593, 648, 703, 758, 898, 953],
    'MAB3, MAB4': [543, 598, 653, 708, 763, 903, 957],
    'AB2, AB4 Junction': [546, 601, 656, 711, 766, 906, 960],
    'AB3': [548, 603, 658, 713, 768, 908, 962],
  };

  // Route order used only for the top progress bars.
  // Repeated stops are expected because the EV returns along the same route.
  static const List<String> _ev1RouteOrder = [
    'AB1',
    'AB3',
    'AB2, AB4 Junction',
    'MAB3, MAB4',
    'AB2, AB4 Junction',
    'AB3',
    'AB1',
  ];

  static const List<String> _ev2RouteOrder = [
    'AB3',
    'AB2, AB4 Junction',
    'MAB3, MAB4',
    'AB5',
    'MAB3, MAB4',
    'AB2, AB4 Junction',
    'AB3',
  ];

  /// Shared map and brand values used across route overlays, markers, and status
  /// widgets. They are kept together here so the screen's visual language remains
  /// consistent without leaking map-specific constants into lower-level services.
  static const Color vitBlue = Color(0xFF0F2C56);
  static const Color vitBlueLight = Color(0xFF1A4A7A);
  static const Color vitGreen = Color(0xFF16A34A);
  static const Color vitGreenSoft = Color(0xFF22C55E);
  static const Color routeYellow = Color(0xFFFACC15);
  static const LatLng vitChennai = LatLng(12.8406, 80.1534);

  static const Color pickupPinColor = Color(0xFFB33A3A);

  // Controls the campus map and recenters it on the faculty user when needed.
  final MapController _mapController = MapController();

  // Uses Firebase for live EV updates on supported mobile devices.
  // Uses an empty fallback provider when Firebase tracking is not available.
  late final EvLocationProvider _evProvider =
      (Platform.isAndroid || Platform.isIOS) && Firebase.apps.isNotEmpty
      ? EvApiProvider()
      : const NoopEvLocationProvider();

  // Gets the faculty user's GPS location.
  late final FacultyLocationService _facultyLocationService;

  // Keeps track of live EV updates, faculty GPS updates, and the EV status check.
  StreamSubscription<EvLocation>? _evSubscription;
  StreamSubscription<Position>? _facultyLocationSubscription;

  Timer? _evAvailabilityTimer;

  /// Current faculty position and block assignment used for map centering, UI
  /// state, and personal arrival checks. It is refreshed by the location stream.
  LatLng? _facultyPosition;

  // Latest location for each online EV.
  // EV1 and EV2 are kept separate, so one offline EV does not hide the other.
  final Map<String, EvLocation> _evLocations = {};

  // Remembers which EVs are already at the faculty user's pickup point.
  // This stops the same arrival alert from appearing repeatedly.
  final Set<String> _evInsideFacultyBlockIds = {};

  // Keeps movement arrows from flickering when GPS speed changes slightly.
  final Map<String, bool> _evMovingStable = {};

  // Last confirmed route stop for each EV.
  // This prevents repeated return-trip stops from jumping back to an earlier stop.
  final Map<String, int> _evLastRouteIndex = {};

  // Tracks whether each EV is still inside its current pickup-point area.
  final Map<String, bool> _evAtPickupStop = {};

  // Gives a short delay before marking an EV as departed, avoiding GPS flicker.
  final Map<String, Timer> _evDepartureTimers = {};

  // Keeps recent speed readings for each EV.
  final Map<String, List<double>> _evRecentSpeeds = {};

  // Faculty location and notification state used by the map and alerts.
  String? _facultyBlockName;
  String? _notificationMessage;

  bool _locationAvailable = false;
  bool _hasInitialMapCentered = false;

  // Used only for map and route animations. They do not change tracking logic.
  late AnimationController _pulseController;
  late AnimationController _glowController;

  // Campus block markers shown on the map.
  static const List<MapEntry<String, LatLng>> _campusBlocks = [
    MapEntry('AB1', EvTrackingService.ab1Block),
    MapEntry('AB3', EvTrackingService.ab3Block),
    MapEntry('AB2', EvTrackingService.ab2Block),
    MapEntry('AB4', EvTrackingService.ab4Block),
    MapEntry('MAB3', EvTrackingService.mab3Block),
    MapEntry('MAB4', EvTrackingService.mab4Block),
    MapEntry('AB5', EvTrackingService.ab5Block),
  ];

  @override
  // Starts animations, location services, and live EV tracking when this screen opens.
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

  // Refreshes EV locations manually using the same logic as live updates.
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

  // Prepares notifications, starts EV tracking, and starts faculty GPS tracking.
  Future<void> _initialize() async {
    await NotificationService.instance.initialize();

    try {
      // Listen before starting the provider so the first EV update is not missed.
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

  // Changes timetable minutes into a readable AM/PM time.
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

  // Outbound trips have no extra label. Return trips show "RETURN".
  static const String _outboundDirectionLabel = '';

  // Finds the next scheduled EV for the selected pickup block.
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

  // Returns the next few shuttle times for the selected pickup block.
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

  /// Checks location services and permission before starting faculty GPS tracking.
  Future<void> _startFacultyLocation() async {
    try {
      // GPS must be enabled to find the faculty user's pickup block.
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

        // Check again because the user may have changed the permission.
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

      // Start GPS updates after location access is allowed.
      final started = await _facultyLocationService.startTracking();

      if (!started) {
        if (mounted) setState(() => _locationAvailable = false);
        return;
      }

      if (mounted) setState(() => _locationAvailable = true);

        // Use the first location immediately instead of waiting for the next stream update.
        final initialPosition = await _facultyLocationService
          .getCurrentPosition();
      if (initialPosition != null) {
        _handleFacultyPosition(initialPosition);
      }

      _facultyLocationSubscription ??= _facultyLocationService.locationStream
          .listen(_handleFacultyPosition, onError: (_) {});
    } catch (_) {}
  }

  // Updates the faculty marker and finds the user's nearby pickup block.
  void _handleFacultyPosition(Position position) {
    final facultyPosition = LatLng(position.latitude, position.longitude);
    final facultyStop = EvTrackingService().findFacultyBlock(facultyPosition);

    if (!mounted) return;

    setState(() {
      _facultyPosition = facultyPosition;
      _locationAvailable = true;
      _facultyBlockName = facultyStop?.name;
    });

    // Center the map only once so later GPS updates do not fight manual map movement.
    if (!_hasInitialMapCentered) {
      _hasInitialMapCentered = true;
      _mapController.move(facultyPosition, 16.8);
    }

    if (facultyStop != null) {
      // Check all current EVs again after the user's block changes.
      for (final location in _evLocations.values) {
        _checkEvArrival(facultyPosition, facultyStop, location);
      }
    }
  }

  // Handles one live EV update from Firebase or manual refresh.
  void _handleEvLocation(EvLocation location) {
    if (!mounted) return;

    final now = DateTime.now().toUtc();
    // Ignore old updates so an offline EV does not stay on the map.
    final isStale = now.difference(location.timestamp).inSeconds > 180;

    if (isStale) {
      _removeEvLocation(location.vehicleId);
      return;
    }

    final speed = location.speed;
    if (speed.isFinite && speed > 0.5) {
      final samples = _evRecentSpeeds.putIfAbsent(
        location.vehicleId,
        () => <double>[],
      );
      samples.add(speed);
      if (samples.length > 10) {
        samples.removeAt(0);
      }
    }

    // Save the latest location for this EV only.
    setState(() {
      _evLocations[location.vehicleId] = location;
    });

    if (_facultyPosition == null) return;

    final facultyStop = EvTrackingService().findFacultyBlock(_facultyPosition!);
    if (facultyStop == null) return;

    _checkEvArrival(_facultyPosition!, facultyStop, location);
  }

  // Removes one offline or stale EV without affecting the others.
  void _removeEvLocation(String vehicleId) {
    if (!mounted) return;

    setState(() {
      _evLocations.remove(vehicleId);
    });

    // Clear old route and animation state so this EV starts fresh next time.
    _evMovingStable.remove(vehicleId);
    final timersToCancel = _evDepartureTimers.keys
        .where((key) => key.startsWith('$vehicleId:'))
        .toList();
    for (final key in timersToCancel) {
      _evDepartureTimers.remove(key)?.cancel();
    }
    _evAtPickupStop.remove(vehicleId);
    _evRecentSpeeds.remove(vehicleId);

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

  // Checks every few seconds for EVs that disappeared from fresh Firebase data.
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
            _handleEvLocation(loc);
          }
        }

        for (final loc in locations) {
          if (now.difference(loc.timestamp).inSeconds <= 180) {
            activeIds.add(loc.vehicleId);
          }
        }

        // Remove EVs that are no longer in the latest active list.
        final staleIds = _evLocations.keys
            .where((id) => !activeIds.contains(id))
            .toList();

        for (final id in staleIds) {
          _removeEvLocation(id);
        }
      } catch (_) {}
    });
  }

  // Clears all EV markers and alerts when no live EV data is available.
  void _clearAllEvLocations() {
    if (!mounted) return;

    setState(() {
      _evLocations.clear();
      _notificationMessage = null;
    });

    _evMovingStable.clear();
    _evLastRouteIndex.clear();
    _evAtPickupStop.clear();
    _evRecentSpeeds.clear();
    for (final timer in _evDepartureTimers.values) {
      timer.cancel();
    }
    _evDepartureTimers.clear();
    _evInsideFacultyBlockIds.clear();

    NotificationService.instance.cancelEvArrival();
  }

  // Checks whether this EV actually serves the faculty user's pickup block.
  bool _vehicleServesFacultyBlock(String vehicleId, String blockName) {
    switch (vehicleId) {
      case 'EV1':
        return _ev1OutboundByBlock.containsKey(blockName) ||
            _ev1ReturnByBlock.containsKey(blockName);

      case 'EV2':
        return _ev2OutboundByBlock.containsKey(blockName) ||
            _ev2ReturnByBlock.containsKey(blockName);

      default:
        return false;
    }
  }

  // Shows an arrival alert only when an EV reaches the faculty user's pickup point.
  void _checkEvArrival(
    LatLng facultyPosition,
    CampusStop facultyStop,
    EvLocation evLocation,
  ) {
    final trackingService = EvTrackingService();
    final vehicleId = evLocation.vehicleId;
    final blockName = facultyStop.name;

    // Do not alert for an EV that does not serve this pickup block.
    final vehicleServesBlock = _vehicleServesFacultyBlock(vehicleId, blockName);

    if (!vehicleServesBlock) {
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

    final evNear = trackingService.isEvNearStop(
      evLocation.position,
      facultyStop,
    );

    if (evNear) {
      if (!_evInsideFacultyBlockIds.contains(vehicleId)) {
        // Alert only once when this EV enters the pickup area.
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
            if (_evInsideFacultyBlockIds.isEmpty) {
              // Keep the alert visible if another EV is still at the pickup point.
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

  // Matches a route label to the campus stop used for route progress checks.
  CampusStop _routeStopFor(String name) {
    // MAB3 and MAB4 use one shared pickup point for route progress.
    if (name == 'MAB3, MAB4') {
      const sharedPickup = LatLng(12.84406852670757, 80.15824012738847);
      return const CampusStop(
        name: 'MAB3, MAB4',
        blockPosition: sharedPickup,
        pickupPosition: sharedPickup,
      );
    }

    final normalizedName = name == 'AB2, AB4 Junction' ? 'AB2-4' : name;

    return EvTrackingService.campusStops.firstWhere(
      (s) => s.name == normalizedName,
      orElse: () => throw StateError('Unknown metro stop: $name'),
    );
  }

  // Searches only ahead in the route so return trips do not jump backward.
  int? _findForwardRouteMatch(
    String vehicleId,
    EvLocation location,
    List<String> routeOrder,
  ) {
    final trackingService = EvTrackingService();
    final lastIndex = _evLastRouteIndex[vehicleId];

    final startIndex = lastIndex == null ? 0 : lastIndex + 1;

    for (int i = startIndex; i < routeOrder.length; i++) {
      final stop = _routeStopFor(routeOrder[i]);
      if (trackingService.isEvNearStop(location.position, stop)) {
        return i;
      }
    }

    return null;
  }

  // Updates the route bar using real pickup-point matches from the live EV location.
  void _updateRouteState(
    String vehicleId,
    EvLocation location,
    List<String> routeOrder,
  ) {
    final trackingService = EvTrackingService();
    final lastIndex = _evLastRouteIndex[vehicleId];

    // Do not guess a starting stop. Wait until the EV reaches a real pickup point.
    if (lastIndex == null) {
      final firstMatch = _findForwardRouteMatch(
        vehicleId,
        location,
        routeOrder,
      );
      if (firstMatch != null) {
        _evLastRouteIndex[vehicleId] = firstMatch;
        _evAtPickupStop[vehicleId] = true;
      }
      return;
    }

    if (lastIndex < 0 || lastIndex >= routeOrder.length) return;

    final currentStop = _routeStopFor(routeOrder[lastIndex]);
    final stillAtCurrentStop = trackingService.isEvNearStop(
      location.position,
      currentStop,
    );

    if (stillAtCurrentStop) {
      final currentTimerKey = '$vehicleId:$lastIndex';
      _evDepartureTimers.remove(currentTimerKey)?.cancel();
      _evAtPickupStop[vehicleId] = true;
      return;
    }

    final departedIndex = lastIndex;
    final departureTimerKey = '$vehicleId:$departedIndex';

    if (_evAtPickupStop[vehicleId] != false) {
      _evAtPickupStop[vehicleId] = true;
    }

    if (!_evDepartureTimers.containsKey(departureTimerKey) &&
        _evAtPickupStop[vehicleId] == true) {
      // Wait briefly before marking the EV as departed to avoid GPS flicker.
      _evDepartureTimers[departureTimerKey] = Timer(
        const Duration(seconds: 3),
        () {
          _evDepartureTimers.remove(departureTimerKey);
          if (!mounted) return;

          if (_evLastRouteIndex[vehicleId] == departedIndex) {
            _evAtPickupStop[vehicleId] = false;
          }

          setState(() {});
        },
      );
    }

    final reachedLaterIndex = _findForwardRouteMatch(
      vehicleId,
      location,
      routeOrder,
    );

    // Move forward only when the EV reaches a later pickup point.
    if (reachedLaterIndex != null) {
      _evLastRouteIndex[vehicleId] = reachedLaterIndex;
      _evAtPickupStop[vehicleId] = true;
    }
  }

  // Returns the last confirmed stop for the EV route progress bar.
  int? _currentRouteIndex(
    String vehicleId,
    EvLocation location,
    List<String> routeOrder,
  ) {
    _updateRouteState(vehicleId, location, routeOrder);
    return _evLastRouteIndex[vehicleId];
  }

  // Shows a clear message when GPS services or permission are needed.
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
    // Stops timers, streams, GPS tracking, and animations when leaving this screen.
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

  @override
  // Builds the map, live EV markers, route bars, alerts, and bottom information panel.
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
            // Main campus map with route lines and live markers.
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

                // Draw the fixed shuttle route below the live markers.
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
                // Draw the fixed shuttle route below the live markers.
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

            // One route bar for each EV.
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

            // Personal pickup alert shown when an EV arrives.
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

            Positioned(
              left: 16,
              top:
                  MediaQuery.of(context).padding.top +
                  12 +
                  _metroAreaHeight(ev1Location, ev2Location) +
                  28,
              child: _buildPickupLegend(),
            ),

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

            // Shows the faculty block and EV status summary.
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

  // Keeps map banners below the route progress bars.
  double _metroAreaHeight(EvLocation? ev1, EvLocation? ev2) {
    const lineHeight = 50.0;
    const gap = 4.0;
    return (lineHeight * 2) + gap;
  }

  // Builds the route progress bar for one EV.
  Widget _buildMetroLine({
    required String vehicleId,
    required List<String> routeOrder,
    required int? currentIndex,
  }) {
    final nextIndex = (currentIndex ?? -1) + 1;
    final isAtPickupStop = _evAtPickupStop[vehicleId] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: _buildGlassContainer(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 42),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: vitGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                vehicleId,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: vitGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(routeOrder.length, (i) {
                    // Green is the current stop, orange is passed, and grey is not reached yet.
                    final isCurrent = isAtPickupStop && i == currentIndex;
                    final isPassed =
                        currentIndex != null &&
                        (i < currentIndex ||
                            (i == currentIndex && !isAtPickupStop));
                    final isNext =
                        currentIndex != null &&
                        i == nextIndex &&
                        isAtPickupStop;

                    final dot = _buildMetroDot(
                      isPassed: isPassed,
                      isCurrent: isCurrent,
                      isNext: isNext,
                    );

                    final stopLabel = routeOrder[i] == 'AB2, AB4 Junction'
                        ? 'AB2, AB4\nJUNCTION'
                        : routeOrder[i] == 'MAB3, MAB4'
                        ? 'MAB3, MAB4\nJUNCTION'
                        : routeOrder[i];

                    final segment = SizedBox(
                      width: 72,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          dot,
                          const SizedBox(height: 3),
                          SizedBox(
                            height: 24,
                            child: Center(
                              child: Text(
                                stopLabel,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  height: 1.05,
                                  fontWeight: isCurrent
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                  letterSpacing: 0.05,
                                  color: isCurrent
                                      ? vitGreen
                                      : (isPassed
                                            ? Colors.orange.shade800
                                            : Colors.grey.shade500),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (i == routeOrder.length - 1) {
                      return segment;
                    }

                    final connectorPassed =
                        currentIndex != null &&
                        (i < currentIndex ||
                            (i == currentIndex && !isAtPickupStop));

                    final isActiveConnector =
                        currentIndex != null &&
                        i == currentIndex &&
                        currentIndex + 1 < routeOrder.length;

                    return Row(
                      children: [
                        segment,
                        SizedBox(
                          width: 20,
                          height: 40,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 18,
                                height: 2,
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
                                        size: 15,
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
            const SizedBox(width: 3),
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

  // Draws one stop dot for the route progress bar.
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

  // Shared frosted-card style used by map controls and route bars.
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

  // Small map key for the pickup-point pins.
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

  // Button for manually refreshing live EV locations.
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

  // Button for returning the map to the faculty user's location.
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

  // Adds pickup points, campus blocks, the faculty user, and active EVs to the map.
  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    for (final pickup in EvTrackingService.pickupPoints) {
      markers.add(_buildPickupMarker(pickup));
    }

    for (final block in _campusBlocks) {
      markers.add(_buildCampusMarker(position: block.value, label: block.key));
    }

    if (_facultyPosition != null) {
      markers.add(_buildFacultyMarker());
    }

    for (final location in _evLocations.values) {
      markers.add(_buildVehicleMarker(location));
    }

    return markers;
  }

  // Checks whether any active EV is close enough to make this pickup pin glow.
  bool _isEvNearPickupPoint(LatLng pickupPosition) {
    const radiusMeters = EvTrackingService.evTriggerRadiusMeters;

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

  // Builds one pickup-point pin. It glows when an EV is nearby.
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

  // Builds the live marker for one EV.
  Marker _buildVehicleMarker(EvLocation location) {
    final vehicleId = location.vehicleId;
    final rawMoving = location.speed >= 1.0;
    final wasMoving = _evMovingStable[vehicleId] ?? rawMoving;

    // Use two speed limits to stop direction arrows from flickering.
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
                if (isMoving)
                  ..._buildDirectionChevrons(
                    headingRad: headingRad,
                    animationValue: _glowController.value,
                  ),

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

  // Builds animated arrows showing the EV's heading direction.
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

  // Builds the "You" marker for the faculty user's location.
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

  // Builds a label marker for a campus block.
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

  // Shows the personal EV arrival message on the map.
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

  double _averageEvSpeedMps(String vehicleId, EvLocation? location) {
    final samples = _evRecentSpeeds[vehicleId];
    if (samples != null && samples.isNotEmpty) {
      final sum = samples.fold<double>(0, (a, b) => a + b);
      final average = sum / samples.length;
      if (average > 0.5) return average;
    }

    final current = location?.speed ?? 0;
    return current > 0.5 ? current : 2.0;
  }

  CampusStop? _facultyEtaStop() {
    if (_facultyPosition == null) return null;
    return EvTrackingService().findFacultyBlock(_facultyPosition!);
  }

  double _routeSegmentDistanceMeters(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  double? _calculateEtaMinutes(
    String vehicleId,
    EvLocation location,
    List<String> routeOrder,
  ) {
    final facultyStop = _facultyEtaStop();
    if (facultyStop == null) return null;

    final targetName = facultyStop.name == 'AB2-4'
        ? 'AB2, AB4 Junction'
        : facultyStop.name;

    int? currentIndex = _evLastRouteIndex[vehicleId];
    final atPickup = _evAtPickupStop[vehicleId] ?? false;

    int? targetIndex;
    final searchStart = currentIndex == null
        ? 0
        : (atPickup ? currentIndex : currentIndex + 1);

    for (int i = searchStart; i < routeOrder.length; i++) {
      if (routeOrder[i] == targetName) {
        targetIndex = i;
        break;
      }
    }

    if (targetIndex == null) return null;

    double distanceMeters = 0;

    if (currentIndex != null && atPickup && currentIndex == targetIndex) {
      return 0;
    }

    int nextStopIndex = currentIndex == null ? 0 : currentIndex + 1;

    if (nextStopIndex <= targetIndex) {
      final firstStop = _routeStopFor(routeOrder[nextStopIndex]);
      distanceMeters += _routeSegmentDistanceMeters(
        location.position,
        firstStop.pickupPosition,
      );

      for (int i = nextStopIndex; i < targetIndex; i++) {
        final a = _routeStopFor(routeOrder[i]).pickupPosition;
        final b = _routeStopFor(routeOrder[i + 1]).pickupPosition;
        distanceMeters += _routeSegmentDistanceMeters(a, b);
      }
    }

    final speedMps = _averageEvSpeedMps(vehicleId, location);
    return (distanceMeters / speedMps) / 60.0;
  }

  String _formatEta(
    String vehicleId,
    EvLocation? location,
    List<String> routeOrder,
  ) {
    if (location == null) return 'ETA: —';

    final minutes = _calculateEtaMinutes(vehicleId, location, routeOrder);
    if (minutes == null) return 'ETA: —';
    if (minutes < 0.5) return 'ETA: <1 min';
    return 'ETA: ${minutes.round()} min';
  }

  bool _isEvInsideAnyPickupPoint(LatLng position) {
    for (final pickup in EvTrackingService.pickupPoints) {
      final distanceMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        pickup.latitude,
        pickup.longitude,
      );
      if (distanceMeters <= EvTrackingService.evTriggerRadiusMeters) {
        return true;
      }
    }
    return false;
  }

  // Shows the current and next stop for one EV.
  Widget _buildEvStatusCard(
    String vehicleId,
    EvLocation? location,
    List<String> routeOrder,
  ) {
    final online = location != null;
    final index = online
        ? (_currentRouteIndex(vehicleId, location, routeOrder) ?? -1)
        : -1;
    final physicallyInsidePickup =
        online && _isEvInsideAnyPickupPoint(location.position);
    final current =
        physicallyInsidePickup && index >= 0 && index < routeOrder.length
        ? routeOrder[index]
        : '-';
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
          const SizedBox(height: 3),
          Text(
            _formatEta(vehicleId, location, routeOrder),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: vitBlue,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // Bottom panel showing the faculty pickup block and EV status.
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

  // Builds one row in the shuttle timetable.
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

  // Message shown when no timetable entries are available.
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

  // Builds one small information row in the bottom panel.
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

  // Shows whether at least one EV is online.
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

// One timetable entry used in the shuttle schedule UI.
class _ScheduleEntry {
  const _ScheduleEntry(
    this.vehicle,
    this.time,
    this.direction, {
    this.tomorrow = false,
  });

  final String vehicle;
  // Time stored as minutes after midnight.
  final int time;
  final String direction;
  final bool tomorrow;
}

// Draws the small pointer below a campus block label.
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
