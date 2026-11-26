//! Compares `teslamate_rust::drives` with the SQL of the "Drive" table in
//! the Grafana dashboard `grafana/dashboards/drives.json`, read at run time,
//! so a change to either side shows up here. See `common` for what it
//! needs; run it with
//!
//! ```sh
//! cargo test --test drives -- --ignored
//! ```

mod common;

use std::{cmp::Ordering, collections::BTreeSet};

use common::{Result, column_names, dashboard_sql, expand, length_unit, preferred_range, utc};
use sqlx::{AssertSqlSafe, Postgres, Row as _, Transaction, postgres::PgRow, types::BigDecimal};
use teslamate_rust::{
    drives::{self, Direction, Efficiency, Geofences, Params, Row, Sort, SortKey},
    settings::{LengthUnit, PreferredRange, TemperatureUnit},
};

const FIXTURES: &str = include_str!("fixtures/drives.sql");

/// The drives of car -1 in the time range that have a distance.
const LISTED: [i32; 8] = [-1, -2, -3, -4, -5, -6, -7, -8];

#[tokio::test]
#[ignore = "needs a Postgres database, see tests/common; fails without one"]
async fn port_returns_the_rows_of_the_dashboard_query() -> Result<()> {
    let sql = dashboard_sql("drives.json", "Drive")?;
    let mut transaction = common::transaction_with(FIXTURES).await?;
    let base = base()?;

    // Every combination of units, preferred range and efficiency mode.
    for length_unit in [LengthUnit::Km, LengthUnit::Mi] {
        for temperature_unit in [TemperatureUnit::Celsius, TemperatureUnit::Fahrenheit] {
            for preferred_range in [PreferredRange::Ideal, PreferredRange::Rated] {
                for efficiency in [Efficiency::SlopeAdjusted, Efficiency::ByDistance] {
                    let params = Params {
                        length_unit,
                        temperature_unit,
                        preferred_range,
                        efficiency,
                        ..base.clone()
                    };
                    let rows = compare(&mut transaction, &sql, &params).await?;
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
    let filtered = [
        (
            Params {
                geofences: Geofences::Any(vec![-12, -13]),
                ..base.clone()
            },
            vec![-1, -2, -5, -6],
        ),
        (
            Params {
                geofences: Geofences::Any(vec![-11]),
                ..base.clone()
            },
            vec![-1, -2, -3],
        ),
        (
            Params {
                location: Some("BAKE".to_owned()),
                ..base.clone()
            },
            vec![-3, -4],
        ),
        (
            Params {
                location: Some("ville".to_owned()),
                ..base.clone()
            },
            vec![-3, -4, -7, -8],
        ),
        // 1.5 km is exactly the distance of drive -3.
        (
            Params {
                min_distance: "1.5".parse()?,
                ..base.clone()
            },
            vec![-1, -2, -3, -4, -5, -6, -7],
        ),
        (
            Params {
                min_distance: BigDecimal::from(15),
                ..base.clone()
            },
            vec![-1, -2, -5],
        ),
        // 36 km/h is exactly the average speed of drive -4.
        (
            Params {
                min_speed: BigDecimal::from(36),
                ..base.clone()
            },
            vec![-1, -4, -5, -8],
        ),
    ];
    for (params, expected) in filtered {
        let rows = compare(&mut transaction, &sql, &params).await?;
        assert_eq!(
            drive_ids(&rows),
            BTreeSet::from_iter(expected),
            "{params:?}: the filtered drives"
        );
    }

    // Every sort key in both directions.
    for key in SortKey::ALL {
        for direction in [Direction::Ascending, Direction::Descending] {
            let params = Params {
                sort: Some(Sort { key, direction }),
                ..base.clone()
            };
            compare(&mut transaction, &sql, &params).await?;
        }
    }

    transaction.rollback().await?;
    Ok(())
}

/// The dashboard's defaults, for car -1 in May 2024.
fn base() -> Result<Params> {
    Ok(Params {
        car_id: -1,
        from: utc("2024-05-01T00:00:00Z")?,
        to: utc("2024-05-31T00:00:00Z")?,
        length_unit: LengthUnit::Km,
        temperature_unit: TemperatureUnit::Celsius,
        preferred_range: PreferredRange::Ideal,
        min_distance: BigDecimal::from(0),
        min_speed: BigDecimal::from(0),
        geofences: Geofences::All,
        location: None,
        efficiency: Efficiency::SlopeAdjusted,
        sort: None,
    })
}

/// Runs the dashboard SQL and the port for `params`, checks that they
/// return the same rows, and returns them. The dashboard's rows are sorted
/// in Rust by `params.sort`, as the port documents it.
async fn compare(
    transaction: &mut Transaction<'static, Postgres>,
    sql: &str,
    params: &Params,
) -> Result<Vec<Row>> {
    let reference = expand_for(sql, params)?;
    let rows = sqlx::query(AssertSqlSafe(reference))
        .fetch_all(&mut **transaction)
        .await?;
    assert!(!rows.is_empty(), "{params:?}: no rows, nothing to compare");
    assert_eq!(
        column_names(rows.first()),
        expected_column_names(params),
        "{params:?}: the dashboard's columns changed",
    );
    let mut expected = rows.iter().map(decode).collect::<sqlx::Result<Vec<_>>>()?;
    // Without a sort key, this is the dashboard's own ORDER BY.
    expected.sort_by(|a, b| compare_rows(a, b, params.sort));

    let actual = drives::fetch(&mut **transaction, params).await?;
    assert_eq!(actual, expected, "{params:?}: port and dashboard differ");
    Ok(actual)
}

/// The dashboard SQL for `params`, with the values formatted as Grafana
/// does. Single values are spliced in as they are; a multi-value variable
/// becomes its quoted values joined by commas
/// (<https://grafana.com/docs/grafana/latest/datasources/postgres/template-variables/>),
/// `${...:pipe}` joins them with `|`
/// (<https://grafana.com/docs/grafana/latest/dashboards/variables/variable-syntax/>).
/// "All" is the custom all value `-1`, which Grafana inserts "never
/// escaped"
/// (<https://grafana.com/docs/grafana/latest/dashboards/variables/add-template-variables/>);
/// that `:pipe` leaves it unformatted too is what the dashboard's
/// `'${geofence:pipe}' = '-1'` relies on, the docs do not say so.
fn expand_for(sql: &str, params: &Params) -> Result<String> {
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
    expand(
        sql,
        params.from,
        params.to,
        &[
            ("$car_id", &params.car_id.to_string()),
            ("$length_unit", length_unit(params.length_unit)),
            ("$temp_unit", temperature_unit(params.temperature_unit)),
            (
                "${preferred_range}",
                preferred_range(params.preferred_range),
            ),
            ("$min_dist", &params.min_distance.to_string()),
            ("$min_speed", &params.min_speed.to_string()),
            ("$geofence", &geofence),
            ("${geofence:pipe}", &geofence_pipe),
            // The dashboard's text box is empty for no filter.
            ("$location", params.location.as_deref().unwrap_or_default()),
            ("$efficiency", efficiency(params.efficiency)),
        ],
    )
}

const fn temperature_unit(unit: TemperatureUnit) -> &'static str {
    match unit {
        TemperatureUnit::Celsius => "C",
        TemperatureUnit::Fahrenheit => "F",
    }
}

const fn efficiency(efficiency: Efficiency) -> &'static str {
    match efficiency {
        Efficiency::SlopeAdjusted => "slope-adjusted",
        Efficiency::ByDistance => "by distance",
    }
}

fn expected_column_names(params: &Params) -> Vec<String> {
    let length = length_unit(params.length_unit);
    // Unquoted in the SQL, so Postgres folds it to lower case.
    let temperature = temperature_unit(params.temperature_unit).to_lowercase();
    [
        "start_date_ts",
        "end_date_ts",
        "car_id",
        "start_path",
        "end_path",
        "duration_str",
        "drive_id",
        "start_date",
        "start_address",
        "end_address",
        "duration_min",
        &format!("distance_{length}"),
        "% Start",
        "% End",
        &format!("outside_temp_{temperature}"),
        &format!("speed_avg_{length}"),
        &format!("speed_max_{length}"),
        "power_max",
        "has_reduced_range",
        "efficiency",
        "consumption_kWh",
        &format!("consumption_kwh_{length}"),
    ]
    .map(str::to_owned)
    .to_vec()
}

/// A dashboard row as a [`Row`], by column position; `column_names`
/// checks the positions.
fn decode(row: &PgRow) -> sqlx::Result<Row> {
    Ok(Row {
        start_date_ts: row.try_get(0)?,
        end_date_ts: row.try_get(1)?,
        car_id: row.try_get(2)?,
        start_path: row.try_get(3)?,
        end_path: row.try_get(4)?,
        duration_str: row.try_get(5)?,
        drive_id: row.try_get(6)?,
        start_date: row.try_get(7)?,
        start_address: row.try_get(8)?,
        end_address: row.try_get(9)?,
        duration_min: row.try_get(10)?,
        distance: row.try_get(11)?,
        start_battery_level: row.try_get(12)?,
        end_battery_level: row.try_get(13)?,
        outside_temp: row.try_get(14)?,
        speed_avg: row.try_get(15)?,
        speed_max: row.try_get(16)?,
        power_max: row.try_get(17)?,
        has_reduced_range: row.try_get(18)?,
        efficiency: row.try_get(19)?,
        consumption_kwh: row.try_get(20)?,
        consumption_wh_per_distance: row.try_get(21)?,
    })
}

/// The order `drives::fetch` documents: by the sort key, NULLs last in
/// either direction, then by drive id, newest first. The fixtures' addresses
/// differ in their first letter, so any collation orders them like Rust.
fn compare_rows(a: &Row, b: &Row, sort: Option<Sort>) -> Ordering {
    let by_key = sort.map_or(Ordering::Equal, |sort| {
        let ordering = match sort.key {
            SortKey::StartDate => nulls_last(a.start_date.as_ref(), b.start_date.as_ref()),
            SortKey::StartAddress => nulls_last(a.start_address.as_ref(), b.start_address.as_ref()),
            SortKey::EndAddress => nulls_last(a.end_address.as_ref(), b.end_address.as_ref()),
            SortKey::DurationMin => nulls_last(a.duration_min.as_ref(), b.duration_min.as_ref()),
            SortKey::Distance => nulls_last(a.distance.as_ref(), b.distance.as_ref()),
            SortKey::StartBatteryLevel => nulls_last(
                a.start_battery_level.as_ref(),
                b.start_battery_level.as_ref(),
            ),
            SortKey::EndBatteryLevel => {
                nulls_last(a.end_battery_level.as_ref(), b.end_battery_level.as_ref())
            }
            SortKey::OutsideTemp => nulls_last(a.outside_temp.as_ref(), b.outside_temp.as_ref()),
            SortKey::SpeedAvg => nulls_last(a.speed_avg.as_ref(), b.speed_avg.as_ref()),
            SortKey::SpeedMax => nulls_last(a.speed_max.as_ref(), b.speed_max.as_ref()),
            SortKey::PowerMax => nulls_last(a.power_max.as_ref(), b.power_max.as_ref()),
            SortKey::HasReducedRange => {
                nulls_last(a.has_reduced_range.as_ref(), b.has_reduced_range.as_ref())
            }
            SortKey::Efficiency => nulls_last(a.efficiency.as_ref(), b.efficiency.as_ref()),
            SortKey::ConsumptionKwh => {
                nulls_last(a.consumption_kwh.as_ref(), b.consumption_kwh.as_ref())
            }
            SortKey::ConsumptionWhPerDistance => nulls_last(
                a.consumption_wh_per_distance.as_ref(),
                b.consumption_wh_per_distance.as_ref(),
            ),
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

fn nulls_last<T: PartialOrd>(a: Option<&T>, b: Option<&T>) -> Order {
    match (a, b) {
        (Some(a), Some(b)) => Order::Values(a.partial_cmp(b).unwrap_or(Ordering::Equal)),
        (Some(_), None) => Order::Nulls(Ordering::Less),
        (None, Some(_)) => Order::Nulls(Ordering::Greater),
        (None, None) => Order::Nulls(Ordering::Equal),
    }
}

fn drive_ids(rows: &[Row]) -> BTreeSet<i32> {
    rows.iter().filter_map(|row| row.drive_id).collect()
}
