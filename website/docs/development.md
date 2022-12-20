---
id: development
title: Development and Contributing
sidebar_label: Development and Contributing
---

## Requirements

- **Elixir** >= 1.12
- **Postgres** >= 10
- An **MQTT broker** e.g. mosquitto (_optional_)
- **NodeJS** >= 14

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

```bash
mix format
```

## Testing

To ensure a commit passes CI you should run `mix ci` locally, which executes the following commands:

- Check formatting (`mix format --check-formatted`)
- Run all tests (`mix test`)

## Making Changes to Grafana Dashboards

To update dashboards you need Grafana running locally. The following _docker-compose.yml_ can be used for this purpose:

```yml
version: "3"
services:
  grafana:
    image: teslamate-grafana:latest
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
