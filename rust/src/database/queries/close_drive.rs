//! Port of the database part of `TeslaMate.Log.close_drive/2`
//! (`elixir/lib/teslamate/log.ex`): aggregate the positions of a drive
//! into the drive, or delete the drive if it has too few of them.
//!
//! This is `close_drive(drive, lookup_address: false)`: the address
//! lookup calls an external geocoder and is not ported, so the address
//! columns stay as they are. The geofences are looked up as in Elixir.
//!
//! Ecto computes three aggregates over the drive's positions —
//! `drive_data` (over all of them), `non_streamed_drive_data` (over those
//! with a range and an odometer) and `elevation_data` (the elevation
//! differences of those with an elevation) — and inner joins them `ON
//! true`. Diesel cannot put several CTEs into one `WITH`, so the port
//! nests them instead: each level's statement joins the level below with
//! `positions`, which keeps the join's meaning — without a position that
//! has a range and an odometer there is no row, and the drive is deleted.
//! The window functions themselves, frames included, are Diesel's; only
//! the elevation sums and the duration, which Elixir writes as
//! `fragment`s, stay raw fragments.
//!
//! The steps run in one transaction, where Elixir runs them without one;
//! called inside a transaction, it becomes a savepoint. `duration_min`,
//! `ascent` and `descent` are bound as `integer` and `bigint` and
//! narrowed to `smallint` by Postgres, which fails with `smallint out of
//! range` where Postgrex fails to encode. A missing drive is
//! [`diesel::result::Error::NotFound`] (Elixir raises a stale entry
//! error). A `NULL` distance keeps the drive, as in Elixir, where
//! `nil >= 0.01` is true in Erlang's term order.
//!
//! The `port_closes_drives_like_the_characterization_goldens`
//! integration test in `tests/close_drive.rs` replays the drives of the
//! Elixir characterization goldens and compares the results.

use bigdecimal::BigDecimal;
use chrono::NaiveDateTime;
use diesel::dsl::FrameClauseDsl;
use diesel::dsl::frame::{Range, UnboundedFollowing, UnboundedPreceding};
use diesel::dsl::sql;
use diesel::dsl::{avg, count_star, first_value, lag, last_value, max, min};
use diesel::expression::BoxableExpression;
use diesel::pg::Pg;
use diesel::prelude::*;
use diesel::query_builder::{Query, QueryFragment, QueryId};
use diesel::sql_types::{BigInt, Bool, Float8, Int2, Int4, Nullable, Numeric, Timestamp};
use diesel_async::AsyncConnection;
use diesel_async::AsyncPgConnection;
use diesel_async::RunQueryDsl;
use diesel_cte_ext::{CteParts, with_cte};

use crate::database::connection::{DatabasePool, Error};
use crate::database::schema::{drives, geofences, positions};

diesel::table! {
    /// The elevation difference to the previous position that has an
    /// elevation, Ecto's `p1` subquery.
    p1 (elevation_diff) {
        elevation_diff -> Nullable<Int2>,
    }
}

diesel::table! {
    /// The elevation sums, Ecto's `elevation_data`.
    e (ascent) {
        ascent -> BigInt,
        descent -> BigInt,
    }
}

diesel::table! {
    /// The ranges at the first and last position with a range and an
    /// odometer, Ecto's `non_streamed_drive_data`, carrying the elevation
    /// sums.
    d1e (start_ideal_range_km) {
        start_ideal_range_km -> Nullable<Numeric>,
        end_ideal_range_km -> Nullable<Numeric>,
        start_rated_range_km -> Nullable<Numeric>,
        end_rated_range_km -> Nullable<Numeric>,
        ascent -> BigInt,
        descent -> BigInt,
    }
}

diesel::table! {
    /// All of Ecto's aggregates joined into one row, as the query the
    /// port loads; `count`, `start_date` and `end_date` are never NULL in
    /// a row that exists.
    d0all (count) {
        count -> BigInt,
        start_position_id -> Nullable<Int4>,
        end_position_id -> Nullable<Int4>,
        outside_temp_avg -> Nullable<Numeric>,
        inside_temp_avg -> Nullable<Numeric>,
        speed_max -> Nullable<Int2>,
        power_max -> Nullable<Int2>,
        power_min -> Nullable<Int2>,
        start_date -> Timestamp,
        end_date -> Timestamp,
        start_km -> Nullable<Float8>,
        end_km -> Nullable<Float8>,
        distance -> Nullable<Float8>,
        duration_min -> Nullable<Int4>,
        start_ideal_range_km -> Nullable<Numeric>,
        end_ideal_range_km -> Nullable<Numeric>,
        start_rated_range_km -> Nullable<Numeric>,
        end_rated_range_km -> Nullable<Numeric>,
        ascent -> BigInt,
        descent -> BigInt,
    }
}

