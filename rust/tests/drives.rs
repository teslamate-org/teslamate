//! The drives port against the dashboard's own query, on a real database.
//!
//! `port_matches_the_original_dashboard_sql` reads the raw SQL of the
//! "Drive" table from `grafana/dashboards/drives.json`, expands the Grafana
//! macros and checks that the port and the dashboard's query return the
//! same rows on the same database, for every unit, preferred range and
//! efficiency combination, each filter and every sort key. The sort is
//! Grafana's browser feature, so the comparison sorts the dashboard's rows
//! in Rust the way the port's `ORDER BY` does. Building the reference from
//! the dashboard file keeps it from drifting silently when the dashboard
//! changes.
//!
//! The database the comparison runs against is `TEST_DATABASE_URL` if set,
//! else `DATABASE_URL`; either way it must be migrated to the `TeslaMate`
//! schema. The macro-expansion tests keep the reference builder honest
//! without needing one.

use std::cmp::Ordering;
use std::collections::BTreeSet;

use bigdecimal::BigDecimal;
use chrono::NaiveDate;
use diesel_async::{AsyncConnection, AsyncPgConnection, RunQueryDsl, SimpleAsyncConnection};

use teslamate_rust::database::queries::drives::{
    Direction, Drive, DrivesParams, Efficiency, Geofences, Sort, SortKey, build_query,
};
use teslamate_rust::settings::{LengthUnit, PreferredRange, TemperatureUnit};

/// The drives of car -1 in the time range that have a distance: what the
/// base case, the dashboard's defaults, lists.
const LISTED: [i32; 8] = [-1, -2, -3, -4, -5, -6, -7, -8];

/// The dashboard's defaults, for car -1 in May 2024.
fn base() -> DrivesParams {
    DrivesParams {
        car_id: -1,
        from: NaiveDate::from_ymd_opt(2024, 5, 1)
            .unwrap_or_default()
            .and_hms_opt(0, 0, 0)
            .unwrap_or_default(),
        to: NaiveDate::from_ymd_opt(2024, 5, 31)
            .unwrap_or_default()
            .and_hms_opt(0, 0, 0)
            .unwrap_or_default(),
        length_unit: LengthUnit::Kilometers,
        temperature_unit: TemperatureUnit::Celsius,
        preferred_range: PreferredRange::Ideal,
        min_distance: BigDecimal::from(0),
        min_speed: BigDecimal::from(0),
        geofences: Geofences::All,
        location: None,
        efficiency: Efficiency::SlopeAdjusted,
        sort: None,
    }
}

/// The dashboard's raw query, read from the dashboard JSON so that the
/// reference used by [`reference_sql`] cannot drift from the dashboard
/// silently.
fn dashboard_raw_sql() -> Result<String, String> {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../grafana/dashboards/drives.json"
    );
    let dashboard: serde_json::Value = std::fs::read_to_string(path)
        .map_err(|e| format!("failed to read {path}: {e}"))
        .and_then(|text| {
            serde_json::from_str(&text).map_err(|e| format!("failed to parse {path}: {e}"))
        })?;

    dashboard
        .get("panels")
        .and_then(|panels| find_panel(panels, "Drive"))
        .and_then(|panel| panel.get("targets"))
        .and_then(|targets| targets.get(0))
        .and_then(|target| target.get("rawSql"))
        .and_then(|raw_sql| raw_sql.as_str())
        .map(str::to_owned)
        .ok_or_else(|| format!("no rawSql found in the Drive panel of {path}"))
}

/// Find a panel by title, descending into nested panels.
fn find_panel<'a>(panels: &'a serde_json::Value, title: &str) -> Option<&'a serde_json::Value> {
    panels.as_array()?.iter().find_map(|panel| {
        if panel.get("title").and_then(serde_json::Value::as_str) == Some(title) {
            Some(panel)
        } else {
            find_panel(panel.get("panels")?, title)
        }
    })
}

const TIME_FILTER: &str = "$__timeFilter(";

