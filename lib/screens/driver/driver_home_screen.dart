import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../services/location_service.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final LocationService _locationService = LocationService();

  Timer? _clockTimer;

  DateTime _currentDateTime = DateTime.now();

  bool _shiftActive = false;
  bool _isProcessing = false;

  // Temporary pilot value.
  // Final backend integration will identify the driver
  // and allocate one of EV1-EV2 as the active tracking slot.
  String? _activeVehicleId;
  String? _selectedVehicleId;

  // Temporary pilot value.
  // Final app will obtain the driver's identity from authentication.
  final String _driverName = 'Driver';

  @override
  void initState() {
    super.initState();
    _locationService.onConnectionChanged = _handleConnectionChanged;
    _locationService.onShiftAutoEnded = _handleShiftAutoEnded;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreExistingShift();
    });

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _currentDateTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _locationService.onConnectionChanged = null;
    _locationService.onShiftAutoEnded = null;
    super.dispose();
  }

  Future<void> _restoreExistingShift() async {
    if (Firebase.apps.isEmpty) {
      return;
    }

    try {
      String? vehicleId;

      // Firebase can take a short moment to reconnect after the app is
      // reopened, so try more than once before deciding that no shift exists.
      for (int attempt = 1; attempt <= 3; attempt++) {
        vehicleId = await _locationService.findExistingShift();
        debugPrint(
          'SHIFT RESTORE CHECK $attempt/3: ${vehicleId ?? 'NO ACTIVE SHIFT'}',
        );

        if (vehicleId != null) break;

        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }

      if (!mounted || vehicleId == null) return;

      // Update the UI as soon as Firebase confirms the active shift.
      // GPS reconnection must not control whether the shift card is shown.
      setState(() {
        _shiftActive = true;
        _activeVehicleId = vehicleId;
        _selectedVehicleId = vehicleId;
        _isProcessing = true;
      });

      final restored = await _locationService.restoreTracking(vehicleId);

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
      });

      if (!restored) {
        _showMessage(
          'Your shift is active, but location tracking could not restart. Please enable GPS and check permissions.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('SHIFT RESTORE ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _startShift() async {
    if (_isProcessing || _shiftActive) {
      return;
    }

    if (_selectedVehicleId == null) {
      _showMessage('Please select an EV before starting your shift.');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    final started = await _locationService
        .startTracking(_selectedVehicleId!)
        .timeout(const Duration(seconds: 12), onTimeout: () => false);

    if (!mounted) {
      return;
    }

    setState(() {
      _isProcessing = false;
      _shiftActive = started;
      _activeVehicleId = started ? _locationService.vehicleId : null;
    });

    if (!started) {
      _showMessage(
        _locationService.lastErrorMessage ??
            'Unable to connect to the server. Please check your internet connection and try again.',
      );
    } else {
      _showMessage(
        'Shift started successfully. ${_activeVehicleId ?? 'EV'} tracking is now active.',
      );
    }
  }

  Future<void> _endShift() async {
    if (_isProcessing || !_shiftActive) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await _locationService.stopTracking().timeout(
        const Duration(seconds: 12),
      );

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
        _shiftActive = false;
        _activeVehicleId = null;
        _selectedVehicleId = null;
      });

      _showMessage('Shift ended successfully. Location tracking stopped.');
    } catch (error) {
      debugPrint('END SHIFT ERROR: $error');
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showMessage(
        'Unable to end your shift. Please check your connection and try again.',
      );
    }
  }

  bool _isNetworkConnected = true;

  void _handleShiftAutoEnded() {
    if (!mounted) return;
    setState(() {
      _shiftActive = false;
      _activeVehicleId = null;
      _selectedVehicleId = null;
      _isProcessing = false;
    });
    _showMessage('Your shift ended automatically after 30 minutes.');
  }

  void _handleConnectionChanged(bool connected) {
    if (!mounted) return;

    final wasDisconnected = !_isNetworkConnected;

    setState(() {
      _isNetworkConnected = connected;
    });

    if (_shiftActive && connected && wasDisconnected) {
      _showMessage(
        'Network connection restored. EV location tracking has resumed.',
      );
    }
  }

  Widget _buildNetworkStatusBanner() {
    if (_isNetworkConnected || !_shiftActive) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.red.shade700,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.wifi_off, color: Colors.white),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Network connection lost. Location updates will resume when the connection returns.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  String get _formattedTime {
    final hour = _currentDateTime.hour;
    final minute = _currentDateTime.minute;

    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;

    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  String get _formattedDate {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[_currentDateTime.month - 1]} '
        '${_currentDateTime.day}, '
        '${_currentDateTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildNetworkStatusBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeSection(),
                    const SizedBox(height: 30),
                    if (_shiftActive)
                      _buildActiveShiftCard()
                    else
                      _buildStartShiftCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF123C69),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'VIT',
                style: TextStyle(
                  color: Color(0xFF123C69),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'VIT EV BUGGY',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome, $_driverName',
          style: const TextStyle(
            color: Color(0xFF183B56),
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _formattedDate,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _formattedTime,
          style: const TextStyle(
            color: Color(0xFF183B56),
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildStartShiftCard() {
    return _buildGlassCard(
      child: Column(
        children: [
          _buildStatusIcon(
            icon: Icons.directions_car_rounded,
            background: const Color(0xFFDDF5E8),
            iconColor: const Color(0xFF18864B),
          ),
          const SizedBox(height: 18),
          const Text(
            'Ready to Start',
            style: TextStyle(
              color: Color(0xFF183B56),
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start your shift to begin live EV location tracking.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _selectedVehicleId,
            decoration: InputDecoration(
              hintText: 'Choose EV',
              filled: true,
              fillColor: const Color(0xFFF2F8F4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'EV1', child: Text('EV1')),
              DropdownMenuItem(value: 'EV2', child: Text('EV2')),
            ],
            onChanged: _isProcessing
                ? null
                : (value) {
                    setState(() => _selectedVehicleId = value);
                  },
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton(
            label: 'START SHIFT',
            icon: Icons.play_arrow_rounded,
            onPressed: _isProcessing ? null : _startShift,
            loading: _isProcessing,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveShiftCard() {
    return _buildGlassCard(
      child: Column(
        children: [
          _buildStatusIcon(
            icon: Icons.location_on_rounded,
            background: const Color(0xFFDDF5E8),
            iconColor: const Color(0xFF18864B),
          ),
          const SizedBox(height: 18),
          const Text(
            'Shift Active',
            style: TextStyle(
              color: Color(0xFF183B56),
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Live location tracking is active',
            style: TextStyle(
              color: Color(0xFF18864B),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F8F4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.electric_car_rounded,
                  color: Color(0xFF18864B),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Active Tracking ID',
                    style: TextStyle(
                      color: Color(0xFF52636F),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  _activeVehicleId ?? 'EV',
                  style: const TextStyle(
                    color: Color(0xFF183B56),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _buildEndShiftButton(),
        ],
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDDEEE4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF18864B).withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStatusIcon({
    required IconData icon,
    required Color background,
    required Color iconColor,
  }) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: 34, color: iconColor),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required bool loading,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF18864B),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF9ABBA8),
          elevation: 5,
          shadowColor: const Color(0xFF18864B).withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 23,
                height: 23,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 25),
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildEndShiftButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: OutlinedButton(
        onPressed: _isProcessing ? null : _endShift,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFC62828),
          side: const BorderSide(color: Color(0xFFC62828), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: _isProcessing
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.stop_rounded, size: 23),
                  SizedBox(width: 8),
                  Text(
                    'END SHIFT',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
