//! Port of the "Drive" table of the Grafana Drives dashboard
//! (`grafana/dashboards/drives.json`): the drives of one car, filtered by
//! the dashboard's variables and sortable by any column the table shows.
//!
//! The original SQL builds two CTEs, `data` (the drives with the columns
//! the table needs) and `reduced_range_info` (whether more than a quarter
//! of a drive's positions had a battery level above the usable level),
//! joins them and applies the location filter. The port keeps `data` as a
//! Diesel CTE; `reduced_range_info` becomes a correlated scalar subquery
//! for `has_reduced_range`, which returns the same value — `count(*) = 0`
//! reproduces the `LEFT JOIN`'s NULL for a drive without qualifying
//! positions — because Diesel cannot express two CTEs consumed by one
//! query. The Grafana variables are bound as parameters, and the sort,
//! which Grafana does in the browser, is built into the `ORDER BY` at
//! runtime: Diesel composes the query, so every key becomes its own
//! expression instead of the `CASE` per key that static SQL would need.
//!
//! The `port_matches_the_original_dashboard_sql` integration test in
//! `tests/drives.rs` compares the port with the dashboard's own query:
//! it reads the raw SQL from `grafana/dashboards/drives.json`, expands the
//! Grafana macros and checks that both return the same rows on the same
//! database, for every unit, range and efficiency combination, every
//! filter and every sort key.

use bigdecimal::BigDecimal;
use chrono::NaiveDateTime;
use diesel::dsl::sql;
use diesel::expression::BoxableExpression;
use diesel::pg::Pg;
use diesel::prelude::*;
use diesel::query_builder::{Query, QueryFragment, QueryId};
use diesel::sql_types::{
    Array, BigInt, Bool, Float8, Int2, Int4, Nullable, Numeric, Text, Timestamp,
};
use diesel_async::RunQueryDsl;
use diesel_cte_ext::{CteParts, with_cte};

use crate::database::connection::{DatabasePool, Error};
use crate::database::schema::{addresses, cars, drives, geofences, positions};
use crate::settings::{LengthUnit, PreferredRange, TemperatureUnit};

diesel::table! {
    data (drive_id) {
        start_date_ts -> Numeric,
        end_date_ts -> Nullable<Numeric>,
        car_id -> Int2,
        start_path -> Nullable<Text>,
        end_path -> Nullable<Text>,
        duration_str -> Nullable<Text>,
        drive_id -> Int4,
        start_date -> Timestamp,
        start_address -> Nullable<Text>,
        end_address -> Nullable<Text>,
        duration_min -> Nullable<Int2>,
        distance -> Nullable<Float8>,
        start_battery_level -> Nullable<Int2>,
        end_battery_level -> Nullable<Int2>,
        start_ideal_range_km -> Nullable<Numeric>,
        end_ideal_range_km -> Nullable<Numeric>,
        start_rated_range_km -> Nullable<Numeric>,
        end_rated_range_km -> Nullable<Numeric>,
        car_efficiency -> Nullable<Float8>,
        outside_temp_avg -> Nullable<Numeric>,
        avg_speed -> Nullable<Float8>,
        speed_max -> Nullable<Int2>,
        power_max -> Nullable<Int2>,
        ascent -> Nullable<Int2>,
        descent -> Nullable<Int2>,
    }
}

/// The CTE the dashboard calls `data`, with the runtime column list
/// `with_cte` declares. It carries both the ideal and the rated range
/// columns instead of the dashboard's single `range_diff`: the
/// preferred-range choice between them is made in the query that reads
/// the CTE, where boxing the columns keeps it type-checked, as in the
/// vampire-drain port.
const DATA_COLUMNS: &[&str] = &[
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
    "distance",
    "start_battery_level",
    "end_battery_level",
    "start_ideal_range_km",
    "end_ideal_range_km",
    "start_rated_range_km",
    "end_rated_range_km",
    "car_efficiency",
    "outside_temp_avg",
    "avg_speed",
    "speed_max",
    "power_max",
    "ascent",
    "descent",
];

diesel::define_sql_function! {
    fn convert_km(value: Nullable<Numeric>, unit: Text) -> Nullable<Numeric>;
}

diesel::define_sql_function! {
    fn convert_celsius(value: Nullable<Numeric>, unit: Text) -> Nullable<Numeric>;
}

