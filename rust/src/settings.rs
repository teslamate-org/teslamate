//! Values of the `settings` table that queries take as parameters, each
//! mapped to the Postgres enum of the same name.

/// Which of the car's range estimates to use, the `preferred_range`
/// setting.
#[derive(Clone, Copy, Debug, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "preferred_range", rename_all = "lowercase")]
pub enum PreferredRange {
    Ideal,
    Rated,
}

/// Unit of distances and ranges, the `unit_of_length` setting.
#[derive(Clone, Copy, Debug, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "unit_of_length", rename_all = "lowercase")]
pub enum LengthUnit {
    Km,
    Mi,
}

/// Unit of temperatures, the `unit_of_temperature` setting.
#[derive(Clone, Copy, Debug, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "unit_of_temperature")]
pub enum TemperatureUnit {
    #[sqlx(rename = "C")]
    Celsius,
    #[sqlx(rename = "F")]
    Fahrenheit,
}
