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
//! [`fetch_original`] runs the dashboard's original raw SQL against the same
//! parameters and returns the same rows, so the port can be compared with its
//! reference on the same database.

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

/// The dashboard's original query, with Grafana's macros expanded the way its
/// Postgres data source does it:
///
/// * `$car_id` and `$duration` become numbered bind placeholders carrying the
///   values from [`VampireDrainParams`];
/// * `$__timeFilter(start_date)` becomes `start_date BETWEEN $n AND $n+1`;
/// * `$preferred_range` selects the ideal/rated range columns;
/// * `$length_unit` becomes the `convert_km` unit argument.
///
/// Two value-preserving deviations from the verbatim dashboard SQL, needed so
/// that this query and the port load into the same [`VampireDrain`] rows:
///
/// * the epoch-millisecond columns are cast to `::bigint` (the dashboard
///   returns them as `numeric`, which Diesel cannot deserialize into `i64`;
///   the cast is exact, as `floor(...) * 1000` is integral);
/// * the `range_diff` and `range_lost_per_hour` aliases drop the dashboard's
///   `_$length_unit` suffix so the column names match the struct (this query
///   is deserialized by column name).
///
/// Bind order: `$1` car id, `$2` from, `$3` to (charging processes), `$4` car
/// id, `$5` from, `$6` to (drives), `$7`/`$8` length unit (`range_diff`/
/// `range_lost_per_hour`), `$9` car id (standby states), `$10` car id (cars
/// join), `$11` minimum duration in hours.
pub fn original_sql(params: &VampireDrainParams) -> String {
    let preferred_range = params.preferred_range.as_str();
    format!(
        r"with merge as (
 SELECT
    c.start_date AS start_date,
    c.end_date AS end_date,
    c.start_ideal_range_km AS start_ideal_range_km,
    c.end_ideal_range_km AS end_ideal_range_km,
    c.start_rated_range_km AS start_rated_range_km,
    c.end_rated_range_km AS end_rated_range_km,
    start_battery_level,
    end_battery_level,
    p.usable_battery_level AS start_usable_battery_level,
    NULL AS end_usable_battery_level,
    p.odometer AS start_km,
    p.odometer AS end_km
 FROM charging_processes c
 JOIN positions p ON c.position_id = p.id
 WHERE c.car_id = $1 AND start_date BETWEEN $2 AND $3
 UNION
 SELECT
    d.start_date AS start_date,
    d.end_date AS end_date,
    d.start_ideal_range_km AS start_ideal_range_km,
    d.end_ideal_range_km AS end_ideal_range_km,
    d.start_rated_range_km AS start_rated_range_km,
    d.end_rated_range_km AS end_rated_range_km,
    start_position.battery_level AS start_battery_level,
    end_position.battery_level AS end_battery_level,
    start_position.usable_battery_level AS start_usable_battery_level,
    end_position.usable_battery_level AS end_usable_battery_level,
    d.start_km AS start_km,
    d.end_km AS end_km
 FROM drives d
 JOIN positions start_position ON d.start_position_id = start_position.id
 JOIN positions end_position ON d.end_position_id = end_position.id
 WHERE d.car_id = $4 AND start_date BETWEEN $5 AND $6
),
v as (
 SELECT
    lag(t.end_date) OVER w AS start_date,
    t.start_date AS end_date,
    lag(t.end_{preferred_range}_range_km) OVER w AS start_range,
    t.start_{preferred_range}_range_km AS end_range,
    lag(t.end_km) OVER w AS start_km,
    t.start_km AS end_km,
    EXTRACT(EPOCH FROM (t.start_date - lag(t.end_date) OVER w)) AS duration,
    lag(t.end_battery_level) OVER w AS start_battery_level,
    lag(t.end_usable_battery_level) OVER w AS start_usable_battery_level,
    start_battery_level AS end_battery_level,
    start_usable_battery_level AS end_usable_battery_level,
    start_battery_level > COALESCE(start_usable_battery_level, start_battery_level) AS has_reduced_range
  FROM merge t
  WINDOW w AS (ORDER BY t.start_date ASC)
  ORDER BY start_date DESC
)

SELECT
  (floor(extract(epoch FROM v.start_date)) * 1000)::bigint AS start_date_ts,
  (ceil(extract(epoch FROM v.end_date)) * 1000)::bigint AS end_date_ts,
  -- Columns
  v.start_date,
  v.end_date,
  v.duration,
  coalesce(s_standby.sleep, 0) / v.duration as standby,
  -greatest(v.start_battery_level - v.end_battery_level, 0) as soc_diff,
  CASE WHEN has_reduced_range THEN 1 ELSE 0 END as has_reduced_range,
  convert_km(CASE WHEN has_reduced_range THEN NULL ELSE (v.start_range - v.end_range)::numeric END, $7) AS range_diff,
  CASE WHEN has_reduced_range THEN NULL ELSE (v.start_range - v.end_range) * c.efficiency END AS consumption,
  CASE WHEN has_reduced_range THEN NULL ELSE ((v.start_range - v.end_range) * c.efficiency) / (v.duration / 3600) * 1000 END as avg_power,
  convert_km(CASE WHEN has_reduced_range THEN NULL ELSE ((v.start_range - v.end_range) / (v.duration / 3600))::numeric END, $8) AS range_lost_per_hour
FROM v,
  LATERAL (
    SELECT EXTRACT(EPOCH FROM sum(
      LEAST(s.end_date, v.end_date)
      - GREATEST(s.start_date, v.start_date)
    )) as sleep
    FROM states s
    WHERE
      state IN ('asleep', 'offline') AND
      s.start_date < v.end_date AND
      (s.end_date IS NULL OR s.end_date > v.start_date) AND
      s.car_id = $9
  ) s_standby
JOIN cars c ON c.id = $10
WHERE
  v.duration > ($11 * 60 * 60)
  AND v.start_range - v.end_range >= 0
  AND v.end_km - v.start_km < 1;"
    )
}

