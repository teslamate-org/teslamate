# Changelog

## [Unreleased]

## [1.3.0] - 2019-07-29

### Changed

- Fix / inverse efficiency calculation: if distance traveled is less than the
  ideal rated distance the efficiency will now be lower than 100% and vice-versa.

  **Important: re-import the Grafana Dashboards (`en_efficiency` & `en_trips`) after restarting TeslaMate**

## [1.2.0] - 2019-07-29

### Added

- Add psql conversion helper functions (**via database migration**)
- Report imperial metrics

  **Important: please re-import the Grafana Dashboards after restarting TeslaMate**

### Fixed

- Remove TZ environment variable from Dockerfile

## [1.1.1] - 2019-07-27

### Changed

- Upgrade tesla_api
- Upgrade Phoenix LiveView

### Fixed

- Fix a few english translations in the en dashboards
- Remove `DATABASE_PORT` from docker-compose example
- Remove port mapping from postgres in docker-compose example
- Extend FAQ

## [1.1.0] - 2019-07-27

### Added

- Support custom database port through `DATABASE_PORT` environment variable
- Add entrypoint to handle db migration

### Changed

- Replace `node-sass` with `sass` to speed up compilation

### Fixed

- Update README.md to fix resume and suspend logging PUT requests.

## [1.0.1] - 2019-07-26

### Changed

- Set unique :id to support multiple vehicles
- Reduce default pool size to 5
- Install python in the builder stage to build on ARM
- Increase timeout used on assert_receive calls

## [1.0.0] - 2019-07-25

[unreleased]: https://github.com/adriankumpf/teslamate/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/adriankumpf/teslamate/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/adriankumpf/teslamate/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/adriankumpf/teslamate/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/adriankumpf/teslamate/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/adriankumpf/teslamate/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/adriankumpf/teslamate/compare/3d95859...v1.0.0
