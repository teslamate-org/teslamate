//! Port of the Grafana "Vampire Drain" dashboard query.
//!
//! The original SQL (see `grafana/dashboards/vampire-drain.json`) chains two
//! CTEs: `merge` lines up every charge and drive behind a common column layout,
//! and `v` pairs each entry with the one before it to measure how much range was
//! lost while the car was parked. The CTE scaffolding is built with
//! `diesel-cte-ext`; the scalar SQL that Diesel has no DSL for (`EXTRACT(EPOCH
//! ...)`, `GREATEST`/`LEAST`, `COALESCE`, `convert_km`, the standby subquery)
//! is emitted as typed raw fragments.
//!
//! The `port_matches_the_original_dashboard_sql` test compares the port with
//! the dashboard's own query: it reads the raw SQL from
//! `grafana/dashboards/vampire-drain.json`, expands the Grafana macros and
//! checks that both return the same rows on the same database. Building the
//! reference from the dashboard file keeps it from drifting silently when the
//! dashboard changes.

use bigdecimal::BigDecimal;
use chrono::NaiveDateTime;
use diesel::dsl::{lag, sql};
use diesel::expression::BoxableExpression;
use diesel::pg::Pg;
use diesel::prelude::*;
use diesel::query_builder::{Query, QueryFragment, QueryId};
use diesel::query_dsl::CombineDsl;
use diesel::sql_types::{BigInt, Bool, Float8, Int2, Int4, Nullable, Numeric, Text, Timestamp};
use diesel_async::RunQueryDsl;
use diesel_cte_ext::{CteParts, with_cte};

use crate::database::connection::{DatabasePool, Error};
use crate::database::schema::{cars, charging_processes, drives, positions};

diesel::table! {
    merge (start_date) {
        start_date -> Timestamp,
        end_date -> Nullable<Timestamp>,
        start_ideal_range_km -> Nullable<Numeric>,
        end_ideal_range_km -> Nullable<Numeric>,
        start_rated_range_km -> Nullable<Numeric>,
        end_rated_range_km -> Nullable<Numeric>,
        start_battery_level -> Nullable<Int2>,
        end_battery_level -> Nullable<Int2>,
        start_usable_battery_level -> Nullable<Int2>,
        end_usable_battery_level -> Nullable<Int2>,
        start_km -> Nullable<Float8>,
        end_km -> Nullable<Float8>,
    }
}

diesel::table! {
    v (end_date) {
        start_date -> Nullable<Timestamp>,
        end_date -> Timestamp,
        start_range -> Nullable<Numeric>,
        end_range -> Nullable<Numeric>,
        start_km -> Nullable<Float8>,
        end_km -> Nullable<Float8>,
        duration -> Numeric,
        start_battery_level -> Nullable<Int2>,
        start_usable_battery_level -> Nullable<Int2>,
        end_battery_level -> Nullable<Int2>,
        end_usable_battery_level -> Nullable<Int2>,
        has_reduced_range -> Bool,
    }
}

diesel::allow_tables_to_appear_in_same_query!(v, cars);

diesel::define_sql_function! {
    fn convert_km(value: Nullable<Numeric>, unit: Text) -> Nullable<Numeric>;
}

const MERGE_COLUMNS: &[&str] = &[
    "start_date",
    "end_date",
    "start_ideal_range_km",
    "end_ideal_range_km",
    "start_rated_range_km",
    "end_rated_range_km",
    "start_battery_level",
    "end_battery_level",
    "start_usable_battery_level",
    "end_usable_battery_level",
    "start_km",
    "end_km",
];

const V_COLUMNS: &[&str] = &[
    "start_date",
    "end_date",
    "start_range",
    "end_range",
    "start_km",
    "end_km",
    "duration",
    "start_battery_level",
    "start_usable_battery_level",
    "end_battery_level",
    "end_usable_battery_level",
    "has_reduced_range",
];

/// A `merge` range column, boxed so that the preferred-range choice between
/// the typed ideal and rated columns can be made at runtime.
type MergeRangeColumn = Box<dyn BoxableExpression<merge::table, Pg, SqlType = Nullable<Numeric>>>;

/// Which battery range column to compare: the ideal range or the rated range.
#[allow(dead_code)]
#[derive(Debug, Clone, Copy)]
pub enum PreferredRange {
    Ideal,
    Rated,
}