/// The dashboard's `$geofence`: all geofences, or only the drives that
/// start or end in one of the given geofences. An empty list matches no
/// drive; Grafana offers no empty selection.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Geofences {
    All,
    Any(Vec<i32>),
}

/// The dashboard's `$efficiency`, the way the efficiency column is
/// computed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Efficiency {
    /// "slope-adjusted": the energy the distance needs at 100 % efficiency
    /// over the energy used, corrected for ascent and descent.
    SlopeAdjusted,
    /// "by distance": distance over range used.
    ByDistance,
}

/// A column the dashboard's table shows, to sort by. The names are the
/// port's output column names, without the unit suffixes the dashboard
/// appends to some of them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortKey {
    StartDate,
    StartAddress,
    EndAddress,
    DurationMin,
    Distance,
    StartBatteryLevel,
    EndBatteryLevel,
    OutsideTemp,
    SpeedAvg,
    SpeedMax,
    PowerMax,
    HasReducedRange,
    Efficiency,
    ConsumptionKwh,
    ConsumptionWhPerDistance,
}

impl SortKey {
    /// Every key, in the order the dashboard's table shows its columns.
    pub const ALL: [Self; 15] = [
        Self::StartDate,
        Self::StartAddress,
        Self::EndAddress,
        Self::DurationMin,
        Self::Distance,
        Self::StartBatteryLevel,
        Self::EndBatteryLevel,
        Self::OutsideTemp,
        Self::SpeedAvg,
        Self::SpeedMax,
        Self::PowerMax,
        Self::HasReducedRange,
        Self::Efficiency,
        Self::ConsumptionKwh,
        Self::ConsumptionWhPerDistance,
    ];
}

/// The direction of a [`Sort`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    Ascending,
    Descending,
}

/// Sort by `key` in `direction`, NULLs last either way.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Sort {
    pub key: SortKey,
    pub direction: Direction,
}

/// The dashboard's variables, plus the sort.
#[derive(Debug, Clone)]
pub struct DrivesParams {
    /// `$car_id`
    pub car_id: i16,
    /// `$__timeFilter(start_date)`: drives that started between `from` and
    /// `to`, both included.
    pub from: NaiveDateTime,
    pub to: NaiveDateTime,
    /// `$length_unit`
    pub length_unit: LengthUnit,
    /// `$temp_unit`
    pub temperature_unit: TemperatureUnit,
    /// `${preferred_range}`
    pub preferred_range: PreferredRange,
    /// `$min_dist`, in `length_unit`. Always applied, as in the dashboard,
    /// so drives without a distance never show up.
    pub min_distance: BigDecimal,
    /// `$min_speed`, the average speed in `length_unit` per hour. Always
    /// applied.
    pub min_speed: BigDecimal,
    /// `$geofence`
    pub geofences: Geofences,
    /// `$location`: drives whose start or end address contains this text,
    /// ignoring case; `%` and `_` match any text or character, as in the
    /// dashboard. `None` is the dashboard's empty box: no filter.
    pub location: Option<String>,
    /// `$efficiency`
    pub efficiency: Efficiency,
    /// `None`: newest drive first, the dashboard's order.
    pub sort: Option<Sort>,
}