/// Expand the Grafana macros and template variables of the dashboard
/// query the way its Postgres data source does, with one deliberate
/// difference: the time filter becomes naive timestamp literals instead of
/// the RFC 3339 ones Grafana substitutes, so the comparison happens in the
/// column's own type instead of depending on the session time zone.
///
/// A multi-value `$geofence` becomes its quoted values joined by commas,
/// `${geofence:pipe}` its values joined by `|`, and "All" the dashboard's
/// custom all value `-1`, which Grafana inserts "never escaped". Unknown
/// variables are an error rather than passed through, so a dashboard
/// change that introduces a new variable fails the tests instead of
/// producing a query the port was never compared against.
fn expand_dashboard_macros(raw_sql: &str, params: &DrivesParams) -> Result<String, String> {
    let from = params.from;
    let to = params.to;

    // `$__timeFilter(<column>)` → `<column> BETWEEN '<from>' AND '<to>'`.
    let mut expanded = String::with_capacity(raw_sql.len());
    let mut rest = raw_sql;
    while let Some(open) = rest.find(TIME_FILTER) {
        let column_start = open + TIME_FILTER.len();
        let Some(close) = rest[column_start..].find(')') else {
            return Err(format!("unterminated {TIME_FILTER} in the dashboard SQL"));
        };
        let column = rest[column_start..column_start + close].trim();
        expanded.push_str(&rest[..open]);
        let filter = format!("{column} BETWEEN '{from}' AND '{to}'");
        expanded.push_str(&filter);
        rest = &rest[column_start + close + 1..];
    }
    expanded.push_str(rest);

    // The remaining variables, substituted textually, longest name first
    // so that none replaces the start of a longer one.
    let (geofence, geofence_pipe) = match &params.geofences {
        Geofences::All => ("-1".to_owned(), "-1".to_owned()),
        Geofences::Any(ids) => (
            ids.iter()
                .map(|id| format!("'{id}'"))
                .collect::<Vec<_>>()
                .join(","),
            ids.iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join("|"),
        ),
    };
    let mut variables: Vec<(&str, String)> = vec![
        ("${geofence:pipe}", geofence_pipe),
        ("$geofence", geofence),
        ("$car_id", params.car_id.to_string()),
        ("$length_unit", params.length_unit.as_str().to_owned()),
        ("$temp_unit", params.temperature_unit.as_str().to_owned()),
        (
            "${preferred_range}",
            params.preferred_range.as_str().to_owned(),
        ),
        ("$min_dist", params.min_distance.to_string()),
        ("$min_speed", params.min_speed.to_string()),
        // The dashboard's text box is empty for no filter.
        ("$location", params.location.clone().unwrap_or_default()),
        (
            "$efficiency",
            efficiency_value(params.efficiency).to_owned(),
        ),
    ];
    variables.sort_by_key(|(name, _)| std::cmp::Reverse(name.len()));
    for (name, value) in variables {
        expanded = expanded.replace(name, &value);
    }

    match expanded.find('$') {
        None => Ok(expanded),
        Some(at) => {
            let rest = expanded[at..].lines().next().unwrap_or_default();
            Err(format!("unexpanded variable in the dashboard SQL: {rest}"))
        }
    }
}

const fn efficiency_value(efficiency: Efficiency) -> &'static str {
    match efficiency {
        Efficiency::SlopeAdjusted => "slope-adjusted",
        Efficiency::ByDistance => "by distance",
    }
}

/// The expanded dashboard query, wrapped so that it loads into the same
/// [`Drive`] rows as the port:
///
/// * the epoch-millisecond columns are cast to `bigint` (the dashboard
///   returns them as `numeric`, which Diesel cannot deserialize into
///   `i64`; the cast is exact, as `floor(...)`/`ceil(...)` times 1000 is
///   integral);
/// * the columns whose names the dashboard derives from the units, and
///   its quoted `% Start`, `% End` and `consumption_kWh`, get the port's
///   plain names (the wrapper deserializes by column name).
///
/// The wrapper is ours, not the dashboard's: if the dashboard renames its
/// output columns, this query fails instead of comparing stale SQL.
fn reference_sql(raw_sql: &str, params: &DrivesParams) -> Result<String, String> {
    let inner = expand_dashboard_macros(raw_sql, params)?;
    let inner = inner.trim().trim_end_matches(';').trim();
    let length = params.length_unit.as_str();
    let temperature = params.temperature_unit.as_str().to_lowercase();
    Ok(format!(
        "SELECT
  dashboard.start_date_ts::bigint AS start_date_ts,
  dashboard.end_date_ts::bigint AS end_date_ts,
  dashboard.car_id,
  dashboard.start_path,
  dashboard.end_path,
  dashboard.duration_str,
  dashboard.drive_id,
  dashboard.start_date,
  dashboard.start_address,
  dashboard.end_address,
  dashboard.duration_min,
  dashboard.distance_{length} AS distance,
  dashboard.\"% Start\" AS start_battery_level,
  dashboard.\"% End\" AS end_battery_level,
  dashboard.outside_temp_{temperature} AS outside_temp,
  dashboard.speed_avg_{length} AS speed_avg,
  dashboard.speed_max_{length} AS speed_max,
  dashboard.power_max,
  dashboard.has_reduced_range,
  dashboard.efficiency,
  dashboard.\"consumption_kWh\" AS consumption_kwh,
  dashboard.consumption_kwh_{length} AS consumption_wh_per_distance
FROM ({inner}) dashboard"
    ))
}