diesel::allow_tables_to_appear_in_same_query!(d0all, d1e, e, p1, positions);

/// The runtime column list of the `p1` CTE.
const P1_COLUMNS: &[&str] = &["elevation_diff"];

/// The runtime column list of the `e` CTE.
const E_COLUMNS: &[&str] = &["ascent", "descent"];

/// The runtime column list of the `d1e` CTE.
const D1E_COLUMNS: &[&str] = &[
    "start_ideal_range_km",
    "end_ideal_range_km",
    "start_rated_range_km",
    "end_rated_range_km",
    "ascent",
    "descent",
];

/// The runtime column list of the `d0all` CTE.
const D0ALL_COLUMNS: &[&str] = &[
    "count",
    "start_position_id",
    "end_position_id",
    "outside_temp_avg",
    "inside_temp_avg",
    "speed_max",
    "power_max",
    "power_min",
    "start_date",
    "end_date",
    "start_km",
    "end_km",
    "distance",
    "duration_min",
    "start_ideal_range_km",
    "end_ideal_range_km",
    "start_rated_range_km",
    "end_rated_range_km",
    "ascent",
    "descent",
];

/// The window specification of Elixir's named window `w`: ordered by the
/// position date, over the whole drive. Diesel has no named windows, so
/// the raw fragments that contain window functions repeat it.
const OVER_DRIVE: &str = r#"OVER (ORDER BY "positions"."date" ASC RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)"#;

/// The drive as `close_drive` leaves it: one row of the `drives` table.
///
/// The `QueryableByName` derive (used by the golden test, which reads the
/// golden's row through `jsonb_populate_record` and deserializes by
/// column name) requires a SQL type per field; the `Queryable` derive
/// (used by the `RETURNING` of the update, which deserializes by
/// position) ignores them.
#[allow(dead_code)]
#[derive(Debug, Queryable, QueryableByName, PartialEq)]
#[diesel(check_for_backend(diesel::pg::Pg))]
pub struct Drive {
    #[diesel(sql_type = Int4)]
    pub id: i32,
    #[diesel(sql_type = Int2)]
    pub car_id: i16,
    #[diesel(sql_type = Timestamp)]
    pub start_date: NaiveDateTime,
    #[diesel(sql_type = Nullable<Timestamp>)]
    pub end_date: Option<NaiveDateTime>,
    #[diesel(sql_type = Nullable<Int4>)]
    pub start_position_id: Option<i32>,
    #[diesel(sql_type = Nullable<Int4>)]
    pub end_position_id: Option<i32>,
    #[diesel(sql_type = Nullable<Int4>)]
    pub start_address_id: Option<i32>,
    #[diesel(sql_type = Nullable<Int4>)]
    pub end_address_id: Option<i32>,
    #[diesel(sql_type = Nullable<Int4>)]
    pub start_geofence_id: Option<i32>,
    #[diesel(sql_type = Nullable<Int4>)]
    pub end_geofence_id: Option<i32>,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub outside_temp_avg: Option<BigDecimal>,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub inside_temp_avg: Option<BigDecimal>,
    #[diesel(sql_type = Nullable<Int2>)]
    pub speed_max: Option<i16>,
    #[diesel(sql_type = Nullable<Int2>)]
    pub power_max: Option<i16>,
    #[diesel(sql_type = Nullable<Int2>)]
    pub power_min: Option<i16>,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub start_ideal_range_km: Option<BigDecimal>,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub end_ideal_range_km: Option<BigDecimal>,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub start_rated_range_km: Option<BigDecimal>,
    #[diesel(sql_type = Nullable<Numeric>)]
    pub end_rated_range_km: Option<BigDecimal>,
    #[diesel(sql_type = Nullable<Float8>)]
    pub start_km: Option<f64>,
    #[diesel(sql_type = Nullable<Float8>)]
    pub end_km: Option<f64>,
    #[diesel(sql_type = Nullable<Float8>)]
    pub distance: Option<f64>,
    #[diesel(sql_type = Nullable<Int2>)]
    pub duration_min: Option<i16>,
    #[diesel(sql_type = Nullable<Int2>)]
    pub ascent: Option<i16>,
    #[diesel(sql_type = Nullable<Int2>)]
    pub descent: Option<i16>,
}

