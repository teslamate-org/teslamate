//! Port of the database part of `TeslaMate.Log.close_drive/2`
//! (`elixir/lib/teslamate/log.ex`): aggregate the positions of a drive into
//! the drive, or delete it if it has too few of them.
//!
//! This is `close_drive(drive, lookup_address: false)`: the address lookup
//! calls an external geocoder and is not ported, so the address columns are
//! left as they are. The geofences are looked up as in Elixir.
//!
//! `tests/close_drive.rs` replays the drives of the Elixir characterization
//! goldens and compares the result.

use sqlx::{
    Acquire, Postgres,
    types::{BigDecimal, chrono::NaiveDateTime},
};

/// The drive as `close_drive` leaves it.
#[derive(Clone, Debug, PartialEq)]
pub struct Drive {
    pub id: i32,
    pub car_id: i16,
    /// UTC
    pub start_date: NaiveDateTime,
    /// UTC
    pub end_date: Option<NaiveDateTime>,
    pub start_position_id: Option<i32>,
    pub end_position_id: Option<i32>,
    pub start_address_id: Option<i32>,
    pub end_address_id: Option<i32>,
    pub start_geofence_id: Option<i32>,
    pub end_geofence_id: Option<i32>,
    pub outside_temp_avg: Option<BigDecimal>,
    pub inside_temp_avg: Option<BigDecimal>,
    pub speed_max: Option<i16>,
    pub power_max: Option<i16>,
    pub power_min: Option<i16>,
    pub start_ideal_range_km: Option<BigDecimal>,
    pub end_ideal_range_km: Option<BigDecimal>,
    pub start_rated_range_km: Option<BigDecimal>,
    pub end_rated_range_km: Option<BigDecimal>,
    pub start_km: Option<f64>,
    pub end_km: Option<f64>,
    pub distance: Option<f64>,
    pub duration_min: Option<i16>,
    pub ascent: Option<i16>,
    pub descent: Option<i16>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Outcome {
    /// Updated with the aggregates of its positions.
    Closed(Box<Drive>),
    /// Deleted: fewer than two positions, less than 0.01 km driven, or no
    /// position with both a range and an odometer.
    Deleted,
}

/// Closes drive `drive_id`, in one transaction (Elixir runs the steps
/// without one).
///
/// # Errors
///
/// Fails if a query fails, if the drive does not exist (Elixir raises a
/// stale entry error then), or if an aggregate does not fit its smallint
/// column.
pub async fn close_drive<'c>(
    connection: impl Acquire<'c, Database = Postgres>,
    drive_id: i32,
) -> Result<Outcome, sqlx::Error> {
    let mut transaction = connection.begin().await?;

    let aggregate = sqlx::query_file!("src/close_drive/aggregate.sql", drive_id)
        .fetch_optional(&mut *transaction)
        .await?;

    // Elixir's condition is `count >= 2 and distance >= 0.01`. A NULL
    // distance (no odometer at the first or the last position) satisfies
    // it there, as `nil >= 0.01` is true in Erlang's term order, so the
    // drive is updated with a NULL distance. Mirrored here on purpose.
    let Some(aggregate) = aggregate.filter(|aggregate| {
        aggregate.count.is_some_and(|count| count >= 2)
            && aggregate.distance.is_none_or(|distance| distance >= 0.01)
    }) else {
        let deleted = sqlx::query!("DELETE FROM drives WHERE id = $1", drive_id)
            .execute(&mut *transaction)
            .await?;
        if deleted.rows_affected() == 0 {
            return Err(sqlx::Error::RowNotFound);
        }
        transaction.commit().await?;
        return Ok(Outcome::Deleted);
    };

    let start_geofence_id = find_geofence(&mut transaction, aggregate.start_position_id).await?;
    let end_geofence_id = find_geofence(&mut transaction, aggregate.end_position_id).await?;

    let drive = sqlx::query_file_as!(
        Drive,
        "src/close_drive/update.sql",
        drive_id,
        aggregate.start_date,
        aggregate.end_date,
        aggregate.start_position_id,
        aggregate.end_position_id,
        aggregate.outside_temp_avg,
        aggregate.inside_temp_avg,
        aggregate.speed_max,
        aggregate.power_max,
        aggregate.power_min,
        aggregate.start_ideal_range_km,
        aggregate.end_ideal_range_km,
        aggregate.start_rated_range_km,
        aggregate.end_rated_range_km,
        aggregate.start_km,
        aggregate.end_km,
        aggregate.distance,
        aggregate.duration_min,
        aggregate.ascent,
        aggregate.descent,
        start_geofence_id,
        end_geofence_id,
    )
    .fetch_one(&mut *transaction)
    .await?;

    transaction.commit().await?;
    Ok(Outcome::Closed(Box::new(drive)))
}

/// The geofence of position `position_id`, if any.
async fn find_geofence(
    transaction: &mut sqlx::Transaction<'_, Postgres>,
    position_id: Option<i32>,
) -> Result<Option<i32>, sqlx::Error> {
    let Some(position_id) = position_id else {
        return Ok(None);
    };
    sqlx::query_file_scalar!("src/close_drive/find_geofence.sql", position_id)
        .fetch_optional(&mut **transaction)
        .await
}
