import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/shift_session.dart';
import '../../services/admin_shift_service.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  static const Color _navyBlue = Color(0xFF0F2C56);
  static const Color _green = Color(0xFF16A34A);
  static const Color _background = Color(0xFFF5F7FA);

  final AdminShiftService _shiftService = AdminShiftService();

  StreamSubscription<List<ShiftSession>>? _shiftSubscription;

  DateTime _selectedDate = _dateOnly(DateTime.now());

  bool _isLoading = true;
  String? _errorMessage;
  List<ShiftSession> _allSessions = const [];

  @override
  void initState() {
    super.initState();
    _startShiftStream();
  }

  @override
  void dispose() {
    _shiftSubscription?.cancel();
    super.dispose();
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  void _startShiftStream() {
    _shiftSubscription?.cancel();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _shiftSubscription = _shiftService.watchAllShiftSessions().listen(
      (sessions) {
        if (!mounted) return;

        setState(() {
          _allSessions = sessions;
          _isLoading = false;
          _errorMessage = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;

        setState(() {
          _errorMessage = error.toString();
          _isLoading = false;
        });
      },
    );
  }

  /// Manual refresh remains useful as a fallback. In normal usage,
  /// Firebase pushes changes automatically through [_shiftSubscription].
  Future<void> _loadSessions() async {
    try {
      final sessions = await _shiftService.fetchAllShiftSessions();

      if (!mounted) return;

      setState(() {
        _allSessions = sessions;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  List<ShiftSession> _sessionsForVehicle(String vehicleId) {
    return _allSessions.where((session) {
      return session.vehicleId == vehicleId &&
          _isSameDate(session.localDateKey, _selectedDate);
    }).toList();
  }

  bool _isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  bool get _isTodaySelected => _isSameDate(_selectedDate, DateTime.now());

  String get _selectedDateLabel {
    if (_isTodaySelected) {
      return 'Today, ${DateFormat('dd MMM yyyy').format(_selectedDate)}';
    }

    return DateFormat('EEEE, dd MMM yyyy').format(_selectedDate);
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      helpText: 'Select shift date',
    );

    if (pickedDate == null || !mounted) return;

    setState(() {
      _selectedDate = _dateOnly(pickedDate);
    });
  }

  void _showToday() {
    setState(() {
      _selectedDate = _dateOnly(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final ev1Sessions = _sessionsForVehicle('EV1');
    final ev2Sessions = _sessionsForVehicle('EV2');

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _navyBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EV Buggy Admin',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
              ),
            ),
            Text(
              'Live shift monitoring dashboard',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFFD7E2F1),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh shift data',
            onPressed: _loadSessions,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: _green),
              )
            : _errorMessage != null
            ? _buildErrorState()
            : RefreshIndicator(
                color: _green,
                onRefresh: _loadSessions,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  children: [
                    _buildDateSelector(),
                    const SizedBox(height: 18),
                    _buildSummaryRow(ev1Sessions, ev2Sessions),
                    const SizedBox(height: 20),
                    _buildVehicleSection(
                      vehicleId: 'EV1',
                      sessions: ev1Sessions,
                      color: _green,
                    ),
                    const SizedBox(height: 18),
                    _buildVehicleSection(
                      vehicleId: 'EV2',
                      sessions: ev2Sessions,
                      color: _navyBlue,
                    ),
                    const SizedBox(height: 20),
                    _buildFooter(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x110F2C56),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: _green,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SHIFT HISTORY FOR',
                  style: TextStyle(
                    color: Color(0xFF718096),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _selectedDateLabel,
                  style: const TextStyle(
                    color: _navyBlue,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (!_isTodaySelected)
            TextButton(
              onPressed: _showToday,
              style: TextButton.styleFrom(
                foregroundColor: _green,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text(
                'TODAY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Choose another date',
            onPressed: _pickDate,
            icon: const Icon(
              Icons.edit_calendar_rounded,
              color: _navyBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    List<ShiftSession> ev1Sessions,
    List<ShiftSession> ev2Sessions,
  ) {
    final totalShifts = ev1Sessions.length + ev2Sessions.length;

    final ongoingCount = [
      ...ev1Sessions,
      ...ev2Sessions,
    ].where((session) => session.isOngoing).length;

    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.event_available_rounded,
            label: 'TOTAL SHIFTS',
            value: '$totalShifts',
            color: _navyBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.directions_car_filled_rounded,
            label: 'LIVE NOW',
            value: '$ongoingCount',
            color: ongoingCount > 0 ? _green : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.13)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF718096),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSection({
    required String vehicleId,
    required List<ShiftSession> sessions,
    required Color color,
  }) {
    final isLive = sessions.any((session) => session.isOngoing);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F2C56),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.electric_rickshaw_rounded,
                    color: color,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicleId,
                        style: const TextStyle(
                          color: _navyBlue,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sessions.isEmpty
                            ? 'No shifts recorded'
                            : '${sessions.length} shift${sessions.length == 1 ? '' : 's'} recorded',
                        style: const TextStyle(
                          color: Color(0xFF718096),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(
                  label: isLive ? 'LIVE' : 'OFFLINE',
                  color: isLive ? _green : Colors.grey.shade600,
                  background: isLive
                      ? _green.withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.10),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: const Color(0xFFE8EDF3),
          ),
          if (sessions.isEmpty)
            _buildNoShiftState()
          else
            ...List.generate(
              sessions.length,
              (index) => _buildShiftRow(
                session: sessions[index],
                color: color,
                showDivider: index != sessions.length - 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildNoShiftState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy_rounded,
            color: Colors.grey.shade400,
            size: 19,
          ),
          const SizedBox(width: 8),
          Text(
            'No shift activity for this date',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftRow({
    required ShiftSession session,
    required Color color,
    required bool showDivider,
  }) {
    final localStart = session.startTime.toLocal();
    final localEnd = session.endTime?.toLocal();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: _buildTimeColumn(
                    label: 'STARTED',
                    value: DateFormat('hh:mm a').format(localStart),
                    icon: Icons.login_rounded,
                    color: _navyBlue,
                  ),
                ),
                Container(
                  width: 28,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.grey.shade400,
                    size: 19,
                  ),
                ),
                Expanded(
                  child: _buildTimeColumn(
                    label: session.isOngoing ? 'STATUS' : 'ENDED',
                    value: session.isOngoing
                        ? 'Ongoing'
                        : DateFormat('hh:mm a').format(localEnd!),
                    icon: session.isOngoing
                        ? Icons.radio_button_checked_rounded
                        : Icons.logout_rounded,
                    color: session.isOngoing ? _green : _navyBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: session.isOngoing
                        ? _green.withValues(alpha: 0.10)
                        : color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _formatDuration(session.duration),
                        style: TextStyle(
                          color: session.isOngoing ? _green : color,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'DURATION',
                        style: TextStyle(
                          color: Color(0xFF718096),
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showDivider)
            const Divider(height: 1, color: Color(0xFFE8EDF3)),
        ],
      ),
    );
  }

  Widget _buildTimeColumn({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF718096),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.45,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours == 0) {
      return '${minutes}m';
    }

    if (minutes == 0) {
      return '${hours}h';
    }

    return '${hours}h ${minutes}m';
  }

  Widget _buildFooter() {
    return Center(
      child: Text(
        'Pull down to refresh manually',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.red,
              size: 52,
            ),
            const SizedBox(height: 14),
            const Text(
              'Unable to load shift history',
              style: TextStyle(
                color: _navyBlue,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _startShiftStream,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reconnect'),
            ),
          ],
        ),
      ),
    );
  }
}