impl PreferredRange {
    /// The column suffix the dashboard interpolates for `$preferred_range`.
    /// Only the dashboard-reference tests use it.
    #[allow(dead_code)]
    const fn as_str(self) -> &'static str {
        match self {
            Self::Ideal => "ideal",
            Self::Rated => "rated",
        }
    }
}

/// Output unit for the converted range columns.
#[allow(dead_code)]
#[derive(Debug, Clone, Copy)]
pub enum LengthUnit {
    Kilometers,
    Miles,
}

impl LengthUnit {
    const fn as_str(self) -> &'static str {
        match self {
            Self::Kilometers => "km",
            Self::Miles => "mi",
        }
    }
}

/// Parameters corresponding to the Grafana dashboard variables.
pub struct VampireDrainParams {
    pub car_id: i16,
    pub from: NaiveDateTime,
    pub to: NaiveDateTime,
    pub minimum_duration_hours: i64,
    pub preferred_range: PreferredRange,
    pub length_unit: LengthUnit,
}

/// One row of the dashboard's table.
///
/// The `QueryableByName` derive (used by the raw reference query, which
/// deserializes by column name) requires a SQL type per field; the `Queryable`
/// derive (used by the ported query, which deserializes by position) ignores
/// them.
#[allow(dead_code)]
#[derive(Debug, Queryable, QueryableByName, PartialEq)]
#[diesel(check_for_backend(diesel::pg::Pg))]
pub struct VampireDrain {
    #[diesel(sql_type = BigInt)]
    pub start_date_ts: i64,
    #[diesel(sql_type = BigInt)]
    pub end_date_ts: i64,
    #[diesel(sql_type = Nullable<Timestamp>)]
    pub start_date: Option<NaiveDateTime>,
    #[diesel(sql_type = Timestamp)]
    pub end_date: NaiveDateTime,
    #[diesel(sql_type = Numeric)]
    pub duration: BigDecimal,
    #[diesel(sql_type = Numeric)]
    pub standby: BigDecimal,
    #[diesel(sql_type = Nullable<Int4>)]
    pub soc_diff: Option<i32>,
    #[diesel(sql_type = Int4)]
    pub has_reduced_range: i32,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub range_diff: Option<BigDecimal>,
    #[diesel(sql_type = Nullable<Float8>)]
    pub consumption: Option<f64>,
    #[diesel(sql_type = Nullable<Float8>)]
    pub avg_power: Option<f64>,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub range_lost_per_hour: Option<BigDecimal>,
}

type DrainRow = (
    BigInt,
    BigInt,
    Nullable<Timestamp>,
    Timestamp,
    Numeric,
    Numeric,
    Nullable<Int4>,
    Int4,
    Nullable<Numeric>,
    Nullable<Float8>,
    Nullable<Float8>,
    Nullable<Numeric>,
);

