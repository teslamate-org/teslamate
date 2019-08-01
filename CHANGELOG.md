# Changelog

## [Unreleased]

## [1.4.2] - 2019-08-01

### Fixed

- Persists tokens after auto refresh

## [1.4.1] - 2019-07-31

### Fixed

- Convert to imperial measurements on status screen
- Fix warnings

## [1.4.0] - 2019-07-31

**1. New custom grafana image: `teslamate/grafana`**

Starting with this release there is a customized Grafana docker image
(`teslamate/grafana`) that auto provisions the datasource and dashboards which
makes upgrading a breeze! I strongly recommend to use it instead of manually
re-importing dashboards.

Just replace the `grafana` service in your `docker-compose.yml`:

```YAML
  # ...

  grafana:
    image: teslamate/grafana:latest
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=secret
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=db
    ports:
      - 3000:3000
    volumes:
      - teslamate-grafana-data:/var/lib/grafana

  # ...
```

And add a new volume at the bottom of the file:

```YAML
volumes:
    # ...
    teslamate-grafana-data:
    # ...
```

Find the full example in the updated README.

**2. Switch to imperial units globally**

![Settings](screenshots/settings.png)

There is a new settings view in the web interface. To use imperial measurements
in grafana and on the status screen just tick the checkbox it shows!

**3. Deprecation of TESLA_USERNAME and TESLA_PASSWORD**

With this release API tokens are stored in the database. After starting
TeslaMate v1.4 once, you can safely remove both environment variables.

New users need to sign in via the web interface.

**Full Changelog:**

### Dashboards

#### Added

- Introduce custom teslamate/grafana Docker image
- Fetch unit variables from database

#### Fixed

- Fix syntax errors in consumption and charging dashboard
- The consumption and charging dashboards can now be viewed without having to
  select a trip / charging process first.

#### Removed

- The German dashboard translations have been removed. It was too time
  consuming to keep everything up to date.

### TeslaMate

#### Added

- Show version on web UI
- Persist API tokens
- Add sign in view
- Add settings view

#### Changed

- Log :car_id

#### Fixed

- Fix generation of `secret_key_base`

## [1.3.0] - 2019-07-29

#### Changed

- Fix / inverse efficiency calculation: if distance traveled is less than the
  ideal rated distance the efficiency will now be lower than 100% and vice-versa.

  **Important: re-import the Grafana Dashboards (`en_efficiency` & `en_trips`) after restarting TeslaMate**

## [1.2.0] - 2019-07-29

#### Added

- Add psql conversion helper functions (**via database migration**)
- Report imperial metrics

  **Important: please re-import the Grafana Dashboards after restarting TeslaMate**

#### Fixed

- Remove TZ environment variable from Dockerfile

## [1.1.1] - 2019-07-27

#### Changed

- Upgrade tesla_api
- Upgrade Phoenix LiveView

#### Fixed

- Fix a few english translations in the en dashboards
- Remove `DATABASE_PORT` from docker-compose example
- Remove port mapping from postgres in docker-compose example
- Extend FAQ

## [1.1.0] - 2019-07-27

#### Added

- Support custom database port through `DATABASE_PORT` environment variable
- Add entrypoint to handle db migration

#### Changed

- Replace `node-sass` with `sass` to speed up compilation

#### Fixed

- Update README.md to fix resume and suspend logging PUT requests.

## [1.0.1] - 2019-07-26

#### Changed

- Set unique :id to support multiple vehicles
- Reduce default pool size to 5
- Install python in the builder stage to build on ARM
- Increase timeout used on assert_receive calls

## [1.0.0] - 2019-07-25

[unreleased]: https://github.com/adriankumpf/teslamate/compare/v1.4.2...HEAD
[1.4.2]: https://github.com/adriankumpf/teslamate/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/adriankumpf/teslamate/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/adriankumpf/teslamate/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/adriankumpf/teslamate/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/adriankumpf/teslamate/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/adriankumpf/teslamate/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/adriankumpf/teslamate/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/adriankumpf/teslamate/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/adriankumpf/teslamate/compare/3d95859...v1.0.0
