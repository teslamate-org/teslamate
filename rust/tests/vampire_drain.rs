//! Compares `teslamate_rust::vampire_drain` with the SQL of the Grafana
//! dashboard it ports, read from `grafana/dashboards/vampire-drain.json` at
//! run time, so a change to either side shows up here.
//!
//! Needs a Postgres database migrated to the current schema (the Ecto
//! migrations in `elixir/priv/repo/migrations`), configured like the app via
//! `DATABASE_USER`, `DATABASE_PASS`, `DATABASE_HOST`, `DATABASE_PORT` and
//! `DATABASE_NAME`. Run it with
//!
//! ```sh
//! cargo test --test vampire_drain -- --ignored
//! ```
//!
//! It inserts `fixtures/vampire_drain.sql` and runs both queries in one
//! transaction that it rolls back, so the database is unchanged afterwards,
//! also when the test fails.

use std::{cmp::Reverse, error::Error, fmt::Write as _, fs, path::Path};

use clap::Parser;
use serde_json::Value;
use sqlx::{
    AssertSqlSafe, Row as _,
    postgres::PgRow,
    types::{
        BigDecimal,
        chrono::{DateTime, Utc},
    },
};
use teslamate_rust::{
    config, db,
    vampire_drain::{self, LengthUnit, Params, PreferredRange, Row},
};

/// The car all fixtures belong to.
const CAR_ID: i16 = -1;

const FIXTURES: &str = include_str!("fixtures/vampire_drain.sql");

type Result<T> = std::result::Result<T, Box<dyn Error>>;

/// The database settings, read from the environment like the app does.
#[derive(Parser)]
struct Env {
    #[command(flatten)]
    database: config::Database,
}

#[tokio::test]
#[ignore = "needs a Postgres database, see the module docs; fails without one"]
async fn port_returns_the_rows_of_the_dashboard_query() -> Result<()> {
    let dashboard_sql = dashboard_sql()?;
    let database = Env::try_parse_from(["vampire_drain"])
        .map_err(|e| format!("configure the test database with DATABASE_*: {e}"))?
        .database;
    let pool = db::connect(&database).await.map_err(|e| {
        format!(
            "cannot connect to database {:?} on {}:{}: {e}",
            database.name, database.host, database.port
        )
    })?;

    // Dropping the transaction, e.g. when an assertion fails, rolls it back.
    let mut transaction = pool.begin().await?;
    sqlx::raw_sql(FIXTURES)
        .execute(&mut *transaction)
        .await
        .map_err(|e| format!("cannot insert the fixtures (is the schema migrated?): {e}"))?;

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

            let sql = expand(&dashboard_sql, &params)?;
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

/// The SQL of the "Vampire Drain" panel.
fn dashboard_sql() -> Result<String> {
    let path =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../grafana/dashboards/vampire-drain.json");
    let json: Value = serde_json::from_str(
        &fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?,
    )?;
    let sql: Vec<&str> = json["panels"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|panel| panel["title"] == "Vampire Drain")
        .flat_map(|panel| panel["targets"].as_array().into_iter().flatten())
        .filter_map(|target| target["rawSql"].as_str())
        .collect();
    match sql[..] {
        [sql] => Ok(sql.to_owned()),
        _ => Err(format!(
            "{}: expected one query in the panel \"Vampire Drain\", found {}",
            path.display(),
            sql.len()
        )
        .into()),
    }
}

/// `sql` with the Grafana macros and variables replaced by `params`, as
/// Grafana's Postgres data source does: values spliced in as text, the time
/// range as UTC timestamps. No casts or other changes are needed for the
/// result to decode into [`Row`].
fn expand(sql: &str, params: &Params) -> Result<String> {
    const TIME_FILTER: &str = "$__timeFilter(";
    // Grafana documents the expansion as `dateColumn BETWEEN
    // '2020-07-13T20:19:09.254Z' AND '2020-07-13T21:19:09.254Z'`: UTC with
    // milliseconds. Time-series macros table on
    // https://grafana.com/docs/grafana/latest/datasources/postgres/query-editor/
    const GRAFANA_TIME: &str = "%Y-%m-%dT%H:%M:%S%.3fZ";

    let mut expanded = String::new();
    let mut rest = sql;
    while let Some((before, after)) = rest.split_once(TIME_FILTER) {
        let (column, after) = after.split_once(')').ok_or("unterminated $__timeFilter(")?;
        expanded.push_str(before);
        write!(
            expanded,
            "{} BETWEEN '{}' AND '{}'",
            column.trim(),
            params.from.format(GRAFANA_TIME),
            params.to.format(GRAFANA_TIME),
        )?;
        rest = after;
    }
    expanded.push_str(rest);

    let range = match params.preferred_range {
        PreferredRange::Ideal => "ideal",
        PreferredRange::Rated => "rated",
    };
    let expanded = expanded
        .replace("${preferred_range}", range)
        .replace("${length_unit}", unit(params.length_unit))
        .replace("$length_unit", unit(params.length_unit))
        .replace("$car_id", &params.car_id.to_string())
        .replace("$duration", &params.min_duration_hours.to_string());

    // Catches variables the dashboard gains later.
    match expanded.find('$') {
        None => Ok(expanded),
        Some(at) => Err(format!(
            "unexpanded variable in the dashboard SQL: {}",
            expanded[at..].lines().next().unwrap_or_default()
        )
        .into()),
    }
}

const fn unit(length_unit: LengthUnit) -> &'static str {
    match length_unit {
        LengthUnit::Km => "km",
        LengthUnit::Mi => "mi",
    }
}

fn expected_column_names(length_unit: LengthUnit) -> Vec<String> {
    let unit = unit(length_unit);
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

fn column_names(row: Option<&PgRow>) -> Vec<String> {
    row.map(|row| {
        row.columns()
            .iter()
            .map(|column| sqlx::Column::name(column).to_owned())
            .collect()
    })
    .unwrap_or_default()
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

fn utc(rfc3339: &str) -> Result<DateTime<Utc>> {
    Ok(DateTime::parse_from_rfc3339(rfc3339)?.to_utc())
}