/// Build the full CTE query. Kept free of any connection so the generated SQL
/// can be inspected in tests via [`diesel::debug_query`].
#[allow(clippy::too_many_lines)]
fn build_query(
    params: &VampireDrainParams,
) -> impl Query<SqlType = DrainRow> + QueryFragment<Pg> + QueryId + Send {
    let car_id = params.car_id;
    let from = params.from;
    let to = params.to;
    let min_duration = BigDecimal::from(params.minimum_duration_hours * 3600);
    let length_unit = params.length_unit.as_str();

    let (start_position, end_position) = diesel::alias!(
        crate::database::schema::positions as start_position,
        crate::database::schema::positions as end_position
    );

    let charges = charging_processes::table
        .inner_join(positions::table.on(charging_processes::position_id.eq(positions::id)))
        .filter(charging_processes::car_id.eq(car_id))
        .filter(
            charging_processes::start_date
                .ge(from)
                .and(charging_processes::start_date.le(to)),
        )
        .select((
            charging_processes::start_date,
            charging_processes::end_date,
            charging_processes::start_ideal_range_km,
            charging_processes::end_ideal_range_km,
            charging_processes::start_rated_range_km,
            charging_processes::end_rated_range_km,
            charging_processes::start_battery_level,
            charging_processes::end_battery_level,
            positions::usable_battery_level,
            sql::<Nullable<Int2>>("NULL"),
            positions::odometer,
            positions::odometer,
        ));

    let journeys = drives::table
        .inner_join(
            start_position
                .on(drives::start_position_id.eq(start_position.field(positions::id).nullable())),
        )
        .inner_join(
            end_position
                .on(drives::end_position_id.eq(end_position.field(positions::id).nullable())),
        )
        .filter(drives::car_id.eq(car_id))
        .filter(drives::start_date.ge(from).and(drives::start_date.le(to)))
        .select((
            drives::start_date,
            drives::end_date,
            drives::start_ideal_range_km,
            drives::end_ideal_range_km,
            drives::start_rated_range_km,
            drives::end_rated_range_km,
            start_position.field(positions::battery_level),
            end_position.field(positions::battery_level),
            start_position.field(positions::usable_battery_level),
            end_position.field(positions::usable_battery_level),
            drives::start_km,
            drives::end_km,
        ));

    let merged = charges.union(journeys);

    // The preferred range picks between the typed ideal/rated columns of the
    // `merge` CTE, which share a SQL type; boxing that choice keeps it
    // type-checked instead of formatting a SQL identifier.
    let merge_start_range: MergeRangeColumn = match params.preferred_range {
        PreferredRange::Ideal => Box::new(merge::start_ideal_range_km),
        PreferredRange::Rated => Box::new(merge::start_rated_range_km),
    };
    let merge_end_range: MergeRangeColumn = match params.preferred_range {
        PreferredRange::Ideal => Box::new(merge::end_ideal_range_km),
        PreferredRange::Rated => Box::new(merge::end_rated_range_km),
    };

    let pairs = merge::table
        .select((
            lag(merge::end_date).window_order(merge::start_date.asc()),
            merge::start_date,
            lag(merge_end_range).window_order(merge::start_date.asc()),
            merge_start_range,
            lag(merge::end_km).window_order(merge::start_date.asc()),
            merge::start_km,
            sql::<Numeric>(
                r#"EXTRACT(EPOCH FROM ("merge"."start_date" - lag("merge"."end_date") OVER (ORDER BY "merge"."start_date" ASC)))"#,
            ),
            lag(merge::end_battery_level).window_order(merge::start_date.asc()),
            lag(merge::end_usable_battery_level).window_order(merge::start_date.asc()),
            merge::start_battery_level,
            merge::start_usable_battery_level,
            sql::<Bool>(
                r#"("merge"."start_battery_level" > COALESCE("merge"."start_usable_battery_level", "merge"."start_battery_level"))"#,
            ),
        ))
        // The original ends the `v` CTE with `ORDER BY start_date DESC`,
        // which Postgres resolves to the *output* `start_date` column — the
        // lagged `end_date` — rather than `merge.start_date`.
        .order_by(
            lag(merge::end_date)
                .window_order(merge::start_date.asc())
                .desc(),
        );

    // Total seconds the car spent asleep or offline between a pair. The
    // original query uses a LATERAL join; a correlated scalar subquery is
    // equivalent and Diesel can express it as a raw fragment.
    let standby = sql::<Numeric>(
        r#"(
            COALESCE((
                SELECT EXTRACT(EPOCH FROM sum(
                    LEAST(s.end_date, "v"."end_date") - GREATEST(s.start_date, "v"."start_date")
                ))
                FROM "states" s
                WHERE s.state IN ('asleep', 'offline')
                  AND s.start_date < "v"."end_date"
                  AND (s.end_date IS NULL OR s.end_date > "v"."start_date")
                  AND s.car_id = "#,
    )
    .bind::<Int2, _>(car_id)
    .sql(r#"), 0) / "v"."duration")"#);

    let reduced = r#""v"."has_reduced_range""#;

    let rows = v::table
        .inner_join(cars::table.on(cars::id.eq(car_id)))
        .select((
            sql::<BigInt>(r#"(floor(extract(epoch FROM "v"."start_date")) * 1000)::bigint"#),
            sql::<BigInt>(r#"(ceil(extract(epoch FROM "v"."end_date")) * 1000)::bigint"#),
            v::start_date,
            v::end_date,
            v::duration,
            standby,
            sql::<Nullable<Int4>>(
                r#"(-greatest("v"."start_battery_level" - "v"."end_battery_level", 0))::int"#,
            ),
            sql::<Int4>(r#"(CASE WHEN "v"."has_reduced_range" THEN 1 ELSE 0 END)"#),
            convert_km(
                sql::<Nullable<Numeric>>(&format!(
                    r#"(CASE WHEN {reduced} THEN NULL ELSE ("v"."start_range" - "v"."end_range")::numeric END)"#
                )),
                length_unit,
            ),
            sql::<Nullable<Float8>>(&format!(
                r#"(CASE WHEN {reduced} THEN NULL ELSE ("v"."start_range" - "v"."end_range") * "cars"."efficiency" END)"#
            )),
            sql::<Nullable<Float8>>(&format!(
                r#"(CASE WHEN {reduced} THEN NULL ELSE (("v"."start_range" - "v"."end_range") * "cars"."efficiency") / ("v"."duration" / 3600) * 1000 END)"#
            )),
            convert_km(
                sql::<Nullable<Numeric>>(&format!(
                    r#"(CASE WHEN {reduced} THEN NULL ELSE (("v"."start_range" - "v"."end_range") / ("v"."duration" / 3600))::numeric END)"#
                )),
                length_unit,
            ),
        ))
        .filter(v::duration.gt(min_duration))
        .filter(sql::<Bool>(r#"("v"."start_range" - "v"."end_range" >= 0)"#))
        .filter(sql::<Bool>(r#"("v"."end_km" - "v"."start_km" < 1)"#));

    let inner = with_cte::<Pg, _, _, _, _>("merge", MERGE_COLUMNS, CteParts::new(merged, pairs));

    with_cte::<Pg, _, _, _, _>("v", V_COLUMNS, CteParts::new(inner, rows))
}

/// Run the vampire drain query for one car.
pub async fn fetch(
    pool: &DatabasePool,
    params: &VampireDrainParams,
) -> Result<Vec<VampireDrain>, Error> {
    let mut conn = pool.get().await?;
    let rows = build_query(params).load::<VampireDrain>(&mut conn).await?;
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::{LengthUnit, PreferredRange, VampireDrain, VampireDrainParams, build_query};
    use chrono::NaiveDate;
    use diesel::debug_query;
    use diesel::pg::Pg;
    use diesel_async::{AsyncConnection, AsyncPgConnection, RunQueryDsl, SimpleAsyncConnection};

    fn params() -> VampireDrainParams {
        VampireDrainParams {
            car_id: 1,
            from: NaiveDate::from_ymd_opt(2024, 1, 1)
                .unwrap_or_default()
                .and_hms_opt(0, 0, 0)
                .unwrap_or_default(),
            to: NaiveDate::from_ymd_opt(2024, 2, 1)
                .unwrap_or_default()
                .and_hms_opt(0, 0, 0)
                .unwrap_or_default(),
            minimum_duration_hours: 1,
            preferred_range: PreferredRange::Ideal,
            length_unit: LengthUnit::Kilometers,
        }
    }

    /// A window wide enough to cover every row of a development database.
    fn db_params() -> VampireDrainParams {
        VampireDrainParams {
            from: NaiveDate::from_ymd_opt(2000, 1, 1)
                .unwrap_or_default()
                .and_hms_opt(0, 0, 0)
                .unwrap_or_default(),
            to: NaiveDate::from_ymd_opt(2100, 1, 1)
                .unwrap_or_default()
                .and_hms_opt(0, 0, 0)
                .unwrap_or_default(),
            ..params()
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
    fn expand_dashboard_macros(
        raw_sql: &str,
        params: &VampireDrainParams,
    ) -> Result<String, String> {
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
    fn builds_a_nested_cte() {
        let sql = debug_query::<Pg, _>(&build_query(&params())).to_string();

        assert!(sql.starts_with(r#"WITH "v" ("start_date""#), "{sql}");
        assert!(sql.contains(r#"WITH "merge" ("start_date""#), "{sql}");
        assert!(sql.contains("UNION"), "{sql}");
        assert!(sql.contains(r#"FROM ("v" INNER JOIN "cars""#), "{sql}");
        // The original ends the `v` CTE with `ORDER BY start_date DESC`,
        // which Postgres resolves to the lagged `end_date`, not
        // `merge.start_date`.
        assert!(
            sql.contains(
                r#"FROM "merge" ORDER BY lag("merge"."end_date") OVER ( ORDER BY "merge"."start_date" ASC) DESC"#
            ),
            "{sql}"
        );
    }

    #[test]
    fn selects_the_preferred_range_columns() {
        let mut rated = params();
        rated.preferred_range = PreferredRange::Rated;
        let sql = debug_query::<Pg, _>(&build_query(&rated)).to_string();

        assert!(
            sql.contains(r#"lag("merge"."end_rated_range_km")"#),
            "{sql}"
        );
        assert!(
            !sql.contains(r#"lag("merge"."end_ideal_range_km")"#),
            "{sql}"
        );
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
    const FIXTURES: &str = include_str!("../../../tests/fixtures/vampire_drain.sql");

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
    fn fixture_params(
        preferred_range: PreferredRange,
        length_unit: LengthUnit,
    ) -> VampireDrainParams {
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
}
