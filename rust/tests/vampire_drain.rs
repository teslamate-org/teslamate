//! The vampire-drain port against the dashboard's own query, on a real
//! database.
//!
//! `port_matches_the_original_dashboard_sql` reads the raw SQL from
//! `grafana/dashboards/vampire-drain.json`, expands the Grafana macros and
//! checks that the port and the dashboard's query return the same rows on the
//! same database, so any difference is a porting bug. Building the reference
//! from the dashboard file keeps it from drifting silently when the dashboard
//! changes.
//!
//! The database the comparison runs against is `TEST_DATABASE_URL` if set,
//! else `DATABASE_URL`; either way it must be migrated to the `TeslaMate`
//! schema. The macro-expansion tests keep the reference builder honest
//! without needing one.

use chrono::NaiveDate;
use diesel_async::{AsyncConnection, AsyncPgConnection, RunQueryDsl, SimpleAsyncConnection};

use teslamate_rust::database::queries::vampire_drain::{
    LengthUnit, PreferredRange, VampireDrain, VampireDrainParams, build_query,
};

/// A window wide enough to cover every row of a development database, with
/// the default dashboard variable values.
fn db_params() -> VampireDrainParams {
    VampireDrainParams {
        car_id: 1,
        from: NaiveDate::from_ymd_opt(2000, 1, 1)
            .unwrap_or_default()
            .and_hms_opt(0, 0, 0)
            .unwrap_or_default(),
        to: NaiveDate::from_ymd_opt(2100, 1, 1)
            .unwrap_or_default()
            .and_hms_opt(0, 0, 0)
            .unwrap_or_default(),
        minimum_duration_hours: 1,
        preferred_range: PreferredRange::Ideal,
        length_unit: LengthUnit::Kilometers,
    }
}