/// One row of the dashboard's table: a drive.
///
/// The `QueryableByName` derive (used by the raw reference query, which
/// deserializes by column name) requires a SQL type per field; the
/// `Queryable` derive (used by the ported query, which deserializes by
/// position) ignores them. Distances and speeds are in
/// [`DrivesParams::length_unit`], temperatures in
/// [`DrivesParams::temperature_unit`]; the dashboard puts the unit into
/// the column names instead (`distance_km`, `outside_temp_c`, ...), and
/// quotes `% Start`, `% End` and `consumption_kWh`.
#[allow(dead_code)]
#[derive(Debug, Queryable, QueryableByName, PartialEq)]
#[diesel(check_for_backend(diesel::pg::Pg))]
pub struct Drive {
    #[diesel(sql_type = BigInt)]
    pub start_date_ts: i64,
    #[diesel(sql_type = Nullable<BigInt>)]
    pub end_date_ts: Option<i64>,
    #[diesel(sql_type = Int2)]
    pub car_id: i16,
    /// Link target into the web UI: the geofence, or a new one there.
    #[diesel(sql_type = Nullable<Text>)]
    pub start_path: Option<String>,
    #[diesel(sql_type = Nullable<Text>)]
    pub end_path: Option<String>,
    /// `HH24:MI`
    #[diesel(sql_type = Nullable<Text>)]
    pub duration_str: Option<String>,
    #[diesel(sql_type = Int4)]
    pub drive_id: i32,
    #[diesel(sql_type = Timestamp)]
    pub start_date: NaiveDateTime,
    #[diesel(sql_type = Nullable<Text>)]
    pub start_address: Option<String>,
    #[diesel(sql_type = Nullable<Text>)]
    pub end_address: Option<String>,
    #[diesel(sql_type = Nullable<Int2>)]
    pub duration_min: Option<i16>,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub distance: Option<BigDecimal>,
    #[diesel(sql_type = Nullable<Int2>)]
    pub start_battery_level: Option<i16>,
    #[diesel(sql_type = Nullable<Int2>)]
    pub end_battery_level: Option<i16>,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub outside_temp: Option<BigDecimal>,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub speed_avg: Option<BigDecimal>,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub speed_max: Option<BigDecimal>,
    /// kW
    #[diesel(sql_type = Nullable<Int2>)]
    pub power_max: Option<i16>,
    /// More than a quarter of the drive's positions had a battery level
    /// above the usable level; NULL without positions that have a range.
    #[diesel(sql_type = Nullable<Bool>)]
    pub has_reduced_range: Option<bool>,
    #[diesel(sql_type = Nullable<Float8>)]
    pub efficiency: Option<f64>,
    /// kWh
    #[diesel(sql_type = Nullable<Float8>)]
    pub consumption_kwh: Option<f64>,
    /// Wh per `length_unit`, the dashboard's `consumption_kWh_km`/`_mi`.
    #[diesel(sql_type = Nullable<Float8>)]
    pub consumption_wh_per_distance: Option<f64>,
}

/// The SQL types of [`Drive`]'s columns, in order.
type DriveRow = (
    BigInt,
    Nullable<BigInt>,
    Int2,
    Nullable<Text>,
    Nullable<Text>,
    Nullable<Text>,
    Int4,
    Timestamp,
    Nullable<Text>,
    Nullable<Text>,
    Nullable<Int2>,
    Nullable<Numeric>,
    Nullable<Int2>,
    Nullable<Int2>,
    Nullable<Numeric>,
    Nullable<Numeric>,
    Nullable<Numeric>,
    Nullable<Int2>,
    Nullable<Bool>,
    Nullable<Float8>,
    Nullable<Float8>,
    Nullable<Float8>,
);

/// The `range_diff` the dashboard computes in its `data` CTE, as a SQL
/// fragment over the CTE's columns: the preferred range chooses between
/// the typed ideal and rated columns, whose names the fragment
/// interpolates. Parenthesized, so that embedding it into the arithmetic
/// of the efficiency and consumption columns keeps the dashboard's
/// grouping.
fn range_diff(preferred_range: PreferredRange) -> String {
    match preferred_range {
        PreferredRange::Ideal => {
            r#"("data"."start_ideal_range_km" - "data"."end_ideal_range_km")"#.to_owned()
        }
        PreferredRange::Rated => {
            r#"("data"."start_rated_range_km" - "data"."end_rated_range_km")"#.to_owned()
        }
    }
}

/// An output column of the query over the `data` CTE, boxed so that the
/// helpers below can hand the same column to both the `SELECT` list and
/// the `ORDER BY` of a sort key.
type DataColumn<ST> = Box<dyn BoxableExpression<data::table, Pg, SqlType = ST>>;