/// The aggregates of a drive's positions, as Ecto's joined query selects
/// them. All nullable but the count and the dates: the row only exists
/// with at least one position, and positions always have a date.
#[allow(dead_code)]
#[derive(Debug, Queryable, PartialEq)]
pub struct Aggregate {
    pub count: i64,
    pub start_position_id: Option<i32>,
    pub end_position_id: Option<i32>,
    pub outside_temp_avg: Option<BigDecimal>,
    pub inside_temp_avg: Option<BigDecimal>,
    pub speed_max: Option<i16>,
    pub power_max: Option<i16>,
    pub power_min: Option<i16>,
    pub start_date: NaiveDateTime,
    pub end_date: NaiveDateTime,
    pub start_km: Option<f64>,
    pub end_km: Option<f64>,
    pub distance: Option<f64>,
    /// Minutes, as Ecto's `::integer`.
    pub duration_min: Option<i32>,
    pub start_ideal_range_km: Option<BigDecimal>,
    pub end_ideal_range_km: Option<BigDecimal>,
    pub start_rated_range_km: Option<BigDecimal>,
    pub end_rated_range_km: Option<BigDecimal>,
    /// Meters climbed, as Ecto's capped sum: a `bigint`, narrowed to the
    /// `smallint` column by Postgres.
    pub ascent: i64,
    pub descent: i64,
}

/// The SQL types of [`Aggregate`]'s columns, in order.
type AggregateRow = (
    BigInt,
    Nullable<Int4>,
    Nullable<Int4>,
    Nullable<Numeric>,
    Nullable<Numeric>,
    Nullable<Int2>,
    Nullable<Int2>,
    Nullable<Int2>,
    Timestamp,
    Timestamp,
    Nullable<Float8>,
    Nullable<Float8>,
    Nullable<Float8>,
    Nullable<Int4>,
    Nullable<Numeric>,
    Nullable<Numeric>,
    Nullable<Numeric>,
    Nullable<Numeric>,
    BigInt,
    BigInt,
);

/// What `close_drive` did to the drive.
#[allow(dead_code)]
#[derive(Debug, PartialEq)]
pub enum Outcome {
    /// Updated with the aggregates of its positions.
    Closed(Box<Drive>),
    /// Deleted: fewer than two positions, less than 0.01 km driven, or no
    /// position with both a range and an odometer.
    Deleted,
}

