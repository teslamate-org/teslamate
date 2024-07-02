---
id: development
title: Development and Contributing
sidebar_label: Development and Contributing
---

## Requirements

- **Elixir** >= 1.16.2-otp-26
- **Postgres** >= 16
- An **MQTT broker** e.g. mosquitto (_optional_)
- **NodeJS** >= 20.15.0

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
      image: ghcr.io/teslamate-org/teslamate/teslamate:pr-3836
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

### Grafana VS Code Extension

The Grafana VS Code extension allows you to open Grafana dashboards as JSON files in VS Code, and preview them live with data from a Grafana instance of your choice.

- Open a Grafana dashboard JSON file
- Start a live preview of that dashboard inside VS Code, connected to live data from a Grafana instance of your choice
- Edit the dashboard in the preview, using the normal Grafana dashboard editor UI
- From the editor UI, save the updated dashboard back to the original JSON file

see: [grafana-vs-code-extension](https://github.com/grafana/grafana-vs-code-extension)
