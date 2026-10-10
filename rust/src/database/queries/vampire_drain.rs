//! Port of the Grafana "Vampire Drain" dashboard query.
//!
//! The original SQL (see `grafana/dashboards/vampire-drain.json`) chains two
//! CTEs: `merge` lines up every charge and drive behind a common column layout,
//! and `v` pairs each entry with the one before it to measure how much range was
//! lost while the car was parked. The CTE scaffolding is built with
//! `diesel-cte-ext`; the scalar SQL that Diesel has no DSL for (`EXTRACT(EPOCH
//! ...)`, `GREATEST`/`LEAST`, `COALESCE`, `convert_km`, the standby subquery)
//! is emitted as typed raw fragments.

use bigdecimal::BigDecimal;
use chrono::NaiveDateTime;
use diesel::dsl::{lag, sql};
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
#[allow(dead_code)]
#[derive(Debug, Queryable)]
pub struct VampireDrain {
    pub start_date_ts: i64,
    pub end_date_ts: i64,
    pub start_date: Option<NaiveDateTime>,
    pub end_date: NaiveDateTime,
    pub duration: BigDecimal,
    pub standby: BigDecimal,
    pub soc_diff: Option<i32>,
    pub has_reduced_range: i32,
    pub range_diff: Option<BigDecimal>,
    pub consumption: Option<f64>,
    pub avg_power: Option<f64>,
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
    let preferred = params.preferred_range.as_str();

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

    let merge_start_range =
        sql::<Nullable<Numeric>>(&format!(r#""merge"."start_{preferred}_range_km""#));
    let merge_end_range =
        sql::<Nullable<Numeric>>(&format!(r#""merge"."end_{preferred}_range_km""#));

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
        .order_by(merge::start_date.desc());

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
    use super::{LengthUnit, PreferredRange, VampireDrainParams, build_query};
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

    #[test]
    fn builds_a_nested_cte() {
        let sql = debug_query::<Pg, _>(&build_query(&params())).to_string();

        assert!(sql.starts_with(r#"WITH "v" ("start_date""#), "{sql}");
        assert!(sql.contains(r#"WITH "merge" ("start_date""#), "{sql}");
        assert!(sql.contains("UNION"), "{sql}");
        assert!(sql.contains(r#"FROM ("v" INNER JOIN "cars""#), "{sql}");
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
}