/// Build Ecto's aggregate query, nested as
/// `d0all(d1e(e(p1)))`, see the module documentation.
///
/// Kept free of any connection so the generated SQL can be inspected in
/// tests via [`diesel::debug_query`], and so the golden test can run it
/// on a transaction-scoped connection.
#[allow(clippy::too_many_lines)]
#[must_use]
pub fn build_aggregate_query(
    drive_id: i32,
) -> impl Query<SqlType = AggregateRow> + QueryFragment<Pg> + QueryId + Send {
    // Ecto's `p1`: the elevation difference to the previous position
    // that has an elevation.
    let p1_query = positions::table
        .filter(positions::drive_id.eq(drive_id))
        .filter(positions::elevation.is_not_null())
        .select((
            positions::elevation - lag(positions::elevation).window_order(positions::date.asc()),
        ));

    // Ecto's `elevation_data`: the sums of the gains and the losses,
    // capped at the `smallint` maximum, which becomes 0 over it.
    let e_select = p1::table.select((
        sql::<BigInt>(
            r#"COALESCE(NULLIF(LEAST(SUM(CASE WHEN "p1"."elevation_diff" > 0 THEN "p1"."elevation_diff" ELSE 0 END), 32768), 32768), 0)"#,
        ),
        sql::<BigInt>(
            r#"COALESCE(NULLIF(LEAST(SUM(CASE WHEN "p1"."elevation_diff" < 0 THEN ABS("p1"."elevation_diff") ELSE 0 END), 32768), 32768), 0)"#,
        ),
    ));

    // Ecto's `non_streamed_drive_data`: the ranges at the first and the
    // last position that has a range and an odometer, carrying the
    // elevation sums. `INNER JOIN ON true` keeps Ecto's meaning: without
    // such a position there is no row, and the drive is deleted.
    let d1e_select = positions::table
        .inner_join(e::table.on(sql::<Bool>("true")))
        .filter(positions::drive_id.eq(drive_id))
        .filter(positions::ideal_battery_range_km.is_not_null())
        .filter(positions::odometer.is_not_null())
        .select((
            first_value(positions::ideal_battery_range_km)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            last_value(positions::ideal_battery_range_km)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            first_value(positions::rated_battery_range_km)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            last_value(positions::rated_battery_range_km)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            e::ascent,
            e::descent,
        ))
        .limit(1);

    // Ecto's `drive_data`: the aggregates over all of the drive's
    // positions, joined with the ranges and the elevation sums. The
    // duration stays a raw fragment, as Ecto writes it as one: it
    // contains two window functions Diesel would otherwise have to
    // repeat anyway.
    let duration_min = format!(
        r#"round(extract(epoch FROM (last_value("positions"."date") {OVER_DRIVE} - first_value("positions"."date") {OVER_DRIVE})) / 60)::integer"#
    );
    let d0all_select = positions::table
        .inner_join(d1e::table.on(sql::<Bool>("true")))
        .filter(positions::drive_id.eq(drive_id))
        .select((
            count_star()
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            first_value(positions::id)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            last_value(positions::id)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            avg(positions::outside_temp)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            avg(positions::inside_temp)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            max(positions::speed)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            max(positions::power)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            min(positions::power)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            first_value(positions::date)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            last_value(positions::date)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            first_value(positions::odometer)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            last_value(positions::odometer)
                .window_order(positions::date.asc())
                .frame_by(Range.frame_between(UnboundedPreceding, UnboundedFollowing)),
            // The distance stays a raw fragment, as Ecto writes it as
            // one: subtracting window functions is no Diesel operation,
            // and both would repeat the window specification anyway.
            sql::<Nullable<Float8>>(&format!(
                r#"last_value("positions"."odometer") {OVER_DRIVE} - first_value("positions"."odometer") {OVER_DRIVE}"#
            )),
            sql::<Nullable<Int4>>(&duration_min),
            d1e::start_ideal_range_km,
            d1e::end_ideal_range_km,
            d1e::start_rated_range_km,
            d1e::end_rated_range_km,
            d1e::ascent,
            d1e::descent,
        ))
        .limit(1);

    let body = d0all::table.select((
        d0all::count,
        d0all::start_position_id,
        d0all::end_position_id,
        d0all::outside_temp_avg,
        d0all::inside_temp_avg,
        d0all::speed_max,
        d0all::power_max,
        d0all::power_min,
        d0all::start_date,
        d0all::end_date,
        d0all::start_km,
        d0all::end_km,
        d0all::distance,
        d0all::duration_min,
        d0all::start_ideal_range_km,
        d0all::end_ideal_range_km,
        d0all::start_rated_range_km,
        d0all::end_rated_range_km,
        d0all::ascent,
        d0all::descent,
    ));

    let e_cte = with_cte::<Pg, _, _, _, _>("p1", P1_COLUMNS, CteParts::new(p1_query, e_select));
    let d1e_cte = with_cte::<Pg, _, _, _, _>("e", E_COLUMNS, CteParts::new(e_cte, d1e_select));
    let d0all_cte =
        with_cte::<Pg, _, _, _, _>("d1e", D1E_COLUMNS, CteParts::new(d1e_cte, d0all_select));
    with_cte::<Pg, _, _, _, _>("d0all", D0ALL_COLUMNS, CteParts::new(d0all_cte, body))
}

