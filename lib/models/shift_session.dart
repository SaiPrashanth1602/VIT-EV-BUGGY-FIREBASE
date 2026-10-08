/// Stores one EV shift with its start time and optional end time.
class ShiftSession {
  const ShiftSession({
    required this.vehicleId,
    required this.startTime,
    this.endTime,
  });

  /// ID of the EV that completed this shift, such as EV1 or EV2.
  final String vehicleId;

  /// Time when the driver started the shift.
  final DateTime startTime;

  /// Time when the driver ended the shift.
  /// This stays null while the shift is still running.
  final DateTime? endTime;

  /// True when the shift has started but has not ended yet.
  bool get isOngoing => endTime == null;

  /// Calculates total shift time.
  /// Uses the current UTC time while the shift is still running.
  Duration get duration {
    final effectiveEndTime = endTime ?? DateTime.now().toUtc();
    return effectiveEndTime.difference(startTime);
  }

  /// Returns the local calendar date used to group shifts by day.
  DateTime get localDateKey {
    final localStartTime = startTime.toLocal();

    return DateTime(
      localStartTime.year,
      localStartTime.month,
      localStartTime.day,
    );
  }
}