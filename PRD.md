# Product Requirements Document: TeslaMate iOS & iPadOS App

**Version:** 1.0
**Date:** 2026-02-23
**Status:** Draft

---

## 1. Executive Summary

This document defines the product requirements for a native iOS and iPadOS application that serves as a **companion to an existing TeslaMate installation**. The app does **not** replace TeslaMate or its Grafana dashboards — it runs alongside them, connecting to the same PostgreSQL database on the user's existing hardware (e.g. a Raspberry Pi), and provides a purpose-built native experience optimised for iPhone and iPad.

TeslaMate continues to handle all data collection, Tesla API communication, MQTT publishing, and Grafana dashboards as it does today. The iOS app adds a **read-optimised native layer** that queries the same database and delivers real-time vehicle monitoring, historical data visualisation, and comprehensive Tesla telemetry analytics — with future iOS-native features like push notifications, Live Activities, and widgets.

A lightweight API server will be deployed alongside the existing TeslaMate stack (on the same Raspberry Pi or home server), exposing a JSON API over the local network (and optionally via a reverse proxy for remote access). The iOS app distributed via the App Store connects to this API.

---

## 2. Problem Statement

TeslaMate is a powerful, self-hosted Tesla data logger with over 6,000 GitHub stars. It excels at data collection and storage but has UX limitations when accessed from mobile devices:

1. **No native mobile experience** — The web UI is a basic Phoenix LiveView interface for configuration only (sign-in, settings, geofences). All data visualisation depends on Grafana dashboards, which are not optimised for mobile.
2. **Poor mobile Grafana experience** — Grafana dashboards on a phone or tablet browser mean small text, no gestures, no offline capability, and no native interactions.
3. **No push notifications** — Users cannot receive alerts for charging completion, vampire drain, geofence events, software updates, or anomalies.
4. **No offline or at-a-glance access** — No widgets, no Apple Watch complications, no quick-glance capability.
5. **No iOS-native features** — No Live Activities for charging/driving, no Lock Screen widgets, no Siri Shortcuts.

**What works well today (and should be preserved):**
- TeslaMate's rock-solid data collection running 24/7 on a Raspberry Pi
- Full Grafana dashboard suite for desktop/power-user analysis
- MQTT integration for home automation
- Self-hosted, privacy-preserving architecture

---

## 3. Vision & Goals

### Vision
Provide the best native iOS/iPadOS companion experience for TeslaMate users — complementing (not replacing) the existing Grafana dashboards with a polished, touch-first app that brings iOS-native capabilities to the TeslaMate data they already have.

### Goals
| # | Goal | Success Metric |
|---|------|----------------|
| G1 | Native iOS access to TeslaMate data | 100% feature parity with all 23 Grafana dashboards, optimised for touch |
| G2 | Real-time vehicle monitoring on mobile | < 5 second latency from vehicle event to app display |
| G3 | Push notifications for key events | Charging complete, geofence enter/exit, vampire drain alert, software update available |
| G4 | iPad-optimised experience | Multi-column layouts, Split View & Slide Over support |
| G5 | Zero disruption to existing TeslaMate setup | Existing TeslaMate + Grafana + MQTT continue running unchanged |
| G6 | App Store distribution | Published on the iOS App Store |

### Non-Goals (Explicit)
- **Not replacing TeslaMate** — the app does not collect data from Tesla's API; TeslaMate continues to do that
- **Not replacing Grafana** — users can continue using Grafana on desktop alongside the iOS app
- **Not a cloud migration** — the primary deployment target is the user's existing hardware (Raspberry Pi, NAS, home server)

---

## 4. Target Audience

### Primary
- **Existing TeslaMate users** (like those running TeslaMate on a Raspberry Pi) who want a native iOS/iPad experience alongside their Grafana dashboards

### Secondary
- **Multi-vehicle TeslaMate users** who need to monitor multiple Tesla vehicles from their phone/tablet
- **Tesla enthusiasts** who want long-term battery health, efficiency, and cost tracking on the go

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

### 6.1 Design Philosophy: Companion, Not Replacement

The key architectural principle is **coexistence**. The user's existing TeslaMate stack (TeslaMate, PostgreSQL, Grafana, Mosquitto MQTT) continues running exactly as it does today. We add a **separate, lightweight API server** alongside it that:

1. **Reads from the same PostgreSQL database** (read-only connection by default)
2. **Subscribes to the same MQTT broker** for real-time vehicle state
3. **Serves a JSON API** to the iOS app over the local network
4. **Optionally exposes itself** via the user's existing reverse proxy for remote access

