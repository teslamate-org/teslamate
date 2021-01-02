# Changelog

## [1.22.0-dev]

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

#### Other enhancements:

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

**Documentation**

[@gundalow](https://github.com/gundalow) has revamped the docs ([#292](https://github.com/adriankumpf/teslamate/pull/292), [#314](https://github.com/adriankumpf/teslamate/pull/314)). The new documentation is available here: [teslamate.readthedocs.io](https://teslamate.readthedocs.io)

**Automatic phase correction**

The phase correction is now applied automatically.

Background: some vehicles incorrectly report 2 instead of 1 or 3 phases when charging. This led to an incorrect calculation of the 'kWh used'. Furthermore, the calculation did not work reliably in three-phase networks with e.g. 127/220V. Therefore it was necessary in the past to manually activate a phase correction for specific geo-fences. With this update the correction is now applied automatically.

**Other enhancements**

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

* Open the geo-fence editor by clicking on the start or destination address of
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

**Dashboards**

- Display car name instead of its id and replace dropdown with separate row for each car
- Improve States dashboard:
  - show state names instead of arbitrary numbers
  - include drives and charge sessions
- Vampire Drain: include offline state when calculating the standby value
- Drive Details: add estimated range graph
- Degradation: Increase resolution of projected 100% range

**Web UI**

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
  cars seem to handle a value of 12min just fine. Doing so reduces the
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

**2. Switch to imperial units**

There is a new settings view in the web interface. To use imperial measurements
in grafana and on the status screen just tick the checkbox it shows!

**3. Deprecation of TESLA_USERNAME and TESLA_PASSWORD**

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

[1.22.0-dev]: https://github.com/adriankumpf/teslamate/compare/v1.21.0...HEAD
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