/// `TeslaMate.Locations.find_geofence/1` for one position: the nearest
/// geofence whose radius contains the position, via the earthdistance
/// extension (`within_geofence?/3` and `distance/2` in
/// `elixir/lib/teslamate/custom_expressions.ex`). Elixir binds the
/// position's coordinates; reading them from the joined row gives the
/// same values.
async fn find_geofence(
    conn: &mut AsyncPgConnection,
    position_id: Option<i32>,
) -> Result<Option<i32>, Error> {
    let Some(position_id) = position_id else {
        return Ok(None);
    };

    let geofence = sql::<Bool>(
        r#"earth_box(ll_to_earth("geofences"."latitude"::numeric, "geofences"."longitude"::numeric), "geofences"."radius") @> ll_to_earth("positions"."latitude"::numeric, "positions"."longitude"::numeric)
            AND earth_distance(ll_to_earth("geofences"."latitude"::numeric, "geofences"."longitude"::numeric), ll_to_earth("positions"."latitude"::numeric, "positions"."longitude"::numeric)) < "geofences"."radius""#,
    );
    let nearest = sql::<Float8>(
        r#"earth_distance(ll_to_earth("geofences"."latitude"::numeric, "geofences"."longitude"::numeric), ll_to_earth("positions"."latitude"::numeric, "positions"."longitude"::numeric))"#,
    );

    // The limit is part of Elixir's query; at most one geofence comes
    // back.
    let found = geofences::table
        .inner_join(positions::table.on(positions::id.eq(position_id)))
        .filter(geofence)
        .order_by(nearest.asc())
        .select(geofences::id)
        .limit(1)
        .load::<i32>(conn)
        .await?;
    Ok(found.into_iter().next())
}

