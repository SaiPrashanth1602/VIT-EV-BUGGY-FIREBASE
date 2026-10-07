import 'package:firebase_database/firebase_database.dart';

import '../models/shift_session.dart';

class _RawShiftEvent {
  const _RawShiftEvent({
    required this.vehicleId,
    required this.status,
    required this.timestamp,
  });

  final String vehicleId;
  final String status;
  final DateTime timestamp;
}

class AdminShiftService {
  AdminShiftService();

  final DatabaseReference _shiftEventsReference = FirebaseDatabase.instance.ref(
    'evShuttle/shiftEvents',
  );

  /// Reads all Firebase shift events and converts them into readable shifts.
  ///
  /// Events are separated by vehicle first, so EV1 can only pair with EV1
  /// and EV2 can only pair with EV2 — even when their Firebase events are
  /// interleaved or stored out of order.
  Future<List<ShiftSession>> fetchAllShiftSessions() async {
    final snapshot = await _shiftEventsReference.get();
    final rawEvents = _parseRawEvents(snapshot.value);

    return _pairEventsByVehicle(rawEvents);
  }

  Stream<List<ShiftSession>> watchAllShiftSessions() {
    return _shiftEventsReference.onValue.map((event) {
      final rawEvents = _parseRawEvents(event.snapshot.value);

      return _pairEventsByVehicle(rawEvents);
    });
  }

  List<_RawShiftEvent> _parseRawEvents(dynamic data) {
    if (data is! Map) {
      return const [];
    }

    final events = <_RawShiftEvent>[];

    for (final entry in data.entries) {
      final rawEvent = entry.value;

      if (rawEvent is! Map) {
        continue;
      }

      final vehicleId = rawEvent['vehicleId']?.toString().trim();
      final status = rawEvent['status']?.toString().trim().toUpperCase();
      final timestampText = rawEvent['timestamp']?.toString().trim();

      if (vehicleId == null ||
          vehicleId.isEmpty ||
          status == null ||
          timestampText == null ||
          timestampText.isEmpty) {
        continue;
      }

      if (status != 'STARTED' && status != 'ENDED') {
        continue;
      }

      final timestamp = DateTime.tryParse(timestampText)?.toUtc();

      if (timestamp == null) {
        continue;
      }

      events.add(
        _RawShiftEvent(
          vehicleId: vehicleId,
          status: status,
          timestamp: timestamp,
        ),
      );
    }

    return events;
  }

  List<ShiftSession> _pairEventsByVehicle(List<_RawShiftEvent> rawEvents) {
    final eventsByVehicle = <String, List<_RawShiftEvent>>{};

    // First separate all mixed Firebase events by EV.
    for (final event in rawEvents) {
      eventsByVehicle.putIfAbsent(event.vehicleId, () => []).add(event);
    }

    final sessions = <ShiftSession>[];

    // Then sort and pair each EV independently.
    for (final entry in eventsByVehicle.entries) {
      final vehicleId = entry.key;
      final vehicleEvents = entry.value
        ..sort((first, second) => first.timestamp.compareTo(second.timestamp));

      DateTime? pendingStartTime;

      for (final event in vehicleEvents) {
        if (event.status == 'STARTED') {
          // If an old STARTED had no ENDED before another STARTED appears,
          // retain it as an incomplete historical record instead of dropping it.
          if (pendingStartTime != null) {
            sessions.add(
              ShiftSession(vehicleId: vehicleId, startTime: pendingStartTime),
            );
          }

          pendingStartTime = event.timestamp;
          continue;
        }

        // Only pair ENDED with the latest unmatched STARTED of THIS vehicle.
        if (event.status == 'ENDED' && pendingStartTime != null) {
          sessions.add(
            ShiftSession(
              vehicleId: vehicleId,
              startTime: pendingStartTime,
              endTime: event.timestamp,
            ),
          );

          pendingStartTime = null;
        }
      }

      // A final unpaired STARTED means that vehicle is currently on shift.
      if (pendingStartTime != null) {
        sessions.add(
          ShiftSession(vehicleId: vehicleId, startTime: pendingStartTime),
        );
      }
    }

    // Newest shift first — makes the UI naturally show today's/latest data at top.
    sessions.sort(
      (first, second) => second.startTime.compareTo(first.startTime),
    );

    return sessions;
  }
}