#[test]
fn expands_the_dashboard_macros() -> Result<(), String> {
    let raw = dashboard_raw_sql()?;
    assert!(raw.contains("WITH data AS"), "{raw}");

    let sql = expand_dashboard_macros(&raw, &base())?;
    assert!(
        sql.contains(
            "WHERE start_date BETWEEN '2024-05-01 00:00:00' AND '2024-05-31 00:00:00' AND drives.car_id = -1"
        ),
        "{sql}"
    );
    // the reduced_range_info CTE is filtered by the same time range
    assert!(
        sql.contains(
            "where date BETWEEN '2024-05-01 00:00:00' AND '2024-05-31 00:00:00' AND car_id = -1"
        ),
        "{sql}"
    );
    assert!(
        sql.contains("start_ideal_range_km - end_ideal_range_km as range_diff"),
        "{sql}"
    );
    // "All" is the dashboard's custom all value, unformatted by :pipe
    assert!(
        sql.contains("('-1' = '-1' OR start_geofence.id in (-1) OR end_geofence.id in (-1))"),
        "{sql}"
    );
    // Every variable must be expanded; a leftover `$` means the dashboard
    // introduced something the expander does not know about.
    assert!(!sql.contains('$'), "{sql}");

    let reference = reference_sql(&raw, &base())?;
    assert!(
        reference.contains("dashboard.distance_km AS distance"),
        "{reference}"
    );
    assert!(
        reference.contains("dashboard.start_date_ts::bigint AS start_date_ts"),
        "{reference}"
    );

    let mut selected = base();
    selected.preferred_range = PreferredRange::Rated;
    selected.length_unit = LengthUnit::Miles;
    selected.temperature_unit = TemperatureUnit::Fahrenheit;
    selected.efficiency = Efficiency::ByDistance;
    selected.geofences = Geofences::Any(vec![-12, -13]);
    let sql = expand_dashboard_macros(&raw, &selected)?;
    assert!(
        sql.contains("start_rated_range_km - end_rated_range_km as range_diff"),
        "{sql}"
    );
    assert!(sql.contains("'mi') AS distance_mi"), "{sql}");
    assert!(
        sql.contains(
            "('-12|-13' = '-1' OR start_geofence.id in ('-12','-13') OR end_geofence.id in ('-12','-13'))"
        ),
        "{sql}"
    );
    Ok(())
}

#[test]
fn rejects_unknown_dashboard_variables() {
    assert!(expand_dashboard_macros("$unknown", &base()).is_err());
}

/// The fixtures for the comparison test, as documented at the top of the
/// file: the drives of car -1, before, inside and after the time range,
/// with the filters' edge cases.
const FIXTURES: &str = include_str!("fixtures/drives.sql");

/// The database the comparison test runs against: `TEST_DATABASE_URL` if
/// set, else `DATABASE_URL`. Either way it must be migrated to the
/// `TeslaMate` schema; the CI build starts a Postgres, migrates it and
/// points `TEST_DATABASE_URL` at it.
fn test_database_url() -> Result<String, String> {
    std::env::var("TEST_DATABASE_URL")
        .or_else(|_| std::env::var("DATABASE_URL"))
        .map_err(|_| {
            "neither TEST_DATABASE_URL nor DATABASE_URL is set: the comparison test \
             needs a Postgres migrated to the TeslaMate schema"
                .to_owned()
        })
}

