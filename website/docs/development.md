---
id: development
title: Development and Contributing
sidebar_label: Development and Contributing
---

## Requirements

- **Elixir** >= 1.17.3-otp-26
- **Postgres** >= 17
- An **MQTT broker** e.g. mosquitto (_optional_)
- **NodeJS** >= 20.15.0

or [Nix](https://nixos.org/download/). You can then use the nix devenv (via direnv) setup.

## Initial Setup

To run the TeslaMate test suite you need a database named `teslamate_test`:

```bash
# download dependencies, create the dev database and run migrations
mix setup

# create the test database
MIX_ENV=test mix ecto.setup
```

## Running locally

Start an iex session in another terminal window:

```elixir
iex -S mix phx.server
```

Then sign in with a Tesla account.

## Hot reloading

To immediately apply your local changes open or reload [http://localhost:4000](http://localhost:4000). You can also reload specific modules via `iex`, for example:

```elixir
iex> r TeslaMate.Vehicles.Vehicle
```

To only compile the changes:

```bash
mix compile
```

## Code formatting

### Format all files

Install [Treefmt](https://github.com/numtide/treefmt/releases) or use the nix devenv (via direnv) setup.

```bash
treefmt
```

You can even use a VS Code extension like [treefmt](https://marketplace.visualstudio.com/items?itemName=ibecker.treefmt-vscode) to format the files on save.

### Only format elixir files

```bash
mix format
```

## Update pot files (extract messages for translation)

```bash
mix gettext.extract --merge
```

## Testing

To ensure a commit passes CI you should run `mix ci` locally, which executes the following commands:

- Check formatting (`mix format --check-formatted`)
- Run all tests (`mix test`)

### Testing with our CI which builds the Docker images automatically per PR

Our CI automatically builds the Docker images for each PR. To test the changes introduce by a PR you can edit your docker-compose.yml file as follows (replace `pr-3836` with the PR number):

For TeslaMate:

```yml
teslamate:
  # image: teslamate/teslamate:latest
  image: ghcr.io/teslamate-org/teslamate:pr-3836
```

For Grafana:

```yml
grafana:
  # image: teslamate/grafana:latest
  image: ghcr.io/teslamate-org/teslamate/grafana:pr-3836
```

## Making Changes to Grafana Dashboards

To update dashboards you need Grafana running locally. The following _docker-compose.yml_ can be used for this purpose:

```yml
services:
  grafana:
    image: teslamate/grafana:latest
    environment:
      - DATABASE_USER=postgres
      - DATABASE_PASS=postgres
      - DATABASE_NAME=teslamate_dev
      - DATABASE_HOST=host.docker.internal
    ports:
      - 3000:3000
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  grafana-data:
```

_(on Linux use the actual IP address of the host as `DATABASE_HOST`instead of `host.docker.internal`)_

Then build the image with `make grafana` and run the container via `docker compose up grafana`.

Access the Grafana at [http://localhost:3000](http://localhost:3000) and sign in with the default user `admin` and password `admin`.

Then edit the respective dashboard(s) locally. To export a dashboard hit the 'Save' button and select `Save JSON to file`. The final JSON file belongs in the directory `./grafana/dashboards/`. To apply the changes rebuild the image and start the container.

### Grafana VS Code Extension

The Grafana VS Code extension allows you to open Grafana dashboards as JSON files in VS Code, and preview them live with data from a Grafana instance of your choice.

- Open a Grafana dashboard JSON file
- Start a live preview of that dashboard inside VS Code, connected to live data from a Grafana instance of your choice
- Edit the dashboard in the preview, using the normal Grafana dashboard editor UI
- From the editor UI, save the updated dashboard back to the original JSON file

see: [grafana-vs-code-extension](https://github.com/grafana/grafana-vs-code-extension)

## Best Practices

### Queries involving timestamp columns

Datetime values are currently stored in columns of type `timestamp`. [This is NOT recommended](https://wiki.postgresql.org/wiki/Don't_Do_This#Don.27t_use_timestamp_.28without_time_zone.29_to_store_UTC_times).

While [Grafana macros](https://grafana.com/docs/grafana/latest/datasources/postgres/#macros) like `$__timeFilter` & `$__timeGroup` are working PostgreSQL functions like `DATE_TRUNC()` require additional treatment.

```sql
DATE_TRUNC('day', TIMEZONE('UTC', date))
```

In addition ensure to compare either values with or without time zone.

### Streaming API data / positions table usage in dashboard queries

When Streaming API is enabled roughly 1 GB of data is gathered per car and 30.000km. Most of that data (95+ percent) is stored in positions table. For optimal dashboard performance these recommendations should be followed:

- only query positions table when really needed
- if data in 15 second intervals is sufficient consider excluding streaming data by adding `ideal_battery_range_km IS NOT NULL and car_id = $car_id` as WHERE conditions

Before opening pull requests please diagnose index usage & query performance by making use of `EXPLAIN ANALYZE`.

### Enable _pg_stat_statements_ to collect query statistics

To quickly identify performance bottlenecks we encourage all contributors to enable the pg_stat_statements extension in their instance. For docker based installs you can follow these steps:

- Enable the pg_stat_statements module

  ```yml
  services:
    database:
      image: postgres:17
      ...
      command: postgres -c shared_preload_libraries=pg_stat_statements
      ...
  ```

- Create Extension to enable `pg_stat_statements` view

  ```sql
  CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
  ```

- Identify potentially slow queries (mean_exec_time)

  ```sql
  SELECT query, calls, mean_exec_time, total_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;
  ```

- Identify frequently executed queries (calls)

  ```sql
  SELECT query, calls, mean_exec_time, total_exec_time FROM pg_stat_statements ORDER BY calls DESC LIMIT 10;
  ```

Additional details about pg_stat_statements can be found here: https://www.postgresql.org/docs/current/pgstatstatements.html
