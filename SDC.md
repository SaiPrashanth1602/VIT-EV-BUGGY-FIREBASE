# VIT EV BUGGY — Software Development & System Documentation

> **Purpose:** Technical handover and developer reference for the VIT EV Buggy system.  
> This document is intentionally more detailed than a normal README. It explains the three Git branches, application responsibilities, project structure, Firebase communication, important files, core logic, configuration points, data flow, and maintenance considerations.

---

## Table of Contents

1. [System at a Glance](#1-system-at-a-glance)
2. [Git Branch Architecture](#2-git-branch-architecture)
3. [How the Three Applications Work Together](#3-how-the-three-applications-work-together)
4. [Technology Stack](#4-technology-stack)
5. [Firebase Architecture](#5-firebase-architecture)
6. [Driver Branch](#6-driver-branch)
7. [Faculty Branch](#7-faculty-branch)
8. [Admin Branch](#8-admin-branch)
9. [Core System Logic](#9-core-system-logic)
10. [APIs, Services & External Integrations](#10-apis-services--external-integrations)
11. [Configuration & Developer Touchpoints](#11-configuration--developer-touchpoints)
12. [Application Data Flow](#12-application-data-flow)
13. [Testing & Validation](#13-testing--validation)
14. [Troubleshooting Guide](#14-troubleshooting-guide)
15. [Safe Modification Guide](#15-safe-modification-guide)
16. [Developer Handover Notes](#16-developer-handover-notes)

---

# 1. System at a Glance

## 1.1 What is VIT EV Buggy?

VIT EV Buggy is a real-time campus shuttle tracking system designed around three separate Flutter applications:

| Application | Git Branch | Primary User | Main Responsibility |
|---|---|---|---|
| Driver App | `driver` | EV Driver | Start/end shifts and publish live EV location |
| Faculty App | `faculty` | Faculty / Passenger | Track EVs, routes, pickup points, ETA and notifications |
| Admin App | `admin` | VIT / System Admin | Monitor EV shift history and live shift status |

The three applications are developed independently but communicate through the **same Firebase project and Realtime Database**.

---

## 1.2 High-Level Architecture

```text
                         VIT EV BUGGY SYSTEM
                                  │
                                  ▼
                         ┌─────────────────┐
                         │     FIREBASE    │
                         │ Realtime DB     │
                         └────────┬────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              │                   │                   │
              ▼                   ▼                   ▼
        ┌───────────┐       ┌───────────┐       ┌───────────┐
        │  DRIVER   │       │  FACULTY  │       │   ADMIN   │
        │    APP    │       │    APP    │       │    APP    │
        └─────┬─────┘       └─────▲─────┘       └─────▲─────┘
              │                   │                   │
              │ GPS               │ Live EV data     │ Shift events
              │ + shifts          │ + route logic    │ + history
              └───────────────────┴───────────────────┘
```

### Main communication paths

```text
DRIVER
  │
  ├── Live vehicle location ─────► Firebase ─────► FACULTY
  │
  ├── STARTED shift event ───────► Firebase ─────► ADMIN
  │
  └── ENDED shift event ─────────► Firebase ─────► ADMIN
```

The Driver application is primarily a **producer** of live operational data.

The Faculty application is primarily a **consumer and interpretation layer** for live vehicle data.

The Admin application is primarily a **consumer and processing layer** for shift-event data.

---

# 2. Git Branch Architecture

The project is divided into three Git branches.

## 2.1 `driver`

Contains the Driver Flutter application.

### Responsibilities

- Driver shift management
- EV selection
- EV allocation
- GPS tracking
- Live location publishing
- Shift restoration
- Network state handling
- Manual shift termination
- Automatic 30-minute shift termination
- Firebase shift events

The Driver branch should be treated as the source of live operational vehicle data.

---

## 2.2 `faculty`

Contains the Faculty Flutter application.

### Responsibilities

- Displaying EV1 and EV2
- Reading live EV locations from Firebase
- Route progression
- Pickup-point detection
- Faculty block detection
- ETA calculation
- Green/yellow stop states
- Skipped-stop handling
- EV arrival notifications
- Faculty device location

The Faculty branch does **not** start or control driver shifts.

---

## 2.3 `admin`

Contains the separate Admin Flutter application.

### Responsibilities

- Daily shift monitoring
- Historical shift viewing
- EV1/EV2 separation
- STARTED → ENDED event pairing
- Ongoing shift detection
- Duration calculation
- Date filtering
- Live Firebase updates
- Dashboard summaries

The Admin application is independent from the Driver and Faculty UI code.

Its purpose is to monitor the operational records already produced by the Driver application.

---

## 2.4 Why Separate Branches?

The three branches allow each application to be developed independently.

```text
driver
   │
   └── Driver-specific development

faculty
   │
   └── Faculty-specific development

admin
   │
   └── Admin-specific development
```

The Admin application was introduced as a separate branch so that the existing Driver and Faculty implementations remain isolated and unaffected.

---

# 3. How the Three Applications Work Together

## 3.1 Driver → Firebase → Faculty

The Driver application obtains the EV's GPS position.

```text
Driver starts shift
       ↓
EV selected
       ↓
GPS tracking starts
       ↓
LocationService
       ↓
Firebase Realtime Database
       ↓
vehicles / EV1 or EV2
       ↓
Faculty Firebase listener
       ↓
EV location displayed
```

The Faculty application then interprets that location according to its route and pickup logic.

---

## 3.2 Driver → Firebase → Admin

The Driver application creates shift events.

```text
Driver taps START SHIFT
        ↓
Firebase shiftEvents
        ↓
STARTED event
        ↓
Admin realtime listener
        ↓
Admin shows EV as LIVE / Ongoing
```

When the driver ends the shift:

```text
Driver taps END SHIFT
        ↓
Firebase shiftEvents
        ↓
ENDED event
        ↓
Admin receives update
        ↓
STARTED + ENDED paired
        ↓
Completed session displayed
```

---

## 3.3 Important Architectural Principle

The Admin application does not need to know how GPS tracking works.

The Faculty application does not need to know how shift pairing works.

The Driver application does not need to know how the Faculty UI displays route progress.

Each application has a focused responsibility, while Firebase provides the shared communication layer.

---

# 4. Technology Stack

## Common

- Flutter
- Dart
- Firebase
- Firebase Realtime Database

## Driver

- Flutter
- Dart
- Firebase Realtime Database
- Device GPS/location services

## Faculty

- Flutter
- Dart
- Firebase Realtime Database
- `flutter_map`
- OpenStreetMap
- Geolocation services
- Local notifications

## Admin

- Flutter
- Dart
- Firebase Realtime Database

---

# 5. Firebase Architecture

## 5.1 Shared Firebase Project

The three applications connect to the same Firebase backend.

This is important because the applications are separate Flutter projects/branches but must observe the same operational data.

---

## 5.2 Main Realtime Database Area

The system uses the `evShuttle` database area.

The important operational sections are:

```text
evShuttle/
│
├── vehicles/
│   ├── EV1/
│   └── EV2/
│
└── shiftEvents/
    ├── <event-id>/
    ├── <event-id>/
    └── ...
```

---

## 5.3 `vehicles`

The Driver application updates the active EV's state and location.

The Faculty application listens to the vehicle data to obtain live EV information.

Only:

```text
EV1
EV2
```

are part of the current system.

---

## 5.4 `shiftEvents`

The Driver application records shift actions.

A shift event contains:

| Field | Meaning |
|---|---|
| `vehicleId` | EV that generated the event |
| `status` | `STARTED` or `ENDED` |
| `timestamp` | Exact time of the event |

Example:

```text
shiftEvents/
  -P39zDMLX2nKLHwqY1xB/
      status: STARTED
      timestamp: 2026-10-05T07:35:08.359438Z
      vehicleId: EV2

  -P39zEj2cDTS9UJbGUXG/
      status: ENDED
      timestamp: 2026-10-05T07:35:13.926406Z
      vehicleId: EV2
```

---

## 5.5 Why `shiftEvents` Is Event-Based

A shift is not stored as one pre-built session.

Instead, the Driver application produces events:

```text
STARTED
ENDED
```

The Admin application converts those raw events into readable sessions.

Example:

```text
Raw Firebase events

EV1 STARTED — 08:00
EV1 ENDED   — 09:15
```

becomes:

```text
EV1
Start:    08:00 AM
End:      09:15 AM
Duration: 1h 15m
Status:   Completed
```

This separation keeps the Driver data simple while allowing the Admin application to perform reporting and analysis.

---

# 6. Driver Branch

## 6.1 Driver Application Purpose

The Driver application is responsible for operating an EV tracking session.

The driver can:

1. Select EV1 or EV2.
2. Start a shift.
3. Begin live location tracking.
4. Continue publishing location during the shift.
5. Restore an existing active shift after reopening the app.
6. End the shift manually.
7. Have the shift automatically end after 30 minutes.

---

## 6.2 Main Driver Screen

### `DriverHomeScreen`

The main Driver UI is responsible for:

- Driver welcome screen
- Current date/time
- EV selection
- Start Shift button
- Active shift display
- End Shift button
- Network status
- Shift restoration
- User-facing status messages

The screen delegates Firebase and GPS operations to `LocationService`.

---

## 6.3 `location_service.dart`

This is the main Driver-side operational service.

It is responsible for the integration layer between the Driver application and the backend/device services.

### Responsibilities

- Firebase Realtime Database communication
- EV allocation
- EV1 / EV2 validation
- GPS tracking
- Live location publishing
- Shift creation
- Shift restoration
- Shift termination
- Heartbeat/update state
- Connection state
- 30-minute shift expiry
- Vehicle release
- Shift event creation

### Conceptual flow

```text
DriverHomeScreen
       │
       ▼
LocationService
       │
       ├──────────────► Device GPS
       │
       └──────────────► Firebase Realtime Database
```

Keeping this logic in a service prevents the UI from directly managing Firebase operations.

---

## 6.4 Driver Shift Lifecycle

```text
                 ┌───────────────┐
                 │  NO ACTIVE    │
                 │     SHIFT     │
                 └───────┬───────┘
                         │
                    START SHIFT
                         │
                         ▼
                 ┌───────────────┐
                 │    ACTIVE     │
                 │     SHIFT     │
                 └───────┬───────┘
                         │
              ┌──────────┴──────────┐
              │                     │
          END SHIFT             30 MINUTES
              │                     │
              └──────────┬──────────┘
                         ▼
                 ┌───────────────┐
                 │     ENDED     │
                 └───────────────┘
```

---

## 6.5 Driver Firebase Data Flow

When a shift starts:

```text
START SHIFT
    ↓
Vehicle claim
    ↓
Firebase vehicle state
    ↓
STARTED shift event
    ↓
GPS tracking begins
```

During the shift:

```text
GPS
 ↓
LocationService
 ↓
Firebase vehicles/EVx
```

When the shift ends:

```text
END SHIFT
    ↓
Firebase shift state updated
    ↓
ENDED shift event
    ↓
Vehicle released
    ↓
GPS tracking stopped
```

---

# 7. Faculty Branch

## 7.1 Faculty Application Purpose

The Faculty application converts live EV data into a useful passenger-facing tracking experience.

It provides:

- Live EV1 / EV2 positions
- Route progress
- Pickup-point detection
- Current/next stop
- ETA
- Stop status
- Skipped-stop handling
- Faculty block detection
- EV arrival notifications
- Campus map visualization

---

## 7.2 Main Faculty Screen

### `faculty_home_screen.dart`

This is the primary Faculty UI and route-management layer.

It coordinates:

- EV display
- Campus blocks
- Route sequences
- Current/next stop
- Pickup status
- ETA
- Notification triggers
- Faculty-selected/current block
- Metro-style route presentation

---

## 7.3 `ev_api_provider.dart`

This is the Faculty-side Firebase EV data provider.

### Main responsibility

Read live EV data from:

```text
evShuttle/
    vehicles/
```

and convert Firebase records into application-level EV location information.

The provider handles the Firebase listener used by the Faculty application.

---

## 7.4 `ev_location_provider.dart`

Provides the EV location state to the Faculty UI and coordinates access to the current EV data.

---

## 7.5 `ev_tracking_service.dart`

This is the core geographic/route utility layer.

It contains important campus coordinates and geographic operations such as:

- Pickup coordinates
- Campus block coordinates
- EV proximity checks
- Faculty block identification
- Pickup-point checks
- Geographic distance calculations

---

## 7.6 `faculty_location_service.dart`

This service handles the **Faculty device's own location**.

This is different from the EV location.

```text
EV LOCATION
    ↓
Driver GPS
    ↓
Firebase
    ↓
Faculty EV provider

FACULTY LOCATION
    ↓
Faculty device GPS
    ↓
Faculty application
```

---

## 7.7 `notification_service.dart`

Responsible for local EV arrival notifications.

When the Faculty application determines that an EV has reached the relevant pickup point, it can notify the faculty member.

---

# 8. Admin Branch

## 8.1 Admin Application Purpose

The Admin application is a dedicated monitoring dashboard for EV1 and EV2 shift activity.

It answers:

- When did EV1 start?
- When did EV1 end?
- How long was EV1 active?
- Is EV1 currently active?
- What were EV2's shifts on a previous date?
- How many shifts occurred on a selected day?

---

## 8.2 Admin Project Structure

```text
vit_ev_buggy_admin/
│
├── android/
├── ios/
├── lib/
│   ├── main.dart
│   │
│   ├── models/
│   │   └── shift_session.dart
│   │
│   ├── services/
│   │   └── admin_shift_service.dart
│   │
│   └── screens/
│       └── admin/
│           └── admin_home_screen.dart
│
├── pubspec.yaml
└── ...
```

---

## 8.3 `main.dart`

Entry point of the Admin application.

Responsibilities:

1. Initialize Firebase.
2. Start the Flutter application.
3. Open the Admin dashboard.

```text
Firebase initialization
        ↓
Flutter application
        ↓
Admin dashboard
```

---

## 8.4 `shift_session.dart`

Defines the processed model representing one readable shift session.

A session contains information such as:

- Vehicle ID
- Start time
- End time
- Duration
- Ongoing/completed state

Example:

```text
Vehicle: EV2
Start: 10:30 AM
End: 11:15 AM
Duration: 45 minutes
Status: Completed
```

An ongoing shift is represented without an END event:

```text
Vehicle: EV1
Start: 02:20 PM
End: Ongoing
Status: Live
```

---

## 8.5 `admin_shift_service.dart`

This is the primary Admin Firebase/data-processing service.

It:

- Reads `evShuttle/shiftEvents`
- Listens for realtime Firebase updates
- Separates EV1 and EV2 events
- Sorts events using their actual timestamps
- Pairs STARTED → ENDED events
- Detects ongoing shifts
- Calculates duration
- Supports date-based session processing

It supports both:

```text
fetchAllShiftSessions()
```

for manual retrieval and:

```text
watchAllShiftSessions()
```

for realtime updates.

---

## 8.6 `admin_home_screen.dart`

The Admin dashboard displays:

- Selected date
- EV1 section
- EV2 section
- Number of shifts
- Live/offline state
- Start time
- End time
- Duration
- Ongoing state
- Total shifts
- Live now count

Manual refresh and pull-to-refresh can remain available as backup controls even though realtime updates are supported.

---

# 9. Core System Logic

> **This section contains the system's important operational logic in one place.**
>
> The purpose is to make the behaviour of the system understandable without having to search through individual files.

---

## 9.1 Supported Vehicles

The current system supports exactly:

```text
EV1
EV2
```

The Driver, Faculty and Admin applications are designed around these two vehicles.

Adding another EV is **not simply a UI change**. It requires checking:

- Driver vehicle allocation
- Firebase vehicle structure
- Faculty tracking
- Faculty route definitions
- Admin filtering/processing
- Any EV-specific configuration

---

## 9.2 Driver Shift Duration

Maximum driver shift duration:

```text
30 minutes
```

The Driver application automatically ends an active shift after the configured duration.

The automatic end must result in the same operational cleanup as a normal shift end:

```text
30 minutes reached
      ↓
Shift ends
      ↓
Firebase state updated
      ↓
ENDED event recorded
      ↓
Vehicle released
      ↓
Tracking stopped
```

---

## 9.3 EV Allocation

When a driver selects an EV:

```text
EV1 or EV2
    ↓
LocationService
    ↓
Firebase vehicle state
    ↓
Vehicle claimed
```

The allocation logic prevents multiple drivers from simultaneously treating the same vehicle as their active tracking vehicle.

---

## 9.4 Live GPS Tracking

The Driver application obtains the driver's/device location while the shift is active.

The location service publishes the active EV's location to Firebase.

```text
Driver device GPS
       ↓
LocationService
       ↓
Firebase vehicles/EVx
       ↓
Faculty listener
       ↓
Live EV marker
```

---

## 9.5 Network Handling

The Driver application monitors network connection state.

If the network is lost during an active shift:

```text
Network lost
    ↓
Driver UI shows connection warning
    ↓
Tracking attempts continue according to the
location service behaviour
    ↓
Network restored
    ↓
Tracking resumes
```

The UI does not automatically treat a temporary network loss as the end of the driver's shift.

---

## 9.6 Shift Restoration

When the Driver application is reopened, it checks Firebase for an existing active shift.

```text
App reopened
    ↓
Firebase active-shift lookup
    ↓
Active vehicle found?
    │
 ┌──┴──┐
YES    NO
 │      │
 ▼      ▼
Restore  Normal
tracking start screen
```

This prevents the UI from incorrectly showing a fresh shift when Firebase already contains an active shift.

---

## 9.7 Campus Pickup Points

The Faculty application uses dedicated pickup coordinates.

Current pickup points are:

```text
AB1
AB3
AB2, AB4
MAB3, MAB4
AB5
```

The combined stops are logical route stops even though some physical campus blocks remain separately represented on the map.

---

## 9.8 EV Pickup Trigger Radius

The EV pickup trigger radius is:

```text
35 metres
```

The system checks the EV's geographic distance from the relevant pickup point.

Conceptually:

```text
Distance <= 35m
       ↓
EV is considered at pickup
```

This radius is used for pickup-state transitions and arrival detection.

---

## 9.9 MAB3 / MAB4 Shared Pickup

MAB3 and MAB4 are treated as one logical pickup stop:

```text
MAB3, MAB4
```

There is one common pickup point for route logic.

However, MAB3 and MAB4 remain separately represented as physical campus/map blocks.

This distinction is important:

```text
Physical map representation:
MAB3
MAB4

Logical route/pickup representation:
MAB3, MAB4
```

---

## 9.10 AB2 / AB4 Combined Stop

AB2 and AB4 are also represented as a combined logical shuttle stop:

```text
AB2, AB4
```

The Faculty application can still represent AB2 and AB4 individually as campus blocks while treating their shared shuttle point as one route stop.

---

## 9.11 Green Pickup State

When the EV enters the relevant pickup radius:

```text
EV enters pickup radius
        ↓
Pickup reached
        ↓
Stop = GREEN
```

Green indicates that the EV has physically reached the pickup area.

---

## 9.12 Green → Yellow Departure Logic

When an EV leaves the pickup point:

```text
EV leaves pickup radius
        ↓
3-second grace period
        ↓
Is EV still outside?
        │
     ┌──┴──┐
    NO     YES
     │       │
     ▼       ▼
 Remain    YELLOW
 GREEN
```

The 3-second grace period prevents an EV from immediately switching to yellow because of small GPS movement/noise around the pickup boundary.

---

## 9.13 Current Stop Display

The Faculty UI should show the current stop only when the EV is physically inside a pickup point.

If the EV is not physically inside any pickup point:

```text
Current: -
```

This prevents the route index alone from being interpreted as physical arrival.

---

## 9.14 Skipped Stops

The system tracks ordered route progression.

If an EV passes a stop without entering its pickup radius and later reaches a subsequent stop:

```text
Stop A
  ↓
Stop B skipped
  ↓
Stop C reached
```

The result is:

```text
Stop B → YELLOW
Stop C → GREEN
```

The skip logic is generic route-progression behaviour.

MAB3/MAB4 are treated specially only because they share a logical pickup coordinate.

---

## 9.15 EV1 Route

Current EV1 route sequence:

```text
AB1
 ↓
AB3
 ↓
AB2, AB4 Junction
 ↓
MAB3, MAB4
 ↓
AB2, AB4 Junction
 ↓
AB3
 ↓
AB1
```

This is a route sequence, not simply a list of nearest geographical points.

The repeated stops represent the vehicle's return journey.

---

## 9.16 EV2 Route

Current EV2 route sequence:

```text
AB3
 ↓
AB2, AB4 Junction
 ↓
MAB3, MAB4
 ↓
AB5
 ↓
MAB3, MAB4
 ↓
AB2, AB4 Junction
 ↓
AB3
```

---

## 9.17 Route Progression

The Faculty application tracks route occurrences rather than treating a stop as globally visited.

This matters because the same physical/logical stop can appear more than once in a route.

For example:

```text
EV1

AB2, AB4
   ↓
MAB3, MAB4
   ↓
AB2, AB4
```

The two AB2/AB4 appearances are different route occurrences.

---

## 9.18 ETA Logic

ETA is calculated relative to the faculty's relevant/current campus block and the EV's route.

Conceptually:

```text
Faculty target block
       ↓
Find target occurrence on EV route
       ↓
Determine forward route distance
       ↓
Estimate travel time using EV speed
       ↓
ETA
```

The intended behaviour is **route-based**, rather than simply using a straight-line distance from the EV to the faculty.

The system uses recent/rolling EV speed information rather than relying solely on one instantaneous speed reading.

---

## 9.19 Faculty Block Detection

The Faculty application determines the relevant campus block using geographic coordinates and configured campus locations.

Special combined-block handling exists for:

```text
AB2 / AB4
MAB3 / MAB4
```

The shared pickup logic and individual physical block representation are intentionally separate.

---

## 9.20 EV Arrival Notification

When the EV reaches the relevant pickup point for the faculty's block:

```text
EV location
    ↓
Pickup detection
    ↓
Faculty block match
    ↓
Arrival condition satisfied
    ↓
Local notification
```

The notification service provides an EV arrival notification to the faculty user.

---

## 9.21 Admin Shift Event Pairing

Firebase contains one mixed stream of shift events.

Example:

```text
EV1 STARTED — 08:00
EV2 STARTED — 08:05
EV1 ENDED   — 09:00
EV2 ENDED   — 09:10
EV1 STARTED — 11:00
```

The Admin application must **not** pair records simply according to Firebase event order.

Instead:

```text
1. Read all events
2. Separate events by vehicle
3. Sort each vehicle's events by timestamp
4. Pair STARTED → ENDED within that vehicle
5. Treat unmatched STARTED as ongoing
```

Result:

```text
EV1
08:00 → 09:00
11:00 → Ongoing

EV2
08:05 → 09:10
```

This prevents incorrect pairings such as:

```text
EV1 STARTED → EV2 ENDED
```

---

## 9.22 Ongoing Shift Detection

If a `STARTED` event does not yet have a corresponding `ENDED` event for the same vehicle:

```text
STARTED
   ↓
No matching END
   ↓
Ongoing / LIVE
```

The Admin dashboard can display the shift as active.

---

## 9.23 Shift Duration Calculation

Completed:

```text
Duration = End Timestamp - Start Timestamp
```

Ongoing:

```text
Duration = Current Time - Start Timestamp
```

The final duration becomes fixed once an END event is received.

---

## 9.24 Admin Date Filtering

The Admin dashboard can select a date.

The application filters processed sessions for the selected date and presents EV1 and EV2 separately.

This allows both:

```text
Today's monitoring
```

and:

```text
Historical shift review
```

---

# 10. APIs, Services & External Integrations

## 10.1 Firebase Realtime Database

Firebase is the primary backend synchronization layer.

Used for:

- Active vehicle information
- Live EV location
- Vehicle status
- Driver shift state
- Shift events
- Driver ↔ Faculty communication
- Driver ↔ Admin communication

The applications do not require a separate custom REST backend for the core EV tracking workflow.

---

## 10.2 Device Location / GPS

The Driver application uses device location services to publish the EV's live position.

The Faculty application separately uses device location services to determine the faculty user's current campus block.

These are two different location streams.

---

## 10.3 OpenStreetMap / Flutter Map

The Faculty application uses OpenStreetMap-based map rendering through the Flutter map stack for campus visualization.

No Google Maps billing/API dependency is required for the core Faculty map.

---

## 10.4 Local Notifications

The Faculty application uses local notification functionality for EV arrival alerts.

---

## 10.5 Firebase Authentication

Authentication should only be considered an extension point unless the submitted application has an active authentication implementation.

The current Driver UI contains a display-level driver name value and is not itself the authentication layer.

---

# 11. Configuration & Developer Touchpoints

> **This is the section developers should check first when adapting the project to another environment.**

## 11.1 Firebase Configuration

Each Flutter application that connects to Firebase requires its corresponding Firebase configuration.

Typical Android Firebase configuration includes:

```text
android/app/google-services.json
```

The Admin application is registered separately as its own Android application in the same Firebase project.

---

## 11.2 Firebase Project

The applications must point to the same intended Firebase project.

The Admin application was configured against:

```text
vit-ev-buggy-demo
```

This allows it to read the same Realtime Database used by Driver and Faculty.

---

## 11.3 EV IDs

Current supported EV IDs:

```text
EV1
EV2
```

These IDs must remain consistent across:

- Driver allocation
- Firebase vehicle records
- Faculty tracking
- Admin shift processing

---

## 11.4 Shift Duration

Current operational limit:

```text
30 minutes
```

This is a system behaviour setting and should not be changed casually.

---

## 11.5 Pickup Radius

Current EV pickup trigger:

```text
35 metres
```

Changing this affects:

- Arrival detection
- Green state
- Yellow transition
- Current stop display
- Notification triggering
- Skip-stop behaviour

Therefore it should be changed only after testing the full Faculty workflow.

---

## 11.6 Route Configuration

The EV route sequences are part of the Faculty application's route logic.

Changing a route can affect:

- Stop progression
- Skip detection
- Current/next stop
- ETA
- Repeated route occurrences

A route modification should therefore be tested with real or simulated EV movement.

---

## 11.7 Campus Coordinates

The Faculty application contains configured coordinates for:

- Campus blocks
- Pickup points
- Combined stops

Changing coordinates can affect geographic detection throughout the Faculty app.

---

# 12. Application Data Flow

## 12.1 Live Vehicle Location

```text
┌───────────────┐
│ Driver Device │
│     GPS       │
└───────┬───────┘
        │
        ▼
┌──────────────────┐
│ LocationService  │
└────────┬─────────┘
         │
         ▼
┌──────────────────────────┐
│ Firebase Realtime DB     │
│ evShuttle/vehicles/EVx   │
└────────────┬─────────────┘
             │
             ▼
┌────────────────────┐
│ ev_api_provider    │
└─────────┬──────────┘
          │
          ▼
┌───────────────────────┐
│ Faculty Tracking      │
│ Route / Pickup / ETA  │
└──────────┬────────────┘
           │
           ▼
      Faculty UI
```

---

## 12.2 Shift Monitoring

```text
Driver
  │
  │ START / END
  ▼
LocationService
  │
  ▼
Firebase
  │
  ▼
evShuttle/shiftEvents
  │
  ▼
AdminShiftService
  │
  ├── Separate EV1 / EV2
  ├── Sort timestamps
  ├── Pair STARTED → ENDED
  ├── Detect ongoing
  └── Calculate duration
  │
  ▼
ShiftSession
  │
  ▼
Admin Dashboard
```

---

## 12.3 Faculty Arrival Flow

```text
EV location
    ↓
Distance calculation
    ↓
Relevant pickup point?
    ↓
Within 35m?
    ↓
Pickup reached
    ↓
Route state updated
    ↓
Faculty block match
    ↓
Notification
```

---

# 13. Testing & Validation

The following behaviours form the main operational validation checklist.

## Driver

- [ ] EV1 can be selected.
- [ ] EV2 can be selected.
- [ ] Shift starts successfully.
- [ ] EV becomes active in Firebase.
- [ ] GPS location updates are published.
- [ ] Existing active shift can be restored.
- [ ] Manual END SHIFT works.
- [ ] 30-minute automatic shift termination works.
- [ ] Vehicle is released after shift termination.
- [ ] Network loss is reflected in the UI.
- [ ] Tracking resumes after network recovery.

## Faculty

- [ ] EV1 appears on the map.
- [ ] EV2 appears on the map.
- [ ] Firebase location changes are reflected.
- [ ] Pickup detection works.
- [ ] 35m trigger radius works.
- [ ] Green state appears on arrival.
- [ ] Green state remains for the configured departure grace period.
- [ ] Stop changes to yellow after departure.
- [ ] Skipped stops become yellow.
- [ ] Later reached stops become green.
- [ ] Current shows `-` when EV is not inside a pickup point.
- [ ] AB2/AB4 combined stop works.
- [ ] MAB3/MAB4 combined stop works.
- [ ] ETA follows route progression.
- [ ] Arrival notification works.
- [ ] Faculty block detection works.

## Admin

- [ ] Firebase connection works.
- [ ] Shift events are retrieved.
- [ ] Realtime shift updates work.
- [ ] EV1 events remain separate from EV2.
- [ ] EV2 events remain separate from EV1.
- [ ] STARTED → ENDED pairing is correct.
- [ ] Unmatched STARTED events show as ongoing.
- [ ] Duration is calculated correctly.
- [ ] Date filtering works.
- [ ] Total shift count is correct.
- [ ] Live shift count is correct.
- [ ] Manual refresh works.

---

# 14. Troubleshooting Guide

## 14.1 Driver Location Not Appearing in Faculty

Check in this order:

```text
1. Is the Driver shift active?
2. Is EV1 or EV2 selected correctly?
3. Is Firebase receiving vehicle data?
4. Is the vehicle ID correct?
5. Is the Faculty Firebase listener active?
6. Is the device connected to the network?
7. Is the Driver device location permission enabled?
```

---

## 14.2 Faculty Shows the Wrong Stop

Check:

```text
1. EV GPS position
2. Pickup coordinates
3. 35m pickup radius
4. Current route occurrence
5. Route order
6. Shared-stop configuration
```

Remember that repeated stops can occur at different positions in a route.

---

## 14.3 Stop Does Not Become Yellow

Check:

```text
1. EV actually left the pickup radius.
2. Departure grace period completed.
3. Firebase location updates are still arriving.
4. Route state is progressing correctly.
```

The system intentionally does not switch to yellow immediately when the EV crosses the boundary.

---

## 14.4 Admin Does Not Show a Shift

Check:

```text
1. evShuttle/shiftEvents exists.
2. Event contains vehicleId.
3. vehicleId is EV1 or EV2.
4. status is STARTED or ENDED.
5. timestamp is valid.
6. Admin Firebase configuration points to the same project.
```

---

## 14.5 Admin Pairs a Shift Incorrectly

The first thing to verify is that the service is grouping events by:

```text
vehicleId
```

before pairing.

Events must never be paired solely according to their global Firebase order.

---

# 15. Safe Modification Guide

## 15.1 General Rule

> **The existing operational logic has been tested as an integrated Driver → Firebase → Faculty/Admin workflow. Avoid refactoring working logic unless there is a clear requirement and the complete workflow can be retested.**

---

## 15.2 If You Need to Change Driver UI

Primary location:

```text
DriverHomeScreen
```

UI changes should not move Firebase operations into the screen.

Keep backend/location behaviour inside:

```text
LocationService
```

---

## 15.3 If You Need to Change Firebase or GPS Behaviour

Primary location:

```text
location_service.dart
```

Test:

```text
Driver → Firebase → Faculty
Driver → Firebase → Admin
```

after the change.

---

## 15.4 If You Need to Change Faculty EV Data Reading

Primary file:

```text
ev_api_provider.dart
```

Check Firebase vehicle data parsing and the Faculty-side state flow.

---

## 15.5 If You Need to Change Route or Geographic Behaviour

Primary areas:

```text
faculty_home_screen.dart
ev_tracking_service.dart
```

Test:

- route progression
- pickup detection
- skipped stops
- green/yellow states
- ETA
- notifications

---

## 15.6 If You Need to Change Faculty Device Location

Primary file:

```text
faculty_location_service.dart
```

This affects faculty block detection and therefore can affect pickup/ETA behaviour.

---

## 15.7 If You Need to Change Notifications

Primary file:

```text
notification_service.dart
```

Test the complete arrival condition, not just notification rendering.

---

## 15.8 If You Need to Change Admin Data Processing

Primary file:

```text
admin_shift_service.dart
```

This is where Firebase shift events become readable shift sessions.

After changing it, verify:

```text
EV1 pairing
EV2 pairing
Ongoing shifts
Duration
Date filtering
Realtime updates
```

---

## 15.9 If You Need to Change Admin UI

Primary file:

```text
admin_home_screen.dart
```

The UI should consume the processed shift-session data rather than implementing Firebase pairing logic itself.

---

# 16. Developer Handover Notes

## 16.1 Most Important Files

| Application | File | Role |
|---|---|---|
| Driver | `DriverHomeScreen` | Driver UI and shift controls |
| Driver | `location_service.dart` | Firebase, GPS, allocation and shift lifecycle |
| Faculty | `faculty_home_screen.dart` | Main Faculty UI and route behaviour |
| Faculty | `ev_api_provider.dart` | Firebase EV location data |
| Faculty | `ev_location_provider.dart` | EV location state |
| Faculty | `ev_tracking_service.dart` | Geographic and pickup logic |
| Faculty | `faculty_location_service.dart` | Faculty device location |
| Faculty | `notification_service.dart` | EV arrival notifications |
| Admin | `main.dart` | Admin app entry point |
| Admin | `shift_session.dart` | Processed shift model |
| Admin | `admin_shift_service.dart` | Firebase event processing |
| Admin | `admin_home_screen.dart` | Admin dashboard |

---

## 16.2 Critical Operational Values

| Item | Current Value |
|---|---|
| Supported EVs | EV1, EV2 |
| Driver shift limit | 30 minutes |
| EV pickup trigger radius | 35 metres |
| Logical combined stop | AB2, AB4 |
| Logical combined stop | MAB3, MAB4 |
| EV1 route | AB1 → AB3 → AB2/AB4 → MAB3/MAB4 → AB2/AB4 → AB3 → AB1 |
| EV2 route | AB3 → AB2/AB4 → MAB3/MAB4 → AB5 → MAB3/MAB4 → AB2/AB4 → AB3 |
| Admin event types | STARTED, ENDED |

---

## 16.3 Key Design Decisions

### Shared Firebase backend

The three applications use a shared Firebase backend so that operational information is synchronized in realtime.

### Separate applications

Driver, Faculty and Admin have different responsibilities and are kept as separate branches.

### EV1 / EV2 only

The current operational deployment is intentionally limited to two EVs.

### Route-based tracking

Faculty route state is based on ordered route progression rather than only nearest-point calculations.

### Shared logical pickup points

AB2/AB4 and MAB3/MAB4 are represented as combined logical shuttle stops while maintaining individual physical campus blocks.

### Event-based admin records

The Admin app reconstructs readable sessions from raw STARTED and ENDED events instead of requiring the Driver app to create a separate reporting record.

### Realtime monitoring

The Admin application listens to Firebase changes so that shift status can update without requiring constant manual refresh.

---

## 16.4 Important Maintenance Principle

Changes to one application can affect another application because they share Firebase data.

For example:

```text
Changing Driver Firebase vehicle structure
              ↓
May break Faculty EV parsing
              ↓
May also affect Admin monitoring
```

Similarly:

```text
Changing EV IDs
      ↓
Driver allocation
      ↓
Faculty tracking
      ↓
Admin filtering
```

Therefore, backend/data-structure changes should always be tested across all three applications.

---

# Final System Summary

```text
                         VIT EV BUGGY
                              │
                              ▼
                     ┌─────────────────┐
                     │     FIREBASE    │
                     │ Realtime DB     │
                     └────────┬────────┘
                              │
            ┌─────────────────┼─────────────────┐
            │                 │                 │
            ▼                 ▼                 ▼
         DRIVER            FACULTY            ADMIN
           APP               APP                APP
            │                 │                 │
            │                 │                 │
     Shift + GPS        Tracking + ETA     Shift History
            │            + Notifications     + Monitoring
            │                 ▲                 ▲
            │                 │                 │
            └────────► Firebase ◄───────────────┘
```

### In one sentence:

> **Driver operates the EV and publishes live operational data, Firebase synchronizes that data, Faculty converts it into real-time shuttle tracking, and Admin converts shift events into an operational monitoring dashboard.**

---

> **Documentation note:** This document is intended to explain the validated system architecture and behaviour. When making future changes, use the actual source code and Firebase configuration as the final authority for implementation-specific details.