/// Runs the port and the dashboard's own query for `params` and returns
/// the port's rows, after checking that both agree.
///
/// The dashboard's own `ORDER BY` is the newest drive first; Grafana sorts
/// the table in the browser instead. Without a sort key the comparison
/// therefore takes both queries' rows as they come back, and with one it
/// checks that the port's rows come back in that order: by the sort key
/// with NULLs last, then the drive id, newest first.
async fn compare(
    conn: &mut AsyncPgConnection,
    raw: &str,
    params: &DrivesParams,
) -> Result<Vec<Drive>, Box<dyn std::error::Error + Send + Sync>> {
    let case = format!("{:?}", (params.length_unit, params.temperature_unit));
    let ported = build_query(params).load::<Drive>(conn).await?;
    let mut original = diesel::sql_query(reference_sql(raw, params)?)
        .load::<Drive>(conn)
        .await?;

    // The comparison needs rows to compare; every case is built to list
    // at least one.
    assert!(!ported.is_empty(), "{case}: the port returned no rows");
    assert!(
        !original.is_empty(),
        "{case}: the dashboard returned no rows"
    );

    // The sort is the port's addition: with a sort key, the dashboard's
    // rows are ordered the way the port's `ORDER BY` does, and the
    // port's rows must already come back in that order. Without one,
    // both queries' own `ORDER BY` is the newest drive first.
    if let Some(sort) = params.sort {
        original.sort_by(|a, b| compare_rows(a, b, Some(sort)));
    }
    assert_eq!(ported, original, "{case}: port and dashboard differ");
    Ok(ported)
}

/// The order the port's `ORDER BY` produces: by the sort key in the given
/// direction, NULLs last either way, then by drive id, newest first. The
/// fixtures' addresses differ in their first letter, so any collation
/// orders them like Rust does.
fn compare_rows(a: &Drive, b: &Drive, sort: Option<Sort>) -> Ordering {
    let by_key = sort.map_or(Ordering::Equal, |sort| {
        let ordering = match sort.key {
            SortKey::StartDate => nulls_last(Some(a.start_date), Some(b.start_date)),
            SortKey::StartAddress => {
                nulls_last(a.start_address.as_deref(), b.start_address.as_deref())
            }
            SortKey::EndAddress => nulls_last(a.end_address.as_deref(), b.end_address.as_deref()),
            SortKey::DurationMin => nulls_last(a.duration_min, b.duration_min),
            SortKey::Distance => nulls_last(a.distance.as_ref(), b.distance.as_ref()),
            SortKey::StartBatteryLevel => nulls_last(a.start_battery_level, b.start_battery_level),
            SortKey::EndBatteryLevel => nulls_last(a.end_battery_level, b.end_battery_level),
            SortKey::OutsideTemp => nulls_last(a.outside_temp.as_ref(), b.outside_temp.as_ref()),
            SortKey::SpeedAvg => nulls_last(a.speed_avg.as_ref(), b.speed_avg.as_ref()),
            SortKey::SpeedMax => nulls_last(a.speed_max.as_ref(), b.speed_max.as_ref()),
            SortKey::PowerMax => nulls_last(a.power_max, b.power_max),
            SortKey::HasReducedRange => nulls_last(a.has_reduced_range, b.has_reduced_range),
            SortKey::Efficiency => nulls_last(a.efficiency, b.efficiency),
            SortKey::ConsumptionKwh => nulls_last(a.consumption_kwh, b.consumption_kwh),
            SortKey::ConsumptionWhPerDistance => {
                nulls_last(a.consumption_wh_per_distance, b.consumption_wh_per_distance)
            }
        };
        match ordering {
            Order::Values(ordering) if sort.direction == Direction::Descending => {
                ordering.reverse()
            }
            Order::Values(ordering) | Order::Nulls(ordering) => ordering,
        }
    });
    by_key.then_with(|| b.drive_id.cmp(&a.drive_id))
}

/// An ordering of two values, or one decided by a NULL, which the
/// direction does not reverse.
enum Order {
    Values(Ordering),
    Nulls(Ordering),
}

fn nulls_last<T: PartialOrd>(a: Option<T>, b: Option<T>) -> Order {
    match (a, b) {
        (Some(a), Some(b)) => Order::Values(a.partial_cmp(&b).unwrap_or(Ordering::Equal)),
        (Some(_), None) => Order::Nulls(Ordering::Less),
        (None, Some(_)) => Order::Nulls(Ordering::Greater),
        (None, None) => Order::Nulls(Ordering::Equal),
    }
}

fn drive_ids(rows: &[Drive]) -> BTreeSet<i32> {
    rows.iter().map(|row| row.drive_id).collect()
}

