# Product Requirements Document: TeslaMate iOS & iPadOS App

**Version:** 1.0
**Date:** 2026-02-23
**Status:** Draft

---

## 1. Executive Summary

This document defines the product requirements for a native iOS and iPadOS application that provides a mobile-first interface to TeslaMate, the self-hosted Tesla data logger. The app replaces the current Grafana-based dashboard experience with a purpose-built native application optimised for iPhone and iPad, delivering real-time vehicle monitoring, historical data visualisation, and comprehensive Tesla telemetry analytics.

The backend (Elixir/Phoenix + PostgreSQL) will be retained for data collection and storage, with a new REST API layer added to serve the mobile app. The system will be deployable on cloud infrastructure (Evroc or equivalent European sovereign cloud), with the iOS app distributed via the App Store.

---

## 2. Problem Statement

TeslaMate is a powerful, self-hosted Tesla data logger with over 6,000 GitHub stars. However, it has significant UX limitations:

1. **No native mobile experience** — The web UI is a basic Phoenix LiveView interface for configuration only (sign-in, settings, geofences). All data visualisation depends on Grafana dashboards, which are not optimised for mobile.
2. **Grafana dependency** — Users must self-host Grafana and navigate complex dashboard URLs. The mobile browser experience is poor: small text, no gestures, no offline capability.
3. **No push notifications** — Users cannot receive alerts for charging completion, vampire drain, geofence events, software updates, or anomalies.
4. **No offline or at-a-glance access** — No widgets, no Apple Watch complications, no quick-glance capability.
5. **Technical barrier to entry** — Setting up TeslaMate requires Docker, PostgreSQL, Grafana, and MQTT knowledge. A cloud-hosted option with a native app would dramatically lower the barrier.

---

## 3. Vision & Goals

### Vision
Deliver the most comprehensive Tesla ownership analytics platform as a native iOS/iPadOS experience, combining the depth of TeslaMate's data collection with the polish and convenience of a first-party Apple app.

### Goals
| # | Goal | Success Metric |
|---|------|----------------|
| G1 | Replace Grafana with native iOS dashboards | 100% feature parity with all 23 Grafana dashboards |
| G2 | Real-time vehicle monitoring on mobile | < 5 second latency from vehicle event to app display |
| G3 | Push notifications for key events | Charging complete, geofence enter/exit, vampire drain alert, software update available |
| G4 | iPad-optimised experience | Multi-column layouts, Split View & Slide Over support |
| G5 | Cloud-hosted backend option | One-click deployment to Evroc (or alternative) with managed PostgreSQL |
| G6 | App Store distribution | Published on the iOS App Store |

---

## 4. Target Audience

### Primary
- **Existing TeslaMate users** who want a native mobile experience instead of Grafana
- **Tesla owners** who want detailed vehicle analytics without the self-hosting complexity

### Secondary
- **Multi-vehicle fleet owners** who need to monitor multiple Tesla vehicles
- **Tesla enthusiasts** who want long-term battery health, efficiency, and cost tracking

---

## 5. Licensing & Legal Considerations

### AGPL-3.0 Compliance
TeslaMate is licensed under **GNU Affero General Public License v3.0 (AGPLv3)**. This has direct implications:

- **All derivative server-side code** (the API layer, any backend modifications) must be released under AGPLv3 with source code available.
- **The iOS app** connects to the backend over a network API. Whether the iOS app itself must be AGPLv3-licensed depends on whether it constitutes a "derivative work" of the TeslaMate codebase. If the iOS app is an independent work that merely communicates over an API, it may be licensed separately. However, the TeslaMate project's stated intent is strong copyleft — consult legal counsel before choosing a proprietary license for the iOS client.
- **Trademark**: The "TeslaMate" name and logo are trademarked. The app must use a distinct name and branding.
- **Tesla API Terms**: The app must comply with Tesla's API terms of service. Tesla has been transitioning to the Fleet API with partner authentication — the app must support this.

