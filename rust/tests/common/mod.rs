//! Shared by the tests that compare a port with the Grafana dashboard query
//! it ports. Each inserts its fixtures and runs both queries in one
//! transaction that it rolls back; see `database` for what they need.

pub mod database;

use std::{fmt::Write as _, fs, path::Path};

pub use database::Result;
use serde_json::Value;
use sqlx::{
    Postgres, Row as _, Transaction,
    postgres::PgRow,
    types::chrono::{DateTime, Utc},
};
use teslamate_rust::settings::{LengthUnit, PreferredRange};

/// A transaction on the test database with `fixtures` inserted.
pub async fn transaction_with(fixtures: &'static str) -> Result<Transaction<'static, Postgres>> {
    let mut transaction = database::transaction().await?;
    sqlx::raw_sql(fixtures)
        .execute(&mut *transaction)
        .await
        .map_err(|e| format!("cannot insert the fixtures (is the schema migrated?): {e}"))?;
    Ok(transaction)
}

/// The SQL of the panel titled `panel` in `grafana/dashboards/<dashboard>`.
pub fn dashboard_sql(dashboard: &str, panel: &str) -> Result<String> {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../grafana/dashboards")
        .join(dashboard);
    let json: Value = serde_json::from_str(
        &fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?,
    )?;
    let sql: Vec<&str> = json["panels"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|candidate| candidate["title"] == panel)
        .flat_map(|candidate| candidate["targets"].as_array().into_iter().flatten())
        .filter_map(|target| target["rawSql"].as_str())
        .collect();
    match sql[..] {
        [sql] => Ok(sql.to_owned()),
        _ => Err(format!(
            "{}: expected one query in the panel {panel:?}, found {}",
            path.display(),
            sql.len()
        )
        .into()),
    }
}

/// `sql` with `$__timeFilter(column)` expanded to the range `from`..`to`
/// and every variable in `variables` replaced by its value, spliced in as
/// text as Grafana does. A variable is given as it appears in the SQL, e.g.
/// `$car_id`, `${preferred_range}` or `${geofence:pipe}`, with its value
/// already formatted the way Grafana formats it there. Fails if a `$` is
/// left, e.g. from a variable the dashboard gained later.
pub fn expand(
    sql: &str,
    from: DateTime<Utc>,
    to: DateTime<Utc>,
    variables: &[(&str, &str)],
) -> Result<String> {
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
            from.format(GRAFANA_TIME),
            to.format(GRAFANA_TIME),
        )?;
        rest = after;
    }
    expanded.push_str(rest);

    // Longest first, so that no variable replaces the start of a longer one.
    let mut variables = variables.to_vec();
    variables.sort_by_key(|(name, _)| std::cmp::Reverse(name.len()));
    for (name, value) in variables {
        expanded = expanded.replace(name, value);
    }

    match expanded.find('$') {
        None => Ok(expanded),
        Some(at) => Err(format!(
            "unexpanded variable in the dashboard SQL: {}",
            expanded[at..].lines().next().unwrap_or_default()
        )
        .into()),
    }
}

/// The value of the dashboard variable `$length_unit`.
pub const fn length_unit(unit: LengthUnit) -> &'static str {
    match unit {
        LengthUnit::Km => "km",
        LengthUnit::Mi => "mi",
    }
}

/// The value of the dashboard variable `${preferred_range}`.
pub const fn preferred_range(range: PreferredRange) -> &'static str {
    match range {
        PreferredRange::Ideal => "ideal",
        PreferredRange::Rated => "rated",
    }
}

/// The column names of `row`, empty without a row.
pub fn column_names(row: Option<&PgRow>) -> Vec<String> {
    row.map(|row| {
        row.columns()
            .iter()
            .map(|column| sqlx::Column::name(column).to_owned())
            .collect()
    })
    .unwrap_or_default()
}

pub fn utc(rfc3339: &str) -> Result<DateTime<Utc>> {
    Ok(DateTime::parse_from_rfc3339(rfc3339)?.to_utc())
}
