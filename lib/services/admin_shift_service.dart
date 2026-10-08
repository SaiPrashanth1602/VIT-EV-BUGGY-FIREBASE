import 'package:firebase_database/firebase_database.dart';

import '../models/shift_session.dart';

/// Stores one raw shift event read from Firebase.
class _RawShiftEvent {
  const _RawShiftEvent({
    required this.vehicleId,
    required this.status,
    required this.timestamp,
  });

  /// EV that created this event, such as EV1 or EV2.
  final String vehicleId;

  /// Shift action saved by the driver: STARTED or ENDED.
  final String status;

  /// Time when the driver started or ended the shift.
  final DateTime timestamp;
}

/// Reads EV shift events from Firebase and turns them into shift sessions.
class AdminShiftService {

  final DatabaseReference _shiftEventsReference = FirebaseDatabase.instance.ref(
    'evShuttle/shiftEvents',
  );

  /// Gets all shift events once and groups them into EV shifts.
  Future<List<ShiftSession>> fetchAllShiftSessions() async {
    final snapshot = await _shiftEventsReference.get();
    final rawEvents = _parseRawEvents(snapshot.value);

    return _pairEventsByVehicle(rawEvents);
  }

  /// Sends updated shift sessions whenever Firebase shift data changes.
  Stream<List<ShiftSession>> watchAllShiftSessions() {
    return _shiftEventsReference.onValue.map((event) {
      final rawEvents = _parseRawEvents(event.snapshot.value);

      return _pairEventsByVehicle(rawEvents);
    });
  }

  // Reads valid STARTED and ENDED events from Firebase data.
  List<_RawShiftEvent> _parseRawEvents(dynamic data) {
    if (data is! Map) {
      // Return no events if Firebase has no shift data.
      return const [];
    }

    final events = <_RawShiftEvent>[];

    for (final entry in data.entries) {
      final rawEvent = entry.value;

      if (rawEvent is! Map) {
        // Skip invalid Firebase entries.
        continue;
      }

      final vehicleId = rawEvent['vehicleId']?.toString().trim();
      final status = rawEvent['status']?.toString().trim().toUpperCase();
      final timestampText = rawEvent['timestamp']?.toString().trim();

      // Skip events missing important shift details.
      if (vehicleId == null ||
          vehicleId.isEmpty ||
          status == null ||
          timestampText == null ||
          timestampText.isEmpty) {
        continue;
      }

      // Only use start and end events.
      if (status != 'STARTED' && status != 'ENDED') {
        continue;
      }

      // Skip events with an invalid date or time.
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

  // Matches each STARTED event with its ENDED event for the same EV.
  List<ShiftSession> _pairEventsByVehicle(List<_RawShiftEvent> rawEvents) {
    final eventsByVehicle = <String, List<_RawShiftEvent>>{};

    // Keep EV1 and EV2 events separate before pairing them.
    for (final event in rawEvents) {
      eventsByVehicle.putIfAbsent(event.vehicleId, () => []).add(event);
    }

    final sessions = <ShiftSession>[];

    // Sort and match shift events for one EV at a time.
    for (final entry in eventsByVehicle.entries) {
      final vehicleId = entry.key;
      final vehicleEvents = entry.value
        ..sort((first, second) => first.timestamp.compareTo(second.timestamp));

      // Holds a start time until a matching end event is found.
      DateTime? pendingStartTime;

      for (final event in vehicleEvents) {
        if (event.status == 'STARTED') {
          // Start a new shift. Keep an older unfinished start if one exists.
          if (pendingStartTime != null) {
            sessions.add(
              ShiftSession(vehicleId: vehicleId, startTime: pendingStartTime),
            );
          }

          pendingStartTime = event.timestamp;
          continue;
        }

        // End only the latest unfinished shift for this same EV.
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

      // No end event means this EV may still be on shift.
      if (pendingStartTime != null) {
        sessions.add(
          ShiftSession(vehicleId: vehicleId, startTime: pendingStartTime),
        );
      }
    }

    // Show newest shifts first in the Admin screen.
    sessions.sort(
      (first, second) => second.startTime.compareTo(first.startTime),
    );

    return sessions;
  }
}