/// [`fetch`], but running the dashboard's original raw SQL ([`original_sql`])
/// against the same parameters — the reference implementation the port is
/// compared with.
pub async fn fetch_original(
    pool: &DatabasePool,
    params: &VampireDrainParams,
) -> Result<Vec<VampireDrain>, Error> {
    let mut conn = pool.get().await?;
    let rows = diesel::sql_query(original_sql(params))
        .bind::<Int2, _>(params.car_id)
        .bind::<Timestamp, _>(params.from)
        .bind::<Timestamp, _>(params.to)
        .bind::<Int2, _>(params.car_id)
        .bind::<Timestamp, _>(params.from)
        .bind::<Timestamp, _>(params.to)
        .bind::<Text, _>(params.length_unit.as_str())
        .bind::<Text, _>(params.length_unit.as_str())
        .bind::<Int2, _>(params.car_id)
        .bind::<Int2, _>(params.car_id)
        .bind::<Numeric, _>(BigDecimal::from(params.minimum_duration_hours))
        .load::<VampireDrain>(&mut conn)
        .await?;
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::{
        Error, LengthUnit, PreferredRange, VampireDrainParams, build_query, fetch, fetch_original,
        original_sql,
    };
    use chrono::NaiveDate;
    use diesel::debug_query;
    use diesel::pg::Pg;

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
    fn renders_the_original_dashboard_sql_with_expanded_macros() {
        let sql = original_sql(&params());

        assert!(sql.starts_with("with merge as ("), "{sql}");
        assert!(sql.contains("LATERAL ("), "{sql}");
        assert!(
            sql.contains("WHERE c.car_id = $1 AND start_date BETWEEN $2 AND $3"),
            "{sql}"
        );
        assert!(
            sql.contains("WHERE d.car_id = $4 AND start_date BETWEEN $5 AND $6"),
            "{sql}"
        );
        assert!(
            sql.contains("lag(t.end_ideal_range_km) OVER w AS start_range"),
            "{sql}"
        );
        assert!(sql.contains("s.car_id = $9"), "{sql}");
        assert!(sql.contains("JOIN cars c ON c.id = $10"), "{sql}");
        assert!(sql.contains("v.duration > ($11 * 60 * 60)"), "{sql}");
        assert!(
            sql.contains(
                "convert_km(CASE WHEN has_reduced_range THEN NULL ELSE (v.start_range - v.end_range)::numeric END, $7) AS range_diff"
            ),
            "{sql}"
        );
        assert!(
            sql.contains(
                "convert_km(CASE WHEN has_reduced_range THEN NULL ELSE ((v.start_range - v.end_range) / (v.duration / 3600))::numeric END, $8) AS range_lost_per_hour"
            ),
            "{sql}"
        );

        let mut rated = params();
        rated.preferred_range = PreferredRange::Rated;
        let sql = original_sql(&rated);
        assert!(
            sql.contains("lag(t.end_rated_range_km) OVER w AS start_range"),
            "{sql}"
        );
        assert!(
            !sql.contains("lag(t.end_ideal_range_km) OVER w AS start_range"),
            "{sql}"
        );
    }

    /// Runs the port and the dashboard's original SQL against the same
    /// database and compares the rows. Both are supposed to return the same
    /// result, so any difference is a porting bug.
    ///
    /// The test needs a `TeslaMate` Postgres reachable via `DATABASE_URL`; run
    /// it with `cargo test -- --ignored`.
    #[tokio::test]
    #[ignore = "needs a TeslaMate Postgres reachable via DATABASE_URL"]
    async fn port_matches_the_original_dashboard_sql() -> Result<(), Error> {
        let pool = match crate::database::connection::init().await {
            Ok(pool) => pool,
            Err(Error::MissingDatabaseUrl) => {
                eprintln!("skipping: DATABASE_URL is not set");
                return Ok(());
            }
            Err(e) => return Err(e),
        };

        for (preferred_range, length_unit) in [
            (PreferredRange::Ideal, LengthUnit::Kilometers),
            (PreferredRange::Ideal, LengthUnit::Miles),
            (PreferredRange::Rated, LengthUnit::Kilometers),
            (PreferredRange::Rated, LengthUnit::Miles),
        ] {
            let params = VampireDrainParams {
                preferred_range,
                length_unit,
                ..db_params()
            };
            let mut ported = fetch(&pool, &params).await?;
            let mut original = fetch_original(&pool, &params).await?;

            // Neither query has a top-level ORDER BY (the dashboard does not
            // either), so compare the rows in a stable order.
            ported.sort_by_key(|row| (row.start_date, row.end_date));
            original.sort_by_key(|row| (row.start_date, row.end_date));
            assert_eq!(
                ported, original,
                "rows differ for {preferred_range:?}/{length_unit:?}"
            );
        }

        Ok(())
    }
}