/// The dashboard's `distance` column: the drive's distance in the length
/// unit. A fragment, because `convert_km` needs the explicit
/// `::numeric` cast of the `double precision` column, which Diesel's
/// casts do not know.
fn distance_in(params: &DrivesParams) -> DataColumn<Nullable<Numeric>> {
    Box::new(convert_km(
        sql::<Nullable<Numeric>>(r#""data"."distance"::numeric"#),
        params.length_unit.as_str(),
    ))
}

/// The dashboard's `outside_temp` column: the average outside temperature
/// in the temperature unit.
fn outside_temp_in(params: &DrivesParams) -> DataColumn<Nullable<Numeric>> {
    Box::new(convert_celsius(
        data::outside_temp_avg,
        params.temperature_unit.as_str(),
    ))
}

/// The dashboard's `speed_avg` column: the average speed in the length
/// unit per hour.
fn speed_avg_in(params: &DrivesParams) -> DataColumn<Nullable<Numeric>> {
    Box::new(convert_km(
        sql::<Nullable<Numeric>>(r#""data"."avg_speed"::numeric"#),
        params.length_unit.as_str(),
    ))
}

/// The dashboard's `speed_max` column: the maximum speed in the length
/// unit per hour.
fn speed_max_in(params: &DrivesParams) -> DataColumn<Nullable<Numeric>> {
    Box::new(convert_km(
        sql::<Nullable<Numeric>>(r#""data"."speed_max"::numeric"#),
        params.length_unit.as_str(),
    ))
}

/// The dashboard's `reduced_range_info` CTE, as a correlated scalar
/// subquery for one drive: `true` when more than a quarter of the drive's
/// positions with a range had a battery level above the usable level.
/// `count(*) = 0` yields NULL, the value the dashboard's `LEFT JOIN`
/// gives a drive without such positions.
fn has_reduced_range(params: &DrivesParams) -> DataColumn<Nullable<Bool>> {
    Box::new(
        sql::<Nullable<Bool>>(
            r#"(
                SELECT CASE WHEN count(*) = 0 THEN NULL
                            WHEN sum(CASE WHEN p.battery_level - p.usable_battery_level > 0 THEN 1 ELSE 0 END)::numeric / count(*) > 0.25 THEN true
                            ELSE false END
                FROM "positions" p
                WHERE p.drive_id = "data"."drive_id"
                  AND p.ideal_battery_range_km IS NOT NULL
                  AND p.car_id = "#,
        )
        .bind::<Int2, _>(params.car_id)
        .sql(" AND p.date BETWEEN ")
        .bind::<Timestamp, _>(params.from)
        .sql(" AND ")
        .bind::<Timestamp, _>(params.to)
        .sql(" ) "),
    )
}

/// The dashboard's `efficiency` column. The dashboard compares its
/// `$efficiency` variable inside the `CASE`; the port knows the mode when
/// it builds the query, so it emits only the matching branch.
fn efficiency_in(params: &DrivesParams) -> DataColumn<Nullable<Float8>> {
    let range_diff = range_diff(params.preferred_range);
    let fragment = match params.efficiency {
        Efficiency::ByDistance => {
            // implicit `ELSE NULL`, as in the dashboard's CASE
            format!(r#"(CASE WHEN {range_diff} > 0 THEN "data"."distance" / {range_diff} END)"#)
        }
        Efficiency::SlopeAdjusted => {
            format!(
                r#"("data"."distance" * "data"."car_efficiency" -- Energy at 100% efficiency
                    / nullif((
                        {range_diff} * "data"."car_efficiency" -- Actual Energy
                        + 2100 * 0.85 * 9.81 * "data"."descent" / 3600 / 1000 -- Potential energy recovered from descent
                        - 2100 * 9.81 * "data"."ascent" / 3600 / 1000 -- Potential energy for ascent
                    ), 0))"#
            )
        }
    };
    Box::new(sql::<Nullable<Float8>>(&fragment))
}

/// The dashboard's `consumption_kWh` column: the energy used, in kWh.
fn consumption_kwh(params: &DrivesParams) -> DataColumn<Nullable<Float8>> {
    let fragment = format!(
        r#"({} * "data"."car_efficiency")"#,
        range_diff(params.preferred_range)
    );
    Box::new(sql::<Nullable<Float8>>(&fragment))
}

/// The dashboard's `consumption_kWh_km`/`_mi` column: the energy used per
/// `length_unit`, in Wh.
fn consumption_wh_per_distance(params: &DrivesParams) -> DataColumn<Nullable<Float8>> {
    let range_diff = range_diff(params.preferred_range);
    let length_unit = params.length_unit.as_str();
    let fragment = format!(
        r#"({range_diff} * "data"."car_efficiency" / convert_km("data"."distance"::numeric, '{length_unit}') * 1000)"#
    );
    Box::new(sql::<Nullable<Float8>>(&fragment))
}

/// Build the full CTE query.
///
/// Kept free of any connection so the generated SQL can be inspected in
/// tests via [`diesel::debug_query`], and so the integration test in
/// `tests/drives.rs` can run it on a transaction-scoped connection that
/// the pool-based [`fetch`] cannot offer.
#[allow(clippy::too_many_lines)]
#[must_use]
pub fn build_query(
    params: &DrivesParams,
) -> impl Query<SqlType = DriveRow> + QueryFragment<Pg> + QueryId + Send {
    let car_id = params.car_id;
    let from = params.from;
    let to = params.to;
    let length_unit = params.length_unit.as_str();

    let (start_address, end_address) = diesel::alias!(
        crate::database::schema::addresses as start_address,
        crate::database::schema::addresses as end_address
    );
    let (start_position, end_position) = diesel::alias!(
        crate::database::schema::positions as start_position,
        crate::database::schema::positions as end_position
    );
    let (start_geofence, end_geofence) = diesel::alias!(
        crate::database::schema::geofences as start_geofence,
        crate::database::schema::geofences as end_geofence
    );
    let car = diesel::alias!(crate::database::schema::cars as car);

    let duration_expr = r#"nullif("drives"."duration_min", 0) * 60, extract(epoch from "drives"."end_date" - "drives"."start_date")"#;

    let data_query = drives::table
        .left_join(
            start_address.on(drives::start_address_id.eq(start_address.field(addresses::id).nullable())),
        )
        .left_join(end_address.on(drives::end_address_id.eq(end_address.field(addresses::id).nullable())))
        .left_join(
            start_position
                .on(drives::start_position_id.eq(start_position.field(positions::id).nullable())),
        )
        .left_join(
            end_position.on(drives::end_position_id.eq(end_position.field(positions::id).nullable())),
        )
        .left_join(
            start_geofence.on(drives::start_geofence_id.eq(start_geofence.field(geofences::id).nullable())),
        )
        .left_join(end_geofence.on(drives::end_geofence_id.eq(end_geofence.field(geofences::id).nullable())))
        .left_join(car.on(car.field(cars::id).eq(drives::car_id)))
        .filter(drives::start_date.between(from, to))
        .filter(drives::car_id.eq(car_id))
        .filter(
            convert_km(
                sql::<Nullable<Numeric>>(r#""drives"."distance"::numeric"#),
                length_unit,
            )
            .ge(params.min_distance.clone()),
        )
        .filter(
            sql::<Nullable<Bool>>(&format!(
                r#"convert_km("drives"."distance"::numeric, '{length_unit}') / coalesce({duration_expr}) * 3600 >= "#,
            ))
            .bind::<Numeric, _>(params.min_speed.clone()),
        )
        .select((
            sql::<Numeric>(r#"floor(extract(epoch FROM "drives"."start_date")) * 1000"#),
            sql::<Nullable<Numeric>>(r#"ceil(extract(epoch FROM "drives"."end_date")) * 1000"#),
            // `nullable()` marks the fields of the LEFT JOIN's right side,
            // which Diesel only accepts wrapped, and changes no SQL.
            car.field(cars::id).nullable(),
            sql::<Nullable<Text>>(
                r#"CASE
                    WHEN "start_geofence"."id" IS NULL THEN CONCAT('new?lat=', "start_position"."latitude", '&lng=', "start_position"."longitude")
                    WHEN "start_geofence"."id" IS NOT NULL THEN CONCAT("start_geofence"."id", '/edit')
                END"#,
            ),
            sql::<Nullable<Text>>(
                r#"CASE
                    WHEN "end_geofence"."id" IS NULL THEN CONCAT('new?lat=', "end_position"."latitude", '&lng=', "end_position"."longitude")
                    WHEN "end_geofence"."id" IS NOT NULL THEN CONCAT("end_geofence"."id", '/edit')
                END"#,
            ),
            sql::<Nullable<Text>>(
                r#"TO_CHAR(("drives"."duration_min" * INTERVAL '1 minute'), 'HH24:MI')"#,
            ),
            drives::id,
            drives::start_date,
            sql::<Nullable<Text>>(
                r#"COALESCE("start_geofence"."name", CONCAT_WS(', ', COALESCE("start_address"."name", nullif(CONCAT_WS(' ', "start_address"."road", "start_address"."house_number"), '')), COALESCE("start_address"."city", "start_address"."neighbourhood")))"#,
            ),
            sql::<Nullable<Text>>(
                r#"COALESCE("end_geofence"."name", CONCAT_WS(', ', COALESCE("end_address"."name", nullif(CONCAT_WS(' ', "end_address"."road", "end_address"."house_number"), '')), COALESCE("end_address"."city", "end_address"."neighbourhood")))"#,
            ),
            drives::duration_min,
            drives::distance,
            start_position.field(positions::battery_level).nullable(),
            end_position.field(positions::battery_level).nullable(),
            drives::start_ideal_range_km,
            drives::end_ideal_range_km,
            drives::start_rated_range_km,
            drives::end_rated_range_km,
            car.field(cars::efficiency).nullable(),
            drives::outside_temp_avg,
            sql::<Nullable<Float8>>(&format!(
                r#""drives"."distance" / coalesce({duration_expr}) * 3600"#,
            )),
            drives::speed_max,
            drives::power_max,
            drives::ascent,
            drives::descent,
        ))
        // A boxed select, so that the geofence filter, applied only when
        // geofences are selected, keeps one query type.
        .into_boxed::<Pg>();

    let data_query = match &params.geofences {
        // The dashboard's "All" is its custom all value -1, which the
        // query tests for; no filter does the same here.
        Geofences::All => data_query,
        Geofences::Any(geofence_ids) => data_query.filter(
            sql::<Nullable<Bool>>(r#"("start_geofence"."id" = ANY("#)
                .bind::<Array<Int4>, _>(geofence_ids.clone())
                .sql(r#") OR "end_geofence"."id" = ANY("#)
                .bind::<Array<Int4>, _>(geofence_ids.clone())
                .sql("))"),
        ),
    };

    let mut rows = data::table
        .select((
            sql::<BigInt>(r#""data"."start_date_ts"::bigint"#),
            sql::<Nullable<BigInt>>(r#""data"."end_date_ts"::bigint"#),
            data::car_id,
            data::start_path,
            data::end_path,
            data::duration_str,
            data::drive_id,
            data::start_date,
            data::start_address,
            data::end_address,
            data::duration_min,
            distance_in(params),
            data::start_battery_level,
            data::end_battery_level,
            outside_temp_in(params),
            speed_avg_in(params),
            speed_max_in(params),
            data::power_max,
            has_reduced_range(params),
            efficiency_in(params),
            consumption_kwh(params),
            consumption_wh_per_distance(params),
        ))
        // A boxed select, so that the location filter, applied only when
        // the dashboard's text box is filled in, keeps one query type —
        // as does the sort below, whose key is chosen at runtime.
        .into_boxed::<Pg>();

    // The dashboard's empty text box matches every row; no filter does
    // the same here.
    if let Some(location) = &params.location {
        rows = rows.filter(
            data::start_address
                .ilike(format!("%{location}%"))
                .or(data::end_address.ilike(format!("%{location}%"))),
        );
    }

    // The dashboard's own ORDER BY is the newest drive first; Grafana
    // sorts the table in the browser instead. The port adds the sort:
    // by the key's expression, NULLs last either way — one arm per key
    // and direction, instead of the `CASE` per key that static SQL would
    // need.
    rows = match params.sort {
        None => rows,
        Some(Sort {
            key: SortKey::StartDate,
            direction: Direction::Ascending,
        }) => rows.order_by(data::start_date.asc().nulls_last()),
        Some(Sort {
            key: SortKey::StartDate,
            direction: Direction::Descending,
        }) => rows.order_by(data::start_date.desc().nulls_last()),
        Some(Sort {
            key: SortKey::StartAddress,
            direction: Direction::Ascending,
        }) => rows.order_by(data::start_address.asc().nulls_last()),
        Some(Sort {
            key: SortKey::StartAddress,
            direction: Direction::Descending,
        }) => rows.order_by(data::start_address.desc().nulls_last()),
        Some(Sort {
            key: SortKey::EndAddress,
            direction: Direction::Ascending,
        }) => rows.order_by(data::end_address.asc().nulls_last()),
        Some(Sort {
            key: SortKey::EndAddress,
            direction: Direction::Descending,
        }) => rows.order_by(data::end_address.desc().nulls_last()),
        Some(Sort {
            key: SortKey::DurationMin,
            direction: Direction::Ascending,
        }) => rows.order_by(data::duration_min.asc().nulls_last()),
        Some(Sort {
            key: SortKey::DurationMin,
            direction: Direction::Descending,
        }) => rows.order_by(data::duration_min.desc().nulls_last()),
        Some(Sort {
            key: SortKey::Distance,
            direction: Direction::Ascending,
        }) => rows.order_by(distance_in(params).asc().nulls_last()),
        Some(Sort {
            key: SortKey::Distance,
            direction: Direction::Descending,
        }) => rows.order_by(distance_in(params).desc().nulls_last()),
        Some(Sort {
            key: SortKey::StartBatteryLevel,
            direction: Direction::Ascending,
        }) => rows.order_by(data::start_battery_level.asc().nulls_last()),
        Some(Sort {
            key: SortKey::StartBatteryLevel,
            direction: Direction::Descending,
        }) => rows.order_by(data::start_battery_level.desc().nulls_last()),
        Some(Sort {
            key: SortKey::EndBatteryLevel,
            direction: Direction::Ascending,
        }) => rows.order_by(data::end_battery_level.asc().nulls_last()),
        Some(Sort {
            key: SortKey::EndBatteryLevel,
            direction: Direction::Descending,
        }) => rows.order_by(data::end_battery_level.desc().nulls_last()),
        Some(Sort {
            key: SortKey::OutsideTemp,
            direction: Direction::Ascending,
        }) => rows.order_by(outside_temp_in(params).asc().nulls_last()),
        Some(Sort {
            key: SortKey::OutsideTemp,
            direction: Direction::Descending,
        }) => rows.order_by(outside_temp_in(params).desc().nulls_last()),
        Some(Sort {
            key: SortKey::SpeedAvg,
            direction: Direction::Ascending,
        }) => rows.order_by(speed_avg_in(params).asc().nulls_last()),
        Some(Sort {
            key: SortKey::SpeedAvg,
            direction: Direction::Descending,
        }) => rows.order_by(speed_avg_in(params).desc().nulls_last()),
        Some(Sort {
            key: SortKey::SpeedMax,
            direction: Direction::Ascending,
        }) => rows.order_by(speed_max_in(params).asc().nulls_last()),
        Some(Sort {
            key: SortKey::SpeedMax,
            direction: Direction::Descending,
        }) => rows.order_by(speed_max_in(params).desc().nulls_last()),
        Some(Sort {
            key: SortKey::PowerMax,
            direction: Direction::Ascending,
        }) => rows.order_by(data::power_max.asc().nulls_last()),
        Some(Sort {
            key: SortKey::PowerMax,
            direction: Direction::Descending,
        }) => rows.order_by(data::power_max.desc().nulls_last()),
        Some(Sort {
            key: SortKey::HasReducedRange,
            direction: Direction::Ascending,
        }) => rows.order_by(has_reduced_range(params).asc().nulls_last()),
        Some(Sort {
            key: SortKey::HasReducedRange,
            direction: Direction::Descending,
        }) => rows.order_by(has_reduced_range(params).desc().nulls_last()),
        Some(Sort {
            key: SortKey::Efficiency,
            direction: Direction::Ascending,
        }) => rows.order_by(efficiency_in(params).asc().nulls_last()),
        Some(Sort {
            key: SortKey::Efficiency,
            direction: Direction::Descending,
        }) => rows.order_by(efficiency_in(params).desc().nulls_last()),
        Some(Sort {
            key: SortKey::ConsumptionKwh,
            direction: Direction::Ascending,
        }) => rows.order_by(consumption_kwh(params).asc().nulls_last()),
        Some(Sort {
            key: SortKey::ConsumptionKwh,
            direction: Direction::Descending,
        }) => rows.order_by(consumption_kwh(params).desc().nulls_last()),
        Some(Sort {
            key: SortKey::ConsumptionWhPerDistance,
            direction: Direction::Ascending,
        }) => rows.order_by(consumption_wh_per_distance(params).asc().nulls_last()),
        Some(Sort {
            key: SortKey::ConsumptionWhPerDistance,
            direction: Direction::Descending,
        }) => rows.order_by(consumption_wh_per_distance(params).desc().nulls_last()),
    }
    .then_order_by(data::drive_id.desc());

    with_cte::<Pg, _, _, _, _>("data", DATA_COLUMNS, CteParts::new(data_query, rows))
}

/// Run the drives query for one car.
///
/// # Errors
///
/// Fails if the pool cannot provide a connection or the query fails.
pub async fn fetch(pool: &DatabasePool, params: &DrivesParams) -> Result<Vec<Drive>, Error> {
    let mut conn = pool.get().await?;
    let rows = build_query(params).load::<Drive>(&mut conn).await?;
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::{Direction, DrivesParams, Efficiency, Geofences, Sort, SortKey, build_query};
    use crate::settings::{LengthUnit, PreferredRange, TemperatureUnit};
    use bigdecimal::BigDecimal;
    use chrono::NaiveDate;
    use diesel::debug_query;
    use diesel::pg::Pg;

    fn params() -> DrivesParams {
        DrivesParams {
            car_id: 1,
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

    #[test]
    fn builds_the_cte_and_the_dashboard_order() {
        let sql = debug_query::<Pg, _>(&build_query(&params())).to_string();

        assert!(sql.starts_with(r#"WITH "data" ("start_date_ts""#), "{sql}");
        assert!(
            sql.contains(r#"FROM ((((((("drives" LEFT OUTER JOIN "addresses" AS "start_address""#),
            "{sql}"
        );
        assert!(sql.contains(r#"LEFT OUTER JOIN "cars" AS "car""#), "{sql}");
        assert!(sql.contains(r#"ORDER BY "data"."drive_id" DESC"#), "{sql}");
        // the dashboard's filters, with the values bound
        assert!(
            sql.contains(r#"WHERE (((("drives"."start_date" BETWEEN $1 AND $2) AND ("drives"."car_id" = $3))"#),
            "{sql}"
        );
        assert!(
            sql.contains(r#"AND (convert_km("drives"."distance"::numeric, $4) >= $5)"#),
            "{sql}"
        );
        assert!(
            sql.contains(
                r#"convert_km("drives"."distance"::numeric, 'km') / coalesce(nullif("drives"."duration_min", 0) * 60, extract(epoch from "drives"."end_date" - "drives"."start_date")) * 3600 >= $6"#
            ),
            "{sql}"
        );
        // the reduced-range subquery stands in for the second CTE
        assert!(sql.contains(r#"p.drive_id = "data"."drive_id""#), "{sql}");
    }

    #[test]
    fn filters_by_the_selected_geofences_and_the_location() {
        let mut filtered = params();
        filtered.geofences = Geofences::Any(vec![-12, -13]);
        filtered.location = Some("BAKE".to_owned());
        let sql = debug_query::<Pg, _>(&build_query(&filtered)).to_string();

        assert!(
            sql.contains(r#"("start_geofence"."id" = ANY($7) OR "end_geofence"."id" = ANY($8))"#),
            "{sql}"
        );
        assert!(
            sql.contains(
                r#"WHERE (("data"."start_address" ILIKE $16) OR ("data"."end_address" ILIKE $17))"#
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
            sql.contains(r#"("data"."start_rated_range_km" - "data"."end_rated_range_km") * "data"."car_efficiency""#),
            "{sql}"
        );
        assert!(
            !sql.contains(r#"("data"."start_ideal_range_km" - "data"."end_ideal_range_km")"#),
            "{sql}"
        );
    }

    #[test]
    fn computes_the_by_distance_efficiency() {
        let mut by_distance = params();
        by_distance.efficiency = Efficiency::ByDistance;
        let sql = debug_query::<Pg, _>(&build_query(&by_distance)).to_string();

        assert!(
            sql.contains(
                r#"(CASE WHEN ("data"."start_ideal_range_km" - "data"."end_ideal_range_km") > 0 THEN "data"."distance" / ("data"."start_ideal_range_km" - "data"."end_ideal_range_km") END)"#
            ),
            "{sql}"
        );
        assert!(!sql.contains("slope-adjusted"), "{sql}");
    }

    #[test]
    fn orders_by_every_sort_key() {
        for key in SortKey::ALL {
            for direction in [Direction::Ascending, Direction::Descending] {
                let sorted = DrivesParams {
                    sort: Some(Sort { key, direction }),
                    ..params()
                };
                let sql = debug_query::<Pg, _>(&build_query(&sorted)).to_string();

                let direction_sql = match direction {
                    Direction::Ascending => "ASC NULLS LAST",
                    Direction::Descending => "DESC NULLS LAST",
                };
                assert!(
                    sql.contains(&format!(r#"{direction_sql}, "data"."drive_id" DESC"#)),
                    "{key:?} {direction:?}: {sql}"
                );
            }
        }
    }
}
