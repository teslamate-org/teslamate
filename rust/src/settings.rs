//! Values of the `settings` table that queries take as parameters: the
//! units and the preferred range.
//!
//! The Postgres columns are enums of the same names; the queries pass
//! these on as text, the way the Grafana dashboards interpolate the
//! variables into their SQL.

/// Which of the car's range estimates to use, the `preferred_range`
/// setting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreferredRange {
    Ideal,
    Rated,
}

impl PreferredRange {
    /// The value the dashboard interpolates for `${preferred_range}` and
    /// the label of the `preferred_range` enum.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Ideal => "ideal",
            Self::Rated => "rated",
        }
    }
}

/// Unit of distances and ranges, the `unit_of_length` setting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LengthUnit {
    Kilometers,
    Miles,
}

impl LengthUnit {
    /// The value the dashboard interpolates for `$length_unit` and the
    /// label of the `unit_of_length` enum.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Kilometers => "km",
            Self::Miles => "mi",
        }
    }
}

/// Unit of temperatures, the `unit_of_temperature` setting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TemperatureUnit {
    Celsius,
    Fahrenheit,
}

impl TemperatureUnit {
    /// The value the dashboard interpolates for `$temp_unit` and the label
    /// of the `unit_of_temperature` enum.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Celsius => "C",
            Self::Fahrenheit => "F",
        }
    }
}
