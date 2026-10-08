<div align="center">

# 🚗 VIT-EV-SHUTTLE

### Intelligent Real-Time EV Shuttle Tracking System

**One campus. Two EVs. One real-time shuttle ecosystem.**

Faculty never wait blindly again — open the app, see the EV, check ETA, arrive on time.

<br/>

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![Realtime DB](https://img.shields.io/badge/Realtime_Database-FFA000?style=for-the-badge&logo=firebase&logoColor=black)
![OpenStreetMap](https://img.shields.io/badge/OpenStreetMap-7EBC6F?style=for-the-badge&logo=openstreetmap&logoColor=white)
![GPS](https://img.shields.io/badge/GPS_Tracking-00BCD4?style=for-the-badge&logo=googlemaps&logoColor=white)
![EV Mobility](https://img.shields.io/badge/EV_Mobility-00C853?style=for-the-badge&logo=electricvehicle&logoColor=white)

<br/>

**Status** · `Prototype / Campus Deployment Ready`  
**Supported Fleet** · `EV1` · `EV2`

</div>

---

<br/>

## 🎯 The Problem

Faculty using campus EV shuttles often stand at pickup points without knowing:

| Uncertainty | Impact |
|-------------|--------|
| Where is the shuttle right now? | Blind waiting |
| Is it moving or stationary? | No confidence |
| Which stop has it reached? | Missed opportunities |
| Has it already passed my stop? | Frustration |
| How long until it arrives? | Wasted time |

**VIT-EV-SHUTTLE** turns the shuttle into a live, observable campus service.

> **Open the app → see the EV → understand its route progress → check ETA → go to the pickup point at the right time.**

---

<br/>

## 🏗️ System Overview

```text
                  🚗 DRIVER APP
                        │
                        │ GPS + vehicle state
                        ▼
                🔥 Firebase Realtime DB
                        │
               ┌────────┴────────┐
               │                 │
               ▼                 ▼
              EV1               EV2
               │                 │
               └────────┬────────┘
                        │
                        │ Real-time location stream
                        ▼
                  📍 FACULTY APP
                        │
            ┌───────────┼───────────┐
            ▼           ▼           ▼
         Live Map      ETA      Route Progress
                        │
                        ▼
                Pickup Verification
                        │
                        ▼
               Arrival Notification
```

<div align="center">

| Layer | Role |
|-------|------|
| 🚗 **Driver App** | Starts/ends shift · Publishes live GPS · Maintains vehicle state |
| 🔥 **Firebase Realtime DB** | Shared live operational state between apps |
| 📍 **Faculty App** | Live map · Route progress · ETA · Arrival notifications |

</div>

---

<br/>

## 🛠️ Technology Stack

<table>
<tr>
<td width="33%" align="center">

### 📱 Mobile
**Flutter** · **Dart** · **Android**  
**Geolocator**

</td>
<td width="33%" align="center">

### ☁️ Backend
**Firebase Realtime Database**  
Real-time synchronization

</td>
<td width="33%" align="center">

### 🗺️ Maps
**OpenStreetMap**  
`flutter_map`

</td>
</tr>
</table>

> No Google Maps billing or API keys required for map visualization.

---

<br/>

## 📱 Applications

### 📍 Faculty Application

The Faculty App continuously reads live EV state from Firebase and updates the interface without manual refresh.

<table>
<tr>
<td width="50%">

**Core Capabilities**
- Live EV locations (EV1 & EV2)
- Interactive campus map
- Campus block markers
- Pickup-point visualization
- Route / metro-style progress
- Current stop & next stop
- ETA to faculty’s current pickup
- Moving / stationary indication
- EV arrival detection
- Arrival notifications
- Online / offline EV state

</td>
<td width="50%">

**Visual Experience**
- Real-time map markers
- Route progress indicator
- Green → Yellow stop logic
- Skip handling for missed stops
- Pickup radius geofence (35 m)
- High-importance notifications

</td>
</tr>
</table>

---

### 🚗 Driver Application

Only **EV1** and **EV2** are valid vehicle IDs.

<table>
<tr>
<td width="50%">

**Core Capabilities**
- EV selection (EV1 / EV2)
- Shift start & end
- Live GPS tracking
- Firebase location publishing
- Connection / heartbeat state
- Shift timer
- Manual End Shift
- Automatic termination after 30 minutes

</td>
<td width="50%">

**Operational Flow**
```text
AVAILABLE
    │
    ▼
START SHIFT
    │
    ▼
STARTED / ACTIVE
    │
    ├── GPS updates
    ├── heartbeat
    └── connection monitoring
    │
    ▼
END SHIFT
    │
    ▼
ENDED → AVAILABLE
```

</td>
</tr>
</table>

At the end of a shift:

```text
active = false
status = ENDED
connectionState = DISCONNECTED
```

The vehicle can then be allocated again.

---

<br/>

## 🔥 Firebase Realtime Database

Live vehicle state lives under:

```text
evShuttle/
└── vehicles/
    ├── EV1/
    └── EV2/
```

A live vehicle record contains:

| Field | Purpose |
|-------|---------|
| `vehicleId` | EV1 or EV2 |
| `active` | Whether the vehicle is currently in use |
| `status` | ACTIVE / ENDED |
| `driverId` | Current driver |
| `shiftStartedAt` | Shift start timestamp |
| `lastSeen` | Last GPS update |
| `connectionState` | CONNECTED / DISCONNECTED |
| `latitude` · `longitude` | Live position |
| `accuracy` · `speed` · `heading` | Motion data |
| `timestamp` · `updatedAt` | Freshness markers |

**Example live record**

```json
{
  "vehicleId": "EV1",
  "active": true,
  "status": "ACTIVE",
  "driverId": "driver-id",
  "shiftStartedAt": "2026-10-08T12:00:00Z",
  "lastSeen": "2026-10-08T12:05:00Z",
  "connectionState": "CONNECTED",
  "latitude": 12.8444,
  "longitude": 80.1549,
  "speed": 3.2,
  "heading": 90.0
}
```

Historical shift information is stored separately under:

```text
evShuttle/
└── shiftEvents/
```

The Faculty App primarily consumes the live `vehicles` data.

---

<br/>

## ⏱️ 30-Minute Shift Limit

Each driver shift has a hard maximum duration of **30 minutes**.

When the limit is reached, the shift ends automatically.

This prevents an EV from remaining permanently locked by an abandoned driver session.

If an application is closed unexpectedly, the next Firebase verification / claim process checks shift age and ends an expired 30-minute shift before allowing a new allocation.

> There is intentionally **no “stale shift” state** in the application.

---

<br/>

## 🗺️ Campus Route Model

The Faculty App uses predefined round-trip routes.  
Repeated stops are tracked by **route occurrence / index**, not just stop name, so outbound and return legs stay distinct.

### EV1 Route

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

### EV2 Route

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

<br/>

## 🟢🟡 Route Progress Logic

The route indicator follows a physical GPS-based state machine.

| Event | Visual State |
|-------|--------------|
| EV enters pickup radius | **GREEN** |
| EV leaves pickup radius | GREEN remains **3 seconds** → then **YELLOW** |
| EV reaches a later stop | Previous stop → **YELLOW** · Later stop → **GREEN** |

The same logic applies to every stop. It is not hard-coded for any specific junction.

### Skip Handling

If the EV skips a stop (never enters its radius) but later reaches a subsequent stop:

```text
AB3 → AB2/AB4 → MAB3/MAB4

AB2/AB4      → YELLOW / PASSED
MAB3/MAB4    → GREEN / CURRENT
```

The engine searches **forward** through the route instead of resetting to an earlier occurrence.

---

<br/>

## 📍 Pickup Radius & Verification

**Pickup trigger radius: 35 meters**

An EV is considered to have reached a pickup point only when its GPS position is physically inside the configured radius.

Faculty location is continuously monitored. The system:

1. Identifies the faculty member’s campus block  
2. Compares EV location with the relevant pickup point  
3. Performs route eligibility check  
4. Performs physical geofence check  
5. Confirms arrival → triggers notification  

This prevents an EV on another route from incorrectly generating an arrival notification.

---

<br/>

## ⏱️ ETA Calculation

ETA is calculated toward the **faculty member’s current pickup point**.

It follows the EV’s current position along the predefined shuttle route rather than using straight-line distance:

```text
Current EV position
        ↓
Next route pickup
        ↓
Next route pickup
        ↓
...
        ↓
Faculty pickup point
```

The calculation uses the EV’s **recent speed history** rather than a single instantaneous GPS speed value, producing a more stable ETA when GPS speed fluctuates.

---

<br/>

## 🔔 Arrival Notifications

When the correct EV reaches the faculty pickup point:

```text
EV ARRIVAL

EV1 has arrived at your AB3 pickup point
```

Notifications use a dedicated high-importance notification channel.

---

<br/>

## 📡 Live Data Flow

```text
Driver Phone GPS
       │
       ▼
Location Service
       │
       ├── latitude
       ├── longitude
       ├── speed
       ├── heading
       ├── accuracy
       └── timestamp
       │
       ▼
Firebase Realtime Database
       │
       ▼
Faculty EV Provider
       │
       ▼
Faculty Home Screen
       │
       ├── Map marker
       ├── EV status
       ├── Route progress
       ├── ETA
       └── Arrival notification
```

---

<br/>

## 🔌 Offline / Expired Vehicle Handling

The Faculty App periodically fetches the latest vehicle state and checks the freshness of the location timestamp.

If a vehicle is no longer considered active / recent:

```text
Firebase
   ↓
Vehicle no longer fresh
   ↓
Faculty removes EV from live state
   ↓
Route state is cleared
```

Old GPS positions are never displayed indefinitely.

**Faculty / EV location freshness window: 180 seconds**

---

<br/>

## 🏢 MAB3 / MAB4 Handling

MAB3 and MAB4 are treated as a **single logical shuttle pickup point**.

Faculty-facing route label:

```text
MAB3, MAB4 JUNCTION
```

Physical map can still show separate MAB3 and MAB4 building markers.  
This keeps the physical campus representation separate from shuttle pickup logic.

---

<br/>

## 🧠 Design Principles

<table>
<tr>
<td width="50%">

**Physical location over assumptions**  
An EV reaches a stop only when GPS is inside the radius.

**Route occurrence over stop name**  
Repeated stops are tracked by index so outbound and return journeys stay distinct.

**Firebase as shared live state**  
Driver publishes · Faculty consumes.

</td>
<td width="50%">

**Graceful offline handling**  
Stale locations are removed, never shown as live.

**Minimal vehicle scope**  
Only EV1 and EV2 are supported.

**No external routing API**  
ETA is calculated from the known campus route — no Google Directions billing.

</td>
</tr>
</table>

---

<br/>

## ⚙️ Important Configuration

| Parameter | Value |
|-----------|-------|
| Supported vehicles | `EV1` · `EV2` |
| Pickup radius | **35 meters** |
| Maximum driver shift | **30 minutes** |
| Faculty / EV location freshness | **180 seconds** |

These values should be changed only intentionally — they directly affect route detection and live-state behavior.

---

<br/>

## 📁 Project Structure

```text
project/
│
├── faculty_app/
│   ├── lib/
│   │   ├── screens/
│   │   ├── services/
│   │   ├── providers/
│   │   └── models/
│   └── pubspec.yaml
│
├── driver_app/
│   ├── lib/
│   │   ├── screens/
│   │   ├── services/
│   │   └── models/
│   └── pubspec.yaml
│
└── README.md
```

Keep Firebase configuration files and Android / iOS platform configuration inside their respective Flutter applications.

---

<br/>

## 🚀 Setup

### Requirements

- Flutter SDK  
- Android Studio  
- Android SDK  
- Android device / emulator  
- Firebase project  
- Internet connection  
- Location permission on the test device  

### Install dependencies

```bash
# Inside each Flutter application
flutter pub get
```

### Run the Driver App

```bash
flutter run
```

Select **EV1** or **EV2** and start the shift.  
Verify that the Firebase vehicle node receives live data.

### Run the Faculty App

```bash
flutter run
```

The Faculty App connects to the same Firebase Realtime Database and displays active EVs.

---

<br/>

## 🧪 Firebase Testing Checklist

### Driver

| Check | Status |
|-------|--------|
| EV1 can start | ☐ |
| EV2 can start | ☐ |
| Only one driver can claim a vehicle at a time | ☐ |
| GPS coordinates update | ☐ |
| Speed updates | ☐ |
| Heading updates | ☐ |
| `lastSeen` updates | ☐ |
| `connectionState` is CONNECTED | ☐ |
| Shift ends after 30 minutes | ☐ |
| End Shift releases the vehicle | ☐ |

### Faculty

| Check | Status |
|-------|--------|
| EV1 appears on map | ☐ |
| EV2 appears on map | ☐ |
| EV marker moves | ☐ |
| Current stop updates | ☐ |
| Next stop updates | ☐ |
| ETA appears | ☐ |
| Pickup radius works | ☐ |
| Green state appears at pickup | ☐ |
| Green remains for 3 seconds after departure | ☐ |
| Stop becomes yellow | ☐ |
| Skipped stops become passed / yellow | ☐ |
| Later stop becomes green | ☐ |
| Arrival notification appears | ☐ |
| Offline EV disappears | ☐ |

---

<br/>

## 🧹 Clean Firebase Test State

For a fresh demonstration, remove the live vehicle state:

```text
evShuttle/
├── vehicles/
└── shiftEvents/
```

**Do not** delete the parent `evShuttle` node or Firebase configuration.

After starting a fresh driver shift, the application recreates the required vehicle state.

---

<br/>

## 🔧 Troubleshooting

<details>
<summary><b>EV does not appear in Faculty App</b></summary>

1. Driver shift is active  
2. Firebase `vehicles/EV1` or `vehicles/EV2` exists  
3. `active` is `true`  
4. `connectionState` is `CONNECTED`  
5. `lastSeen` is recent  
6. Latitude and longitude are present  

</details>

<details>
<summary><b>EV appears but does not move</b></summary>

1. Driver GPS permission  
2. Device location services  
3. Internet connection  
4. Firebase `latitude` / `longitude` updates  
5. Driver app is still tracking  

</details>

<details>
<summary><b>Stop does not turn green</b></summary>

The EV must physically enter the configured 35 m pickup radius.  
Moving near the building is not enough if the GPS coordinate remains outside the geofence.

</details>

<details>
<summary><b>Stop does not turn yellow</b></summary>

1. The EV first entered the pickup radius  
2. The EV actually moved outside the 35 m radius  
3. Firebase is still sending fresh GPS updates  
4. The Faculty App is using the latest build  

The departure transition is intentionally delayed by 3 seconds to avoid GPS jitter.

</details>

---

<br/>

## ⚠️ Known Operational Considerations

GPS accuracy can vary depending on:

- Device hardware  
- Indoor / outdoor environment  
- Satellite visibility  
- Network conditions  
- Campus buildings and obstructions  

Pickup detection therefore uses a configured radius rather than requiring an exact coordinate match.

**Test outdoors with location permission enabled.**

---

<br/>

## 🏁 Final Architecture Summary

```text
                    ┌─────────────────────┐
                    │     🚗 DRIVER APP   │
                    │                     │
                    │ EV selection        │
                    │ GPS tracking        │
                    │ Shift management    │
                    │ 30-min auto end     │
                    └──────────┬──────────┘
                               │
                               │ Realtime GPS
                               ▼
                    ┌─────────────────────┐
                    │ 🔥 Firebase Realtime│
                    │      Database       │
                    │                     │
                    │ EV1                 │
                    │ EV2                 │
                    │ Shift events        │
                    └──────────┬──────────┘
                               │
                               │ Live state
                               ▼
                    ┌─────────────────────┐
                    │   📍 FACULTY APP    │
                    │                     │
                    │ Live map            │
                    │ Route progress      │
                    │ Pickup geofence     │
                    │ ETA                 │
                    │ Notifications       │
                    └─────────────────────┘
```

---

<br/>

## 🎯 Project Goal

> **Faculty should never have to stand at a shuttle pickup point without knowing where the EV is or whether it is actually coming.**

VIT-EV-SHUTTLE delivers that visibility through live GPS tracking, route-aware ETA, pickup verification, and real-time shuttle status.

---

<div align="center">

**Prototype · Campus Deployment Ready**

Supported fleet · **EV1** · **EV2**

Core tracking · Route progress · Pickup verification · ETA · Notifications · Driver shift management  
— implemented and tested.

<br/>

</div>