Nothing about the existing TeslaMate installation changes. If the companion API server is stopped or removed, TeslaMate and Grafana continue working exactly as before.

### 6.2 High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     Raspberry Pi / Home Server                     │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │               EXISTING (unchanged)                          │   │
│  │                                                             │   │
│  │  ┌──────────────┐    ┌──────────────┐    ┌─────────────┐   │   │
│  │  │  TeslaMate    │───▶│  PostgreSQL  │◀───│   Grafana    │   │   │
│  │  │  (Elixir)     │    │  Database    │    │  Dashboards  │   │   │
│  │  └──────┬───────┘    └──────▲───────┘    └─────────────┘   │   │
│  │         │                   │                               │   │
│  │         ▼                   │ (read-only)                   │   │
│  │  ┌──────────────┐          │                               │   │
│  │  │ MQTT Broker   │          │                               │   │
│  │  │ (Mosquitto)   │          │                               │   │
│  │  └──────┬───────┘          │                               │   │
│  └─────────┼──────────────────┼───────────────────────────────┘   │
│            │ (subscribe)      │                                    │
│  ┌─────────▼──────────────────┼───────────────────────────────┐   │
│  │            NEW: Companion API Server                        │   │
│  │            (lightweight service)                             │   │
│  │                                                             │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │   │
│  │  │ REST API      │  │ WebSocket    │  │ Push Notification│  │   │
│  │  │ (JSON)        │  │ (real-time)  │  │ Relay (APNs)     │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────────────┘  │   │
│  └─────────────────────────────┬──────────────────────────────┘   │
│                                │                                    │
└────────────────────────────────┼────────────────────────────────────┘
                                 │
                  LAN / Tailscale / Reverse Proxy
                                 │
                    ┌────────────┴───────────────┐
                    │                            │
              ┌─────▼─────┐              ┌──────▼──────┐
              │  iOS App   │              │  iPad App   │
              │ (SwiftUI)  │              │ (SwiftUI)   │
              └────────────┘              └─────────────┘
```

### 6.3 Companion API Server (New)

A **separate, lightweight service** deployed as an additional Docker container alongside the existing TeslaMate stack. It does NOT modify TeslaMate's code — it is an independent service that connects to the same infrastructure.

**Why a separate service (not a TeslaMate fork)?**
- **Zero risk to existing setup** — TeslaMate continues running unmodified
- **Independent release cycle** — API server can be updated without touching TeslaMate
- **Easy to add/remove** — Just add one container to `docker-compose.yml`
- **Read-only by default** — The API server connects to PostgreSQL with a read-only user, minimising risk to data integrity
- **Simpler maintenance** — No need to track upstream TeslaMate changes or manage fork conflicts

**Technology options for the API server:**
- **Option A: Elixir/Phoenix** — Same stack as TeslaMate; can reuse Ecto schemas; natural fit for WebSockets via Phoenix Channels
- **Option B: Go or Rust** — Lighter resource footprint on Raspberry Pi; but requires reimplementing data access
- **Recommended: Elixir/Phoenix** — Leverages the existing Ecto schema definitions, Phoenix Channels for real-time, and runs efficiently on the same BEAM VM ecosystem

#### Deployment: Adding to Existing Docker Compose

Users add one service to their existing `docker-compose.yml`:

```yaml
# Existing services (unchanged)
services:
  teslamate:
    image: teslamate/teslamate:latest
    # ... existing config ...

  database:
    image: postgres:16
    # ... existing config ...

  grafana:
    image: teslamate/grafana:latest
    # ... existing config ...

  mosquitto:
    image: eclipse-mosquitto:2
    # ... existing config ...

  # NEW: Companion API server for iOS app
  teslapulse-api:
    image: teslapulse/api:latest
    restart: unless-stopped
    environment:
      DATABASE_HOST: database
      DATABASE_NAME: teslamate
      DATABASE_USER: teslamate_readonly  # read-only DB user recommended
      DATABASE_PASS: ${DATABASE_PASS}
      MQTT_HOST: mosquitto
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      APNS_KEY_ID: ${APNS_KEY_ID}        # optional, for push notifications
      APNS_TEAM_ID: ${APNS_TEAM_ID}      # optional, for push notifications
    ports:
      - "4001:4001"   # API on a different port than TeslaMate's 4000
    depends_on:
      - database
      - mosquitto