/// The dashboard's raw query, read from the dashboard JSON so that the
/// reference used by [`reference_sql`] cannot drift from the dashboard
/// silently.
fn dashboard_raw_sql() -> Result<String, String> {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../grafana/dashboards/vampire-drain.json"
    );
    let dashboard: serde_json::Value = std::fs::read_to_string(path)
        .map_err(|e| format!("failed to read {path}: {e}"))
        .and_then(|text| {
            serde_json::from_str(&text).map_err(|e| format!("failed to parse {path}: {e}"))
        })?;

    dashboard
        .get("panels")
        .and_then(|panels| find_panel(panels, "Vampire Drain"))
        .and_then(|panel| panel.get("targets"))
        .and_then(|targets| targets.get(0))
        .and_then(|target| target.get("rawSql"))
        .and_then(|raw_sql| raw_sql.as_str())
        .map(str::to_owned)
        .ok_or_else(|| format!("no rawSql found in the Vampire Drain panel of {path}"))
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
/// Unknown variables are an error rather than passed through, so a
/// dashboard change that introduces a new variable fails the tests
/// instead of producing a query the port was never compared against.
fn expand_dashboard_macros(raw_sql: &str, params: &VampireDrainParams) -> Result<String, String> {
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

    // `${name}` and `$name` variables, substituted textually.
    let mut substituted = String::with_capacity(expanded.len());
    let mut rest = expanded.as_str();
    while let Some(dollar) = rest.find('$') {
        substituted.push_str(&rest[..dollar]);
        let after = &rest[dollar + 1..];
        if let Some(name) = after.strip_prefix('{') {
            let Some(end) = name.find('}') else {
                return Err("unterminated ${...} variable in the dashboard SQL".into());
            };
            let value = variable_value(&name[..end], params)
                .ok_or_else(|| format!("unknown dashboard variable: ${{{name}}}"))?;
            substituted.push_str(&value);
            rest = &name[end + 1..];
        } else {
            let name_len = after
                .find(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .unwrap_or(after.len());
            if name_len == 0 {
                // A `$` that is not followed by a variable name.
                substituted.push('$');
                rest = after;
            } else {
                let name = &after[..name_len];
                let value = variable_value(name, params)
                    .ok_or_else(|| format!("unknown dashboard variable: ${name}"))?;
                substituted.push_str(&value);
                rest = &after[name_len..];
            }
        }
    }
    substituted.push_str(rest);
    Ok(substituted)
}

/// The values the dashboard's template variables take in the comparison.
fn variable_value(name: &str, params: &VampireDrainParams) -> Option<String> {
    match name {
        "car_id" => Some(params.car_id.to_string()),
        "duration" => Some(params.minimum_duration_hours.to_string()),
        "preferred_range" => Some(params.preferred_range.as_str().to_owned()),
        "length_unit" => Some(params.length_unit.as_str().to_owned()),
        _ => None,
    }
}

/// The expanded dashboard query, wrapped so that it loads into the same
/// [`VampireDrain`] rows as the port:
///
/// * the epoch-millisecond columns are cast to `bigint` (the dashboard
///   returns them as `numeric`, which Diesel cannot deserialize into
///   `i64`; the cast is exact, as `floor(...) * 1000` is integral);
/// * the `range_diff` and `range_lost_per_hour` aliases drop the
///   dashboard's `_$length_unit` suffix so the column names match the
///   struct (the wrapper deserializes by column name).
///
/// The wrapper is ours, not the dashboard's: if the dashboard renames its
/// output columns, this query fails instead of comparing stale SQL.
fn reference_sql(raw_sql: &str, params: &VampireDrainParams) -> Result<String, String> {
    let inner = expand_dashboard_macros(raw_sql, params)?;
    let inner = inner.trim().trim_end_matches(';').trim();
    let length_unit = params.length_unit.as_str();
    Ok(format!(
        "SELECT
  dashboard.start_date_ts::bigint AS start_date_ts,
  dashboard.end_date_ts::bigint AS end_date_ts,
  dashboard.start_date,
  dashboard.end_date,
  dashboard.duration,
  dashboard.standby,
  dashboard.soc_diff,
  dashboard.has_reduced_range,
  dashboard.range_diff_{length_unit} AS range_diff,
  dashboard.consumption,
  dashboard.avg_power,
  dashboard.range_lost_per_hour_{length_unit} AS range_lost_per_hour
FROM ({inner}) dashboard"
    ))
}

#[test]
fn expands_the_dashboard_macros() -> Result<(), String> {
    let raw = dashboard_raw_sql()?;
    assert!(raw.contains("with merge as"), "{raw}");

    let sql = expand_dashboard_macros(&raw, &db_params())?;
    assert!(
        sql.contains(
            "WHERE c.car_id = 1 AND start_date BETWEEN '2000-01-01 00:00:00' AND '2100-01-01 00:00:00'"
        ),
        "{sql}"
    );
    assert!(
        sql.contains("lag(t.end_ideal_range_km) OVER w AS start_range"),
        "{sql}"
    );
    assert!(
        sql.contains(
            "convert_km(CASE WHEN has_reduced_range THEN NULL ELSE (v.start_range - v.end_range)::numeric END, 'km') AS range_diff_km"
        ),
        "{sql}"
    );
    assert!(sql.contains("v.duration > (1 * 60 * 60)"), "{sql}");
    // Every variable must be expanded; a leftover `$` means the dashboard
    // introduced something the expander does not know about.
    assert!(!sql.contains('$'), "{sql}");

    let reference = reference_sql(&raw, &db_params())?;
    assert!(
        reference.contains("dashboard.range_diff_km AS range_diff"),
        "{reference}"
    );
    assert!(
        reference.contains("dashboard.start_date_ts::bigint AS start_date_ts"),
        "{reference}"
    );

    let mut rated = db_params();
    rated.preferred_range = PreferredRange::Rated;
    rated.length_unit = LengthUnit::Miles;
    let sql = expand_dashboard_macros(&raw, &rated)?;
    assert!(
        sql.contains("lag(t.end_rated_range_km) OVER w AS start_range"),
        "{sql}"
    );
    assert!(sql.contains("'mi') AS range_diff_mi"), "{sql}");
    Ok(())
}

#[test]
fn rejects_unknown_dashboard_variables() {
    assert!(expand_dashboard_macros("$unknown", &db_params()).is_err());
}

/// The fixtures for the comparison test: a documented timeline of one
/// parked Tesla losing range, with every row on a negative id.
const FIXTURES: &str = include_str!("fixtures/vampire_drain.sql");

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

/// The comparison window of the fixture timeline: 2024-03-01 08:00 to
/// 2024-03-05 18:00, both ends exactly on an entry, with the minimum
/// duration of its design.
fn fixture_params(preferred_range: PreferredRange, length_unit: LengthUnit) -> VampireDrainParams {
    VampireDrainParams {
        car_id: -1,
        from: NaiveDate::from_ymd_opt(2024, 3, 1)
            .unwrap_or_default()
            .and_hms_opt(8, 0, 0)
            .unwrap_or_default(),
        to: NaiveDate::from_ymd_opt(2024, 3, 5)
            .unwrap_or_default()
            .and_hms_opt(18, 0, 0)
            .unwrap_or_default(),
        minimum_duration_hours: 6,
        preferred_range,
        length_unit,
    }
}

/// Runs the port and the dashboard's own query — read from
/// `grafana/dashboards/vampire-drain.json` with its macros expanded — on
/// [`FIXTURES`] and compares the rows. Both are supposed to return the
/// same result, so any difference is a porting bug.
///
/// The fixtures run in a transaction that is rolled back, so the database
/// is unchanged; they all belong to car -1, so the result does not depend
/// on whatever else the database holds.
#[tokio::test]
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

            for (preferred_range, length_unit) in [
                (PreferredRange::Ideal, LengthUnit::Kilometers),
                (PreferredRange::Ideal, LengthUnit::Miles),
                (PreferredRange::Rated, LengthUnit::Kilometers),
                (PreferredRange::Rated, LengthUnit::Miles),
            ] {
                let params = fixture_params(preferred_range, length_unit);
                let case = format!("{preferred_range:?}/{length_unit:?}");
                let mut ported = build_query(&params).load::<VampireDrain>(conn).await?;
                let mut original = diesel::sql_query(reference_sql(&raw, &params)?)
                    .load::<VampireDrain>(conn)
                    .await?;

                // The timeline in the fixture file has three parked
                // periods that become rows: G1, G5 and G6.
                assert_eq!(ported.len(), 3, "{case}: rows");
                assert_eq!(original.len(), 3, "{case}: rows");

                // The fixtures must exercise both branches of
                // has_reduced_range and a nonzero standby, or the port
                // could drop either unnoticed.
                assert!(
                    ported.iter().any(|row| row.has_reduced_range == 0)
                        && ported.iter().any(|row| row.has_reduced_range == 1),
                    "{case}: the fixtures no longer cover both has_reduced_range values"
                );
                assert!(
                    ported.iter().any(|row| row.standby > 0),
                    "{case}: the fixtures no longer cover standby"
                );

                // Neither query has a top-level ORDER BY (the dashboard
                // does not either), so compare the rows in a stable order.
                ported.sort_by_key(|row| (row.start_date, row.end_date));
                original.sort_by_key(|row| (row.start_date, row.end_date));
                assert_eq!(ported, original, "{case}: port and dashboard differ");
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
