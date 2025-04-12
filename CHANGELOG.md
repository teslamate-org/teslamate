# Changelog

## [unreleased]

### New features

### Improvements and bug fixes

#### Build, CI, internal

- build(deps): bump image-size from 1.2.0 to 1.2.1 in /website (#4622)
- ci: switch to cache-nix-action as Magic Nix Cache is deprecated (#4626 - @JakobLichterfeld)
- build(deps): update flake.lock (#4603)
- build(deps): bump crate-ci/typos from 1.30.0 to 1.31.1 (#4611)
- build(deps): bump docker/login-action from 3.3.0 to 3.4.0 (#4612)
- build(deps): bump actions/cache from 4.2.2 to 4.2.3 (#4613)
- build(deps): bump tesla from 1.13.2 to 1.14.1 (#4616)
- ci(sec): remove pull_request_target workflow triggers to improve sec even further, the downside is that test images are now only created for repo's own PRs (#4637 - @JakobLichterfeld / Thanks to @Firebasky for responsibly disclosing the vulnerability)
- ci: fix ghcr build ([..ddf85e6](https://github.com/teslamate-org/teslamate/commit/ba35f417014e6be742ee2b0713cfa7876ddf85e6) - @JakobLichterfeld)
- ci: ensure ghcr images build correctly even if branch contains backslash (#4655 - @JakobLichterfeld)

#### Dashboards

- fix: improve calc for usable (now) in battery health dashboard (#4644 - @swiffer)
- feat: make use of car filter, add timefilter in locations dashboard (#4647 - @swiffer)

#### Translations

#### Documentation

- chore(issue-template): add PostgreSQL version input and checkbox for latest version check in bug report template (#4643 - @JakobLichterfeld)

## [1.33.0] - 2025-03-28

As always, there are many improvements.

We now use Grafana 11.6.0 which was release the last days, improved the logging and state transitions, added a new dashboard for database information and improved other dashboards. We also added a new section to the documentation about the Entity Relationship Model (ERM) of TeslaMate. This is a great help for developers who want to understand the data model of TeslaMate and how to extend it.

Enjoy it.

### New features

### Improvements and bug fixes

- fix(nix): wait for mosquitto to start before starting teslamate (#4419 - @brianmay)
- feat: use Grafana 11.4.0 (#4299 - @swiffer)
- feat: improve logging messages (#4467 - @micves and @brianmay)
- feat: optimize state transitions (#4473 - @micves and @brianmay)
  - don't try to sleep if power > 0
  - cancel an ongoing suspended state/trying to sleep and go back to online
  - add conditions to enter charging
- feat: support accessing PostgreSQL on unix domain sockets (#4456 - @j-baker)
- fix(nix): temporarily disable browser locale in date formats for nix deployment as well (#4480 - @swiffer)
- feat: Grafana 11.5.0 (#4509 - @swiffer)
- feat: Grafana 11.5.2 (#4551 - @swiffer)
- fix(nix): update mix dependency hash in nix builds. (#4577 - @weiren2)
- feat: Grafana 11.6.0 (#4570 - @swiffer)

#### Build, CI, internal

- build(deps): bump castore from 1.0.9 to 1.0.10 (#4414)
- build(deps): bump @docusaurus/preset-classic from 3.5.2 to 3.6.3 in /website (#4412)
- build(deps): bump path-to-regexp from 1.8.0 to 1.9.0 in /website (#4424)
- build(deps): bump crate-ci/typos from 1.27.0 to 1.28.1 (#4411)
- build(deps): bump tesla from 1.13.0 to 1.13.2 (#4416)
- build(deps): bump postgrex from 0.19.1 to 0.19.3 (#4415)
- build(nix): switch to nixos-24.11 (#4420 - @brianmay)
- build(deps): update flake.lock (#4427)
- fix: update mix deps hash to fix build error on recent NixOS 24.11 update (#4428)
- build(deps): bump path-to-regexp and express in /website (#4433)
- build(deps): update flake.lock (#4440)
- build(deps): bump actions/cache from 4.1.2 to 4.2.0 (#4465)
- build(deps): bump phoenix from 1.7.14 to 1.7.18 (#4462)
- build(deps-dev): bump dialyxir from 1.4.4 to 1.4.5 (#4460)
- build(deps): bump ex_cldr from 2.40.1 to 2.40.2 (#4461)
- build(deps): bump crate-ci/typos from 1.28.1 to 1.29.0 (#4464)
- ci: update actions/cache to v4.2.0 ([79107d5](https://github.com/teslamate-org/teslamate/commit/79107d53b7712934587bbe40c503e63d5dd9f122) - @JakobLichterfeld)
- build(deps): bump DeterminateSystems/magic-nix-cache-action from 8 to 9 (#4515)
- build(deps): bump actions/stale from 9.0.0 to 9.1.0 (#4516)
- build(deps): bump crate-ci/typos from 1.29.0 to 1.29.5 (#4514)
- build(deps-dev): bump excoveralls from 0.18.3 to 0.18.5 (#4524)
- build(deps-dev): bump credo from 1.7.8 to 1.7.11 (#4523)
- build(deps): bump @docusaurus/preset-classic from 3.6.3 to 3.7.0 in /website (#4518)
- build(deps): bump serialize-javascript from 6.0.1 to 6.0.2 in /website (#4548)
- build(deps): update flake.lock (#4455)
- style(markdownlint): allow 'details', 'summary', and 'TabItem' elements ([d5b1a55](https://github.com/teslamate-org/teslamate/commit/d5b1a55007eefedd5d852ecd50d67b8c4d36faa5) - @JakobLichterfeld)
- style(environment_variables): remove multiple whitespaces ([603ff82](https://github.com/teslamate-org/teslamate/commit/603ff824b052b4465fcce9fe77e5e40ad586c07a) - @JakobLichterfeld)
- style(docs): fix line length fenced-code-style, no bare url links, multiple whitespaces, alt text, header style ([1972584](https://github.com/teslamate-org/teslamate/commit/1972584d8f9d11c2f640de046a8e9fd47b43c4fb) - @JakobLichterfeld)
- build(deps): bump actions/cache from 4.2.0 to 4.2.2 (#4564)
- build(deps): bump crate-ci/typos from 1.29.5 to 1.30.0 (#4563)
- build(deps): bump castore from 1.0.11 to 1.0.12 (#4565)
- build(deps): bump plug_cowboy from 2.7.2 to 2.7.3 (#4566)
- build(deps): bump prismjs from 1.29.0 to 1.30.0 in /website (#4582)
- build(deps): bump @babel/runtime from 7.26.0 to 7.26.10 in /website (#4589)
- build(deps): bump @babel/helpers from 7.26.7 to 7.26.10 in /website (#4588)
- build(deps): bump @babel/runtime-corejs3 in /website (#4587)
- build(deps): update flake.lock (#4562)

#### Dashboards

- fix: for battery health dashboard erroring out if no charge data has been collected so far (#4448 - @swiffer)
- fix: url for releases in home dashboard (#4452 -@FLX3009)
- feat: add 0 as lower bound for gauge to ensure proper scaling (#4498 - @swiffer)
- feat(dashboards): improve elevation scale in drive stats (#4546 - @swiffer)
- feat: add Database Information Dashboard (#4578 - @jheredianet)

#### Translations

- feat: Translate remaining Spanish sentences (#4529 - @jheredianet)

#### Documentation

- doc: bump elixir based on availability (#4431 - @swiffer)
- doc: align node req with what is used in CI (#4430 - @swiffer)
- doc: added missing topic "charging_state" in mqtt doc (#4466 - @Beme99)
- docs: Grafana 11.4 for manual install on FreeBSD (#4474 - @swiffer)
- doc: Fixing typo for sensor psi calculation (#4470 - @Phazz)
- doc: Simplify Home Assistant sensors, add device_class to allow changing measurement units (#4472 - @longzheng)
- docs: add reindexing instructions for database maintenance to improve performance in case of index bloat due to frequent updates or deletions (#4558 and #4574 - @jheredianet)
- docs: Update projects using TeslaMate (#4573 - @jheredianet)
- docs: fix and rearrange screenshot links (alphabetical) (#4580 - @swiffer)
- docs: enhance TeslaFi import documentation with updated Python script for bulk data export (#4575 - @TheLinuxGuy and @JakobLichterfeld)
- docs: add Entity Relationship Model section to development documentation (#4586 - @DrMichael and @JakobLichterfeld)

## [1.32.0] - 2024-11-23

As always, there are many improvements. The focus has been on quality of life improvements and standardization across all dashboards. Enjoy it.

### New features

### Improvements and bug fixes

- feat: use Grafana 11.2.3 (#4338 - @swiffer)
- feat: Update marketing name to recognize Model S LR+ (#4370 - @cwanja)
- fix(nix): bump hash for dependencies (#4371 - @brianmay)

#### Build, CI, internal

- ci: remove unknown flag --ref for gh cache delete in cleanup_caches workflow ([3a515df](https://github.com/teslamate-org/teslamate/commit/3a515df5aa400139acf8ef638e5ae37339c553cf) - @JakobLichterfeld)
- build(deps): bump actions/checkout from 4.2.1 to 4.2.2 (#4340)
- build(deps): bump actions/cache from 4.0.2 to 4.1.2 (#4341)
- build(deps): bump cachix/install-nix-action from 27 to 30 (#4342)
- build(deps): bump tesla from 1.12.1 to 1.13.0 (#4335)
- build(deps): bump floki from 0.36.2 to 0.36.3 (#4336)
- feat: add CONTRIBUTING file to exclusion lists for treefmt (#4359 - @JakobLichterfeld)
- ci: create PR to update flake.lock every saturday (#4372 - @brianmay)
- ci(fix): correct permissions for flake.lock updates ([c673ef3](https://github.com/teslamate-org/teslamate/commit/c673ef363ba73ad076680d71ef54bd549582d41f)- @JakobLichterfeld)
- ci: update flake.lock workflow with appropriate labels for created pr's ([54c41c1](https://github.com/teslamate-org/teslamate/commit/54c41c1fe66664b62d817502d1b2bdb244b70dc2) - @JakobLichterfeld)
- build(deps): bump cross-spawn from 7.0.3 to 7.0.6 in /website (#4391)
- build(deps): bump crate-ci/typos from 1.26.0 to 1.27.0 (#4344)
- build(deps): update flake.lock (#4381)

#### Dashboards

- fix: allow editing of dashboards - [changes will be overwritten on update](https://grafana.com/docs/grafana/latest/administration/provisioning/#making-changes-to-a-provisioned-dashboard) (#4338 - @swiffer)
- fix: ensure max speed panels are converted according to length unit setting in drive stats dashboard (#4338 - @swiffer)
- perf: speed up queries used to calculate max speed in drive stats dashboard (#4338 - @swiffer)
- feat: add a welcome dashboard (#4338 - @swiffer)
- fix: Charges Dashboard -> Range added renamed to Ø Charge rate (#4349 - @swiffer)
- fix: Axis Labels for XY Chart in Battery Health and reduces Query count in Visited (#4364 - @swiffer)
- feat: Dashboard refinements and standardization (#4367 - @swiffer)
- feat: add Detailed Energy Use to drive-details (#4386 - @jameskitt616)

#### Translations

#### Documentation

docs: add contributing guidelines link for GitHub (#4345 - @JakobLichterfeld)
docs: update Home Assistant integration documentation with configuration URL and model name hints (#4359 - @JakobLichterfeld)
docs: Remove availability from Home Assistant MQTT sensors, as it can be misleading and prevent sensors from receiving updated values (#4362 - @longzheng)
docs: Introducing TeslaMate Guru on Gurubase.io (#4390 - @kursataktas)

## [1.31.1] - 2024-10-29

This release primarily prevents beam.smp from overloading the CPU on ARM hosts. It also includes a number of other bug fixes and performance improvements. Enjoy it.
Please also note: [v1.31.0 Release Notes](https://github.com/teslamate-org/teslamate/releases/tag/v1.31.0)

### New features

### Improvements and bug fixes

- fix: use elixir-1.17.3-otp-26 to avoid beam.smp chewing CPU on arm (#4319 - @brianmay, @swiffer and @JakobLichterfeld)

#### Build, CI, internal

- ci(fix): update cleanup_caches.yml to use new cache management commands and fix permissions ([d6793ce](https://github.com/teslamate-org/teslamate/commit/d6793ce5717687b9e984067bf4c208415e15fdac), [b0b694f](https://github.com/teslamate-org/teslamate/commit/b0b694fc8c3c45036aafda45200f3b0d068a2f50), [16bb503](https://github.com/teslamate-org/teslamate/commit/16bb5032c7d81cb86e76cc19662e3332456291a0) - @JakobLichterfeld)
- ci: Add workflow to manually cleanup largest 100 caches ([dad7e3d](https://github.com/teslamate-org/teslamate/commit/dad7e3dea0ae1d799398bf1b31a0d598eff784bf), [523419d](https://github.com/teslamate-org/teslamate/commit/523419d35a610c7b06bbf7e9c2edd105e7d089aa) - @JakobLichterfeld)

#### Dashboards

- perf: add ideal_battery_range_km as query condition (#4305 - @swiffer)
- fix: re-add missing changes from pr 4124 (#4310 - @swiffer)
- feat: add max speed & speed histogram to drive stats (#4253 - @js94x)
- fix: remove convert_km from kwh calculations in timeline dashboard (#4318 - @swiffer)
- fix: ensure dutch-tax dashboard is not repeating multiple times per car (row and table) (#4317 - @swiffer)

#### Translations

- Update default.po for thai (#4312 - @tomzt)
- Spanish translation of missing items (#4320 -@ferminmg)

#### Documentation

- docs: fix ghcr image path in contributing guide (#4309 - @swiffer)

## [1.31.0] - 2024-10-27

As always, lots of improvements. The focus has been on performance improvements, especially on slow HW like Raspberry Pi 3B+. We achieved 240x speed improvements in several dashboards :rocket: And we welcomed @swiffer to the TeslaMate-Org team :wave: And much, much more. Enjoy it.

**Regarding PostgreSQL 17:** TeslaMate uses PostgreSQL as database, this is an external dependency and needs to be updated by yourself. Although TeslaMate currently runs fine with PostgreSQL 14+ we strongly recommend upgrading to the latest supported version. We recommend that you do this as follows:

- [Backup your data](https://docs.teslamate.org/docs/maintenance/backup_restore#backup)
- [Upgrade TeslaMate to this version](https://docs.teslamate.org/docs/upgrading)
- [Backup your data after the upgrade](https://docs.teslamate.org/docs/maintenance/backup_restore#backup)
- [Upgrade PostgreSQL to postgres:17](https://docs.teslamate.org/docs/maintenance/upgrading_postgres) (Yes, you will have to erase your data, which is why you need your backup in the first place.)

**Additional info:** In some very rare cases with very old installations of TeslaMate (from 2019) we have observed performance issues due to missing indexes. These should normally be added with our automatic migrations. If you think your installation may be missing some indexes, see #4201 for the corrective SQL command.

### New features

### Improvements and bug fixes

- fix: 401 on direct Fleet API calls (#4095 - @jlestel)
- feat: add support for PostgreSQL 17 (#4231 - @swiffer)
- fix: add nix module option to specify postgres package (#4227 - @brianmay)
- perf: limit positions to set elevation for to last 10 days (#4228 - @swiffer)
- feat: add treefmt-nix to nix flake (#4219 - @JakobLichterfeld)
- feat: use Grafana 11.0.6-security-01 (#4279 - @swiffer)

#### Build, CI, internal

- ci: pin GitHub action dependencies to protect against supply chain attacks (#4076 - @JakobLichterfeld)
- chore: correct comment for pinned Docker login-action to version 3.2.0 (#4120 - @JakobLichterfeld)
- build(deps): bump erlef/setup-beam from 1.18.0 to 1.18.1 (#4116)
- build(deps): bump docker/login-action from 3.2.0 to 3.3.0 (#4115)
- chore: update PostgreSQL to version 16 in flake.nix (#4135- @JakobLichterfeld)
- build(deps): bump webpack from 5.92.1 to 5.94.0 in /website (#4171)
- build(deps): bump micromatch from 4.0.5 to 4.0.8 in /website (#4174)
- chore: Update tzdata to version 1.1.2 and mimerl to version 1.3.0 (#4205 - @JakobLichterfeld)
- build(deps): bump send and express in /website (#4203)
- ci: enable dependabot for mix and npm (#4207 - @JakobLichterfeld)
- build(deps): bump @docusaurus/preset-classic from 3.4.0 to 3.5.2 in /website (#4210)
- build(deps): bump phoenix_ecto from 4.4.3 to 4.6.2 (#4213)
- build(deps): bump jason from 1.4.1 to 1.4.4 (#4216)
- build(deps): bump classnames from 2.3.2 to 2.5.1 in /website (#4211)
- ci: add treefmt as code formatting multiplexer (#4219 - @JakobLichterfeld)
- ci(refactor): use composite action to avoid duplication in elixir workflow (#4219 - @JakobLichterfeld)
- ci: prevent workflow runs for certain conditions and allow scheduled runs (#4219 - @JakobLichterfeld)
- ci(refactor): use reusable workflow to check paths (#4219 - @JakobLichterfeld)
- ci(refactor): use reusable workflows for streamlined DevOps pipeline (#4219 - @JakobLichterfeld)
- ci(refactor): allow ghcr_build parallel to elixir test (#4219 - @JakobLichterfeld)
- ci: ensure proper linting via treefmt (#4219 - @JakobLichterfeld)
- doc: update CI badge URL for devops workflow (#4219 - @JakobLichterfeld)
- ci(fix): handle empty path filter output (#4219 - @JakobLichterfeld)
- fix: avoid the need for impure for devenv (#4245 - @brianmay)
- ci(fix): run ghcr build workflow only for specific conditions (#4219 - @JakobLichterfeld)
- ci: remove branch restriction for check_paths workflow to increase sec (#4219 - @JakobLichterfeld)
- build(deps): bump actions/checkout from 4.1.7 to 4.2.1 (#4262)
- ci(fix): only run ghcr build in DevOps workflow on own repo ([022b173](https://github.com/teslamate-org/teslamate/commit/022b173430221d385479f4ec9d91d8ccffbfe7b9) - @JakobLichterfeld)
- ci: pin ubuntu-24.04 as runner OS ([40dab3e](https://github.com/teslamate-org/teslamate/commit/40dab3e2a978b8a867f1159626d4c157ccab6c56) - @JakobLichterfeld)
- ci: cleanup caches when pr is closed ([75cfc7c](https://github.com/teslamate-org/teslamate/commit/75cfc7cdd4b8f83f247211dc7fc5c5cd433bf746) - @JakobLichterfeld)
- ci(fix): run ghcr build in DevOps workflow for forks ([688147e](https://github.com/teslamate-org/teslamate/commit/688147e2cf3fb5b55e702185a97a4a4ebb14d7ca) - @JakobLichterfeld)
- ci(fix): correct syntax in ghcr_build workflow for workflow_call ([9e6a275](https://github.com/teslamate-org/teslamate/commit/9e6a2758d5ff21604976184ad69befc1c546e600) - @JakobLichterfeld)
- ci(fix): run ghcr build as separate workflow to fix permission issues with forks ([0410593](https://github.com/teslamate-org/teslamate/commit/0410593850cde00e8f201a9b7d6009f0581ed43c) - @JakobLichterfeld)
- build(deps-dev): bump credo from 1.7.1 to 1.7.8 (#4238)
- build(deps): bump crate-ci/typos from 1.22.9 to 1.26.0 (#4261)
- refactor: Cleanup nix code (#4265 - @scottbot95)
- build(deps): bump elixir from 1.16.2-otp-26 to 1.17.2-otp-27 (#4296 - @JakobLichterfeld)
- build(deps): bump http-proxy-middleware from 2.0.6 to 2.0.7 in /website (#4303)
- feat: update to Phoenix HTML 4.1, bump dependencies (#4277 - sdwalker and @JakobLichterfeld)

#### Dashboards

- Improve Battery Health dashboard estimations on rated range (#4074 - @jheredianet)
- Update charges.json: range added per hour (#4089 - @DrMichael)
- small visual distinguish between AC & DC charging in charges dashboard and unification of the DC coloring in all dashboards (#4124 - @stauffenberg2020)
- Improve drive stats (#4148 - @jheredianet)
- Improve drives dashboard (#4146 - @jheredianet)
- Odometer in charges (#4144 - @jheredianet)
- Update charging-stats for handling suc cost mixed with AC charge on TWC (#4137 - @cyberden)
- Fix the issue of failing to restore efficiency dashboard (#4153 - @ghostiee)
- Improve rounding to month / weeks / days in Updates "Since Previous Update" column (#4164 - @swiffer)
- feat: Improve cost filter on Charges dashboard to show charges with negative cost as well (#4179 - @jheredianet)
- feat: display vehicle VIN as a fallback for vehicle name on grafana dashboards (#4198 - @arcastro)
- feat: Add Moving Average / Percentiles to Charge Level dashboard & bucket data to support longer periods (#4200 - @swiffer)
- increase max battery charge gauge threshold to 101 in case of LFP (#4191 - @neothematrix)
- multiple cars, same name, add VIN next to name (#4230 - @swiffer)
- json_build_object instead of concat in battery-health (#4229 - @swiffer)
- perf: fix skipping streaming data in charging stats (#4252 - @swiffer)
- perf: improvements drive stats (#4258 - @swiffer)
- fix: for drives not showing if duration < 1 minute (#4284 - @swiffer)
- feat: add max speed in drives dashboard (#4284 / #4267 - @js94x)
- perf: exclude streaming data when getting battery level (#4286 - @swiffer)
- perf: exclude streaming data in visited dashboard (#4287 - @swiffer)
- fix: weighted average calculation for consumption in drives dashboard (#4289 - @swiffer)
- perf: improvement in charge level (#4301 - @swiffer)
- perf: improvement and deprecated syntax removal (#4304 - @swiffer)

#### Translations

- Adding missing Swedish translation (#4097 - @tobiasehlert)

#### Documentation

- doc: Add initial author and list of contributors to README.md (#4084 - @JakobLichterfeld)
- doc: add steps to the guide regarding how to switch to Fleet API (#4103 - @yangiak)
- doc: align TPMS Pressure naming in sensor config to match UI config for home assistant (#4104 - @helmo)
- doc: Update screenshots and rearrange links (#4151 - @jheredianet)
- doc: fix markdownlint warnings in fleet API documentation (#4173 - @JakobLichterfeld)
- doc: clarify using fleet API has lots of drawbacks (#4173 - @JakobLichterfeld)
- docs: fix Home Assistant MQTT sensor JSON templates warnings (#4257 - @longzheng)
- docs: add recommended RAM size (#4278 - @JakobLichterfeld)
- docs: add best practice section to contribution guide (#4288 - @swiffer)

## [1.30.1] - 2024-07-10

This is a hotfix release to work around the map fit problem in the new Upstream Grafana. As soon as a new Grafana version is available, we will update again.

### Improvements and bug fixes

- downgrade grafana until maps issue in upstream grafana is resolved (#4071 - @swiffer)

#### Build, CI, internal

- ci: fix coverage report env variable (#4066 - @JakobLichterfeld)

#### Dashboards

- Configure Grafana to use browser language / date formats (#4064 - @swiffer)
- Fix hard coded information (timezone and orgId) (#4056 - @jlestel)

#### Translations

- update zh_hans localized string (#4073 - @mrgaolei)
- Update default.po for thai (#4072 - @tomzt)

## [1.30.0] - 2024-07-07

As always with many improvements. Cleaner LFP battery handling, 100x speed improvement in dashboards and much, much more. Enjoy it.

### New features

- Track open/close states for individual doors (#3962 - @SaswatPadhi), new MQTT values see [documentation](https://docs.teslamate.org/docs/integrations/mqtt)
- Allow Fleet API users to change client_id (#3984 - @jlestel)
- Customize intervals between vehicle_data calls (#3940 - @jlestel)
- feat: Create NixOS module (#3998 - @scottbot95)
- feat: Add ability to enable and disable data collection for cars (#3993 - @mark3-dev)
- publish center_display_state to mqtt (#3813 - @Atrox), new MQTT values see [documentation](https://docs.teslamate.org/docs/integrations/mqtt)
- feat: add LFP Battery setting for car settings (#4007 -@cwanja)
- Add icon to summary when Sentry Mode is triggered and recording (#4043 -@kolaCZek)

### Improvements and bug fixes

- Update vehicle.ex with marketing name for Model Y Long Range RWD (#3989 - @stefanlange)
- feat: use Grafana 11.1.0 (#4019 - @swiffer)
- Update vehicle.ex with marketing name for Model Y SR (#4042 - @kolaCZek)
- feat: update breadcrumb links to use Phoenix path helpers (#4052 - @JakobLichterfeld)

#### Build, CI, internal

- build(deps): bump crate-ci/typos from 1.21.0 to 1.22.9 (#4021)
- build(deps): bump express from 4.18.2 to 4.19.2 in /website (#3790)
- chore: update @docusaurus/core and @docusaurus/preset-classic dependencies to v3.4.0 and react and react-dom to 18.3.1 (#4046 - @JakobLichterfeld)
- build: specify node.js version for Netlify in base dir as latest lts major version (#4046 - @JakobLichterfeld)
- style: fix single quoted string in car_live (#4049 - @JakobLichterfeld)

#### Dashboards

- Improve drive details (#4004 - @jheredianet)
- Improve visualizations on Battery Health dashboard (#4005 - @jheredianet)
- Update drives.json: show drives with duration=0 but distance>0 (#3867 - @DrMichael)
- Improve performance of timeline dashboard (#4019 - @swiffer)
- Fix detection of missing data (geofence condition) in timeline dashboard (#4019 - @swiffer)
- Fix time filter for links to trip dashboard in timeline dashboard (#4019 - @swiffer)
- Reduce number of queries executed in overview dashboard to increase performance (#4019 - @swiffer)
- Ensure Index usage when getting temperatures in overview dashboard (#4019 - @swiffer)
- re-enable time picker by default in drive-details, charge-details dashboards (#3985)
- Improve "Charges" dashboard (#4031 - @jheredianet)
- Improve "Drives" dashboard (#4033 - @jheredianet)
- Update overview.json: Add Distance (#4034 - @DrMichael)
- Update overview.json: fix Net (#4045 - @DrMichael)
- update overview dashboard to fix units for energy consumption (#4048 - @JakobLichterfeld)
- use lfp_battery setting in dashboards & speed up updates dashboard (#4051 - @swiffer)

#### Translations

- feat: update German translations missing messages (#4054 - @JakobLichterfeld)

#### Documentation

- doc: remove outdated, unsupported, unmaintained portainer doc (#3972 - @JakobLichterfeld)
- doc: fix MMM-Teslamate and ha-addon-teslamate project links (#3973 - @olexs)
- doc: update the Contributor's Guide with the latest requirements (#4017 - @JakobLichterfeld)
- doc: Documentation for new endpoint changes (#3978 - @jlestel)
- doc: Add Grafana VS Code extension documentation (#4025 - @JakobLichterfeld)
- doc: fix markdown linter warnings in faq (#4046 - @JakobLichterfeld)
- doc: fix typo in MQTT location JSON format (#4047 - @JakobLichterfeld)

## [1.29.2] - 2024-06-18

This release improve TeslaMate behavior on Tesla API rate limits, which occur from time to time. We respect the retry-after header on 429 response code to not hammer the API unnecessarily in these cases.

### New features

- feat: Dynamic endpoints and token to use official Tesla API (self-hosted or from third party provider) (#3903 - @jlestel)

### Improvements and bug fixes

- fix: Update statistics.json: change back uid (#3907 -@DrMichael)
- feat: Update TeslaFi importer to accept newer export formats (#3431 - @ithinuel)
- feat: Upgrade PostgreSQL to v16 (#3884 -@enoch85)
- feat: Respect Retry-After header on 429 response code (#3943 - @jlestel)
- feat: use Grafana 11.0.0 (#3895 - @swiffer)

#### Build, CI, internal

- ci: Upgrade PostgreSQL to v16 in elixir workflow (#3916 - @JakobLichterfeld)
- build(deps): bump docker/login-action from 3.1.0 to 3.2.0 (#3933)
- build(deps): bump elixir from 1.16.1-otp-26 to 1.16.2-otp-26 (#3935 - @JakobLichterfeld)
- build(deps): bump braces from 3.0.2 to 3.0.3 in /website #3967

#### Dashboards

- Remove A lot of empty space on the drive graph (#3927 - @jheredianet)
- Add more ways to recognize Supercharger locations (#3863 -@woyteck1)
- Projected Range fix (using usable_battery_level) (#3859 -@woyteck1)
- Update and fix timeline dashboard (#3951 -@jheredianet)
- Remove A lot of empty space on the drive graph (#3950 -@jheredianet)
- Integrate LFP specific dashboards into regular dashboards (#3966 - @swiffer)
- Export all Dashboards via Grafana 11.0.0 (#3971 - @swiffer)

#### Translations

- feat: Update default.po for Thai translation (#3906, #3945 - @tomzt)

#### Documentation

- doc: update backup path location to current directory to work around no write access to placeholder directory issue (#3908 - @JakobLichterfeld)
- doc: Update MQTT examples of location/active_route (#3919 - @longzheng)
- doc: Update HomeAssistant docs to use new MQTT values (#3923 - @longzheng)
- doc: Add network flows that should be authorized (#3886 - @fl42)
- doc: Update projects.md with new MMM (#3953 - @top-gun)

## [1.29.1] - 2024-05-20

same as 1.29.0 but reverted: "Dynamic endpoints and token to use official Tesla API (self-hosted or from third party provider) (#3866 - @jlestel)" as it was breaking backwards compatibility

## [1.29.0] - 2024-05-20

### New features

- Publish extra active_route fields to mqtt output (#3789 - @brianmay)
- Dynamic endpoints and token to use official Tesla API (self-hosted or from third party provider) (#3866 - @jlestel)

### Improvements and bug fixes

- fix: errors from Timex.Timezone.local() during switchover to DST (#3848 - @dyxyl)

#### Build, CI, internal

- build(deps): bump dorny/paths-filter from 3.0.1 to 3.0.2 (#3799)
- build(deps): bump docker/login-action from 3.0.0 to 3.1.0 (#3798)
- build(deps): bump grafana/grafana from 10.4.0 to 10.4.1 in /grafana (#3800)
- build(deps): bump grafana/grafana from 10.4.1 to 10.4.2 in /grafana (#3876)
- ci: update typos false positive list (#3808 - @JakobLichterfeld)
- build(deps): bump docker/login-action from 3.0.0 to 3.1.0 in custom action ([b9f1f8b](https://github.com/teslamate-org/teslamate/commit/b9f1f8b956c7fb531321a2d3d875efffd4be6ead) - @JakobLichterfeld)
- ci: pin crate-ci/typos action to version v1.20.1 ([bd50177](https://github.com/teslamate-org/teslamate/commit/bd50177a454426501a9dd7fca000b44c62f10113) and [53d8e62](https://github.com/teslamate-org/teslamate/commit/53d8e625ae4483789b456458a8bb43af9f009361) - @JakobLichterfeld)
- build(deps): bump crate-ci/typos from 1.20.1 to 1.21.0 (#3875)

#### Dashboards

- Battery Health: Fix a bug on efficiency estimations (#3795 - @jheredianet)
- Add more info on charge details dashboard (#3821, #3827 -@jheredianet)
- Battery Health dashboard: new stats panel for efficiency and improve query performance (#3806 -@jheredianet)
- Add stats to Visited dashboard (#3824 - @jheredianet)
- Update Thresholds colors for ºF temperature in Charges dashboard (#3834 - @jheredianet)
- Velocity/Speed histogram in drive details dashboard (#3836 - @jheredianet)
- Change car id selector by row on Charge Details dashboard (#3844- @jheredianet)
- Fix missing units when miles is used (#3850 - @sdwalker)
- Statistics: Add max value for efficiency thresholds (#3852 - @sdwalker)
- Add average cost per kWh for AC and DC as separate values (#3841 -@woyteck1)
- Update statistics.json: timezone issues addressed (#3862 - @DrMichael)
- Statistics: fix temperature colors and column layout for Fahrenheit (#3854 - @sdwalker)

#### Translations

- Update zh_Hans default.po typo (#3804 - @liopoos)

#### Documentation

- doc: remove update steps in installation instructions and link to maintenance section ([dbf23fa](https://github.com/teslamate-org/teslamate/commit/dbf23faa31d84f222c99dba9f5de52c69dd43afb) and #3794 - @JakobLichterfeld and @brianmay)
- doc: add instructions how to update pot files to development guide ([3ab8ee8](https://github.com/teslamate-org/teslamate/commit/3ab8ee8535da32ba0c11307aaacc65379ddcc0b2) - @JakobLichterfeld)
- doc: update links to token apps in FAQ (#3833 - @JakobLichterfeld)
- doc: add testing with ci build docker images to contributing guide (#3856- @JakobLichterfeld)
- doc: adding filename specification for TeslaFi import file (#3872 - @spinecho31)

## [1.28.5] - 2024-03-25

### New features

- feat: Add URL_PATH environment variable for reverse proxy deployments (#3771 -@b1c1l1)

### Improvements and bug fixes

- fix: permissions denied error when specifying user (#3772 -@tobiasehlert)

#### Build, CI, internal

- Update to latest devenv in nix flake (#3760 - @brianmay)
- build(deps): bump webpack-dev-middleware from 5.3.3 to 5.3.4 in /website (#3766)

#### Dashboards

- Improve estimations on Battery Health dashboard (#3756 - @jheredianet)
- Update overview.json: add time range to states link (#3757 - @DrMichael)
- Update overview.json: add time range to charges links (#3758 - @DrMichael)

#### Translations

#### Documentation

- doc: version tag in docker-compose.yml is obsolete since docker 25.05 (#3761 - @JakobLichterfeld)

## [1.28.4] - 2024-03-19

### New features

- Add navigation active route drive state data (#3657 - @longzheng)
- Add location topic (lat and long in one json blob) (#3729 - @brianmay)

### Improvements and bug fixes

- Fix aggressive switch to offline when stream gets offline message (#3672 - @micves)
- feat: Grafana 10.4.0 & Angular Deprecation (#3726 - @swiffer and @JakobLichterfeld)
- test: Make tests non-async (#3738 - @brianmay)

#### Build, CI, internal

- ci: prevent workflow runs for certain conditions and allow scheduled runs ([f71cc51](https://github.com/teslamate-org/teslamate/commit/f71cc51271007da70e7dc57c00e292acdf20e8d6) and [596a10f](https://github.com/teslamate-org/teslamate/commit/596a10f1eeb5c81f1f79293684a06241cc68d465) - @JakobLichterfeld)
- feat: Upgrade web development framework to Phoenix 1.7 (#3615 - @marvelm and @JakobLichterfeld)
- ci: stale after 30 days ([07670fa](https://github.com/teslamate-org/teslamate/commit/07670fa014b4d79d6907e7198960ec13c5cdae71) -@JakobLichterfeld)
- ci: run edge build every night ([206d731](https://github.com/teslamate-org/teslamate/commit/206d731935a5e8ebc350a7981df8c6d92480b88b) - @JakobLichterfeld)
- ci: update upload-artifact action (#3689 - @JakobLichterfeld)
- fix: upload and merge artifact naming conflict since action version v4 (#3689 - @JakobLichterfeld)
- build: bump app base image to fix 'GLIBC_2.34' not found error (#3691- @JakobLichterfeld)
- build: bump app dependencies for libssl and netcat to packages available in debian bookworm (#3691- @JakobLichterfeld)
- build: use netcat-openbsd to support ipv6 again (#3732 - @JakobLichterfeld)
- build: reduce the size of the Docker image by cleaning the APT cache (#3692- @JakobLichterfeld)
- ci: bump dorny/paths-filter from 3.0.0 to 3.0.1 (#3712)
- build: pin elixir image full version to elixir:1.16.1-otp-26 (#3733 - @brianmay and @JakobLichterfeld)
- build: adding chmod to file copy in app stage (#3740 - @tobiasehlert)
- ci: bump actions/delete-package-versions from 4 to 5 (#3713)
- Replace tortoise library with tortoise311 (#3697 - @brianmay)
- build(deps): bump follow-redirects from 1.15.4 to 1.15.6 in /website (#3743)
- feat: experimental nix flake (#3485 - @brianmay)

#### Dashboards

- feat: Add stat panel for selected duration in drive details dashboard (#3667 - @oivindoh)
- Change tracking line color on Maps to blue (#3670 - @jheredianet)
- Select last three drives in trip dashboard now opens in new tab to work reliable ([ca9816b](https://github.com/teslamate-org/teslamate/commit/ca9816ba4905c653b5f4daad533bf2caf2fe1d9c) - @DrMichael)
- Battery health dashboard: Added Distance (Logged - Mileage) stats (#3741 - @jheredianet)
- Update timeline.json: column Action correct width with new grafana version (#3744 - @DrMichael)

#### Translations

- Add Thai Translation (#3566 - @tomzt)
- Update default.po missing french translations (#3662 - @pquattro)
- update zh_Hans text (#3664 - @mrgaolei)
- Add missing German translation for new messages, fix mistakes (#3694 - @accolon)
- feat: add missing translation for new messages for Korean (#3693 - @zipizigi)
- add Traditional Chinese translation for new messages (#3699 and #3709 - @occultsound)
- Adding missing Swedish translation for new messages (#3716 -@tobiasehlert)

#### Documentation

- Add details how to configuring the TZ environment variable (#3650 - @NirKli)
- doc: add instructions, how to connect to database before editing cars (#3656 - @JakobLichterfeld)
- Fix name in lovelace example to match sensor name (#3718 - @js94x)
- doc: Hint for null value in Grafana if car has not been renamed yet (#3720 -@js94x)
- doc: Updated links for TeslaMate projects ([bf50f79](https://github.com/teslamate-org/teslamate/commit/bf50f799941ade1810fadacc408392e274afa459) - @JakobLichterfeld)

## [1.28.3] - 2024-02-02

### New features

- Support listening on unix domain socket (#3328 - @PhracturedBlue)
- Added expected finish charging localtime to teslamate overview in web (#3646 - @NirKli)

### Improvements and bug fixes

- CI: Remove deprecated probot-no-response and update to stale workflow (#3525 - @JakobLichterfeld)
- Fix an issue when car is could enter sleep mode while dog mode is enabled (#3538 - @NirKli)
- Handle stream getting the message "Vehicle is offline" and change the state to offline in vehicle (#3508 - @micves)
- fix: use product api endpoint to fetch vehicles (#3630 - @brianmay and @JakobLichterfeld)

#### Dashboards

- Update locations.json with car selector (@DrMichael)
- Fix Odometer_mi charger dashboard (#3534 - @mechoriet)
- Update charges.json: reenable cost per kWh re added (#3544 - @DrMichael)
- Improve Battery health derived efficiency estimations and Fix error divided by zero (#3593 - @jheredianet)
- Battery Health - Improve performance & adjust queries to handle empty or null data (#3627 - @jheredianet)
- charging-stats: map - add charges count and move label (#3625 - @fmossott)

#### Translations

- fix: translation Update default.po for simplified Chinese (#3600 - @ycjcl868)
- Improvements for Spanish translations (#3610 - @jheredianet)

#### Documentation

- Node-RED required modules should be saved under /data (#3623 - @ToniA)
- Use recommended format for Home Assistant MQTT sensor configuration (#3344)
- Update projects.md with TeslaBox (#3542 - @mluggy)
- update tesla-youq project (#3547 - @brchri)
- doc: Fix TPMS sensor names to match binary_sensor.yaml (#3613 - @kenni)
- update docker-compose.yml for Docker Compose version v2.24.1 (#3626 - @realJustinLee)

### Configure Timezone Setting for Accurate Local Time Display

To ensure time-related features display accurately in your local timezone, configure the TZ environment variable.
Detailed instructions are available in our [configuration guide](https://docs.teslamate.org/docs/configuration/environment_variables/).

## [1.28.2] - 2023-11-27

### New features

### Improvements and bug fixes

- grafana: support DATABASE_SSL_MODE (#3498 - @simonsmh)
- Support server_name_indication for ssl (#3497 - @simonsmh)
- grafana: Fix Dashboard dropdown link display (#3501 - @oivindoh)
- Ci: GHCR Purge success even if package doesn't exist (#3480 - @jlestel and #3504 - @JakobLichterfeld)

#### Dashboards

#### Translations

#### Documentation

## [1.28.1] - 2023-11-26

### New features

### Improvements and bug fixes

- Fix display version in settings

#### Dashboards

#### Translations

#### Documentation

## [1.28.0] - 2023-11-26

Note: First release as @teslamate-org organization.

### New features

- Added tire low pressure icon to teslamate web (#3424 - @NirKli)
- Add charging_state to VehicleSummary (#3471 - @brianmay)

### Improvements and bug fixes

- UI: sync meta theme-color with header background color for iOS status bar (#2840 - @libotony)
- Linting in dashboard links (#3443 - @jlestel)
- Update Grafana to 10.1.2 (#3455 - @swiffer)
- CI: Build PR images on GHCR, so every PR will have a dedicated dockerfile for testing purpose (#3445, #3480, #3481, #3491 -@jlestel)
- Update to Node.js 20 (#3477 - @PhilThurston)
- Add credo lint support for static code analysis (#3452 - @brianmay)

#### Dashboards

- Fix link to Charge Level dashboard (#3263 - @Sjorsa)
- Add LFP variants of Grafana dashboards (#3311 - @eden881)
- Average cost stat in stats dashboard (#3030 - @fmossott)
- Odometer in Charges dashboard (#3463 - @DrMichael)
- Use built-in Grafana visuals instead of plugins (#3439 - @oivindoh and @swiffer)
- Ensure that dashboards can be modified after import (#3454 - @swiffer)
- Migrate projected range to TimeSeries (#3454 - @swiffer)

#### Translations

- There is nothing new here.

#### Documentation

- Gaussmeter units no longer for sale, #3419 - @LelandSindt
- Docker backup restore note about update command when using different TM_DB_USER (#3291 - @tsongalin)
- Update FreeBSD installation instructions (#3277 - @uqs)
- Updated Docker Compose instructions (#3320 - @Dulanic)
- Update HA integration docs with TPMS sensors and examples (#2845 - @marspath)
- Fix code style in FreeBSD section (#3461 and #3462 - @ivanovd)
- Advise that docker-compose v1 is EOL and to upgrade to v2 (#3472 - @cwanja)
- Fix tpms bar sensors name in template for psi (#3490 - @virtualm2000)

## [1.27.4] - 2023-11-12

Note: TeslaMate moved to the new @teslamate-org organization.

### Improvements and Bug Fixes

- Add endpoints query param to `vehicle_data` request to [reflect changes](https://developer.tesla.com/docs/fleet-api?shell#vehicle_data) to the API (#3398 - @swiffer)
- Remove donation links
- Fix warnings on Elixir 1.16
- Upgrade Grafana to 9.5
- Trim whitespace from geofence names
- Support self-signed certificates via (`DATABASE_SSL_CA_CERT_FILE`)
- Use preferred tile.openstreetmap.org URL (#3368)
- Update dependencies

#### Dashboards

- Charges: Mark `end_date` as `dateTimeAsLocal` (#3033 - @DrMichae)
- Add Battery Health dashboard (#3059 - @jheredianet)
- Show all vehicles on drive stats dashboard (#3342 - @yoyostile)
- Updates: Fix for div by zero error (#3289 - @Dulanic)
- Show location name in charge details (#3294 - @DrMichael)
- Fix broken links when orgId is not 1 (#3380 - @jlestel)
- Update query to get car efficiency on Battery Health dashboard (#3245 - @jheredianet)

#### Translations

- Updated Spanish translation (#3244 - @jheredianet)

#### Documentation

- Update docs to use Docker Compose V2 (#3025 - @eden881)
- Update FreeBSD instructions (#3394 - @ivanovd)
- Add Tesla-YouQ project (#3347 - @brchri)

## [1.27.3] - 2023-06-12

### Improvements and Bug Fixes

- Read the vehicle name from the `vehicle_data` response as Tesla has made [some changes](https://github.com/timdorr/tesla-api/issues/728) to the API
- Add composite index to position and drop drive_id index (#3186 - @IlyaDiallo)
- Bump Grafana to 8.5.26
- Ship Docker image with OTP 26 (this should improve performance on ARM devices)
- Optimize automatic Docker image builds

#### Dashboards

- Update drive-details.json missing dataSource for pressure units (#3225 - @OrangeBean)
- Bump pr0ps-trackmap-panel to 2.1.4 (#3076 - @Obihoernchen)

#### Translations

- Fix Korean translation (#3126 - @nanishin)

#### Documentation

- Update docs to manually remove vehicle (#3075 - @cwanja)
- Update Project: Tesla Home Assistant Integration (#3194 - @Megabytemb)
- Updated menu route to Download TeslaFi Data (#3218 - @helmo)

## [1.27.2] - 2023-01-13

### Improvements and Bug Fixes

- Bump pr0ps-trackmap-panel to 2.1.3 (fixes #2770)
- Bump grafana to 8.5.15
- Fix GPX format (#2925 - @martinh2011)
- Change esbuild target to es2017
- Update Elixir and frontend dependencies
- Update GH action workflows

#### Dashboards

- Charging Stats: Update the filter for superchargers (#2832 - @sultantariq)

#### Translations

- Add Ukrainian translations (#3039 - @ZeusF1)
- Update Korean translations (#2898 - @zipizigi)
- Update Chinese (traditional) translations (#2852 - @occultsound)
- Update Chinese translations (#2855 - @JhouXerox)
- Update French translations (#2844 - @CrowMash)

#### Documentation

- Fix typo (#2843 - @CrowMash)
- Improve FreeBSD installation documentation (#2885 - @victori)
- Fix tesla_power unit from W to kW (#3024 - @enzo2)
- Added "Custom Grafana Dashboards" to project list (#3056 - @CarlosCuezva)

## [1.27.1] - 2022-07-22

### Improvements and Bug Fixes

- Add setting to select tire pressure units
- Fix `Protocol 'inet_tcp': register/listen error: econnrefused` error (#2771 - @manuduarte)
- Bump minimum supported Elixir version to 1.12
- Improve handling of invalid API tokens

#### Dashboards

- Charging Stats: Include SuC geofences to calculate charging cost

## [1.27.0] - 2022-07-15

### 🔓 Encryption of API tokens

To ensure that the Tesla API tokens are stored securely, **an encryption key must be provided via the `ENCRYPTION_KEY` environment variable**.

If you use a `docker-compose.yml` file to run TeslaMate, add a line with the `ENCRYPTION_KEY` to the `environment` section or check out the updated installation guides on [docs.teslamate.org](https://docs.teslamate.org):

```yaml
services:
  teslamate:
    image: teslamate/teslamate:latest
    environment:
      - ENCRYPTION_KEY=your_secret_encryption_key
      # ...
```

If no `ENCRYPTION_KEY` environment variable is provided when running the database migrations a **randomly generated key will be set for you** to encrypt the tokens. In that case, a warning with further instructions will be displayed.

### Improvements and Bug Fixes

- Add `charge_current_request` and `charge_current_request_max` MQTT topics
- Add detection of refresh Model X (2022) (#2455 - @cwanja)
- Restart streaming API process if token expired
- Do not start erlang's EPMD service
- Store vehicle marketing names in the database
- Allow customizing the default geofence via the `DEFAULT_GEOFENCE` environment variable (#2564)
- Bump Grafana to 8.5.6

#### Dashboards

- Add datasource to table and map panels (#2391- @andrewjw)
- Charge Details: Ensure that battery heater is shown when active during charging (#2527 - @woyteck1)
- Charging Stats, Charges: Add average cost per kWh to charging stats (#2693 - @yoyostile)
- Charging Stats, Charging Details: Add Charging curve (#2093 - @ToniA, #2152 - @fmossott)
- Charging Stats: Add panel with the cost of charges at SuC (#2448 - @carloscuezva)
- Charging Stats: Fix for better "Charge deltas" when the charging process is interrupted and re-started (#2566, #2656 - @nicoladefranceschi)
- Charging Stats: Set Y-Axis max of heatmap to 100 (#2461 - @DrMichael)
- Charging Stats: Update Charging Stats panel styling (#2481 - @cwanja)
- Drive Details: Add elevation summary (#2449 - @coreGreenberet)
- Drive Details: Record the tire pressure which was made available by Tesla in the 2022.4 SW release (#2706 - @NirKli)
- Drive Details: Set elevation units on axis
- Drive Stats: Optimize query to estimate mileage calculation (#2464 - @coreGreenberet)
- Locations: Let the gauge scale up to the maximum value (#2647 - @DrMichael)
- States: Update States top row panels height (#2487 - @cwanja)
- Timeline: Fix links (#2601 - @DrMichael)
- Trip: Render Trip piechart legend (#2473 - @cwanja)
- Migrate dashboards to the new timeseries panels
- Change unit of boolean fields

#### Translations

- Update Chinese translation (#2479 - @AemonCao)
- Add missing Swedish translation (#2731 - @tobiasehlert)

#### Documentation

- Add ProxyPreserveHost On to the Grafana entries in Apache2 config (#2471 - @DrMichael)
- Node-RED: Fix typo (#2410 - @baylanger)
- Update to projects page (TeslaMate-ABRP) (#2518 - @fetzu)
- Update HomeAssistant Integration examples for HA 2022.6 (#2704 - @star114)
- HomeAssistant Integration: enhance km to mi conversion / add timestamp class to charge time (#2735 - @dcod3d)
- Add FAQ around Docker timestamp logs (#2655 - @cwanja)
- Add HomeAssistant notification example (#2712 - @brombomb)

## [1.26.1] - 2022-01-28

### Improvements and Bug Fixes

- Add link on the TeslaMate overview page to the notateslaapp.com release notes ([#2390](https://github.com/adriankumpf/teslamate/pull/2390) by [cwanja](https://github.com/cwanja))
- Fix token refresh for Chinese accounts

#### Dashboards

- Charges: Show link if the charge cost is not set ([#2380](https://github.com/adriankumpf/teslamate/pull/2380) by [carloscuezva](https://github.com/carloscuezva))
- Efficiency: Add min & max values to the Temperature-Efficiency gauge ([#2395](https://github.com/adriankumpf/teslamate/pull/2395) by [DrMichael](https://github.com/DrMichael))
- Overview / Updates: Fix software version format

#### Translations

- Adding missing Swedish translation ([#2373](https://github.com/adriankumpf/teslamate/pull/2373) by [tobiasehlert](https://github.com/tobiasehlert))
- Small correction for Spanish translation ([#2379](https://github.com/adriankumpf/teslamate/pull/2379) by [carloscuezva](https://github.com/carloscuezva))
- Spanish translation refinements ([#2388](https://github.com/adriankumpf/teslamate/pull/2388) by [jmalcaide](https://github.com/jmalcaide))

## [1.26.0] - 2022-01-25

### Improvements and Bug Fixes

- Remove support for logins with username/password
- Show zoom controls when hovering over or tapping the map ([#2184](https://github.com/adriankumpf/teslamate/pull/2184) by [bogosj](https://github.com/bogosj))
- Use new Chinese Tesla API endpoints
- Fix MFA for Chinese accounts ([#2234](https://github.com/adriankumpf/teslamate/pull/2234) by [howard0su](https://github.com/howard0su))
- Fix detection of refreshed Model S
- Guard against duplicate vehicle API responses
- Don't suspend logging while a car software update is downloaded
- Don't warn if the update status completing the of a car software update is still reported as 'downloading'
- Bump Docker app base image to Debian 11
  - Raspberry Pi users unfortunately have to upgrade to Raspbian Bullseye or install the backports version `libseccomp2` (see [#2302](https://github.com/adriankumpf/teslamate/issues/2302))

#### Dashboards

##### Upgrade Grafana to version 8

> ⚠️ Manually managed Grafana instances have to be upgraded to v8.3.4 or higher!

- All table panels have been migrated to the new table component
  - This brings a bunch of improvements including an improved experience on small screen sizes
  - The date columns now use a local format depending on your browser language setting
- The pie chart panels have been migrated to the new native pie charts component
- The discrete panels have been replaced by the native state timeline panel

##### Other

- Drive Details: Display if the car is preconditioning ([#2281](https://github.com/adriankumpf/teslamate/pull/2281) by [carloscuezva](https://github.com/carloscuezva))
- Timeline: Add filters for destination ([#2354](https://github.com/adriankumpf/teslamate/pull/2354) by [DrMichael](https://github.com/DrMichael))

#### Translations

- Update Chinese translation ([#2232](https://github.com/adriankumpf/teslamate/pull/2232) by [howard0su](https://github.com/howard0su))
- Update Chinese translation ([#2236](https://github.com/adriankumpf/teslamate/pull/2236) by [summergeorge](https://github.com/summergeorge))
- Update French translation ([#2216](https://github.com/adriankumpf/teslamate/pull/2216) by [tydoo](https://github.com/tydoo))
- Update Spanish translation ([#2148](https://github.com/adriankumpf/teslamate/pull/2148) by [jmalcaide](https://github.com/jmalcaide))
- Update Italian translation ([#2146](https://github.com/adriankumpf/teslamate/pull/2146) by [ludovi-com](https://github.com/ludovi-com))

#### Documentation

- Update FreeBSD docs ([#2226](https://github.com/adriankumpf/teslamate/pull/2226) by [rustikles](https://github.com/rustikles))
- Update FAQ: Clarified how the consumption values are calculated and what triggers the recalculations ([#2345](https://github.com/adriankumpf/teslamate/pull/2345)) by [cwanja](https://github.com/cwanja)
- Added [TeslaMate-ABRP](https://github.com/fetzu/teslamate-abrp) to list of projects ([#2314](https://github.com/adriankumpf/teslamate/pull/2314))
- Fix typo ([#2217](https://github.com/adriankumpf/teslamate/pull/2217) by [Oddadin](https://github.com/Oddadin))
- Clarify that the pull command needs to be ran from the directory where the docker YML file is located ([#2368](https://github.com/adriankumpf/teslamate/pull/2368) by [cwanja](https://github.com/cwanja))

## [1.25.2] - 2022-01-12

- Bump app base image to Debian 11 to fix `GLIBC_2.29' not found` error
- Bump Grafana to 7.5.12

## [1.25.1] - 2022-01-12

Disable anonymous logins to Grafana by default (when using the `teslamate/grafana` Docker image)

- The first time you visit Grafana, you will be asked to log in. Use the default user `admin` with the password `admin`. After successful login, you will be prompted to change the password.
- To allow anonymous logins set the environment variable of the Grafana image `GF_AUTH_ANONYMOUS_ENABLED` to `true` (use only if your Grafana instance is not exposed to the internet!)

> This change only affects users who followed the [basic Docker installation guide](https://docs.teslamate.org/docs/installation/docker) which, as mentioned in the guide, is intended for home network use only and not for exposure to the internet. Users who followed one of the [advanced installation guides](https://docs.teslamate.org/docs/guides/traefik) are not affected as their Grafana instances always had anonymous logins disabled.

## [1.25.0] - 2021-11-12

### Improvements and Bug Fixes

- Add Apple mobile web app capable meta tag ([#2128](https://github.com/adriankumpf/teslamate/pull/2128))
- Add NOT NULL constraint to the charging_processes.start_date column
- Add workaround for an error that occurred when the OS does not return the current date and time
- Display marketing names (again). This was necessary due to an API change.
  - Add Mid-Range Model 3 ([#2057](https://github.com/adriankumpf/teslamate/pull/2057) by [RickyRomero](https://github.com/RickyRomero))
- Show the token sign-up form by default
- Sign out if the Tesla API repeatedly returns 401 responses
- Use SSO access tokens instead of Owner API tokens (except for Chinese accounts)

#### Dashboards

- Timeline: bugfixes and improvements ([#2125](https://github.com/adriankumpf/teslamate/pull/2125), [#2092](https://github.com/adriankumpf/teslamate/pull/2092), [#2061](https://github.com/adriankumpf/teslamate/pull/2061) by [DrMichael](https://github.com/DrMichael))

#### Translations

- Update French translation ([#2091](https://github.com/adriankumpf/teslamate/pull/2091) by [ranaud80](https://github.com/ranaud80))

#### Documentation

- Add integration Guide for Node-RED, with examples ([#2098](https://github.com/adriankumpf/teslamate/pull/2098) by [pmboothby](https://github.com/pmboothby))
- Update upgrade guide ([#2043](https://github.com/adriankumpf/teslamate/pull/2043) by [withanhdammit](https://github.com/withanhdammit))

## [1.24.2] - 2021-09-29

### Improvements and Bug Fixes

- Discard stale data originating from the Tesla Streaming API
- Broadcast offline state via MQTT when car goes offline while driving

#### Dashboards

- Updates and Timeline: Link to [notateslaapp.com](https://www.notateslaapp.com/software-updates/history/) for release notes

## [1.24.1] - 2021-09-29

- Update error message that is shown if reCAPTCHA is required
- Update Erlang/OTP version to [prevent possible outages due to DST Root CA expiry on Sep 30th](https://elixirforum.com/t/psa-preventing-outages-due-to-dst-root-ca-expiry-on-sep-30th/42247)

**⚠️ NOTE:** Tesla have tightened the captcha security once again and now require Google reCAPTCHA to generate API tokens. reCAPTCHA is implemented in a way that makes it impossible to bypass for applications like TeslaMate. There are third-party services that offer to fill these captchas (by having humans solve them manually), but they're slow and can be pricey if you're making a large a mount of requests.

So if you are having issues signing in to your Tesla account via TeslaMate, the only remaining **workaround** right now is to sign in using `existing API tokens` (there is a button on the TeslaMate sign-in form). There are multiple apps available to securely generate access tokens yourself, for example:

- [Auth app for Tesla (iOS)](https://apps.apple.com/us/app/auth-app-for-tesla/id1552058613#?platform=iphone)
- [Tesla Tokens (Android)](https://play.google.com/store/apps/details?id=net.leveugle.teslatokens)
- [Tesla Auth (macOS, Linux)](https://github.com/adriankumpf/tesla_auth)

Users who are already signed in in do not have to worry about it. TeslaMate will continue to be able to access the Tesla API.

## [1.24.0] - 2021-08-31

### Improvements and Bug Fixes

- Tesla have once again made changes to the login: TeslaMate can now handle a delayed captcha that first appears after submitting the login form …
- Handle Tesla OwnerAPI errors returned by streaming API
- Lay the groundwork for the ability to customize the displayed order of vehicles ([#1904](https://github.com/adriankumpf/teslamate/pull/1904) by [leewillis77](https://github.com/leewillis77))
  - The order can currently be customized by manually updating the `display_priority` column in the `cars` database table

#### Dashboards

- Charging Stats: Use the full range of colors in the heatmap ([#1821](https://github.com/adriankumpf/teslamate/pull/1821) by [dyxyl](https://github.com/dyxyl))
- Projected Range: Change right y-axis battery level range max from 200% to 100% ([#1840](https://github.com/adriankumpf/teslamate/pull/1840) by [toneus](https://github.com/toneus))
- Timeline: Fix for missing drives and add links to the Action column ([1818](https://github.com/adriankumpf/teslamate/pull/1818) and [#1872](https://github.com/adriankumpf/teslamate/pull/1872) by [DrMichael](https://github.com/DrMichael))
- Charge Level: Fix diagram glitch ([#1936](https://github.com/adriankumpf/teslamate/pull/1936) by [DrMichael](https://github.com/DrMichael))

#### Translations

- Add Japanese translation ([#1909](https://github.com/adriankumpf/teslamate/pull/1909) by [kuma](https://github.com/kuma))

#### Documentation

- Add a note about RAM needed after having issues, also a small clarification on where to place the .env file in the advanced guide ([#1857](https://github.com/adriankumpf/teslamate/pull/1857) by [billerby](https://github.com/billerby))
- Add note with custom TM_DB_USER when backing up ([#1931](https://github.com/adriankumpf/teslamate/pull/1931) by [kyleawayan](https://github.com/kyleawayan))
- Advanced installation with Traefik: Update Grafana rule to limit to TeslaMate host ([#1937](https://github.com/adriankumpf/teslamate/pull/1937) by [benoitm974](https://github.com/benoitm974))

## [1.23.7] - 2021-07-16

### Improvements and Bug Fixes

- Since Tesla have once again made changes to the login with captcha, this version fixes the problems caused by it
- Update permissions to the Grafana plugin directory ([#1814](https://github.com/adriankumpf/teslamate/pull/1814) by [letienne](https://github.com/letienne))

#### Documentation

- Fix heading of the Home Assistant binary_sensor config ([#1756](https://github.com/adriankumpf/teslamate/pull/1756) by [mrzeldaguy](https://github.com/mrzeldaguy))

## [1.23.6] - 2021-07-08

### Improvements and Bug Fixes

- Disable sign-in button if captcha code is missing
- Fix login for Chinese accounts

## [1.23.5] - 2021-07-08

### Improvements and Bug Fixes

- Fix login with captcha

#### Dashboards

- Timeline: Make added kWh more accurate

## [1.23.4] - 2021-06-18

### Improvements and Bug Fixes

#### Dashboards

- Drive Details: Don't round down duration ([#1677](https://github.com/adriankumpf/teslamate/pull/1677) by [Dulanic](https://github.com/Dulanic))
- Projected Range: Prevent division by zero ([#1678](https://github.com/adriankumpf/teslamate/pull/1678) by [Dulanic](https://github.com/Dulanic))
- Updates / States / Stastistics: Use local browser time ([#1685](https://github.com/adriankumpf/teslamate/pull/1685) by [Ed-M72](https://github.com/Ed-M72))
- Charge Level: Simplify database query ([#1693](https://github.com/adriankumpf/teslamate/pull/1693) by [Dulanic](https://github.com/Dulanic))
- Timeline: Add new category `Missing` and some other adjustments ([#1708](https://github.com/adriankumpf/teslamate/pull/1708) by [DrMichael](https://github.com/DrMichael))
- Timeline: Fix missing datasources ([#1730](https://github.com/adriankumpf/teslamate/pull/1730) by [nickbock](https://github.com/nickbock))
- Bump Grafana to 7.5.8 (Docker image)

#### Documentation

- Fix Home Assistant Lovelace UI and sensors ([#1711](https://github.com/adriankumpf/teslamate/pull/1711) by [JakobLichterfeld](https://github.com/JakobLichterfeld))
- Add FreeBSD guide ([#1646](https://github.com/adriankumpf/teslamate/pull/1646) and [#1712](https://github.com/adriankumpf/teslamate/pull/1712) by [tuxbox](https://github.com/tuxbox))

## [1.23.3] - 2021-06-02

### Bug Fixes

- Fix API tokens form

## [1.23.2] - 2021-06-02

### Bug Fixes

- Fix sign-in for Chinese accounts

## [1.23.1] - 2021-06-02

### Improvements and Bug Fixes

- Tesla has removed the captcha again …
- Fix error when changing the language to Chinese

#### Translations

- Update Swedish translations ([#1655](https://github.com/adriankumpf/teslamate/pull/1655) by [tobiasehlert](https://github.com/tobiasehlert))

## [1.23.0] - 2021-06-01

### Improvements and Bug Fixes

- Support Tesla's new captcha verification
- Improve naming of addresses (city aliases)
- Add `power` to published MQTT topics ([#1504](https://github.com/adriankumpf/teslamate/pull/1504) by [mnadvornik](https://github.com/mnadvornik))
- The Docker image now ships with Erlang/OTP 24 which comes with a JIT-compiler (enabled on most x86 64-bit platforms)
- Only publish geofence via MQTT if it has changed
- Fix calculation of gross consumption while charging
- Fix service mode detection
- Fix typo in code_challenge_method ([#1571](https://github.com/adriankumpf/teslamate/pull/1571) by [tuxbox](https://github.com/tuxbox))
- Make `dashboards.sh` script portable e.g. to BSD ([#1645](https://github.com/adriankumpf/teslamate/pull/1645) by [tuxbox](https://github.com/tuxbox))

#### Dashboards

- Add a new Timeline dashboard ([#1621](https://github.com/adriankumpf/teslamate/pull/1621) by [DrMichael](https://github.com/DrMichael))
- Statistics: Fix `pq: time zone "" not recognized` error ([#1470](https://github.com/adriankumpf/teslamate/pull/1470) and [#1559](https://github.com/adriankumpf/teslamate/pull/1559) by [Dulanic](https://github.com/Dulanic))

#### Translations

- Update Swedish translations ([#1461](https://github.com/adriankumpf/teslamate/pull/1461) by [tobiasehlert](https://github.com/tobiasehlert))
- Update French translations ([#1473](https://github.com/adriankumpf/teslamate/pull/1473) by [ranaud80](https://github.com/ranaud80))
- Update German translations

#### Documentation

- Update Mosquitto version used in docker-compose examples
- Add device classes and binary sensors to documented Home Assistant config ([#1597](https://github.com/adriankumpf/teslamate/pull/1597) by [flacjacket](https://github.com/flacjacket) and [#1634](https://github.com/adriankumpf/teslamate/pull/1634) by [ffeingol](https://github.com/ffeingol))

## [1.22.0] - 2021-03-17

### Improvements and Bug Fixes

- Add option to sign in with existing API tokens
- Avoid false `plugged_in` events ([#1423](https://github.com/adriankumpf/teslamate/pull/1423) by [brianmay](https://github.com/brianmay))
- Handle distinct OSM IDs gracefully when changing the address language
- Set another user agent for auth requests.
  - ⚠️ _This fixes timeouts when signing in for the time being. Most users who are affected reported using a cloud hosting service. Expect this to break anytime Tesla decides to block this type of traffic coming from these providers._
- Update user agent used for API requests to GitHub and OpenStreetMap

#### Dashboards

- Add battery heater info to Overview / Charging Details and Charge Details dashboards ([#1428](https://github.com/adriankumpf/teslamate/pull/1428) by [ToniA](https://github.com/ToniA))
- Statistics: Calculate efficiency from charged energy ([#1445](https://github.com/adriankumpf/teslamate/pull/1445) by [ToniA](https://github.com/ToniA))
- Make Statistics dashboard look the same on both kilometers and miles ([#1439](https://github.com/adriankumpf/teslamate/pull/1439) by [ToniA](https://github.com/ToniA))
- Updates: Rename column to "Since Previous Update"

#### Translations

- Update Spanish translation ([#1446](https://github.com/adriankumpf/teslamate/pull/1446) by [alceasan](https://github.com/alceasan))

#### Documentation

- Explaining the asleep mode with MCU1 and the non-streaming mode ([#1453](https://github.com/adriankumpf/teslamate/pull/1453) by [ToniA](https://github.com/ToniA))

## [1.21.6] - 2021-03-10

### Improvements and Bug Fixes

- Change HTTP headers again to avoid auth requests timing out
- Fix changing the address language
- Add health check route ([#1422](https://github.com/adriankumpf/teslamate/pull/1422) by [brianmay](https://github.com/brianmay))

#### Translations

- Update Korean translation ([#1381](https://github.com/adriankumpf/teslamate/pull/1381) by [dongbum](https://github.com/dongbum))
- Updated Danish translation ([#1404](https://github.com/adriankumpf/teslamate/pull/1404) by [larskochhansen](https://github.com/larskochhansen))

#### Documentation

- Add fixed pricing information to [TeslaMateApi](https://github.com/tobiasehlert/TeslaMateApi) project description ([#1399](https://github.com/adriankumpf/teslamate/pull/1399) by [tobiasehlert](https://github.com/tobiasehlert))

## [1.21.5] - 2021-02-21

### Improvements and Bug Fixes

- Implement a workaround for login requests timing out
- Handle failed token refresh requests gracefully

#### Dashboards

- Overview: Fix Gross Panel font size ([#1363](https://github.com/adriankumpf/teslamate/pull/1363) by [DrMichael](https://github.com/DrMichael))
- Charging Stats: Set bucket size on charging heatmap ([#1355](https://github.com/adriankumpf/teslamate/pull/1355) by [leewillis77](https://github.com/leewillis77))
- Downgrade Grafana to 7.3.7 because of an incompatibility with the Trackmap plugin

## [1.21.4] - 2021-02-16

### Enhancements and Bug Fixes

- Point out more clearly when starting into import mode
- Hide sign-out button in import mode
- Don't purge debug log statements from production release
- Handle non-existing range values after the car was offline

#### Dashboards

- Statistics: Show "Starting at" column and fix timezone issue ([#1254](https://github.com/adriankumpf/teslamate/pull/1254) by [DrMichael](https://github.com/DrMichael))
- Charge Level: Fix usable battery level alternating between usable battery level and regular battery level
- Bump Grafana to v7.4.1

#### Documentation

- Add [TeslaMateApi](https://github.com/tobiasehlert/TeslaMateApi) to the list of projects using TeslaMate ([#1350](https://github.com/adriankumpf/teslamate/pull/1350) by [tobiasehlert](https://github.com/tobiasehlert))
- Update installation docks ([#1287](https://github.com/adriankumpf/teslamate/pull/1287) by [tobiasehlert](https://github.com/tobiasehlert))
- Update HomeAssistant documentation ([#1321](https://github.com/adriankumpf/teslamate/pull/1321) by [jschollenberger](https://github.com/jschollenberger))

## [1.21.3] - 2021-02-06

- Add support for v3 API tokens in China
- Detect if TeslaFi CSV files contain data for more than one car
- Change log level for streaming timeouts to debug

## [1.21.2] - 2021-01-31

> **⚠️ NOTE**: Any previously stored API refresh tokens will no longer function, as Tesla has deprecated the existing authentication endpoint. Existing access tokens will continue to work **until they expire**. Eventually, a full login will be needed to obtain new refresh tokens.
>
> **To immediately obtain new tokens after upgrading**, go to the TeslaMate settings page, **sign out via the button** at the bottom of the page and then sign in again.

Additional:

> **⚠️ NOTE**: This release changes TeslaMate's base Docker image to Debian. If you have any customizations on top of TeslaMate (like healthchecks), they could need updates to work on top of this new image.

### Enhancements

- Use the new Tesla authentication endpoint for refreshing access tokens
- Drop support for the `/oauth/token` endpoint
- Add a sign-out button at the bottom of the settings page

#### Translations

- Add Turkish Language Support ([#1194](https://github.com/adriankumpf/teslamate/pull/1194) by [neocorp](https://github.com/neocorp))

#### Dashboards

- Display average outside temperature in charges dashboard ([#1213](https://github.com/adriankumpf/teslamate/pull/1213) by [DrMichael](https://github.com/DrMichael))

## [1.21.1] - 2021-01-10

### Enhancements

#### Translations

- Add Finnish translation ([#1190](https://github.com/adriankumpf/teslamate/pull/1190) by [puppee](https://github.com/puppee))

#### Documentation

- Add some documentation about updating TeslaMate when installed with Docker ([#1170](https://github.com/adriankumpf/teslamate/pull/1170) by [fatbasstard](https://github.com/fatbasstard))
- Update "Import from tesla-apiscraper" documentation: Give an example how to get the vehicle_id from TeslaMate ([#1174](https://github.com/adriankumpf/teslamate/pull/1174) by [Bdot42](https://github.com/Bdot42))
- Add link to unofficial Home Assistant addon ([#1188](https://github.com/adriankumpf/teslamate/pull/1188) by [matt-FFFFFF](https://github.com/matt-FFFFFF))

#### Other

- Allow to use non-standard MQTT ports (via [MQTT_PORT](https://docs.teslamate.org/docs/configuration/environment_variables))
- Refactoring: Use built-in Ecto enum type
- Guard against unexpected MFA errors

### Bug Fixes

- Update drive duration query to avoid displaying different times for drives (Details vs Overview) ([#1191](https://github.com/adriankumpf/teslamate/pull/1191) by [fatbasstard](https://github.com/fatbasstard))
- Fix font colors for light theme (Updates dashboard) ([#1169](https://github.com/adriankumpf/teslamate/pull/1169) by [fatbasstard](https://github.com/fatbasstard))
- Fix typo (Statistics dashboard) ([#1185](https://github.com/adriankumpf/teslamate/pull/1185) by [rogiervandergeer](https://github.com/rogiervandergeer))

## [1.21.0] - 2021-01-02

### Enhancements

#### Dashboards

- Drive Details: Add button to download a drive as GPX file ([#993](https://github.com/adriankumpf/teslamate/pull/993) by [ayonix](https://github.com/ayonix))
- New dashboard for reporting to Dutch tax ([#998](https://github.com/adriankumpf/teslamate/pull/998) and [#1051](https://github.com/adriankumpf/teslamate/pull/1051) by [roadrash2108](https://github.com/roadrash2108))
- Locations: Add panel to see when an address was last visited
- Charges/Drives: Add more filtering capabilities ([#1016](https://github.com/adriankumpf/teslamate/pull/1016) by [Kosta-Github](https://github.com/Kosta-Github))
- Overview: Fix unit of measurement for charge energy added ([#1061](https://github.com/adriankumpf/teslamate/pull/1061) by [landler](https://github.com/landler))
- Charge Level: Add green bars (20/80%) to match "Charge Delta" graph ([#1059](https://github.com/adriankumpf/teslamate/pull/1059) by [roadrash2108](https://github.com/roadrash2108))
- Charging-Stats/Trip: Change colors of AC/DC ([#1058](https://github.com/adriankumpf/teslamate/pull/1058) by [roadrash2108](https://github.com/roadrash2108))
- Statistics: Resolve issue with month groupings ([#1082](https://github.com/adriankumpf/teslamate/pull/1082) by [leewillis77](https://github.com/leewillis77))
- Updates: Apply number of charges and average rated range to the correct update ([#1147](https://github.com/adriankumpf/teslamate/pull/1147) by [tlj](https://github.com/tlj))

#### Other

- Add support for Tesla’s new authentication process (two-factor authentication)
- Optimize TeslaFi CSV file import: reduced memory usage and increased performance
- Require [Elixir v1.11](https://docs.teslamate.org/docs/installation/debian#requirements)
- Allow to connect to Postgres via IPv6 (via [DATABASE_IPV6](https://docs.teslamate.org/docs/configuration/environment_variables))
- Allow to connect to MQTT broker via IPv6 (via [MQTT_IPV6](https://docs.teslamate.org/docs/configuration/environment_variables))
- Improve detection of whether the vehicle is plugged in during cold weather (+ fix [#1154](https://github.com/adriankumpf/teslamate/pull/1154) by [virtualm2000](https://github.com/virtualm2000))
- Use connection pooling for SRTM downloads
- Optimize Docker layer caching to speed up image build times
- Battery level tooltip: Prevent division by zero error if car is totally down to 0%
- Display the actual error if the import directory is not accessible

#### Translations

- Add Italian translation ([#1095](https://github.com/adriankumpf/teslamate/pull/1095) and [#1096](https://github.com/adriankumpf/teslamate/pull/1096) by [HavanaMan](https://github.com/HavanaMan))

#### Documentation

- Fix version info on development guide & minor spelling fix ([#994](https://github.com/adriankumpf/teslamate/pull/994) by [techgaun](https://github.com/techgaun))
- Update backup_restore.md ([#1027](https://github.com/adriankumpf/teslamate/pull/1027) by [pihomeserver](https://github.com/pihomeserver))
- Improve garage door automation example ([#1039](https://github.com/adriankumpf/teslamate/pull/1039) by [andrewfoster](https://github.com/andrewfoster))
- Update traefik guide to use a single public hostname instead of two ([#1101](https://github.com/adriankumpf/teslamate/pull/1101) by [pmboothby](https://github.com/pmboothby))
- Projects using TeslaMate:
  - [TeslaMateAgile](https://github.com/MattJeanes/TeslaMateAgile): mention Tibber support ([#1097](https://github.com/adriankumpf/teslamate/pull/1097) by [tobiasehlert](https://github.com/tobiasehlert))
  - Add [TeslaMate_Telegram_Bot](https://github.com/JakobLichterfeld/TeslaMate_Telegram_Bot) ([#1122](https://github.com/adriankumpf/teslamate/pull/1122) by [JakobLichterfeld](https://github.com/JakobLichterfeld))
- Update installation instructions for Apache ([#1124](https://github.com/adriankumpf/teslamate/pull/1124) by [juankymoral](https://github.com/juankymoral))

## [1.20.1] - 2020-10-24

### Enhancements

#### Dashboards

- Charge Level: Always show 0% and 100% when state of charge is shown in a diagram ([#980](https://github.com/adriankumpf/teslamate/pull/980) by [mbertheau](https://github.com/mbertheau))
- Charging Stats: Titles/labels now match pie-charts ([#998](https://github.com/adriankumpf/teslamate/pull/998) by [roadrash2108](https://github.com/roadrash2108))
- Drive Details: Increase width of odometer panel
- Efficiency: Set a fixed max value and use LCD gauge
- Overview: Fix overlapping timestamps in discrete map ([#995](https://github.com/adriankumpf/teslamate/pull/995) by [pmboothby](https://github.com/pmboothby))
- Fix overlapping timestamps in trip and states dashboard
- Statistics: Add links to other dashboards ([#973](https://github.com/adriankumpf/teslamate/pull/973) by [DrMichael](https://github.com/DrMichael))

#### Translations

- Update Norwegian translation ([#996](https://github.com/adriankumpf/teslamate/pull/996) and [#1007](https://github.com/adriankumpf/teslamate/pull/1007) by [spacecosmos](https://github.com/spacecosmos))
- Update Swedish translation ([#1029](https://github.com/adriankumpf/teslamate/pull/1029) by [tobiasehlert](https://github.com/tobiasehlert))

#### Other

- Display update version in the homescreen update tooltip ([#976](https://github.com/adriankumpf/teslamate/pull/976) by [ayonix](https://github.com/ayonix))
- Customize Grafana home screen logo ([#1004](https://github.com/adriankumpf/teslamate/pull/1004) by [gimmespam](https://github.com/gimmespam))
- Bump Grafana to 7.2.1

### Bug Fixes

- Fix tooltips in car overview being hidden by .card ([#975](https://github.com/adriankumpf/teslamate/pull/975) by [ayonix](https://github.com/ayonix))
- Make Statistics dashboard compatible with older versions of Postgres
- Open Statistics dashboard with browser time zone when coming from the TeslaMate UI

## [1.20.0] - 2020-10-04

### Enhancements

#### Dashboards

- Update consumption unit to Watt-hour to match in-car unit ([#717](https://github.com/adriankumpf/teslamate/pull/717) by [mattw01](https://github.com/mattw01))
- Update dashboards to use the new components from Grafana 7
- Charges: Show very short charging sessions
- Charges: Add filter for voltage ([#857](https://github.com/adriankumpf/teslamate/pull/857) by [Dulanic](https://github.com/Dulanic))
- Charging Details: Show kWh even if still charging ([#744](https://github.com/adriankumpf/teslamate/pull/744) by [Dulanic](https://github.com/Dulanic))
- Charging Stats: Visualize % of sum instead of max kWh in charging heat map ([#680](https://github.com/adriankumpf/teslamate/pull/680) by [Dulanic](https://github.com/Dulanic))
- Charging Stats: Show cost per 100 km/mi (Charging Stats)
- Drives: Update possible values for the "cold" column to be consistent ([#702](https://github.com/adriankumpf/teslamate/pull/702) by [Dulanic](https://github.com/Dulanic))
- Drive Details: Show drive efficiency
- Mileage: Optimize query to get odometer ([#804](https://github.com/adriankumpf/teslamate/pull/804) by [Dulanic](https://github.com/Dulanic))
- Overview: Add 'total energy added' to chart ([#690](https://github.com/adriankumpf/teslamate/pull/690) by [Dulanic](https://github.com/Dulanic))
- Overview: Hide stale temperatures
- Overview: Show most recent driver temp setting while driving
- Overview: Add efficiency ([#970](https://github.com/adriankumpf/teslamate/pull/970) by [DrMichael](https://github.com/DrMichael))
- States: Display all states names ([#755](https://github.com/adriankumpf/teslamate/pull/755) by [DrMichael](https://github.com/DrMichael))
- Updates: Add links to release notes ([#797](https://github.com/adriankumpf/teslamate/pull/797) and [#823](https://github.com/adriankumpf/teslamate/pull/823) by [pmboothby](https://github.com/pmboothby))
- Updates: Show average range and number of chargers per software version to identify if an update had a bigger than expected impact on range ([#731](https://github.com/adriankumpf/teslamate/pull/731) and [#762](https://github.com/adriankumpf/teslamate/pull/762) by [Dulanic](https://github.com/Dulanic))
- Updates: Fix up the version display when it only has a week value and no point release ([#925](https://github.com/adriankumpf/teslamate/pull/925) by [pyjamasam](https://github.com/pyjamasam))
- Vampire Drain: Utilize charges as additional anchor points ([#769](https://github.com/adriankumpf/teslamate/pull/769) by [tacotran](https://github.com/tacotran))
- Add new Statistics dashboard ([#965](https://github.com/adriankumpf/teslamate/pull/965) by [DrMichael](https://github.com/DrMichael))
- Add the "shared crosshair" setting to some of the dashboards ([#932](https://github.com/adriankumpf/teslamate/pull/932) and [#962](https://github.com/adriankumpf/teslamate/pull/936) by [Kosta-Github](https://github.com/Kosta-Github))
- "Customize" Grafana logo ([#890](https://github.com/adriankumpf/teslamate/pull/890) by [https://github.com/fatbasstard](https://github.com/fatbasstard))

##### Note

- The dashboards require **Grafana 7**. Make sure you are running the latest version of Grafana if you are not using the Docker installation.

#### Translations

- Update Chinese (Simplified) translation ([#747](https://github.com/adriankumpf/teslamate/pull/747) by [edward4hgl](https://github.com/edward4hgl))
- Update French translation ([#693](https://github.com/adriankumpf/teslamate/pull/693) by [tomS3210](https://github.com/tomS3210))
- Tweak Dutch translation ([#880](https://github.com/adriankumpf/teslamate/pull/880) and[#881](https://github.com/adriankumpf/teslamate/pull/881) by [https://github.com/fatbasstard](https://github.com/fatbasstard))

#### Documentation

- Update HomeAssistant documentation ([#705](https://github.com/adriankumpf/teslamate/pull/705) by [ngardiner](https://github.com/ngardiner))
- TeslaFi Import: Clarify steps 3 and 4 about emptying the import folder ([#703](https://github.com/adriankumpf/teslamate/pull/703) by [ramonsmits](https://github.com/ramonsmits))
- Update Upgrade documentation ([#790](https://github.com/adriankumpf/teslamate/pull/790) by [roadrash2108](https://github.com/roadrash2108))
- Add a page that lists projects that use TeslaMate: [docs.teslamate.org/docs/projects](https://docs.teslamate.org/docs/projects)
- An note about moving the backup file ([#813](https://github.com/adriankumpf/teslamate/pull/813) by [traviscollins](https://github.com/traviscollins))
- Add `-T` flag to backup command ([#851](https://github.com/adriankumpf/teslamate/pull/851) by [acemtp](https://github.com/acemtp))

#### Other

- Optimize conversion helper functions
- Allow to set a cost by the minute per geo-fence
- Allow to set charge cost by minute
- Allow negative charge costs
- Periodically store vehicle data while charging
- Use a more performant HTTP client
- Try to keep using API tokens if initial refresh at startup fails
- Tweak streaming timeouts and create a new connection after too many disconnects
- Change default sleep requirements to not require the car to be locked
- Use GitHub Actions to build docker images and publish them to DockerHub
- For those who want to help **testing the latest development version**: the docker images with the `edge` tag (`teslamate/teslamate:edge` and `teslamate/grafana:edge`) are for you.
- Allow negative cost_per_unit for geofences ([#968](https://github.com/adriankumpf/teslamate/pull/968) by [ayonix](https://github.com/ayonix))
- Speed up parsing of CSV files (data import)

### Bug Fixes

- Vampire Drain: Fix duplicate values with multiple cars ([#726](https://github.com/adriankumpf/teslamate/pull/726) by [Dulanic](https://github.com/Dulanic))
- Tooling: Ensure dashboards are restored into the same folder as they currently belong to ([#712](https://github.com/adriankumpf/teslamate/pull/712) by [sumnerboy12](https://github.com/sumnerboy12))
- Battery Level & Range: fix wrongly displayed values for multiple cars ([#843](https://github.com/adriankumpf/teslamate/issues/843) by [lemmerk](https://github.com/lemmerk))
- Fix handling of locations that cannot be geocoded
- Show in progress charging sessions
- Handle API errors during initialization

## [1.19.4] - 2020-06-04

- Bump Grafana to 6.7.4 which includes an [important security patch](https://grafana.com/blog/2020/06/03/grafana-6.7.4-and-7.0.2-released-with-important-security-fix)

## [1.19.3] - 2020-05-03

### Enhancements

#### Translations

- Improve Chinese (Traditional) translation accuracy ([#650](https://github.com/adriankumpf/teslamate/pull/650) by [occultsound](https://github.com/occultsound))
- Improve Chinese (Simplified) translation accuracy ([#649](https://github.com/adriankumpf/teslamate/pull/649) by [edward4hgl](https://github.com/edward4hgl))
- Improve Korean translation ([#663](https://github.com/adriankumpf/teslamate/pull/663) by [dongbum](https://github.com/dongbum))

#### Dashboards

- Overview: Update battery gauge thresholds ([#651](https://github.com/adriankumpf/teslamate/pull/651) by [wooter](https://github.com/wooter))
- Drives: Add column header for reduced range ([#662](https://github.com/adriankumpf/teslamate/pull/662) by [Dulanic](https://github.com/Dulanic))
- Charging Stats: Show map with frequently used chargers ([#666](https://github.com/adriankumpf/teslamate/pull/666) by [Dulanic](https://github.com/Dulanic))

  - _Manual install: requires Grafana plugin **grafana-map-panel**_

    ```bash
    grafana-cli --pluginUrl https://github.com/panodata/grafana-map-panel/releases/download/0.9.0/grafana-map-panel-0.9.0.zip plugins install grafana-worldmap-panel-ng
    ```

#### Other

- Add option `HTTP_BINDING_ADDRESS` to control the bound IP address ([#665](https://github.com/adriankumpf/teslamate/pull/665) by [dyxyl](https://github.com/dyxyl))
- Docker image: Pre-install Grafana plugins
- Drop unused indexes

### Bug Fixes

- Fix an issue that could cause a missed firmware update not to be logged retroactively
- Fix an issue where the vehicle process could crash when logging was suspended manually
- Improve error message for an invalid tokens table
- Fix `min. distance per drive` on Efficiency dashboard to filter correctly in miles ([#672](https://github.com/adriankumpf/teslamate/pull/672) by [Dulanic](https://github.com/Dulanic))

## [1.19.2] - 2020-04-26

### Enhancements

#### Translations

- Add Chinese (Simplified) translation ([#625](https://github.com/adriankumpf/teslamate/pull/625) by [edward4hgl](https://github.com/edward4hgl))
- Add Chinese (Traditional) translation ([#633](https://github.com/adriankumpf/teslamate/pull/633) by [occultsound](https://github.com/occultsound))
- Fix typo in French translation ([#638](https://github.com/adriankumpf/teslamate/pull/638) by [tobiasehlert](https://github.com/tobiasehlert))
- Add Dutch translation ([#647](https://github.com/adriankumpf/teslamate/pull/647) by [wooter](https://github.com/wooter))

#### Dashboards

- Updates: Show update duration and time since last update ([#632](https://github.com/adriankumpf/teslamate/pull/632) by [Dulanic](https://github.com/Dulanic))
- Charging Stats: Show kWh at non-decimal level and MWh at the 3 decimal point level ([#642](https://github.com/adriankumpf/teslamate/pull/642) and [#646](https://github.com/adriankumpf/teslamate/pull/646) by [Dulanic](https://github.com/Dulanic))

### Bug Fixes

- Do not publish NULL or incorrect values to MQTT topics if TeslaMate is restarted while the car is asleep

## [1.19.1] - 2020-04-20

### Enhancements

#### Translations

- Add Korean translation ([#614](https://github.com/adriankumpf/teslamate/pull/614) by [dongbum](https://github.com/dongbum))

### Bug Fixes

- Fix an issue where the map tiles would disappear when editing a geofence
- Fix a few things in the docs ([#611](https://github.com/adriankumpf/teslamate/pull/611) by [tobiasehlert](https://github.com/tobiasehlert))

## [1.19.0] - 2020-04-19

### Enhancements

#### Streaming API

As the first and only Tesla logging app out there, TeslaMate now use the Tesla streaming API! This brings the following improvements:

- **High precision drive data**. Rather than active polling, the streaming API allows for passive consumption of a high frequency data stream with the most important drive data (position, heading, speed, power, elevation etc.).
- **Actual elevation above sea level**. Up until now TeslaMate used satellite terrain data to get the elevation. Driving through tunnels or across a bridges therefore resulted in inaccurate recordings. This is no longer the case!
- **Bluetooth hints are no longer needed!** Using the streaming API does not prevent the vehicle from falling asleep, thus enabling continuous monitoring. This allows the car to fall asleep more quickly (no more idle timer) and we don't miss up to 21 minutes of driving because of halted polling.

**Many thanks to everyone who participated in testing this release and contributed improvements!**

#### Translations

- Add Danish translation ([#584](https://github.com/adriankumpf/teslamate/pull/584) by [MartinNielsen](https://github.com/MartinNielsen))
- Update Norwegian translation ([#544](https://github.com/adriankumpf/teslamate/pull/544) and [#591](https://github.com/adriankumpf/teslamate/pull/591) by [spacecosmos](https://github.com/spacecosmos))
- Update Swedish translation ([#522](https://github.com/adriankumpf/teslamate/pull/522) by [tobiasehlert](https://github.com/tobiasehlert))
- Update French translation ([#598](https://github.com/adriankumpf/teslamate/pull/598) by [tomS3210](https://github.com/tomS3210) and [MaxG88](https://github.com/MaxG88))
- Updated Labels to Title Case ([#578](https://github.com/adriankumpf/teslamate/pull/578) by [jmiverson](https://github.com/jmiverson))

#### Other enhancements

- Send credentials with manifest request ([#555](https://github.com/adriankumpf/teslamate/pull/555) by [MaxG88](https://github.com/MaxG88))
- Add option to change the language of the web interface
- Reduce docker image size
- Display an arrow instead of a generic marker to indicate in which direction the vehicle is heading
- Show spinner before the map is initialized
- Wait until the doors/trunk/frunk are closed before attempting to fall asleep
- Inform if a new TeslaMate update is available
- Add icons to navbar items
- Add 'About' section to the settings page
- Publish only those values via MQTT that have actually changed
- Improve detection of available vehicle software updates

#### New MQTT Topics

- `teslamate/cars/$car_id/elevation`
- `teslamate/cars/$car_id/trunk_open`
- `teslamate/cars/$car_id/frunk_open`

#### Documentation

The docs were revised (once again). You can find them at **[docs.teslamate.org](https://docs.teslamate.org)**.

- Add portainer guide to the documentation ([#581](https://github.com/adriankumpf/teslamate/pull/581) by [DrMichael](https://github.com/DrMichael))
- Improve Apache2 guide ([#570](https://github.com/adriankumpf/teslamate/pull/570) by [DrMichael](https://github.com/DrMichael))
- Bump traefik to v2.2 ([#603](https://github.com/adriankumpf/teslamate/pull/603) by [oittaa](https://github.com/oittaoittaaa))

### Bug Fixes

- Display vampire drain range loss per hour in the correct units ([#543](https://github.com/adriankumpf/teslamate/pull/543) by [ograff](https://github.com/ograff)).
- Trip dashboard: Add title to the drives table to allow sorting ([#592](https://github.com/adriankumpf/teslamate/pull/592) by [MaxG88](https://github.com/MaxG88))
- Add `tini` as the init process for the TeslaMate Docker container to avoid zombie processes ([#606](https://github.com/adriankumpf/teslamate/pull/606) by [dbussink](https://github.com/dbussink))
- Sort "Drives" table properly by drive date ([#595](https://github.com/adriankumpf/teslamate/pull/595) by [Dulanic](https://github.com/Dulanic))
- Fix flashing modal on the geofence page
- Publish an MQTT message when the health check succeeds again
- Handle various invalid API responses that could previously cause problems
- Fix an issue where ambiguous dates could cause the TeslaFi import to fail
- Terminate an in progress drive when the car is put into service mode

### Changed

- Increase the minimum Elixir version to 1.10

### Removed

- Remove sleep mode requirements that are no longer needed
- Remove option to disable sleep mode

## [1.18.2] - 2020-03-28

### Bug Fixes

- Fix an issue that could cause charging sessions not to be properly recorded if the API reported incomplete charge data
- Fix a problem that could cause the TeslaFi import to fail

## [1.18.1] - 2020-03-23

### Bug Fixes

- Fix settings dropdown and Swedish translation ([#525](https://github.com/adriankumpf/teslamate/pull/525) by [tobiasehlert](https://github.com/tobiasehlert))

## [1.18.0] - 2020-03-21

### Enhancements

- Add Swedish translation ([#485](https://github.com/adriankumpf/teslamate/pull/485) and [#522](https://github.com/adriankumpf/teslamate/pull/522) by [tobiasehlert](https://github.com/tobiasehlert))
- Add Norwegian translation ([#500](https://github.com/adriankumpf/teslamate/pull/500) by [spacecosmos](https://github.com/spacecosmos))
- Add Spanish translation ([#519](https://github.com/adriankumpf/teslamate/pull/519) by [alceasan](https://github.com/alceasan))
- Overview: Add states panel ([#520](https://github.com/adriankumpf/teslamate/pull/520) by [DrMichael](https://github.com/DrMichael))
- Immediately display the current car software version after restarting TeslaMate
- Add mileage to the summary page
- Add option to calculate charging costs retroactively
- Allow to enter total cost or cost per KWh used
- Indicate if any of the doors are open
- Add support for session fees
- Store more vehicle config attributes (`exterior_color`, `wheel_type`, `spoiler_type`)
- Bump Grafana to 6.7.1

#### New MQTT Topics

- `teslamate/cars/$car_id/doors_open`
- `teslamate/cars/$car_id/model`
- `teslamate/cars/$car_id/trim_badging`
- `teslamate/cars/$car_id/exterior_color`
- `teslamate/cars/$car_id/wheel_type`
- `teslamate/cars/$car_id/spoiler_type`

### Bug Fixes

- Drive Stats: Show stats in desired units ([#484](https://github.com/adriankumpf/teslamate/pull/484) by [pichalite](https://github.com/pichalite))
- Drive Details: Fix odometer units ([#487](https://github.com/adriankumpf/teslamate/pull/487) by [pichalite](https://github.com/pichalite))
- Update address formatting to avoid showing obscure names instead of towns/cities
- Charge Details: Hide empty series
- Suppress `Cldr.NoMatchingLocale` warnings
- Trip: Prevent 'division by zero' error
- Open dashboard links in a new tab to work around Grafana regression
- Use the maximum kWh to calculate the charge cost

## [1.17.1] - 2020-02-23

### Bug Fixes

- Fix an error that could prevent new users from logging in, among other things
- Overview dashboard: Display odometer in desired units

## [1.17.0] - 2020-02-23

### Enhancements

[olexs](https://github.com/olexs) has developed a toolkit to export data from the [tesla-apiscraper](https://github.com/lephisto/tesla-apiscraper) InfluxDB backend and convert it to a CSV format that can be imported using the [TeslaFi Import](https://teslamate.readthedocs.io/en/latest/import/teslafi.html). Check it out if you want to migrate data to TeslaMate: [**Import from tesla-apiscraper (BETA)**](https://teslamate.readthedocs.io/en/latest/import/tesla_apiscraper.html)

- Simplify geofence editing: The radius can now be changed interactively.
- Allow geofences to overlap: If multiple geofences cover a position, the geofence whose centre is closest is selected.
- Increase charge cost scale / kWh ([#440](https://github.com/adriankumpf/teslamate/pull/440) by [baylanger](https://github.com/baylanger))
- Charge cost view: Show zoom controls
- TeslaFi Import: Preselect the timezone
- Add configuration option [`DATABASE_SSL`](https://teslamate.readthedocs.io/en/latest/configuration/environment_variables.html)
- Use 'rated' as default preferred range
- Collapse 'Dashboards' dropdown on mobile

#### Dashboards

- Add **Trip dashboard**: This dashboard was built to visualize longer trips. It provides an overview of all drives and charges that were logged over a period of several hours or days.
- _All:_ Link to the web interface and other dashboards
- _Overview:_ Speed up database queries
- _Charges:_ Add geofence filter
- _Charge Details:_ Add cost overview ([#460](https://github.com/adriankumpf/teslamate/pull/460) by [Niek](https://github.com/Niek))
- _Drive Details:_ Add usable battery level graph

#### New MQTT Topics

- `teslamate/cars/$car_id/geofence`: The name of the geofence at the current position

#### Documentation

- Add docs for tesla-apiscraper import ([#454](https://github.com/adriankumpf/teslamate/pull/454) by [olexs](https://github.com/olexs))
- Update Backup & Restore docs ([#438](https://github.com/adriankumpf/teslamate/pull/438) by [AlwindB](https://github.com/AlwindB))
- Revamp manual install docs

### Bug Fixes

- Fix an issue where some CSV files could not be imported

## [1.16.0] - 2020-02-07

### Enhancements

- [Import from TeslaFi (BETA)](https://teslamate.readthedocs.io/en/latest/import/teslafi.html)
- Calculate charge cost based on location and kWh
- Automatically set charge cost to zero if free supercharging is enabled (configurable on the settings page)
- Add French translation ([#397](https://github.com/adriankumpf/teslamate/pull/397) by [tomS3210](https://github.com/tomS3210))
- Improve language detection
- Show odometer on 'Drive Details' dashboard
- Bump Grafana to 6.6.1
- Bump Elixir to 1.10

#### Documentation

- New FAQ entry for adding API tokens directly into the database instead of using username/password ([#412](https://github.com/adriankumpf/teslamate/pull/412) by [wishbone1138](https://github.com/wishbone1138))
- Improve standalone install documentation ([#416](https://github.com/adriankumpf/teslamate/pull/416) by [Niek](https://github.com/Niek))
- Improve iOS Shortcuts guide ([#405](https://github.com/adriankumpf/teslamate/pull/405) by [DP19](https://github.com/DP19))

### Bug Fixes

- Re-add charge annotations to the 'Projected Range' dashboard ([#393](https://github.com/adriankumpf/teslamate/pull/393) by [ctraber](https://github.com/ctraber))
- Correct typos in projected-range.json ([#395](https://github.com/adriankumpf/teslamate/pull/395) by [shagberg](https://github.com/shagberg))
- Increase height of the pie charts panels
- Address an issue where a drive would not be properly completed if the vehicle was suddenly reported as asleep after being offline for a while
- Fix energy used in 'Drive Details'

## [1.15.1] - 2020-01-25

### Enhancements

- Tweak polling intervals
- Make the web interface feel snappier

### Bug Fixes

- Fix an issue where distance, energy used and duration were missing on the Drive Details dashboard if the length unit was set to miles

## [1.15.0] - 2020-01-23

### Enhancements

- Add charge cost interface
- Display usable SOC and show snowflake icon on summary page ([#338](https://github.com/adriankumpf/teslamate/pull/338) by [ctraber](https://github.com/ctraber))
- Log missed software updates
- Add tooltip with the estimated range at 100%
- Remove software version commit hash
- Format remaining charge time
- Add option to use a custom namespace for MQTT topics
- Periodically store vehicle data while online
- Use the Accept-Language HTTP header get the locale (Supported languages: English, German)
- Add setting to change the preferred language of OpenStreetMap results
- Show spinner while fetching vehicle data
- Add dropdown with dashboard links to the navigation bar

#### New MQTT Topics

- `teslamate/cars/$car_id/usable_battery_level`

#### Dashboards

- Projected Range: Use `usable_battery_level` to calculate the projected range and add more panels ([#338](https://github.com/adriankumpf/teslamate/pull/338), [#367](https://github.com/adriankumpf/teslamate/pull/367) by [ctraber](https://github.com/ctraber))
- Add `tesla` tag ([#369](https://github.com/adriankumpf/teslamate/pull/369) by [TechForze](https://github.com/TechForze))
- Vampire Drain: show SOC difference and ❄ (reduced range)
- Charging Stats: Show share of AC/DC charging
- Charging Stats: Show top charging stations by cost
- Overview dashboard: Use the preferred range
- Overview dashboard: Always show latest voltage and power while charging
- Add Charge Level dashboard
- Add Drive Stats dashboard
- Revamp Drives/Drive Details and Charges/Charge Details dashboards

#### Documentation

- Add docs for an advanced Docker install with Apache2 ([#361](https://github.com/adriankumpf/teslamate/pull/361) by [DrMichael](https://github.com/DrMichael))
- Add docs for backup and restore ([#361](https://github.com/adriankumpf/teslamate/pull/361) by [DrMichael](https://github.com/DrMichael))
- Update the macrodroid docs ([#359](https://github.com/adriankumpf/teslamate/pull/359) by [markusdd](https://github.com/markusdd))
- Add docs for manually fixing data
- Add docs for updating Postgres

### Bug Fixes

- Fix tooltips in Safari (iOS)
- Always publish the shift state via MQTT
- Fix an issue where he charge location was not be displayed
- Fix an issue that could cause the added charge kWh to be shown as 0

**⚠️ Please note:** Due to internal changes, all addresses will be recalculated on first startup. Depending on the amount of data, this process may take up to 30 minutes or longer.

## [1.14.3] - 2020-01-06

### Enhancements

- Locations dashboard: Visualize cities and states with the most stored addresses

### Bug Fixes

- Fix an issue where a broken rear window sensor could cause the windows to always be displayed as open
- Address an issue where a charge wouldn't be properly logged if the Tesla API reported invalid charge data
- Fix a bug that could cause the geo-fence form to become unresponsive

## [1.14.2] - 2020-01-03

### Bug Fixes

- Fix an issue where invalid or revoked tokens could cause the application to crash after startup
- Change default time range in the 'Updates' dashboard

## [1.14.1] - 2019-12-24

### Bug Fixes

- Fix an issue where the database migrations would not succeed if there were charges without any data points

## [1.14.0] - 2019-12-22

### Enhancements

#### Documentation

[@gundalow](https://github.com/gundalow) has revamped the docs ([#292](https://github.com/adriankumpf/teslamate/pull/292), [#314](https://github.com/adriankumpf/teslamate/pull/314)). The new documentation is available here: [teslamate.readthedocs.io](https://teslamate.readthedocs.io)

#### Automatic phase correction

The phase correction is now applied automatically.

Background: some vehicles incorrectly report 2 instead of 1 or 3 phases when charging. This led to an incorrect calculation of the 'kWh used'. Furthermore, the calculation did not work reliably in three-phase networks with e.g. 127/220V. Therefore it was necessary in the past to manually activate a phase correction for specific geo-fences. With this update the correction is now applied automatically.

#### Other enhancements

- Refactored API module
- Increased polling frequency in asleep state
- New OSM aliases
- ... and other minor improvements

### Bug Fixes

- Efficiency Dashboard: convert km/h to mph in the temperature efficiency table
- Fix an issue where the application could crash because the database pool was too small
- Fix an issue where a drive/charge could be split into two parts due to API timeouts

## [1.13.2] - 2019-12-07

### Enhancements

- Enable the time range control in the "Charging Stats" dashboard ([#278](https://github.com/adriankumpf/teslamate/pull/278) by [@nnoally](https://github.com/nnoally))
- Various docs improvements ([#285](https://github.com/adriankumpf/teslamate/pull/285) by [@gundalow](https://github.com/gundalow))

### Bug Fixes

- Fix issue where on a brand new installation suspending logging would only work after a restart
- Fix the elevation scale in the Drive Details

## [1.13.1] - 2019-11-26

### Enhancements

Add a database column that will allow tracking charge costs:

- Merge 20191117042320_add_cost_field_to_charges.exs (Charge Cost field) ([#258](https://github.com/adriankumpf/teslamate/pull/258) by [@ngardiner](https://github.com/ngardiner))
- Grafana Dashboard Integration for Charge Cost ([#273](https://github.com/adriankumpf/teslamate/pull/273) by [@ngardiner](https://github.com/ngardiner))

Note: There is no charging cost interface either manual or automatic at this point but there will be in the future.

### Bug Fixes

- Downgrade the Grafana docker image to v6.3.7 because there are still issues with ARM-compatible images
- Fix an issue where the selected car was not displayed when opening the drive or charging details

## [1.13.0] - 2019-11-25

### New Features

- Display link "Dashboards" inside the navigation bar (it becomes visible after clicking an address in one of the Grafana dashboards. Alternatively the Grafana URL can be added manually on the settings page)
- Enable or disable the sleep mode depending on the location. For example, the car can be allowed to sleep at home or work, but nowhere else.
- Extend Charge Stats Dashboard with discharge stats, a charge delta graph and a charge heatmap ([#270](https://github.com/adriankumpf/teslamate/pull/270) by [@marcogabriel](https://github.com/marcogabriel))

### Enhancements

- Make sleep mode separately configurable for each car
- Reduce default "Time to try sleeping" to 12 minutes for newer vehicles
- The "States" dashboard now includes software updates
- Automatically repair trips and charges with missing addresses (e.g. because OpenStreetMap was temporarily unavailable)
- Update thresholds of the battery level gauge ([#256](https://github.com/adriankumpf/teslamate/pull/256) by [@marcogabriel](https://github.com/marcogabriel))

### Bug Fixes

- Fix issue where consumption values were displayed as 0
- Fix issue where installing a software update when charging would produce an incomplete charge record

## [1.12.2] - 2019-11-06

### Bug Fixes

- Fix an issue where the "states" graph would not show every drive/charge
- Fix an issue where the application would not start if the vehicle was parked at a place with poor reception
- Remove duplicate table row "Remaining Time"

## [1.12.1] - 2019-11-03

### Enhancements

- Display remaining time while charging

### New MQTT Topics

- `teslamate/cars/$car_id/heading`

### Bug Fixes

- Consistent language for label of charging events ([#299](https://github.com/adriankumpf/teslamate/pull/229))
- Cap charging efficiency to 100%

## [1.12.0] - 2019-10-28

We finally have **documentation**! Many thanks to [@ngardiner](https://github.com/ngardiner), who gave the impulse and did most of the work and also to [@krezac](https://github.com/krezac), who contributed a guide to creating iOS Shortcuts for TeslaMate!

### New Features

#### Vehicle Efficiency

Previous versions of TeslaMate shipped with hard-coded efficiency values for the various Tesla models. These efficiency values are needed to calculate trip consumptions, because the Tesla API does not provide them directly.

The hard-coded values were _probably_ pretty accurate, but it was impossible to ensure the correctness of all of them. In addition, the new Model S and X "Raven" could not be reliably identified because the Tesla API returns wrong option codes for both.

This version eliminates the need to use these hard-coded values and instead calculates them based on the recorded charging data. It takes **at least two** charges to display the first estimate. Each subsequent charge will then continue to improve the accuracy of the estimate, which is applied retroactively to all data.

#### Charge energy used

In addition to the kWh added to the battery during the charge TeslaMate now calculates the actual energy used by the charger, which in most cases is higher than the energy added to the battery.

Consider this feature somewhat experimental. Theoretically, however, it should be pretty accurate as long as the vehicle has a stable internet connection while charging (other paid Tesla loggers use the same calculation method).

Currently, a firmware bug in some vehicles may cause the wrong number of phases to be reported when charging at some chargers. As a workaround, a phase correction can be activated per geo-fence.

#### New MQTT Topics

- `teslamate/cars/$car_id/update_available`
- `teslamate/cars/$car_id/is_climate_on`
- `teslamate/cars/$car_id/is_preconditioning`
- `teslamate/cars/$car_id/is_user_present`

### Enhancements

- Show icon indicators for various states (sentry mode, vehicle locked, windows open, pre-conditioning etc.)
- Various UI Tweaks
- Grafana: show the precise duration of a trip in a tooltip
- Serve gzipped assets
- Disable origin check by default to simplify the installation of TeslaMate. (⚠️ For publicly exposed TeslaMate instances it is advisable to re-enable the check by adding the environment variable `CHECK_ORIGIN=true`.)

### Bug Fixes

- Set the correct end date for charges where the vehicle remains plugged in after completion
- Fix an issue with vehicles that were removed from the Tesla Account
- Correctly handle API responses which indicate that the vehicle is in service
- Display effects of range gains (e.g. from supercharging pre-conditioning a cold battery) as NULL

## [1.11.1] - 2019-10-13

### Bug Fixes

- Show all cars in the Overview dashboard

## [1.11.0] - 2019-10-12

### New Features

- Add overview dashboard (by DBemis;
  [#196](https://github.com/adriankumpf/teslamate/pull/196))
- Make :check_origin option configurable via environment variable
  `CHECK_ORIGIN`
- Open GitHub release page when clicking the version tag in the navbar
- Display the current software version

### New MQTT topics

- `teslamate/cars/$car_id/version`: Current software version

### Enhancements

- Tweak the mobile and desktop views
- Add GIST index based on `ll_to_earth` to speed up geo-fence lookups
- Improve accuracy of geo-fence lookups for some edge cases
- Log option codes as well if the vehicle identification fails
- Delete trips with less than 10m driven
- Add/Update efficiency factors

### Bug Fixes

- Fix an issue where postgres' automatic analyze couldn't succeed
- Fix an issue where the derived efficiency factors could not be calculated
- Exit early if migrations fail
- Downgrade Grafana to v6.3.5

## [1.10.0] - 2019-10-05

### Enhancements

- Allow editing of geo-fence positions
- Show warning icon if the health check fails for a vehicle
- Use the best available SRTM data source which provides global elevation data
  including 60N and above
- Optimize the comparison of geo-fences by moving the lookup into the database
- Use the exact position instead of the center of an address for the geo-fence
  lookup
- Generally improve error handling and error messages
- Improve landscape mode on devices with a notch

- Open the geo-fence editor by clicking on the start or destination address of
  a trip

  **Note:** For this feature to work Grafana needs to know the base URL of the
  TeslaMate web interface. To automatically set the base URL open the web
  interface once after upgrading to this version. Manually changing the base
  URL is possible via the settings page.

#### New MQTT topics

- `teslamate/cars/$car_id/healthy`: Reports the health status of the logger
- `teslamate/cars/$car_id/windows_open`
- `teslamate/cars/$car_id/shift_state`
- `teslamate/cars/$car_id/latitude`
- `teslamate/cars/$car_id/longitude`
- `teslamate/cars/$car_id/odometer`
- `teslamate/cars/$car_id/charge_port_door_open`
- `teslamate/cars/$car_id/charger_actual_current`
- `teslamate/cars/$car_id/charger_phases`
- `teslamate/cars/$car_id/charger_power`
- `teslamate/cars/$car_id/charger_voltage`
- `teslamate/cars/$car_id/time_to_full_charge`

### Bug Fixes

- Automatically restart parts of the application if Tesla decides yet again to
  change the IDs of some vehicles
- Request to sign in again if the access tokens become invalid e.g. because the
  password of the Tesla Account has been changed
- Protect against empty payloads during an update to prevent an update from
  not being fully logged
- Log the number of charging phases as returned by the API

### ⚠️ Running Migrations

_Users of the default `docker-compose.yml` can skip this part._

To run the migrations successfully, the database user has to have
superuser rights (temporarily):

- To add superuser rights: `ALTER USER teslamate WITH SUPERUSER;`
- To remove superuser rights: `ALTER USER teslamate WITH NOSUPERUSER;`

## [1.9.1] - 2019-09-24

### Fixed

- Set position when selecting a search entry
- Fix deletion of geo-fences

## [1.9.0] - 2019-09-24

### Added

- Show a map with the current vehicle position on the web interface
- Add a satellite/hybrid layer to the geo-fence map
- Use elevation data with 1 arc second (~30m) accuracy everywhere not just in
  the US
- Add support for MQTT SSL ([#140](https://github.com/adriankumpf/teslamate/pull/140))
- Add "Charged" annotation to the degradation dashboard
- Add preferred range setting: you can now choose between "ideal" and "rated"
  range to use as the basis for efficiency and other metrics

### Changed

- Require a data source named "TeslaMate":

  If you don't run the `teslamate/grafana` docker container the Grafana data
  source has to have the name "TeslaMate". Prior to this change the default
  data source was used.

- Renamed the MQTT topic `teslamate/cars/$car_id/battery_range_km` to
  `teslamate/cars/$car_id/rated_battery_range_km`.

### Fixed

- Prevent suspending when an update is in progress
- Fix charge counter when using with multi vehicles
  ([#175](https://github.com/adriankumpf/teslamate/pull/175))

### Removed

- Drop support for the deprecated env variables `TESLA_USERNAME` and
  `TESLA_PASSWORD`

## [1.8.0] - 2019-09-03

### Added

- Identify cars by VIN: This hopefully eliminates any upcoming problems when
  Tesla decides yet again to change the IDs of their cars ...
- Pick geo-fences from a map and show their radius

### Fixed

- Only add elevation to positions for which SRTM elevation data is available
- [Security] Bump Grafana version

## [1.7.0] - 2019-08-29

### Added

- Locally (!) query all locations for elevation data from the NASA Shuttle
  Radar Topography Mission (SRTM)
- Add elevation graph to the `Drive Details` dashboard
- Display rated range on the web interface and on the `Drive Details` dashboard
- Switch to the `vehicle_config` API endpoint to identify vehicles
- Display the default and derived efficiency factor on the `Efficiency` dashboard
  to detect inaccuracies and to **crowdsource** the correct factors:

  **Note:** If there is no default efficiency factor or you think the default factor for
  your vehicle might be wrong, please open an issue and attach a screenshot of
  the table showing the efficiency factor(s) for your vehicle.

- Display charger power on the web interface

### Fixed

- Fix calculation of `charge_energy_added` if a previously stopped charge
  session is resumed

## [1.6.2] - 2019-08-26

### Fixed

- Fix migration that could panic when upgrading from v1.4 to v1.6
- Fix efficiency calculation

## [1.6.1] - 2019-08-25

### Added

- Add separately configurable sleep requirements

### Fixed

- Improve identification of performance models
- Fix Model X identification
- Improve browser compatibility of the web interface
- Disable basic auth in Grafana
- Remove pre-calculated consumption columns and instead calculate consumption
  values dynamically based on the given efficiency factor
- Add various database constraints to keep data in a consistent state

## [1.6.0] - 2019-08-18

### Added / Changed

#### Dashboards

- Display car name instead of its id and replace dropdown with separate row for each car
- Improve States dashboard:
  - show state names instead of arbitrary numbers
  - include drives and charge sessions
- Vampire Drain: include offline state when calculating the standby value
- Drive Details: add estimated range graph
- Degradation: Increase resolution of projected 100% range

#### Web UI

- Add favicons
- Fetch last known values from database after (re)starting TeslaMate
- Show duration of current state
- Show estimated range
- Hide stale temperature data
- Hide some metrics when they're not needed

### Fixed

- Interpret a significant offline period with SOC gains as a charge session
- Timeout drive after being offline for too long
- Dashboards: Dynamically calculate consumption values based on stored `car.efficiency`

## [1.5.3] - 2019-08-14

### Fixed

- Add extra values to the "Time to Try Sleeping" dropdown
- Rollback the "Time to Try Sleeping" setting to previous pre v1.5 value (21 min) to play it safe

  **Note to Model 3 owners and everyone who likes to tweak things a bit**: most
  cars seem to handle a value of 12 min just fine. Doing so reduces the
  likelihood of potential data gaps. Just keep an eye on your car afterwards to
  see if it still goes into sleep mode.

- Enable filtering of charges by date
- Fix charges query to include the very first charge

## [1.5.2] - 2019-08-13

### Fixed

- Fix migration that could panic if upgrading from &lt;v1.4.3 to v1.5

## [1.5.1] - 2019-08-13

### Fixed

- Remove `shift_state` condition which could prevent some cars from falling asleep

## [1.5.0] - 2019-08-12

### Added

- Add geo-fence feature
- Make units of length and temperature separately configurable
- Make `time to try sleeping` and `idle time before trying to sleep` configurable
- Show buttons `try to sleep` and `cancel sleep attempt` on status screen if possible
- Add charging stats: charged in total, total number of charges, top charging stations

### Changed

- Reduce time to try sleeping from 21 to 12 minutes
- Increase test coverage
- Rename some dashboards / panels

### Fixed

- Add order by clause to degradation query
- Read `LOCALE` at runtime

## 1.4

### 1. New custom grafana image: `teslamate/grafana`

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

### 2. Switch to imperial units

There is a new settings view in the web interface. To use imperial measurements
in grafana and on the status screen just tick the checkbox it shows!

### 3. Deprecation of TESLA_USERNAME and TESLA_PASSWORD

With this release API tokens are stored in the database. After starting
TeslaMate v1.4 once, you can safely remove both environment variables.

New users need to sign in via the web interface.

**Full Changelog:**

## [1.4.3] - 2019-08-05

### Added

- Status screen: show additional charging related information
- MQTT: add new topics

  ```text
  teslamate/cars/$car_id/plugged_in
  teslamate/cars/$car_id/scheduled_charging_start_time
  teslamate/cars/$car_id/charge_limit_soc
  ```

### Fixed

- Fix an issue where charging processes were not completed and new charging
  processes were created after waking up from sleep mode while still plugged in
  to a charger.
- Add migration to fix incomplete charging processes
- Use local time in debug logs:

  Add a `TZ` variable with your local timezone name to the environment of the
  `teslamate` container. Otherwise timestamps use UTC.

- Charging History: hide entries with 0kWh charge energy added
- Charging History: include current `car-id` in links to `Charging` dashboard
- Charging History: use slightly earlier start date in links to `Charging`
  dashboard to always show the current position

## [1.4.2] - 2019-08-01

### Fixed

- Persists tokens after auto refresh

## [1.4.1] - 2019-07-31

### Fixed

- Convert to imperial measurements on status screen
- Fix warnings

## [1.4.0] - 2019-07-31

### Dashboards

#### Added

- Introduce custom teslamate/grafana Docker image
- Fetch unit variables from database

#### Fixed

- Fix syntax errors in consumption and charging dashboard
- The consumption and charging dashboards can now be viewed without having to
  select a drive / charging process first.

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

[unreleased]: https://github.com/teslamate-org/teslamate/compare/v1.33.0...HEAD
[1.33.0]: https://github.com/teslamate-org/teslamate/compare/v1.32.0...v1.33.0
[1.32.0]: https://github.com/teslamate-org/teslamate/compare/v1.31.1...v1.32.0
[1.31.1]: https://github.com/teslamate-org/teslamate/compare/v1.31.0...v1.31.1
[1.31.0]: https://github.com/teslamate-org/teslamate/compare/v1.30.1...v1.31.0
[1.30.1]: https://github.com/teslamate-org/teslamate/compare/v1.30.0...v1.30.1
[1.30.0]: https://github.com/teslamate-org/teslamate/compare/v1.29.2...v1.30.0
[1.29.2]: https://github.com/teslamate-org/teslamate/compare/v1.29.1...v1.29.2
[1.29.1]: https://github.com/teslamate-org/teslamate/compare/v1.29.0...v1.29.1
[1.29.0]: https://github.com/teslamate-org/teslamate/compare/v1.28.5...v1.29.0
[1.28.5]: https://github.com/teslamate-org/teslamate/compare/v1.28.4...v1.28.5
[1.28.4]: https://github.com/teslamate-org/teslamate/compare/v1.28.3...v1.28.4
[1.28.3]: https://github.com/teslamate-org/teslamate/compare/v1.28.2...v1.28.3
[1.28.2]: https://github.com/teslamate-org/teslamate/compare/v1.28.1...v1.28.2
[1.28.1]: https://github.com/teslamate-org/teslamate/compare/v1.28.0...v1.28.1
[1.28.0]: https://github.com/teslamate-org/teslamate/compare/v1.27.4...v1.28.0
[1.27.4]: https://github.com/adriankumpf/teslamate/compare/v1.27.3...v1.27.4
[1.27.3]: https://github.com/adriankumpf/teslamate/compare/v1.27.2...v1.27.3
[1.27.2]: https://github.com/adriankumpf/teslamate/compare/v1.27.1...v1.27.2
[1.27.1]: https://github.com/adriankumpf/teslamate/compare/v1.27.0...v1.27.1
[1.27.0]: https://github.com/adriankumpf/teslamate/compare/v1.26.1...v1.27.0
[1.26.1]: https://github.com/adriankumpf/teslamate/compare/v1.26.0...v1.26.1
[1.26.0]: https://github.com/adriankumpf/teslamate/compare/v1.25.2...v1.26.0
[1.25.2]: https://github.com/adriankumpf/teslamate/compare/v1.25.1...v1.25.2
[1.25.1]: https://github.com/adriankumpf/teslamate/compare/v1.25.0...v1.25.1
[1.25.0]: https://github.com/adriankumpf/teslamate/compare/v1.24.2...v1.25.0
[1.24.2]: https://github.com/adriankumpf/teslamate/compare/v1.24.1...v1.24.2
[1.24.1]: https://github.com/adriankumpf/teslamate/compare/v1.24.0...v1.24.1
[1.24.0]: https://github.com/adriankumpf/teslamate/compare/v1.23.7...v1.24.0
[1.23.7]: https://github.com/adriankumpf/teslamate/compare/v1.23.6...v1.23.7
[1.23.6]: https://github.com/adriankumpf/teslamate/compare/v1.23.5...v1.23.6
[1.23.5]: https://github.com/adriankumpf/teslamate/compare/v1.23.4...v1.23.5
[1.23.4]: https://github.com/adriankumpf/teslamate/compare/v1.23.3...v1.23.4
[1.23.3]: https://github.com/adriankumpf/teslamate/compare/v1.23.2...v1.23.3
[1.23.2]: https://github.com/adriankumpf/teslamate/compare/v1.23.1...v1.23.2
[1.23.1]: https://github.com/adriankumpf/teslamate/compare/v1.23.0...v1.23.1
[1.23.0]: https://github.com/adriankumpf/teslamate/compare/v1.22.0...v1.23.0
[1.22.0]: https://github.com/adriankumpf/teslamate/compare/v1.21.6...v1.22.0
[1.21.6]: https://github.com/adriankumpf/teslamate/compare/v1.21.5...v1.21.6
[1.21.5]: https://github.com/adriankumpf/teslamate/compare/v1.21.4...v1.21.5
[1.21.4]: https://github.com/adriankumpf/teslamate/compare/v1.21.3...v1.21.4
[1.21.3]: https://github.com/adriankumpf/teslamate/compare/v1.21.2...v1.21.3
[1.21.2]: https://github.com/adriankumpf/teslamate/compare/v1.21.1...v1.21.2
[1.21.1]: https://github.com/adriankumpf/teslamate/compare/v1.21.0...v1.21.1
[1.21.0]: https://github.com/adriankumpf/teslamate/compare/v1.20.1...v1.21.0
[1.20.1]: https://github.com/adriankumpf/teslamate/compare/v1.20.0...v1.20.1
[1.20.0]: https://github.com/adriankumpf/teslamate/compare/v1.19.4...v1.20.0
[1.19.4]: https://github.com/adriankumpf/teslamate/compare/v1.19.3...v1.19.4
[1.19.3]: https://github.com/adriankumpf/teslamate/compare/v1.19.2...v1.19.3
[1.19.2]: https://github.com/adriankumpf/teslamate/compare/v1.19.1...v1.19.2
[1.19.1]: https://github.com/adriankumpf/teslamate/compare/v1.19.0...v1.19.1
[1.19.0]: https://github.com/adriankumpf/teslamate/compare/v1.18.2...v1.19.0
[1.18.2]: https://github.com/adriankumpf/teslamate/compare/v1.18.1...v1.18.2
[1.18.1]: https://github.com/adriankumpf/teslamate/compare/v1.18.0...v1.18.1
[1.18.0]: https://github.com/adriankumpf/teslamate/compare/v1.17.1...v1.18.0
[1.17.1]: https://github.com/adriankumpf/teslamate/compare/v1.17.0...v1.17.1
[1.17.0]: https://github.com/adriankumpf/teslamate/compare/v1.16.0...v1.17.0
[1.16.0]: https://github.com/adriankumpf/teslamate/compare/v1.15.1...v1.16.0
[1.15.1]: https://github.com/adriankumpf/teslamate/compare/v1.15.0...v1.15.1
[1.15.0]: https://github.com/adriankumpf/teslamate/compare/v1.14.3...v1.15.0
[1.14.3]: https://github.com/adriankumpf/teslamate/compare/v1.14.2...v1.14.3
[1.14.2]: https://github.com/adriankumpf/teslamate/compare/v1.14.1...v1.14.2
[1.14.1]: https://github.com/adriankumpf/teslamate/compare/v1.14.0...v1.14.1
[1.14.0]: https://github.com/adriankumpf/teslamate/compare/v1.13.2...v1.14.0
[1.13.2]: https://github.com/adriankumpf/teslamate/compare/v1.13.1...v1.13.2
[1.13.1]: https://github.com/adriankumpf/teslamate/compare/v1.13.0...v1.13.1
[1.13.0]: https://github.com/adriankumpf/teslamate/compare/v1.12.2...v1.13.0
[1.12.2]: https://github.com/adriankumpf/teslamate/compare/v1.12.1...v1.12.2
[1.12.1]: https://github.com/adriankumpf/teslamate/compare/v1.12.0...v1.12.1
[1.12.0]: https://github.com/adriankumpf/teslamate/compare/v1.11.1...v1.12.0
[1.11.1]: https://github.com/adriankumpf/teslamate/compare/v1.11.0...v1.11.1
[1.11.0]: https://github.com/adriankumpf/teslamate/compare/v1.10.0...v1.11.0
[1.10.0]: https://github.com/adriankumpf/teslamate/compare/v1.9.1...v1.10.0
[1.9.1]: https://github.com/adriankumpf/teslamate/compare/v1.9.0...v1.9.1
[1.9.0]: https://github.com/adriankumpf/teslamate/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/adriankumpf/teslamate/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/adriankumpf/teslamate/compare/v1.6.2...v1.7.0
[1.6.2]: https://github.com/adriankumpf/teslamate/compare/v1.6.1...v1.6.2
[1.6.1]: https://github.com/adriankumpf/teslamate/compare/v1.6.0...v1.6.1
[1.6.0]: https://github.com/adriankumpf/teslamate/compare/v1.5.3...v1.6.0
[1.5.3]: https://github.com/adriankumpf/teslamate/compare/v1.5.2...v1.5.3
[1.5.2]: https://github.com/adriankumpf/teslamate/compare/v1.5.1...v1.5.2
[1.5.1]: https://github.com/adriankumpf/teslamate/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/adriankumpf/teslamate/compare/v1.4.3...v1.5.0
[1.4.3]: https://github.com/adriankumpf/teslamate/compare/v1.4.2...v1.4.3
[1.4.2]: https://github.com/adriankumpf/teslamate/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/adriankumpf/teslamate/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/adriankumpf/teslamate/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/adriankumpf/teslamate/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/adriankumpf/teslamate/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/adriankumpf/teslamate/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/adriankumpf/teslamate/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/adriankumpf/teslamate/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/adriankumpf/teslamate/compare/3d95859...v1.0.0