```

Then add a route in the existing Cloudflare Tunnel config (`~/.cloudflared/config.yml`):

```yaml
ingress:
  # ... existing rules (e.g. API scraper) ...
  - hostname: teslapulse.yourdomain.com
    service: http://localhost:4001
  - service: http_status:404
```

The app is then configured with `https://teslapulse.yourdomain.com` — accessible from anywhere.

#### Network Access: Single URL via Cloudflare Tunnel

The app connects to a single HTTPS URL regardless of network — at home on WiFi, on cellular, or anywhere else. The user's existing Cloudflare Tunnel on the Raspberry Pi handles all routing and TLS.

**How it works:**
1. User already has `cloudflared` running on the Pi (for their existing API scraper)
2. Add one route to the tunnel config pointing a subdomain to the companion API (e.g. `teslapulse.yourdomain.com → localhost:4001`)
3. App is configured once with `https://teslapulse.yourdomain.com` — works everywhere, always HTTPS

**Benefits:**
- **One URL, always works** — no switching between LAN/remote, no split-DNS logic in the app
- **TLS built-in** — Cloudflare manages certificates automatically
- **No port forwarding** — tunnel handles everything
- **WebSocket support** — Cloudflare Tunnels support WebSocket connections for real-time updates
- **Already deployed** — user already has the tunnel infrastructure running

**LAN latency trade-off:** Requests from the iPad on the same WiFi network take a small detour through Cloudflare's edge (~10-30ms added). This is negligible for a dashboard app.

**Alternative access methods** (for users without Cloudflare Tunnel):

| Method | Complexity | Notes |
|--------|-----------|-------|
| **Tailscale** | Low | Mesh VPN; free for personal use; no port forwarding |
| **Reverse proxy + DDNS** | Medium | User's own Nginx/Caddy with Let's Encrypt |
| **Direct LAN** | Lowest | `http://raspberrypi.local:4001` — home network only, no TLS |

The app's settings screen lets users configure the server URL once during onboarding.

#### API Design Principles
- RESTful JSON API with versioned endpoints (`/api/v1/...`)
- Token-based authentication (JWT or Phoenix token) — **not** Tesla credentials (those stay in TeslaMate)
- WebSocket channel for real-time updates (powered by MQTT subscription on the backend)
- Read-only database access by default; write operations limited to app-specific data (notification preferences, display settings)
- Pagination, filtering, and date range support on all list endpoints
- OpenAPI 3.0 specification for documentation

#### Core API Endpoints

All endpoints are served by the companion API server (not TeslaMate itself). The companion API reads from the shared PostgreSQL database.

| Category | Endpoint | Method | Description |
|----------|----------|--------|-------------|
| **Auth** | `/api/v1/auth/login` | POST | Authenticate with companion API, return JWT |
| **Auth** | `/api/v1/auth/refresh` | POST | Refresh JWT token |
| **Health** | `/api/v1/health` | GET | Health check (DB connection, MQTT status, TeslaMate version) |
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

### 6.4 Connectivity Model

The app uses a **single server URL** configured once during onboarding. The recommended setup is a **Cloudflare Tunnel** subdomain (e.g. `https://teslapulse.yourdomain.com`) which works identically from any network.

From the app's perspective, connectivity is simple:
1. User enters their server URL in settings
2. App connects to that URL for REST API calls and WebSocket
3. If connection drops, app shows cached data with a "Last updated X ago" indicator and retries with exponential backoff
4. When connection resumes, real-time updates resume automatically

There is no LAN-vs-remote switching logic in the app — the URL is the URL. How that URL resolves (Cloudflare Tunnel, Tailscale, direct LAN, VPN) is the user's infrastructure concern, handled once at setup time.

### 6.5 Future: Optional Cloud Deployment

A future phase may offer cloud-hosted deployment for users who don't want to self-host, but this is **not** the primary use case. The architecture is Docker-based and cloud-agnostic. Potential providers if a hosted option is explored:
- European sovereign cloud (Evroc, Scaleway, Hetzner, OVH)
- Standard providers (any VPS or container hosting)

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

**Data Source:** `GET /api/v1/cars/:id/summary` (from PostgreSQL) + WebSocket real-time channel (from MQTT relay)

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
- **Server connection:**
  - Server URL (e.g. `https://teslapulse.yourdomain.com`) — configured once during onboarding
  - Connection status indicator (connected / disconnected / error)
  - Test connection button
  - API token / authentication