/// The geofence of a closed drive, as the `UPDATE` binds it, boxed so it
/// fits the `set` tuple: `COALESCE` with the column, because Ecto writes
/// a geofence only when one was found, so a missing one keeps the
/// column's value.
fn keep_geofence(
    column: &'static str,
    geofence_id: Option<i32>,
) -> Box<dyn BoxableExpression<drives::table, Pg, SqlType = Nullable<Int4>>> {
    let head = "COALESCE(".to_owned();
    let tail = format!(r#", "drives"."{column}")"#);
    Box::new(
        sql::<Nullable<Int4>>(&head)
            .bind::<Nullable<Int4>, _>(geofence_id)
            .sql(&tail),
    )
}

/// Close drive `drive_id` on `conn`, in one transaction: Elixir runs the
/// steps without one. Called inside a transaction, it becomes a
/// savepoint.
///
/// # Errors
///
/// Fails if a query fails; if the drive does not exist, as
/// [`diesel::result::Error::NotFound`] (Elixir raises a stale entry
/// error then); or if an aggregate does not fit its `smallint` column,
/// which Postgres rejects where Postgrex fails to encode.
pub async fn close_drive_on(conn: &mut AsyncPgConnection, drive_id: i32) -> Result<Outcome, Error> {
    conn.transaction::<Outcome, Error, _>(async |conn| {
        // At most one row: the aggregate deletes the drive without one.
        let aggregate = build_aggregate_query(drive_id)
            .load::<Aggregate>(conn)
            .await?
            .into_iter()
            .next();

        // Elixir's condition is `count >= 2 and distance >= 0.01`, and a
        // drive without a row at all — no position with a range and an
        // odometer — is deleted too. A NULL distance keeps the drive
        // there, as `nil >= 0.01` is true in Erlang's term order;
        // mirrored here on purpose.
        let Some(aggregate) = aggregate.filter(|aggregate| {
            aggregate.count >= 2 && aggregate.distance.is_none_or(|distance| distance >= 0.01)
        }) else {
            let deleted = diesel::delete(drives::table)
                .filter(drives::id.eq(drive_id))
                .execute(conn)
                .await?;
            if deleted == 0 {
                return Err(Error::from(diesel::result::Error::NotFound));
            }
            return Ok(Outcome::Deleted);
        };

        let start_geofence_id = find_geofence(conn, aggregate.start_position_id).await?;
        let end_geofence_id = find_geofence(conn, aggregate.end_position_id).await?;

        let drive =
            diesel::update(drives::table)
                .filter(drives::id.eq(drive_id))
                .set((
                    drives::start_date.eq(aggregate.start_date),
                    drives::end_date.eq(aggregate.end_date),
                    drives::start_position_id.eq(aggregate.start_position_id),
                    drives::end_position_id.eq(aggregate.end_position_id),
                    drives::outside_temp_avg.eq(aggregate.outside_temp_avg),
                    drives::inside_temp_avg.eq(aggregate.inside_temp_avg),
                    drives::speed_max.eq(aggregate.speed_max),
                    drives::power_max.eq(aggregate.power_max),
                    drives::power_min.eq(aggregate.power_min),
                    drives::start_ideal_range_km.eq(aggregate.start_ideal_range_km),
                    drives::end_ideal_range_km.eq(aggregate.end_ideal_range_km),
                    drives::start_rated_range_km.eq(aggregate.start_rated_range_km),
                    drives::end_rated_range_km.eq(aggregate.end_rated_range_km),
                    drives::start_km.eq(aggregate.start_km),
                    drives::end_km.eq(aggregate.end_km),
                    drives::distance.eq(aggregate.distance),
                    // bound as `integer`/`bigint`, narrowed to the `smallint`
                    // columns by Postgres
                    drives::duration_min
                        .eq(sql::<Nullable<Int2>>("")
                            .bind::<Nullable<Int4>, _>(aggregate.duration_min)),
                    drives::ascent
                        .eq(sql::<Nullable<Int2>>("").bind::<BigInt, _>(aggregate.ascent)),
                    drives::descent
                        .eq(sql::<Nullable<Int2>>("").bind::<BigInt, _>(aggregate.descent)),
                    drives::start_geofence_id
                        .eq(keep_geofence("start_geofence_id", start_geofence_id)),
                    drives::end_geofence_id.eq(keep_geofence("end_geofence_id", end_geofence_id)),
                ))
                // the columns in `Drive`'s field order, which `Queryable`
                // deserializes by position
                .returning((
                    drives::id,
                    drives::car_id,
                    drives::start_date,
                    drives::end_date,
                    drives::start_position_id,
                    drives::end_position_id,
                    drives::start_address_id,
                    drives::end_address_id,
                    drives::start_geofence_id,
                    drives::end_geofence_id,
                    drives::outside_temp_avg,
                    drives::inside_temp_avg,
                    drives::speed_max,
                    drives::power_max,
                    drives::power_min,
                    drives::start_ideal_range_km,
                    drives::end_ideal_range_km,
                    drives::start_rated_range_km,
                    drives::end_rated_range_km,
                    drives::start_km,
                    drives::end_km,
                    drives::distance,
                    drives::duration_min,
                    drives::ascent,
                    drives::descent,
                ))
                .get_result::<Drive>(conn)
                .await?;

        Ok(Outcome::Closed(Box::new(drive)))
    })
    .await
}

/// Close drive `drive_id`: [`close_drive_on`] on a connection checked out
/// of `pool`.
///
/// # Errors
///
/// Fails if the pool cannot provide a connection, or as
/// [`close_drive_on`].
pub async fn close_drive(pool: &DatabasePool, drive_id: i32) -> Result<Outcome, Error> {
    let mut conn = pool.get().await?;
    close_drive_on(&mut conn, drive_id).await
}

#[cfg(test)]
mod tests {
    use super::build_aggregate_query;
    use diesel::debug_query;
    use diesel::pg::Pg;

    #[test]
    fn builds_the_nested_aggregate_ctes() {
        let sql = debug_query::<Pg, _>(&build_aggregate_query(-1)).to_string();

        // the CTE chain, outermost first
        assert!(sql.starts_with(r#"WITH "d0all" ("count""#), "{sql}");
        assert!(
            sql.contains(r#"WITH "d1e" ("start_ideal_range_km""#),
            "{sql}"
        );
        assert!(sql.contains(r#"WITH "e" ("ascent", "descent")"#), "{sql}");
        assert!(sql.contains(r#"WITH "p1" ("elevation_diff")"#), "{sql}");
        // the joins that keep Ecto's INNER JOIN ON true
        assert!(
            sql.contains(r#"FROM ("positions" INNER JOIN "d1e" ON true)"#),
            "{sql}"
        );
        assert!(
            sql.contains(r#"FROM ("positions" INNER JOIN "e" ON true)"#),
            "{sql}"
        );
        // the window frame of Ecto's named window w, over the whole drive
        assert!(
            sql.contains(r#"COUNT(*) OVER ( ORDER BY "positions"."date" ASC RANGE"#),
            "{sql}"
        );
        // the elevation cap, and the duration fragment
        assert!(
            sql.contains(r#"LEAST(SUM(CASE WHEN "p1"."elevation_diff" > 0"#),
            "{sql}"
        );
        assert!(
            sql.contains(r#"round(extract(epoch FROM (last_value("positions"."date")"#),
            "{sql}"
        );
        // the filters of the three aggregates
        assert!(
            sql.contains(
                r#"("positions"."drive_id" = $1) AND ("positions"."elevation" IS NOT NULL)"#
            ),
            "{sql}"
        );
        assert!(
            sql.contains(r#"("positions"."ideal_battery_range_km" IS NOT NULL"#),
            "{sql}"
        );
        assert!(
            sql.contains(r#"("positions"."odometer" IS NOT NULL)"#),
            "{sql}"
        );
    }
}