### Recommended Approach
- Release the backend API layer as open source under AGPLv3 (contributed back to the community)
- Release the iOS app under AGPLv3 as well (aligned with the project's values, avoids legal ambiguity)
- Use a distinct app name and branding (not "TeslaMate")

### App Name
The app needs its own name due to trademark restrictions. Working title for this PRD: **"TeslaPulse"** (placeholder — final name TBD, subject to trademark search).

---

## 6. System Architecture

### 6.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Tesla API                             │
│              (Fleet API / Owner API / Streaming)             │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    TeslaMate Backend                         │
│              (Elixir/Phoenix + PostgreSQL)                    │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ Data Logger   │  │  MQTT Broker │  │  New: REST API   │   │
│  │ (existing)    │  │  (existing)  │  │  Layer (Phoenix) │   │
│  └──────────────┘  └──────────────┘  └────────┬─────────┘   │
│                                                │             │
│  ┌──────────────────────────────────────────┐  │             │
│  │           PostgreSQL Database             │  │             │
│  └──────────────────────────────────────────┘  │             │
└────────────────────────────────────────────────┼─────────────┘
                                                 │
                              HTTPS + WebSocket  │
                                                 │
                    ┌────────────────────────────┐
                    │                            │
              ┌─────▼─────┐              ┌──────▼──────┐
              │  iOS App   │              │  iPad App   │
              │ (SwiftUI)  │              │ (SwiftUI)   │
              └────────────┘              └─────────────┘
```

### 6.2 Backend: API Layer (New)

The existing TeslaMate backend will be extended with a JSON REST API served by Phoenix. This approach:
- Preserves the battle-tested data collection pipeline
- Avoids rewriting the Tesla API integration, streaming, and logging logic
- Adds a thin API layer on top of the existing Ecto schemas and database

#### API Design Principles
- RESTful JSON API with versioned endpoints (`/api/v1/...`)
- Token-based authentication (JWT or Phoenix token)
- WebSocket channel for real-time updates (leveraging Phoenix Channels, which already power the LiveView)
- Pagination, filtering, and date range support on all list endpoints
- OpenAPI 3.0 specification for documentation

#### Core API Endpoints

| Category | Endpoint | Method | Description |
|----------|----------|--------|-------------|
| **Auth** | `/api/v1/auth/login` | POST | Authenticate user, return JWT |
| **Auth** | `/api/v1/auth/refresh` | POST | Refresh JWT token |
| **Auth** | `/api/v1/auth/tesla/callback` | POST | Handle Tesla OAuth callback |
| **Cars** | `/api/v1/cars` | GET | List all vehicles |
| **Cars** | `/api/v1/cars/:id` | GET | Get vehicle details + current state |
| **Cars** | `/api/v1/cars/:id/summary` | GET | Live summary (state, SOC, location, etc.) |
| **Drives** | `/api/v1/cars/:id/drives` | GET | List drives (paginated, filterable) |
| **Drives** | `/api/v1/drives/:id` | GET | Drive detail with positions |
| **Drives** | `/api/v1/drives/:id/gpx` | GET | GPX export of drive |
| **Charges** | `/api/v1/cars/:id/charges` | GET | List charging sessions |
| **Charges** | `/api/v1/charges/:id` | GET | Charge detail with granular data |
| **Positions** | `/api/v1/cars/:id/positions` | GET | Position history (date range) |
| **States** | `/api/v1/cars/:id/states` | GET | Vehicle state history |
| **Updates** | `/api/v1/cars/:id/updates` | GET | Firmware update history |
| **Stats** | `/api/v1/cars/:id/stats/battery` | GET | Battery health analytics |
| **Stats** | `/api/v1/cars/:id/stats/charging` | GET | Charging statistics |
| **Stats** | `/api/v1/cars/:id/stats/driving` | GET | Drive statistics |
| **Stats** | `/api/v1/cars/:id/stats/efficiency` | GET | Efficiency metrics |
| **Stats** | `/api/v1/cars/:id/stats/vampire-drain` | GET | Vampire drain analysis |
| **Stats** | `/api/v1/cars/:id/stats/mileage` | GET | Mileage tracking |
| **Geofences** | `/api/v1/geofences` | GET/POST | List/create geofences |
| **Geofences** | `/api/v1/geofences/:id` | GET/PUT/DELETE | CRUD geofence |
| **Settings** | `/api/v1/settings` | GET/PUT | Global settings |
| **Settings** | `/api/v1/cars/:id/settings` | GET/PUT | Per-vehicle settings |
| **Real-time** | `wss://.../socket/v1/car/:id` | WS | Real-time vehicle updates via Phoenix Channel |

### 6.3 Cloud Deployment (Evroc or Alternative)

#### Requirements
- European sovereign cloud hosting (Evroc preferred, alternatives: Scaleway, Hetzner, OVH)
- Managed PostgreSQL (or containerised)
- Container orchestration (Docker Compose for single-user, Kubernetes for multi-tenant)
- TLS termination (Let's Encrypt or managed certificates)
- MQTT broker (Mosquitto, containerised)
- Automated backups for PostgreSQL

#### Deployment Architecture
```
┌──────────────────────────────────────────┐
│              Evroc Cloud                  │
│                                           │
│  ┌─────────────────────────────────────┐  │
│  │        Reverse Proxy (Caddy)        │  │
│  │        TLS termination              │  │
│  └──────────────┬──────────────────────┘  │
│                 │                          │
│  ┌──────────────▼──────────────────────┐  │
│  │     TeslaMate + API (Container)     │  │
│  │     Elixir/Phoenix                  │  │
│  └──────────────┬──────────────────────┘  │
│                 │                          │
│  ┌──────────────▼──────────────────────┐  │
│  │     PostgreSQL (Managed/Container)  │  │
│  └─────────────────────────────────────┘  │
│                                           │
│  ┌─────────────────────────────────────┐  │
│  │     Mosquitto MQTT (Container)      │  │
│  └─────────────────────────────────────┘  │
│                                           │
│  ┌─────────────────────────────────────┐  │
│  │     Push Notification Service       │  │
│  │     (APNs relay)                    │  │
│  └─────────────────────────────────────┘  │
└───────────────────────────────────────────┘
```

---

## 7. iOS / iPadOS Application

### 7.1 Technology Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| UI Framework | SwiftUI | Modern, declarative, native iOS/iPadOS support, widgets |
| Minimum iOS | 17.0 | Latest SwiftUI features, interactive widgets, StandBy mode |
| Architecture | MVVM + Swift Concurrency | Clean separation, async/await, Combine where needed |
| Networking | URLSession + async/await | Native, no third-party dependency |
| WebSocket | URLSessionWebSocketTask | Native WebSocket support |
| Charts | Swift Charts | Apple's native charting framework |
| Maps | MapKit | Native maps for drive routes and locations |
| Local Storage | SwiftData | Offline caching, persistence |
| Push Notifications | APNs | Apple Push Notification service |
| Widgets | WidgetKit | Home screen and Lock Screen widgets |
| Keychain | Security framework | Secure credential storage |
| Localisation | String Catalogs | Multi-language support |

### 7.2 App Structure & Navigation

The app uses a **TabView** on iPhone and a **NavigationSplitView** (sidebar) on iPad.

#### iPhone Tab Bar
```
┌─────────┬──────────┬──────────┬──────────┬──────────┐
│ Overview │  Drives  │ Charges  │  Stats   │ Settings │
└─────────┴──────────┴──────────┴──────────┴──────────┘
```

#### iPad Sidebar
```
┌──────────────┬─────────────────────────────────────────┐
│  VEHICLES    │                                         │
│  ├ Model 3   │           Content Area                  │
│  └ Model Y   │                                         │
│              │                                         │
│  DASHBOARDS  │                                         │
│  ├ Overview  │                                         │
│  ├ Drives    │                                         │
│  ├ Charges   │                                         │
│  ├ Battery   │                                         │
│  ├ Efficiency│                                         │
│  ├ Statistics│                                         │
│  └ Timeline  │                                         │
│              │                                         │
│  MANAGE      │                                         │
│  ├ Geofences │                                         │
│  ├ Settings  │                                         │
│  └ About     │                                         │
└──────────────┴─────────────────────────────────────────┘
```

### 7.3 Screens & Feature Specifications

Each screen below maps to one or more of the existing Grafana dashboards, reimagined as native iOS views.

---

#### 7.3.1 Overview Screen (Home)
**Maps to:** Grafana "Overview" + "Home" dashboards

**Purpose:** At-a-glance vehicle status — the first thing users see when opening the app.

**Layout (iPhone):**
```
┌─────────────────────────────────┐
│  [Vehicle Name]     Model 3 LR  │
│  ┌─────────────────────────────┐│
│  │    🔋 78%                    ││
│  │    ████████████░░░░          ││
│  │    Est. Range: 312 km        ││
│  └─────────────────────────────┘│
│                                 │
│  State: Parked · Since 2h 14m   │
│  Location: Home                  │
│  Temperature: 18°C outside       │
│                                 │
│  ┌──────────┐ ┌──────────┐      │
│  │ Locked 🔒│ │Sentry Off│      │
│  └──────────┘ └──────────┘      │
│  ┌──────────┐ ┌──────────┐      │
│  │Doors     │ │Windows   │      │
│  │ Closed   │ │ Closed   │      │
│  └──────────┘ └──────────┘      │
│                                 │
│  Software: 2025.48.2            │
│  Odometer: 47,832 km            │
│                                 │
│  ┌─────────────────────────────┐│
│  │ Tyre Pressures              ││
│  │  FL: 2.9   FR: 2.9         ││
│  │  RL: 2.9   RR: 2.9  (bar)  ││
│  └─────────────────────────────┘│
│                                 │
│  ┌─ Last Drive ──────────────┐  │
│  │ Home → Office · 23 km     │  │
│  │ 142 Wh/km · 28 min       │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌─ Last Charge ─────────────┐  │
│  │ Home · 42→87% · 18.4 kWh │  │
│  │ Cost: €2.76 · 3h 12m     │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

**Data Source:** `GET /api/v1/cars/:id/summary` + WebSocket real-time channel

**Key Features:**
- Real-time updates via WebSocket (battery, state, location update live)
- Pull-to-refresh
- Vehicle picker for multi-car accounts (swipeable cards or dropdown)
- Contextual display: shows charging progress when charging, drive info when driving
- Tap any section to drill into the relevant detail screen

---

#### 7.3.2 Drives Screen
**Maps to:** Grafana "Drives" dashboard

**Purpose:** Scrollable list of all driving sessions with summary metrics.

**Layout:**
- **Header stats:** Total distance, total energy consumed, average efficiency, drive count (for selected period)
- **Filter bar:** Date range picker, geofence filter, minimum distance filter
- **List:** Each row shows:
  - Date/time
  - Start → End location (geofence name or address)
  - Distance
  - Duration
  - Efficiency (Wh/km) with colour indicator (green/yellow/red)
  - Temperature
  - Max speed
  - Battery % start → end

**Drill-down: Drive Detail Screen**
**Maps to:** Grafana "Drive Details" dashboard

- **Map view** (MapKit) showing the drive route plotted from position data, with elevation colouring
- **Elevation profile** chart (Swift Charts)
- **Speed over time** chart
- **Power/consumption over time** chart
- **Battery level over time** chart
- **Temperature** (inside/outside) chart
- **Key metrics:** Distance, duration, avg speed, max speed, efficiency, energy used, elevation gain/loss
- **GPX export** button (share sheet)

---

#### 7.3.3 Charges Screen
**Maps to:** Grafana "Charges" dashboard

**Purpose:** List of all charging sessions with cost tracking.

**Layout:**
- **Header stats:** Total energy added, total energy used (from grid), total cost, average cost per kWh
- **Filter bar:** Date range, geofence, charger type (AC/DC), minimum cost
- **List:** Each row shows:
  - Date/time
  - Location (geofence name or address)
  - Charger type (AC/DC) with icon
  - Battery % start → end (visual bar)
  - Energy added (kWh)
  - Cost
  - Duration
  - Charge rate (max kW)

**Drill-down: Charge Detail Screen**
**Maps to:** Grafana "Charge Details" dashboard

- **Charge curve chart:** Power (kW) over time
- **Battery level** over time during charge
- **Voltage/current** chart
- **Temperature** chart
- **Key metrics:** Energy added, energy from grid, efficiency, max power, avg power, cost, duration
- **Charger info:** Cable type, fast charger brand/type, phases
- **Cost editing** (tap to manually set/override cost)

---

#### 7.3.4 Battery Health Screen
**Maps to:** Grafana "Battery Health" dashboard

**Purpose:** Long-term battery degradation tracking.

**Components:**
- **Battery capacity gauge:** Original vs current capacity
- **Degradation percentage** (prominently displayed)
- **Battery health percentage** (bar gauge)
- **Scatter plot:** Battery capacity vs mileage (Swift Charts XY plot)
- **Key metrics:** Usable capacity (new/current), max range (new/current), range lost
- **Charging stats:** Total charges, charging cycles, total energy added
- **AC/DC energy split** (pie chart)
- **Current SOC** and stored energy
- **Derived rated efficiency**

---

#### 7.3.5 Charge Level Screen
**Maps to:** Grafana "Charge Level" dashboard

**Purpose:** Historical SOC (State of Charge) over time.

**Components:**
- **Time series chart:** Battery level over time with:
  - Moving average line
  - Percentile bands (7.5%, 50%, 92.5%)
  - Colour-coded threshold zones
- **Date range selector** (1 week, 1 month, 3 months, 1 year, all time)
- **Statistics:** Average SOC, time spent above 90%, time spent below 20%

---

#### 7.3.6 Charging Stats Screen
**Maps to:** Grafana "Charging Stats" dashboard

**Purpose:** Aggregate charging analytics.

**Components:**
- **Summary cards:** Number of charges, total energy, supercharger cost, total cost, avg cost/100km
- **Charge heatmap:** Battery level distribution over time (native heatmap using Swift Charts)
- **Charge delta chart:** Start vs end SOC distribution
- **AC/DC breakdown:** Pie charts for energy and duration
- **DC charging curve:** Power vs SOC scatter plot (shows fast-charging degradation)
- **Charging map:** MapKit view with markers at charging locations (circle size = energy added)
- **Top stations table:** Ranked by energy added and cost
- **SOC distribution stats** table

---

#### 7.3.7 Drive Stats Screen
**Maps to:** Grafana "Drive Stats" dashboard

**Purpose:** Aggregate driving analytics.

**Components:**
- **Summary cards:** Number of drives, total distance, average efficiency, total energy
- **Monthly trends:** Distance and efficiency over time
- **Trip cost tracking**

---

#### 7.3.8 Efficiency Screen
**Maps to:** Grafana "Efficiency" dashboard

**Purpose:** Consumption analysis over time.

**Components:**
- **Consumption trend chart:** Wh/km (or Wh/mi) over time
- **Temperature vs efficiency** correlation
- **Seasonal patterns**

---

#### 7.3.9 Mileage Screen
**Maps to:** Grafana "Mileage" dashboard

**Purpose:** Odometer and distance tracking.

**Components:**
- **Odometer reading** (large display)
- **Distance over time** chart (cumulative and per-period)
- **Monthly/yearly breakdowns**

---

#### 7.3.10 Projected Range Screen
**Maps to:** Grafana "Projected Range" dashboard

**Purpose:** Battery range tracking and degradation prediction.

**Components:**
- **Range over time** chart with step-function line
- **Charge event annotations** on the chart
- **Projected future range** (trend extrapolation)

---

#### 7.3.11 States Screen
**Maps to:** Grafana "States" dashboard

**Purpose:** Vehicle connectivity and power state history.

**Components:**
- **Timeline view:** Colour-coded bars showing online/offline/asleep states over time
- **State distribution:** Pie chart of time in each state
- **Date range selector**

---

#### 7.3.12 Timeline Screen
**Maps to:** Grafana "Timeline" dashboard

**Purpose:** Chronological view of all events (drives, charges, states, updates).

**Components:**
- **Vertical timeline:** Scrollable list of events with icons, times, and summaries
- **Filterable** by event type
- **Tap to drill into** drive/charge/update detail

---

#### 7.3.13 Statistics Screen
**Maps to:** Grafana "Statistics" dashboard

**Purpose:** Aggregate lifetime statistics.

**Components:**
- **Key lifetime metrics** displayed as a dashboard of cards
- **Comparison periods** (this month vs last month, this year vs last year)

---

#### 7.3.14 Trip Screen
**Maps to:** Grafana "Trip" dashboard

**Purpose:** Multi-drive trip aggregation.

**Components:**
- **Trip definition** (date range or geofence-to-geofence)
- **Aggregated stats** for all drives in the trip
- **Combined route map**
- **Total cost, distance, energy, time**

---

#### 7.3.15 Updates Screen
**Maps to:** Grafana "Updates" dashboard

**Purpose:** Firmware update history.

**Components:**
- **List of updates:** Version, date installed, duration
- **Current version** prominently displayed
- **Update timeline** chart

---

#### 7.3.16 Vampire Drain Screen
**Maps to:** Grafana "Vampire Drain" dashboard

**Purpose:** Monitor battery drain while parked.

**Components:**
- **Drain rate chart:** Battery level loss over time while parked
- **Average drain rate** (% per hour, kWh per day)
- **Comparison by location** (home vs work vs other)
- **Anomaly highlighting** (unusually high drain)

---

#### 7.3.17 Visited (Lifetime Map) Screen
**Maps to:** Grafana "Visited" dashboard

**Purpose:** Map of all locations ever visited.

**Components:**
- **Full-screen MapKit view** with heat map overlay or plotted route history
- **Cluster markers** for frequently visited locations
- **Statistics overlay:** Countries, cities, total unique locations

---

#### 7.3.18 Locations / Geofences Screen
**Maps to:** Grafana "Locations" + existing Phoenix web UI geofence management

**Purpose:** Manage geofences and view location statistics.

**Components:**
- **Map view** with geofence circles displayed
- **List view** of all geofences with visit count, last visited, charge cost settings
- **Add/edit geofence:** Map pin placement, radius slider, name, billing settings (per kWh / per minute / session fee)
- **Delete geofence** with confirmation

---

#### 7.3.19 Settings Screen
**Maps to:** Existing Phoenix web UI settings

**Components:**
- **Units:** Length (km/mi), Temperature (°C/°F), Pressure (bar/psi)
- **Range display:** Ideal / Rated
- **Language** selection
- **Theme:** Light / Dark / System
- **Per-vehicle settings:**
  - Suspend timeout
  - Idle timeout
  - Require unlocked
  - Free supercharging flag
  - Use streaming API
  - Enabled/disabled
  - LFP battery flag
  - Sleep mode enabled
- **Backend connection:** Server URL, authentication
- **Notifications:** Toggle per notification type
- **Data management:** Import from TeslaFi, export data
- **About:** Version, licenses, source code link

---

### 7.4 Real-Time Updates

The app maintains a persistent WebSocket connection (Phoenix Channel) for real-time vehicle data:

**Channel:** `car:<car_id>`

**Events pushed to client:**
| Event | Payload | Trigger |
|-------|---------|---------|
| `summary` | Full vehicle summary | Any state change |
| `position` | lat, lon, speed, power, elevation | While driving (every ~1-5 seconds) |
| `charge_update` | SOC, power, voltage, current, energy | While charging (every ~30 seconds) |
| `state_change` | New state (online/offline/asleep/driving/charging) | State transition |
| `geofence` | Geofence entered/exited | Location change near geofence boundary |

**Reconnection:** Exponential backoff (1s, 2s, 4s, 8s... max 30s), automatic resume on network change.

### 7.5 Push Notifications

Push notifications are delivered via APNs (Apple Push Notification service) from a notification service running alongside the TeslaMate backend.

| Notification | Trigger | Content |
|-------------|---------|---------|
| Charge Complete | `charging_state` changes to `Complete` | "Model 3 finished charging at 87% (Home)" |
| Charge Started | New charging process detected | "Model 3 started charging at Office (23%)" |
| Charge Interrupted | Charging stops unexpectedly | "Model 3 stopped charging at 45% — check connection" |
| Geofence Enter | Vehicle enters geofence | "Model 3 arrived at Home" |
| Geofence Exit | Vehicle exits geofence | "Model 3 left Office" |
| Software Update | New `update` record created | "Software update 2025.48.2 installing..." |
| Update Complete | Update `end_date` set | "Software update 2025.48.2 installed" |
| Vampire Drain | Drain exceeds threshold while parked | "Model 3 lost 5% in 8h at Home — possible vampire drain" |
| Vehicle Went to Sleep | State changes to `asleep` | (Optional, default off) |
| Vehicle Woke Up | State changes from `asleep` to `online` | (Optional, default off) |
| Sentry Mode Alert | Sentry mode activated/deactivated | (Optional, default off) |

### 7.6 Widgets (WidgetKit)

#### Home Screen Widgets

| Widget | Size | Content |
|--------|------|---------|
| Battery | Small | SOC percentage + range estimate |
| Battery | Medium | SOC + range + charging status + time remaining |
| Status | Small | Vehicle state (parked/driving/charging) + location |
| Status | Medium | State + location + lock status + sentry + temperature |
| Last Drive | Medium | Start→end, distance, efficiency, duration |
| Last Charge | Medium | Location, SOC change, energy, cost |

#### Lock Screen Widgets

| Widget | Type | Content |
|--------|------|---------|
| Battery | Circular | SOC gauge |
| Battery | Inline | "🔋 78% · 312 km" |
| State | Rectangular | State + location + duration |

#### StandBy Mode
- Clock-style widget showing SOC and vehicle state

### 7.7 Offline Support

- **SwiftData local cache:** Recent summaries, last 30 drives, last 30 charges cached locally
- **Graceful degradation:** App shows cached data with "Last updated X ago" indicator when offline
- **Background refresh:** Periodic background fetch to update cached data and widgets
- **Offline-first widgets:** Widgets always show the most recent cached data

### 7.8 Accessibility

- Full VoiceOver support on all screens
- Dynamic Type support (all text sizes)
- Sufficient colour contrast ratios (WCAG AA)
- Chart accessibility: data table alternatives for all charts
- Reduce Motion support (minimise animations)

### 7.9 Multi-Vehicle Support

- Vehicle picker in navigation (segmented control on iPhone, sidebar grouping on iPad)
- Per-vehicle notification preferences
- Quick-switch between vehicles
- Overview screen can show summary cards for all vehicles simultaneously

---

## 8. Data Model (iOS Client)

The iOS app maintains local Swift models that mirror the backend database schema:

```swift
// Core Models (simplified)

struct Vehicle: Identifiable, Codable {
    let id: Int
    let eid: Int
    let vid: Int
    let vin: String
    let name: String
    let model: String
    let trimBadging: String?
    let marketingName: String?
    let exteriorColor: String?
    let wheelType: String?
    let spoilerType: String?
    let efficiency: Double
}

struct VehicleSummary: Codable {
    let state: VehicleState          // online, offline, asleep, driving, charging, updating
    let since: Date
    let batteryLevel: Int
    let usableBatteryLevel: Int
    let idealBatteryRangeKm: Double
    let estBatteryRangeKm: Double
    let ratedBatteryRangeKm: Double
    let latitude: Double?
    let longitude: Double?
    let heading: Int?
    let speed: Int?
    let power: Int?
    let shiftState: String?
    let isClimateOn: Bool
    let isPreconditioning: Bool
    let locked: Bool
    let sentryMode: Bool
    let pluggedIn: Bool
    let chargingState: String?
    let chargerPower: Int?
    let timeToFullCharge: Double?
    let chargeLimitSoc: Int?
    let outsideTemp: Double?
    let insideTemp: Double?
    let odometer: Double
    let geofence: String?
    let version: String?
    let updateAvailable: Bool
    let updateVersion: String?
    // ... tpms, doors, windows, trunk, frunk
}

struct Drive: Identifiable, Codable {
    let id: Int
    let startDate: Date
    let endDate: Date?
    let startAddress: String?
    let endAddress: String?
    let startGeofence: String?
    let endGeofence: String?
    let distance: Double
    let durationMin: Int
    let speedMax: Int?
    let outsideTempAvg: Double?
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let efficiency: Double          // Wh/km
    let startRatedRangeKm: Double?
    let endRatedRangeKm: Double?
}

struct DriveDetail: Codable {
    let drive: Drive
    let positions: [Position]       // For map route and charts
}

struct Position: Codable {
    let date: Date
    let latitude: Double
    let longitude: Double
    let elevation: Int?
    let speed: Int?
    let power: Int?
    let batteryLevel: Int?
    let outsideTemp: Double?
    let insideTemp: Double?
}

struct ChargingSession: Identifiable, Codable {
    let id: Int
    let startDate: Date
    let endDate: Date?
    let address: String?
    let geofence: String?
    let chargeEnergyAdded: Double?
    let chargeEnergyUsed: Double?
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let durationMin: Int?
    let outsideTempAvg: Double?
    let cost: Double?
    let chargerType: ChargerType    // AC or DC
    let maxPower: Int?
}

struct ChargeDataPoint: Codable {
    let date: Date
    let batteryLevel: Int?
    let chargerPower: Int?
    let chargerVoltage: Int?
    let chargerActualCurrent: Int?
    let chargerPhases: Int?
    let chargeEnergyAdded: Double?
    let outsideTemp: Double?
    let fastChargerPresent: Bool
    let fastChargerBrand: String?
    let fastChargerType: String?
    let connChargeCable: String?
}

struct Geofence: Identifiable, Codable {
    let id: Int
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Int
    var billingType: BillingType    // perKwh or perMinute
    var costPerUnit: Double?
    var sessionFee: Double?
}

struct BatteryHealth: Codable {
    let originalCapacity: Double
    let currentCapacity: Double
    let degradationPercent: Double
    let healthPercent: Double
    let totalCharges: Int
    let chargingCycles: Double
    let totalEnergyAdded: Double
    let acEnergyUsed: Double
    let dcEnergyUsed: Double
    let capacityByMileage: [(mileage: Double, capacity: Double)]
}

struct FirmwareUpdate: Identifiable, Codable {
    let id: Int
    let version: String
    let startDate: Date
    let endDate: Date?
}
```

---

## 9. Non-Functional Requirements

### 9.1 Performance

| Metric | Target |
|--------|--------|
| App launch to content | < 1.5 seconds (cold start) |
| Screen transitions | < 300ms |
| Real-time update latency | < 5 seconds (vehicle event → app display) |
| Chart rendering (1000 data points) | < 500ms |
| API response time (p95) | < 500ms |
| Background fetch interval | 15 minutes (system-managed) |
| Widget refresh | System-managed timeline (15-60 min) |

### 9.2 Security

| Requirement | Implementation |
|-------------|----------------|
| API authentication | JWT tokens stored in iOS Keychain |
| Token refresh | Automatic refresh before expiry |
| Data in transit | TLS 1.3 minimum |
| Data at rest (device) | iOS Data Protection (NSFileProtectionComplete) |
| Tesla credentials | Never stored on device; handled server-side only |
| Certificate pinning | Pin backend server certificate |
| Biometric lock | Optional Face ID / Touch ID to open app |

### 9.3 Reliability

- Graceful handling of network interruptions
- Automatic WebSocket reconnection with exponential backoff
- Local data cache survives app termination
- Background task completion for in-progress data fetches
- Crash-free rate target: > 99.5%

### 9.4 Scalability

The backend API layer should support:
- Up to 10 concurrent vehicles per user
- Up to 5 concurrent WebSocket connections per user
- Database query optimisation for large datasets (years of position data — potentially millions of rows)
- Pagination on all list endpoints (cursor-based for positions, offset-based for drives/charges)

### 9.5 Internationalisation

- All user-facing strings in String Catalogs
- Support for languages already in TeslaMate: English, German, French, Spanish, Italian, Dutch, Swedish, Norwegian, Danish, Finnish, Chinese, Japanese, Korean, and others
- RTL layout support
- Locale-aware number and date formatting (via CLDR, matching TeslaMate's existing Cldr integration)
- Unit conversion (km/mi, °C/°F, bar/psi) consistent with user settings

---

## 10. Phased Delivery

### Phase 1: Foundation (MVP)
- Backend API layer (all core endpoints)
- iOS app with: Overview, Drives (list + detail + map), Charges (list + detail), Settings
- Authentication flow (Tesla OAuth via backend)
- Real-time updates via WebSocket
- Basic offline caching
- Single vehicle support
- Cloud deployment (Docker Compose on Evroc or chosen provider)

### Phase 2: Full Dashboard Parity
- All remaining dashboard screens (Battery Health, Charging Stats, Drive Stats, Efficiency, Mileage, Projected Range, States, Timeline, Statistics, Trip, Updates, Vampire Drain, Visited)
- Multi-vehicle support
- Geofence management (CRUD with map)
- Charge cost editing
- iPad optimised layouts (NavigationSplitView, multi-column)

### Phase 3: Native Mobile Features
- Push notifications (all types)
- WidgetKit widgets (Home Screen, Lock Screen, StandBy)
- GPX export / share
- Data import from TeslaFi
- Biometric app lock
- Full internationalisation
- App Store submission

### Phase 4: Advanced Features (Post-Launch)
- Apple Watch app (glanceable SOC, state, notifications)
- Siri Shortcuts integration ("Hey Siri, what's my Tesla's battery?")
- Live Activities (charging progress, drive in progress on Lock Screen / Dynamic Island)
- CarPlay dashboard (if applicable)
- Vehicle commands (lock/unlock, climate control, charge port, etc.) — requires Tesla Fleet API partner authentication
- Multi-user support (shared vehicle access)
- Data export (CSV, JSON)
- Comparison analytics (vehicle vs vehicle, period vs period)

---

## 11. Dependencies & Risks

### Dependencies

| Dependency | Risk Level | Mitigation |
|-----------|-----------|------------|
| Tesla API availability | High | Implement retry logic, caching, graceful degradation. Monitor Tesla API changes. |
| Tesla Fleet API migration | High | Tesla is transitioning from Owner API to Fleet API with partner auth. Must register as a Fleet API partner. |
| Evroc cloud availability | Medium | Architecture is Docker-based; can deploy to any cloud provider. |
| Apple App Store approval | Medium | Follow Apple guidelines strictly. AGPL compliance may require source code link in app. |
| TeslaMate upstream changes | Medium | Fork may diverge. Maintain ability to merge upstream updates. |

### Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Tesla blocks third-party API access | Low | Critical | Monitor Tesla developer communications. The Fleet API programme suggests continued support. |
| AGPL license dispute with TeslaMate org | Medium | High | Engage early with the TeslaMate community. Comply fully with AGPL. Consider contributing the API layer upstream. |
| Performance issues with large datasets | Medium | Medium | Implement server-side pagination, aggregation queries, and database indexes. Use SwiftData for client-side caching with TTL. |
| App Store rejection for AGPL compliance | Low | Medium | Include source code link in app, host source publicly on GitHub. Apple has approved AGPL apps (e.g., Signal components). |

---

## 12. Success Metrics

| Metric | Target (6 months post-launch) |
|--------|-------------------------------|
| App Store rating | ≥ 4.5 stars |
| Daily active users | Track adoption curve |
| Crash-free sessions | ≥ 99.5% |
| API p95 latency | < 500ms |
| Real-time update latency | < 5 seconds |
| Feature parity with Grafana | 100% of dashboard data accessible |
| Push notification delivery rate | ≥ 98% |

---

## 13. Open Questions

| # | Question | Decision Needed By |
|---|---------|-------------------|
| 1 | **Final app name and branding** — "TeslaPulse" is a working title. Needs trademark search. | Before App Store submission |
| 2 | **Evroc vs alternative cloud** — Evroc is preferred but availability and pricing need validation. Alternatives: Scaleway, Hetzner, OVH. | Before Phase 1 deployment |
| 3 | **Tesla Fleet API partner registration** — Required for continued API access. Process and timeline? | Immediately |
| 4 | **Monetisation model** — Free? Freemium? Subscription? One-time purchase? This affects architecture (multi-tenant vs single-tenant). | Before Phase 3 |
| 5 | **Vehicle commands in scope?** — Phase 4 lists commands (lock, climate, etc.). This significantly increases scope and security requirements. Confirm priority. | Before Phase 4 |
| 6 | **AGPL compliance for iOS app** — Legal review needed on whether the iOS client must be AGPL. | Before Phase 3 |
| 7 | **Multi-tenant architecture** — If this becomes a hosted service, the backend needs user isolation, billing, and tenant management. | Before Phase 1 if multi-tenant |
| 8 | **Grafana retention** — Keep Grafana as a power-user option alongside the iOS app, or deprecate? | Phase 2 |

---

## 14. Appendix

### A. Existing TeslaMate Grafana Dashboard Inventory

The following 23 dashboards must have feature parity in the iOS app:

1. Battery Health
2. Charge Level
3. Charges
4. Charge Details (internal, drill-down)
5. Charging Stats
6. Database Info (admin only — may not need iOS equivalent)
7. Drive Stats
8. Drives
9. Drive Details (internal, drill-down)
10. Efficiency
11. Locations
12. Mileage
13. Overview
14. Projected Range
15. States
16. Statistics
17. Timeline
18. Trip
19. Updates
20. Vampire Drain
21. Visited
22. Home (internal, landing page)
23. Dutch Tax Report (regional report — lower priority)

### B. Existing TeslaMate Database Tables

| Table | Purpose | Row Growth Rate |
|-------|---------|----------------|
| `cars` | Vehicle records | Static (1 per vehicle) |
| `car_settings` | Per-vehicle config | Static |
| `settings` | Global config | Static (1 row) |
| `positions` | GPS + vehicle state samples | **High** (~1 per second while driving) |
| `drives` | Driving sessions | ~2-6 per day |
| `charging_processes` | Charging sessions | ~1-2 per day |
| `charges` | Granular charge data | **Medium** (~1 per 30s while charging) |
| `states` | Online/offline/asleep | ~5-20 per day |
| `updates` | Firmware updates | ~1-2 per month |
| `addresses` | Geocoded locations | Grows with unique locations |
| `geofences` | User-defined areas | Static (user-managed) |
| `tokens` | Encrypted Tesla API tokens | Static (1 per auth) |

### C. MQTT Topics Published by TeslaMate

All topics follow the pattern `teslamate/cars/<car_id>/<key>`:

`display_name`, `state`, `since`, `healthy`, `latitude`, `longitude`, `heading`, `battery_level`, `charging_state`, `usable_battery_level`, `ideal_battery_range_km`, `est_battery_range_km`, `rated_battery_range_km`, `charge_energy_added`, `speed`, `outside_temp`, `inside_temp`, `is_climate_on`, `is_preconditioning`, `locked`, `sentry_mode`, `plugged_in`, `scheduled_charging_start_time`, `charge_limit_soc`, `charger_power`, `windows_open`, `doors_open`, `driver_front_door_open`, `driver_rear_door_open`, `passenger_front_door_open`, `passenger_rear_door_open`, `odometer`, `shift_state`, `charge_port_door_open`, `time_to_full_charge`, `charger_phases`, `charger_actual_current`, `charger_voltage`, `version`, `update_available`, `update_version`, `is_user_present`, `model`, `trim_badging`, `exterior_color`, `wheel_type`, `spoiler_type`, `trunk_open`, `frunk_open`, `elevation`, `power`, `charge_current_request`, `charge_current_request_max`, `tpms_pressure_fl/fr/rl/rr`, `tpms_soft_warning_fl/fr/rl/rr`, `climate_keeper_mode`, `center_display_state`, `location` (JSON), `geofence`, `active_route`, `active_route_destination`, `active_route_latitude`, `active_route_longitude`

### D. Tesla API Endpoints Used by TeslaMate

| Endpoint | Purpose |
|----------|---------|
| `GET /api/1/products` | List vehicles |
| `GET /api/1/vehicles/:id` | Get vehicle basic info |
| `GET /api/1/vehicles/:id/vehicle_data` | Get full vehicle state (charge, climate, drive, config, vehicle state) |
| `WSS /streaming/` | Real-time streaming (speed, odometer, SOC, elevation, heading, lat, lng, power, shift_state, range) |
| `POST /oauth2/v3/token` | Token refresh (via auth.tesla.com) |

---

*End of PRD*