- **Notifications:** Toggle per notification type
- **Data management:** Export data
- **About:** Version, licenses, source code link, TeslaMate version detected

---

### 7.4 Real-Time Updates

The companion API server subscribes to TeslaMate's existing MQTT topics and relays updates to connected iOS clients via WebSocket (Phoenix Channel). This means:
- **No changes to TeslaMate** — it already publishes to MQTT
- **No additional Tesla API calls** — all data flows through the existing pipeline
- **Low latency** — MQTT → API server → WebSocket → iOS app (typically < 2 seconds)

**Channel:** `car:<car_id>`

**Events pushed to client (sourced from MQTT topics):**
| Event | Payload | MQTT Source Topics |
|-------|---------|-------------------|
| `summary` | Full vehicle summary | Multiple `teslamate/cars/<id>/*` topics |
| `position` | lat, lon, speed, power, elevation | `latitude`, `longitude`, `speed`, `power`, `elevation` |
| `charge_update` | SOC, power, voltage, current, energy | `battery_level`, `charger_power`, `charger_voltage`, `charge_energy_added` |
| `state_change` | New state (online/offline/asleep/driving/charging) | `state` |
| `geofence` | Geofence entered/exited | `geofence` |

**Reconnection:** Exponential backoff (1s, 2s, 4s, 8s... max 30s), automatic resume on network change.

### 7.5 Push Notifications

