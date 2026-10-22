//! Port of the "Drive" table of the Grafana dashboard
//! `grafana/dashboards/drives.json`: the drives of a car, filtered by the
//! dashboard's variables, sortable by any column the table shows.
//!
//! The SQL in `drives.sql` is the dashboard's, with the Grafana variables
//! turned into bind parameters and a sort added; the file lists every
//! deviation. `tests/drives.rs` runs both against the same data and compares
//! the rows.

use sqlx::{
    PgExecutor,
    types::{
        BigDecimal,
        chrono::{DateTime, NaiveDateTime, Utc},
    },
};

use crate::settings::{LengthUnit, PreferredRange, TemperatureUnit};

/// The dashboard's `$geofence`: "All", or the drives that start or end in
/// one of the given geofences. An empty list matches no drive; Grafana
/// offers no empty selection.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Geofences {
    All,
    Any(Vec<i32>),
}

/// The dashboard's `$efficiency`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Efficiency {
    /// "slope-adjusted": the energy the distance needs at 100 % efficiency
    /// over the energy used, corrected for ascent and descent.
    SlopeAdjusted,
    /// "by distance": distance over range used.
    ByDistance,
}

impl Efficiency {
    /// The dashboard's value, which the SQL compares against.
    const fn as_str(self) -> &'static str {
        match self {
            Self::SlopeAdjusted => "slope-adjusted",
            Self::ByDistance => "by distance",
        }
    }
}

/// A column the dashboard table shows, to sort by.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
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

    /// The column name, which the SQL's ORDER BY compares against. Nothing
    /// checks at compile time that the SQL spells it the same way;
    /// `tests/drives.rs` sorts by every key.
    const fn as_str(self) -> &'static str {
        match self {
            Self::StartDate => "start_date",
            Self::StartAddress => "start_address",
            Self::EndAddress => "end_address",
            Self::DurationMin => "duration_min",
            Self::Distance => "distance",
            Self::StartBatteryLevel => "start_battery_level",
            Self::EndBatteryLevel => "end_battery_level",
            Self::OutsideTemp => "outside_temp",
            Self::SpeedAvg => "speed_avg",
            Self::SpeedMax => "speed_max",
            Self::PowerMax => "power_max",
            Self::HasReducedRange => "has_reduced_range",
            Self::Efficiency => "efficiency",
            Self::ConsumptionKwh => "consumption_kwh",
            Self::ConsumptionWhPerDistance => "consumption_wh_per_distance",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Direction {
    Ascending,
    Descending,
}

impl Direction {
    const fn as_str(self) -> &'static str {
        match self {
            Self::Ascending => "asc",
            Self::Descending => "desc",
        }
    }
}

/// Sort by `key` in `direction`, NULLs last either way, then by drive id,
/// newest first.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Sort {
    pub key: SortKey,
    pub direction: Direction,
}

/// The dashboard's variables, plus the sort.
#[derive(Clone, Debug)]
pub struct Params {
    /// `$car_id`
    pub car_id: i16,
    /// `$__timeFilter(start_date)`: drives that started between `from` and
    /// `to`, both included.
    pub from: DateTime<Utc>,
    pub to: DateTime<Utc>,
    /// `$length_unit`
    pub length_unit: LengthUnit,
    /// `$temp_unit`
    pub temperature_unit: TemperatureUnit,
    /// `${preferred_range}`
    pub preferred_range: PreferredRange,
    /// `$min_dist`, in `length_unit`. Always applied, as in the dashboard,
    /// so drives without a distance never show up.
    pub min_distance: BigDecimal,
    /// `$min_speed`, average speed in `length_unit` per hour. Always applied.
    pub min_speed: BigDecimal,
    /// `$geofence`
    pub geofences: Geofences,
    /// `$location`: drives whose start or end address contains this text,
    /// ignoring case; `%` and `_` match any text or character. `None` for
    /// no filter, which is what the dashboard's empty box does.
    pub location: Option<String>,
    /// `$efficiency`
    pub efficiency: Efficiency,
    /// `None`: newest drive first, the dashboard's order.
    pub sort: Option<Sort>,
}

/// One row of the dashboard table: a drive.
///
/// Columns and Postgres types are the dashboard's; NUMERIC decodes to
/// `BigDecimal`. Distances and speeds are in [`Params::length_unit`],
/// temperatures in [`Params::temperature_unit`]; the dashboard puts the
/// unit into the column names instead (`distance_km`, ...). sqlx infers
/// every column as nullable, see `vampire_drain::Row`.
#[derive(Clone, Debug, PartialEq)]
pub struct Row {
    pub start_date_ts: Option<BigDecimal>,
    pub end_date_ts: Option<BigDecimal>,
    pub car_id: Option<i16>,
    /// Link target into the web UI: the geofence, or a new one there.
    pub start_path: Option<String>,
    pub end_path: Option<String>,
    /// `HH24:MI`
    pub duration_str: Option<String>,
    pub drive_id: Option<i32>,
    /// UTC
    pub start_date: Option<NaiveDateTime>,
    pub start_address: Option<String>,
    pub end_address: Option<String>,
    pub duration_min: Option<i16>,
    pub distance: Option<BigDecimal>,
    /// The dashboard's `% Start`.
    pub start_battery_level: Option<i16>,
    /// The dashboard's `% End`.
    pub end_battery_level: Option<i16>,
    pub outside_temp: Option<BigDecimal>,
    pub speed_avg: Option<BigDecimal>,
    pub speed_max: Option<BigDecimal>,
    /// kW
    pub power_max: Option<i16>,
    /// More than a quarter of the drive's positions had a battery level
    /// above the usable level; NULL without positions with a range.
    pub has_reduced_range: Option<bool>,
    pub efficiency: Option<f64>,
    /// The dashboard's `consumption_kWh`.
    pub consumption_kwh: Option<f64>,
    /// Wh per `length_unit`, the dashboard's `consumption_kWh_km` / `_mi`.
    pub consumption_wh_per_distance: Option<f64>,
}

/// The drives matching `params`, in the order of [`Params::sort`].
///
/// # Errors
///
/// Fails if the query fails, e.g. because the database is unreachable.
pub async fn fetch<'e>(
    executor: impl PgExecutor<'e>,
    params: &Params,
) -> Result<Vec<Row>, sqlx::Error> {
    let geofences = match &params.geofences {
        Geofences::All => None,
        Geofences::Any(ids) => Some(ids.as_slice()),
    };
    sqlx::query_file_as!(
        Row,
        "src/drives.sql",
        params.car_id,
        params.from.naive_utc(),
        params.to.naive_utc(),
        // sqlx has no built-in mapping for the Postgres enums; `as` names
        // the Rust type to encode them with. Only the Rust type is checked
        // at compile time, not that it matches the Postgres enum.
        params.length_unit as LengthUnit,
        params.temperature_unit as TemperatureUnit,
        params.preferred_range as PreferredRange,
        params.min_distance,
        params.min_speed,
        geofences,
        params.location,
        params.efficiency.as_str(),
        params.sort.map(|sort| sort.key.as_str()),
        params.sort.map(|sort| sort.direction.as_str()),
    )
    .fetch_all(executor)
    .await
}
