---
title: Runtime health
---

TeslaMate exposes an aggregate runtime health response at `GET /api/health`.
It checks the database and reports whether the vehicle logger, Tesla API,
streaming connection, and MQTT path are current enough to trust.

```json
{
  "schema_version": 1,
  "status": "ok",
  "mqtt": { "status": "ok" },
  "vehicles": { "total": 1, "ok": 1, "degraded": 0 }
}
```

The public response does not include vehicle IDs, logger states, timestamps,
failure reasons, or vehicle data. Detailed component state stays inside the
TeslaMate process.

The endpoint returns HTTP 503 when the database or runtime health collector is
unavailable. A collected response returns HTTP 200 and uses its `status` field
to distinguish `ok` from `degraded`. Responses include `Cache-Control:
no-store` so a proxy does not reuse an old liveness result.

The existing `GET /health_check` endpoint is unchanged.
