# Optional Simplified Chinese dashboard export

This directory contains a Simplified Chinese catalog and a manual, display-only
exporter for the bundled Grafana dashboards. It is not called by the Docker build,
provisioning, TeslaMate's web UI, or any installation/update script. English
remains the default. Nothing is installed or connected to a database by the tool.

## Scope and terminology

The catalog covers the 24 dashboards and 200 panels shipped with v4.4.0,
including detail pages and the Dutch tax report. It translates titles, column and
legend names, descriptions, custom filter labels, and selected display values.
It does not translate Grafana itself or user-entered locations and vehicle names.

| Source term            | Chinese              | Meaning retained                                                            |
| ---------------------- | -------------------- | --------------------------------------------------------------------------- |
| Energy added           | 充入电量             | Energy added to the battery, not electricity purchased from the grid.       |
| Energy used (charging) | 充电耗电量           | The upstream charging-energy accounting, including its fallbacks.           |
| Consumption (net)      | 行驶电耗             | Driving consumption, including the net effect of regeneration.              |
| Consumption (gross)    | 综合电耗             | Includes non-driving consumption; not charger-to-battery losses.            |
| Driving efficiency     | 续航达成率           | Actual distance compared with reported range reduction.                     |
| Derived efficiency     | 基准电耗             | A range-to-energy conversion estimate, not measured driving efficiency.     |
| Projected range        | 估算满电续航         | A full-charge extrapolation, not navigation arrival range or a CLTC rating. |
| Charging cycles        | 等效完整充电循环次数 | Equivalent full cycles, not the number of charging sessions.                |

Battery capacity and degradation descriptions identify their estimates and data
limitations. Rated/ideal range is not relabeled as CLTC. The Dutch tax report
retains its jurisdiction; the Chinese text does not imply Chinese tax compliance.
Temperature range labels use 15% and 85% quantiles as the lower and upper
bounds; the band contains the middle 70% of readings. Display selectors also
recognize translated names so temperature and state statistics retain their fields.

Units and currency are not converted. For example, 100 Wh/km is 10 kWh/100 km;
the exporter never labels an unchanged Wh/km value as kWh/100 km.

## Generate and inspect

Use Python 3.9 or later, with no third-party Python dependencies, from this
repository's root. Choose an output directory that does not already exist:

```sh
python3 grafana/i18n/zh-Hans/export.py grafana/dashboards ../grafana-zh-Hans
```

The output contains `main/`, `internal/`, `reports/`, and a source hash manifest.
Source files are never modified. Existing output directories are refused.

The catalog pins the exact upstream dashboard file set and SHA-256 hashes for
v4.4.0. A different snapshot or edited/private dashboard export is refused until
its source and catalog have been reviewed. Descriptions match complete source
strings, not prefixes. This intentionally favors explicit review over silently
applying old translations to new formulas or dashboard structures.

## Optional manual use with the bundled Grafana image

Back up Grafana's data and configuration first. Review the generated JSON. Keep
the output on persistent storage and append these **read-only** bind mounts to
Grafana's existing volumes, replacing the example source paths:

```yaml
services:
  grafana:
    volumes:
      - /absolute/path/grafana-zh-Hans/main:/dashboards:ro
      - /absolute/path/grafana-zh-Hans/internal:/dashboards_internal:ro
      - /absolute/path/grafana-zh-Hans/reports:/dashboards_reports:ro
```

Recreate only Grafana using the installation's existing Compose file and project
name. Keep its existing data volume, environment, ports, and other configuration.
The dashboards retain their original UIDs, so this replaces their display content
rather than installing another set alongside English. Shared instances therefore
use one dashboard-content language; this is not per-user language selection.
Grafana's own language setting and the provisioning folder names are separate.

To return to the bundled English definitions, remove these three bind mounts and
recreate only Grafana. Do not delete directories while they are still mounted.
Before updating TeslaMate, compare the new upstream definitions and review the
catalog and its source hashes. Do not simply refresh hashes to bypass the guard.

## Validation

```sh
python3 -m unittest discover -s grafana/i18n/zh-Hans -p 'test_*.py' -v
```

Tests exercise the complete bundled snapshot and synthetic cases for SQL aliases,
`time` columns, transformation inputs, field matchers, units, links, filter values,
and context-sensitive charging terminology. The exporter also checks invariants
before writing output. Translation rules were manually checked with actual data
on five key dashboards in Grafana 13.2.4; no installation settings, telemetry,
credentials, or private screenshots are included here.

Translations and tooling were prepared with AI assistance. Additional native
language and domain review is welcome. Code and translations follow this
repository's AGPL-3.0-or-later license.
