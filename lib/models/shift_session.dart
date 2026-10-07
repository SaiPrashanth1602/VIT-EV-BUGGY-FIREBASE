class ShiftSession {
  const ShiftSession({
    required this.vehicleId,
    required this.startTime,
    this.endTime,
  });

  final String vehicleId;
  final DateTime startTime;
  final DateTime? endTime;

  bool get isOngoing => endTime == null;

  Duration get duration {
    final effectiveEndTime = endTime ?? DateTime.now().toUtc();
    return effectiveEndTime.difference(startTime);
  }

  // Groups the shift by the local calendar day of its start time.
  DateTime get localDateKey {
    final localStartTime = startTime.toLocal();

    return DateTime(
      localStartTime.year,
      localStartTime.month,
      localStartTime.day,
    );
  }
}