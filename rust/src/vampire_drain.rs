//! Port of the "Vampire Drain" table of the Grafana dashboard
//! `grafana/dashboards/vampire-drain.json`: how much range a car lost while
//! parked between two drives or charges.
//!
//! The SQL in `vampire_drain.sql` is the dashboard's, with the Grafana
//! variables turned into bind parameters; the file lists every deviation.
//! `tests/vampire_drain.rs` runs both against the same data and compares
//! the rows.

use sqlx::{
    PgExecutor,
    types::{
        BigDecimal,
        chrono::{DateTime, NaiveDateTime, Utc},
    },
};

/// Which of the car's range estimates to compare, the `preferred_range`
/// setting. Maps to the Postgres enum of the same name.
#[derive(Clone, Copy, Debug, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "preferred_range", rename_all = "lowercase")]
pub enum PreferredRange {
    Ideal,
    Rated,
}

/// Unit of the range columns, the `unit_of_length` setting. Maps to the
/// Postgres enum of the same name.
#[derive(Clone, Copy, Debug, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "unit_of_length", rename_all = "lowercase")]
pub enum LengthUnit {
    Km,
    Mi,
}

/// The dashboard's variables.
#[derive(Clone, Copy, Debug)]
pub struct Params {
    /// `$car_id`
    pub car_id: i16,
    /// `$__timeFilter(start_date)`: drives and charges that started between
    /// `from` and `to`, both included.
    pub from: DateTime<Utc>,
    pub to: DateTime<Utc>,
    /// `$duration`: only parked periods longer than this many hours.
    pub min_duration_hours: i32,
    /// `${preferred_range}`
    pub preferred_range: PreferredRange,
    /// `$length_unit`
    pub length_unit: LengthUnit,
}

/// One row of the dashboard table: a parked period.
///
/// Columns and Postgres types are the dashboard's; NUMERIC decodes to
/// `BigDecimal`, so no digit is lost. `range_diff` and `range_lost_per_hour`
/// are in [`Params::length_unit`]; the dashboard names them
/// `range_diff_km` etc. instead.
///
/// Every field is an `Option` because sqlx infers nullability from the query
/// plan, and through the CTEs, window functions and expressions here it
/// cannot prove any column non-null. Overriding that (`AS "end_date!"`)
/// would be a claim only checked at run time, so the inferred types stay.
#[derive(Clone, Debug, PartialEq)]
pub struct Row {
    /// Start of the parked period in milliseconds since the epoch, rounded
    /// down to the second.
    pub start_date_ts: Option<BigDecimal>,
    /// End of the parked period in milliseconds since the epoch, rounded up
    /// to the second.
    pub end_date_ts: Option<BigDecimal>,
    /// UTC
    pub start_date: Option<NaiveDateTime>,
    /// UTC
    pub end_date: Option<NaiveDateTime>,
    /// Seconds
    pub duration: Option<BigDecimal>,
    /// Share of the period the car was asleep or offline, 0 to 1.
    pub standby: Option<BigDecimal>,
    /// Lost battery level in percentage points, zero or negative.
    pub soc_diff: Option<i32>,
    /// 1 if the battery level exceeded the usable battery level at the end
    /// (e.g. in the cold), else 0. The range columns are NULL then.
    pub has_reduced_range: Option<i32>,
    pub range_diff: Option<BigDecimal>,
    /// kWh
    pub consumption: Option<f64>,
    /// Watts
    pub avg_power: Option<f64>,
    pub range_lost_per_hour: Option<BigDecimal>,
}

/// The parked periods of the car in `params`, newest first.
///
/// # Errors
///
/// Fails if the query fails, e.g. because the database is unreachable.
pub async fn fetch<'e>(
    executor: impl PgExecutor<'e>,
    params: &Params,
) -> Result<Vec<Row>, sqlx::Error> {
    sqlx::query_file_as!(
        Row,
        "src/vampire_drain.sql",
        params.car_id,
        params.from.naive_utc(),
        params.to.naive_utc(),
        params.min_duration_hours,
        // sqlx has no built-in mapping for the Postgres enums; `as` names
        // the Rust type to encode them with. Only the Rust type is checked
        // at compile time, not that it matches the Postgres enum.
        params.preferred_range as PreferredRange,
        params.length_unit as LengthUnit,
    )
    .fetch_all(executor)
    .await
}