Push notifications are delivered via APNs (Apple Push Notification service) from the companion API server. The API server monitors MQTT topics for trigger conditions and sends push notifications to registered iOS devices. This requires the user to configure APNs credentials (provided via the app's onboarding flow).

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

### 7.6 Live Activities (Phase 3)

Live Activities display real-time information on the Lock Screen and Dynamic Island while an event is in progress.

| Activity | Trigger | Lock Screen Display | Dynamic Island (Compact) |
|----------|---------|-------------------|------------------------|
| **Charging** | Charging session starts | SOC gauge filling, current power, time remaining, energy added | SOC % + time remaining |
| **Driving** | Drive starts (shift state != P) | Speed, distance from start, current efficiency, elapsed time | Speed + distance |
| **Software Update** | Update starts installing | Version number, progress indicator | Update progress % |

**Data Flow:** Companion API server detects state changes via MQTT → sends push notification with Live Activity payload → iOS updates the Live Activity in real-time via subsequent pushes.

### 7.7 Widgets (WidgetKit)

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

### 7.8 Offline Support

- **SwiftData local cache:** Recent summaries, last 30 drives, last 30 charges cached locally
- **Graceful degradation:** App shows cached data with "Last updated X ago" indicator when offline
- **Background refresh:** Periodic background fetch to update cached data and widgets
- **Offline-first widgets:** Widgets always show the most recent cached data

### 7.9 Accessibility

- Full VoiceOver support on all screens
- Dynamic Type support (all text sizes)
- Sufficient colour contrast ratios (WCAG AA)
- Chart accessibility: data table alternatives for all charts
- Reduce Motion support (minimise animations)

### 7.10 Multi-Vehicle Support

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
| API authentication | JWT tokens for companion API, stored in iOS Keychain |
| Token refresh | Automatic refresh before expiry |
| Data in transit | TLS 1.3 minimum — always HTTPS via Cloudflare Tunnel (recommended setup) |
| Data at rest (device) | iOS Data Protection (NSFileProtectionComplete) |
| Tesla credentials | **Never touched by the companion API or iOS app** — they remain encrypted in TeslaMate's database, managed solely by TeslaMate |
| Certificate pinning | Pin backend server certificate (when using TLS) |
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
- **Companion API server** as a Docker container (connects to existing PostgreSQL + MQTT)
- Docker Compose snippet for easy addition to existing TeslaMate stack
- Core API endpoints (cars, drives, charges, positions, summary)
- iOS app with: Overview, Drives (list + detail + map), Charges (list + detail), Settings (including server URL configuration)
- Simple authentication (API token or basic auth for the companion API)
- Real-time updates via WebSocket (sourced from MQTT, through Cloudflare Tunnel)
- Basic offline caching
- Single vehicle support
- Connectivity via Cloudflare Tunnel (single HTTPS URL, works from any network)

### Phase 2: Full Dashboard Parity
- All remaining dashboard screens (Battery Health, Charging Stats, Drive Stats, Efficiency, Mileage, Projected Range, States, Timeline, Statistics, Trip, Updates, Vampire Drain, Visited)
- Multi-vehicle support
- Geofence management (CRUD with map — writes to the shared PostgreSQL database)
- Charge cost editing
- iPad optimised layouts (NavigationSplitView, multi-column)

### Phase 3: Native iOS Features
- Push notifications (all types) — requires APNs relay in companion API server
- WidgetKit widgets (Home Screen, Lock Screen, StandBy)
- Live Activities (charging progress on Lock Screen / Dynamic Island, drive in progress)
- GPX export / share
- Biometric app lock
- Full internationalisation
- App Store submission

### Phase 4: Advanced Features (Post-Launch)
- Apple Watch app (glanceable SOC, state, notifications)
- Siri Shortcuts integration ("Hey Siri, what's my Tesla's battery?")
- CarPlay dashboard (if applicable)
- Vehicle commands (lock/unlock, climate control, charge port, etc.) — requires Tesla Fleet API partner authentication and goes beyond read-only access
- Data export (CSV, JSON)
- Comparison analytics (vehicle vs vehicle, period vs period)
- Optional cloud-hosted deployment for non-self-hosting users

---

## 11. Dependencies & Risks

### Dependencies

| Dependency | Risk Level | Mitigation |
|-----------|-----------|------------|
| Existing TeslaMate installation | Required | App is designed for users who already run TeslaMate. Clear documentation and setup guides. |
| TeslaMate database schema stability | Medium | Monitor TeslaMate releases for schema changes. Pin to supported TeslaMate versions. |
| PostgreSQL access from companion service | Low | Standard Docker networking. Read-only DB user for safety. |
| MQTT broker access | Low | Companion API subscribes to existing MQTT topics published by TeslaMate. |
| Apple App Store approval | Medium | Follow Apple guidelines strictly. Source code link in app for AGPL compliance. |
| Raspberry Pi resource headroom | Medium | Profile companion API server memory/CPU on Pi 4. Keep it lightweight. |

### Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| TeslaMate schema changes break companion API | Medium | High | Version-pin supported TeslaMate versions. Integration tests against TeslaMate DB schema. |
| Companion API server too heavy for Raspberry Pi | Low-Medium | Medium | Profile aggressively. Consider Go/Rust if Elixir/Phoenix is too heavy. Target < 128MB RAM. |
| Cloudflare Tunnel WebSocket reliability | Low | Medium | Cloudflare supports WebSockets. Test long-lived Phoenix Channel connections. Implement reconnection with exponential backoff on the iOS client. |
| Performance issues with large datasets (years of positions) | Medium | Medium | Server-side pagination, aggregation queries, database indexes. SwiftData for client-side caching with TTL. |
| AGPL license dispute | Low | Medium | Companion API is an independent service (not a TeslaMate fork). Engage with community. Open-source the API server. |

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
| 2 | **Companion API server technology** — Elixir/Phoenix (recommended for Ecto schema reuse) vs Go/Rust (lighter on Raspberry Pi). Profile resource usage on Pi. | Phase 1 |
| 3 | **Database write access** — Should the companion API be strictly read-only, or also handle writes (geofence CRUD, charge cost editing)? Writes require a shared-write DB user. | Phase 1 |
| 4 | **Push notification architecture** — APNs requires server-side credentials. Should we bundle a relay service, or use a third-party push service (e.g. ntfy.sh, Pushover) as an interim? | Phase 3 |
| 5 | **AGPL compliance for iOS app** — The companion API server reads from TeslaMate's database (not TeslaMate's code). Likely independent work. Legal review still recommended. | Before App Store submission |
| 6 | **Vehicle commands in scope?** — Phase 4 lists commands (lock, climate, etc.). This goes beyond read-only and requires Tesla Fleet API partner registration. Confirm priority. | Before Phase 4 |
| 7 | **Monetisation model** — Free? Freemium? One-time purchase? Since it's self-hosted, recurring subscription may not fit. | Before App Store submission |
| 8 | **Raspberry Pi resource budget** — How much CPU/RAM overhead is acceptable for the companion API server on a Pi 4 that's already running TeslaMate + Grafana + Mosquitto + PostgreSQL? | Phase 1 |
| 9 | **WebSocket over Cloudflare Tunnel** — Verify Phoenix Channel WebSocket connections work reliably through Cloudflare Tunnel (they should, but needs testing with long-lived connections and reconnection). | Phase 1 |

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
