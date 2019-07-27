# Changelog

## [Unreleased]

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

[unreleased]: https://github.com/adriankumpf/teslamate/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/adriankumpf/teslamate/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/adriankumpf/teslamate/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/adriankumpf/teslamate/compare/3d95859...v1.0.0
