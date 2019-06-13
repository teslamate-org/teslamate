# TeslaMate

To start your Phoenix server:

- Install dependencies with `mix deps.get`
- Create and migrate your database with `mix ecto.setup`
- Install Node.js dependencies with `cd assets && npm install`
- Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Dashboards

### Prerequisites

1. Download and install wizzy: [Installation](https://utkarshcmu.github.io/wizzy-site/home/getting-started/)
2. Configure grafana properties:

```bash
wizzy set grafana url http://localhost:3000
wizzy set grafana username admin
wizzy set grafana password password
```

### Backup Dashboards

To backup (import) all dashboards from grafana run: `wizzy import dashboards`.

### Restore Dashboards

To restore (export) all dashboards to grafana run: `wizzy export dashboards`.
