# TeslaMate iOS

A native iOS companion app for [TeslaMate](https://github.com/teslamate-org/teslamate), the self-hosted Tesla data logger.

TeslaMate iOS gives you a fast, native mobile interface to the data your TeslaMate instance already collects — vehicle status, drive history, and charging sessions — without replacing the existing web UI or Grafana dashboards.

## How It Works

This repo is a fork of TeslaMate with two additions:

1. **A JSON API layer** on the Elixir/Phoenix backend (`/api/v1/`) that exposes your existing TeslaMate data over authenticated REST endpoints and a real-time WebSocket channel.
2. **A SwiftUI iOS app** that connects to that API to display your vehicle data natively on iPhone and iPad.

Your TeslaMate instance continues to run exactly as before. The API is off by default and must be explicitly enabled. The iOS app is a read-only client — it does not write to your database or send commands to your car.

## Features

- **Live vehicle overview** — battery level, charge state, location, climate, sentry mode, doors/trunk/frunk status, and software version, updated in real time over WebSocket
- **Drive history** — paginated list of all drives with distance, duration, energy used, and route visualization on a map
- **Charge history** — charging sessions with energy added, cost, SoC progression, and charge curve charts
- **Multi-vehicle support** — switch between cars if your TeslaMate instance tracks more than one
- **Offline caching** — recently viewed data is cached locally via SwiftData so the app is usable without connectivity
- **Secure authentication** — JWT-based auth with tokens stored in the iOS Keychain; API gated behind a shared secret

## Architecture

```
┌─────────────┐         ┌──────────────────────────────────┐
│   iOS App   │◀──JWT──▶│         TeslaMate Server         │
│  (SwiftUI)  │   REST  │  ┌────────────┐  ┌───────────┐  │
│             │◀──WS───▶│  │ JSON API   │  │ Web UI    │  │
└─────────────┘         │  │ /api/v1/   │  │ (existing)│  │
                        │  └─────┬──────┘  └───────────┘  │
                        │        │                         │
                        │  ┌─────▼──────┐  ┌───────────┐  │
                        │  │  Postgres  │  │  Grafana   │  │
                        │  │  (data)    │  │ (existing) │  │
                        │  └────────────┘  └───────────┘  │
                        └──────────────────────────────────┘
```

The iOS app talks exclusively to the JSON API. It never touches Postgres or Grafana directly. The existing web interface and dashboards continue to work unchanged.

## Setup

### 1. Enable the API on your TeslaMate server

Add these environment variables to your TeslaMate deployment:

```env
ENABLE_API=true
API_AUTH_TOKEN=<a-strong-shared-secret>
```

Restart TeslaMate. The API will be available at `/api/v1/health`.

### 2. Connect the iOS app

Open the app, enter your TeslaMate server URL and the API auth token from step 1, and tap Connect. The app exchanges the token for a JWT and begins fetching data.

## Development

### Backend (Elixir)

The server runs in Docker — no local Elixir install needed. The API source lives in `lib/teslamate_web/api/`. Tests are in `test/teslamate_web/api/`.

```bash
docker compose up    # start TeslaMate + Postgres + Grafana
```

### iOS App

Open `ios/TeslaMateApp/TeslaMateApp.xcodeproj` in Xcode 16+. The app targets iOS 17.0 and has no external dependencies.

```bash
# Run tests from the command line
cd ios/TeslaMateApp
xcodebuild test \
  -project TeslaMateApp.xcodeproj \
  -scheme TeslaMateApp \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### CI

GitHub Actions runs both Elixir and iOS tests on every push and PR. See `.github/workflows/devops.yml`.

## Project Structure

```
lib/teslamate_web/api/     # JSON API controllers, auth, WebSocket channel
ios/TeslaMateApp/          # SwiftUI app (Models, Services, ViewModels, Views)
test/teslamate_web/api/    # Elixir API tests
ios/.../TeslaMateAppTests/ # iOS unit tests
```

## License

This project is a fork of [TeslaMate](https://github.com/teslamate-org/teslamate) and is licensed under the [GNU Affero General Public License v3.0](LICENSE).
