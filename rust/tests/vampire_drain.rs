//! Compares `teslamate_rust::vampire_drain` with the SQL of the Grafana
//! dashboard it ports, read from `grafana/dashboards/vampire-drain.json` at
//! run time, so a change to either side shows up here. See `common` for
//! what it needs; run it with
//!
//! ```sh
//! cargo test --test vampire_drain -- --ignored
//! ```

mod common;

use std::cmp::Reverse;

use common::{Result, column_names, dashboard_sql, expand, length_unit, preferred_range, utc};
use sqlx::{AssertSqlSafe, Row as _, postgres::PgRow, types::BigDecimal};
use teslamate_rust::{
    settings::{LengthUnit, PreferredRange},
    vampire_drain::{self, Params, Row},
};

/// The car all fixtures belong to.
const CAR_ID: i16 = -1;

const FIXTURES: &str = include_str!("fixtures/vampire_drain.sql");

#[tokio::test]
#[ignore = "needs a Postgres database, see the module docs; fails without one"]
async fn port_returns_the_rows_of_the_dashboard_query() -> Result<()> {
    let dashboard_sql = dashboard_sql("vampire-drain.json", "Vampire Drain")?;
    let mut transaction = common::transaction_with(FIXTURES).await?;

    for preferred_range in [PreferredRange::Ideal, PreferredRange::Rated] {
        for length_unit in [LengthUnit::Km, LengthUnit::Mi] {
            let params = Params {
                car_id: CAR_ID,
                from: utc("2024-03-01T08:00:00Z")?,
                to: utc("2024-03-05T18:00:00Z")?,
                min_duration_hours: 6,
                preferred_range,
                length_unit,
            };
            let case = format!("{preferred_range:?}, {length_unit:?}");

            let sql = expand_for(&dashboard_sql, &params)?;
            let rows = sqlx::query(AssertSqlSafe(sql))
                .fetch_all(&mut *transaction)
                .await?;
            assert!(!rows.is_empty(), "{case}: no rows, nothing to compare");
            assert_eq!(
                column_names(rows.first()),
                expected_column_names(length_unit),
                "{case}: the dashboard's columns changed",
            );
            let mut expected = rows.iter().map(decode).collect::<sqlx::Result<Vec<_>>>()?;
            // The dashboard leaves the order to its CTE; the port orders
            // newest first. The fixtures have no two equal start dates.
            expected.sort_by_key(|row| Reverse(row.start_date));

            assert!(
                expected.iter().any(|row| row.has_reduced_range == Some(1))
                    && expected.iter().any(|row| row.has_reduced_range == Some(0)),
                "{case}: the fixtures no longer cover both has_reduced_range values",
            );
            assert!(
                expected.iter().any(|row| row
                    .standby
                    .as_ref()
                    .is_some_and(|s| s > &BigDecimal::from(0))),
                "{case}: the fixtures no longer cover standby",
            );

            let actual = vampire_drain::fetch(&mut *transaction, &params).await?;
            assert_eq!(actual, expected, "{case}: port and dashboard differ");
        }
    }

    transaction.rollback().await?;
    Ok(())
}

/// The dashboard SQL for `params`. No casts or other changes are needed
/// for the result to decode into [`Row`].
fn expand_for(sql: &str, params: &Params) -> Result<String> {
    expand(
        sql,
        params.from,
        params.to,
        &[
            ("$car_id", &params.car_id.to_string()),
            ("$duration", &params.min_duration_hours.to_string()),
            (
                "${preferred_range}",
                preferred_range(params.preferred_range),
            ),
            ("$length_unit", length_unit(params.length_unit)),
            ("${length_unit}", length_unit(params.length_unit)),
        ],
    )
}

fn expected_column_names(length_unit: LengthUnit) -> Vec<String> {
    let unit = common::length_unit(length_unit);
    [
        "start_date_ts",
        "end_date_ts",
        "start_date",
        "end_date",
        "duration",
        "standby",
        "soc_diff",
        "has_reduced_range",
        &format!("range_diff_{unit}"),
        "consumption",
        "avg_power",
        &format!("range_lost_per_hour_{unit}"),
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
        start_date: row.try_get(2)?,
        end_date: row.try_get(3)?,
        duration: row.try_get(4)?,
        standby: row.try_get(5)?,
        soc_diff: row.try_get(6)?,
        has_reduced_range: row.try_get(7)?,
        range_diff: row.try_get(8)?,
        consumption: row.try_get(9)?,
        avg_power: row.try_get(10)?,
        range_lost_per_hour: row.try_get(11)?,
    })
}