/// Runs the port and the dashboard's own query — read from
/// `grafana/dashboards/drives.json` with its macros expanded — on
/// [`FIXTURES`] and compares the rows: every combination of units,
/// preferred range and efficiency mode, each filter, and every sort key
/// in both directions. Both are supposed to return the same result, so
/// any difference is a porting bug.
///
/// The fixtures run in a transaction that is rolled back, so the database
/// is unchanged; they all belong to car -1, so the result does not depend
/// on whatever else the database holds.
#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn port_matches_the_original_dashboard_sql()
-> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let url = test_database_url()?;
    let raw = dashboard_raw_sql()?;
    let mut conn = AsyncPgConnection::establish(&url).await?;

    // Returning Err(RollbackTransaction) rolls the transaction back: the
    // fixtures must never reach the database, pass or fail.
    let outcome = conn
        .transaction::<(), Box<dyn std::error::Error + Send + Sync>, _>(async |conn| {
            conn.batch_execute(FIXTURES).await.map_err(|e| {
                format!("cannot insert the fixtures (is the schema migrated?): {e}")
            })?;

            // Every combination of units, preferred range and efficiency
            // mode, with the dashboard's defaults otherwise.
            for length_unit in [LengthUnit::Kilometers, LengthUnit::Miles] {
                for temperature_unit in [TemperatureUnit::Celsius, TemperatureUnit::Fahrenheit] {
                    for preferred_range in [PreferredRange::Ideal, PreferredRange::Rated] {
                        for efficiency in [Efficiency::SlopeAdjusted, Efficiency::ByDistance] {
                            let params = DrivesParams {
                                length_unit,
                                temperature_unit,
                                preferred_range,
                                efficiency,
                                ..base()
                            };
                            let rows = compare(conn, &raw, &params).await?;
                            assert_eq!(
                                drive_ids(&rows),
                                BTreeSet::from(LISTED),
                                "{params:?}: the time, car and distance filters"
                            );
                        }
                    }
                }
            }

            // Each filter, which has to remove rows the base case lists.
            let filtered: [(DrivesParams, &[i32]); 7] = [
                (
                    DrivesParams {
                        geofences: Geofences::Any(vec![-12, -13]),
                        ..base()
                    },
                    &[-1, -2, -5, -6],
                ),
                (
                    DrivesParams {
                        geofences: Geofences::Any(vec![-11]),
                        ..base()
                    },
                    &[-1, -2, -3],
                ),
                (
                    DrivesParams {
                        location: Some("BAKE".to_owned()),
                        ..base()
                    },
                    &[-3, -4],
                ),
                (
                    DrivesParams {
                        location: Some("ville".to_owned()),
                        ..base()
                    },
                    &[-3, -4, -7, -8],
                ),
                // 1.5 km is exactly the distance of drive -3.
                (
                    DrivesParams {
                        min_distance: BigDecimal::from(15) / 10,
                        ..base()
                    },
                    &[-1, -2, -3, -4, -5, -6, -7],
                ),
                (
                    DrivesParams {
                        min_distance: BigDecimal::from(15),
                        ..base()
                    },
                    &[-1, -2, -5],
                ),
                // 36 km/h is exactly the average speed of drive -4.
                (
                    DrivesParams {
                        min_speed: BigDecimal::from(36),
                        ..base()
                    },
                    &[-1, -4, -5, -8],
                ),
            ];
            for (params, expected) in filtered {
                let rows = compare(conn, &raw, &params).await?;
                assert_eq!(
                    drive_ids(&rows),
                    expected.iter().copied().collect::<BTreeSet<_>>(),
                    "{params:?}: the filtered drives"
                );
            }

            // Every sort key in both directions, and the dashboard's own
            // order without one.
            for key in SortKey::ALL {
                for direction in [Direction::Ascending, Direction::Descending] {
                    let params = DrivesParams {
                        sort: Some(Sort { key, direction }),
                        ..base()
                    };
                    let rows = compare(conn, &raw, &params).await?;
                    assert_eq!(drive_ids(&rows), BTreeSet::from(LISTED), "{key:?}");
                }
            }

            Err(diesel::result::Error::RollbackTransaction.into())
        })
        .await;

    match outcome {
        Err(e)
            if matches!(
                e.downcast_ref::<diesel::result::Error>(),
                Some(diesel::result::Error::RollbackTransaction)
            ) =>
        {
            Ok(())
        }
        Err(e) => Err(e),
        // The callback never returns Ok; a commit would persist fixtures.
        Ok(()) => Err("the fixture transaction committed instead of rolling back".into()),
    }
}
