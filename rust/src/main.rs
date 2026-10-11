mod cli;
mod config;
mod database;
mod logging;
mod version;
// Compiled into build.rs; part of the crate only for its tests.
#[cfg(test)]
mod version_file;

use std::ops::Sub;
use std::process::ExitCode;

use clap::Parser;
use tracing::{info, instrument};

use crate::database::connection::{get_migrations, init};
use crate::database::queries::vampire_drain::{
    self, LengthUnit, PreferredRange, VampireDrainParams,
};

#[tokio::main]
async fn main() -> ExitCode {
    let config = cli::Args::parse().config;

    let otel_guard = match logging::init_tracing_subscriber() {
        Ok(guard) => guard,
        Err(err) => {
            eprintln!("Failed to initialize tracing subscriber: {err}");
            return ExitCode::FAILURE;
        }
    };

    info!("Starting teslamate-rust version {}", version::VERSION);

    let pool = match init().await {
        Ok(pool) => pool,
        Err(e) => {
            eprintln!("Failed to initialize database: {e}");
            return ExitCode::FAILURE;
        }
    };
    match get_migrations(&pool).await {
        Ok(migrations) => {
            println!("Found {} migrations:", migrations.len());
            for (version, inserted_at) in migrations {
                println!("  version={version}, inserted_at={inserted_at:?}");
            }
        }
        Err(e) => {
            eprintln!("Failed to get migrations: {e}");
            return ExitCode::FAILURE;
        }
    }

    let params = VampireDrainParams {
        car_id: config.car_id,
        from: chrono::Utc::now().naive_utc().sub(chrono::Days::new(90)),
        to: chrono::Utc::now().naive_utc(),
        minimum_duration_hours: 1,
        preferred_range: PreferredRange::Ideal,
        length_unit: LengthUnit::Kilometers,
    };
    // Smoke query: the ported dashboard query and the original raw SQL are
    // supposed to return the same rows.
    let mut ported = match vampire_drain::fetch(&pool, &params).await {
        Ok(rows) => rows,
        Err(e) => {
            eprintln!("Failed to query vampire drain: {e}");
            return ExitCode::FAILURE;
        }
    };
    let mut original = match vampire_drain::fetch_original(&pool, &params).await {
        Ok(rows) => rows,
        Err(e) => {
            eprintln!("Failed to query vampire drain (original SQL): {e}");
            return ExitCode::FAILURE;
        }
    };
    println!("Found {} vampire drain rows", ported.len());
    for row in ported.iter().take(3) {
        println!("  {row:?}");
    }
    // Neither query has a top-level ORDER BY (the dashboard does not either),
    // so compare the rows in a stable order.
    ported.sort_by_key(|row| (row.start_date, row.end_date));
    original.sort_by_key(|row| (row.start_date, row.end_date));
    if ported != original {
        eprintln!(
            "Ported query differs from the original dashboard SQL: {} vs {} rows",
            ported.len(),
            original.len()
        );
        for (i, (ported_row, original_row)) in
            ported.iter().zip(original.iter()).enumerate().take(5)
        {
            if ported_row != original_row {
                eprintln!(
                    "  row {i}:\n    ported:    {ported_row:?}\n    original:  {original_row:?}"
                );
            }
        }
        return ExitCode::FAILURE;
    }
    println!("Ported query matches the original dashboard SQL");

    let Some(result) = add(config.operand_a, config.operand_b) else {
        eprintln!(
            "error: add({}, {}) overflows",
            config.operand_a, config.operand_b
        );
        return ExitCode::FAILURE;
    };
    println!("add({}, {}) = {result}", config.operand_a, config.operand_b);

    drop(otel_guard);
    ExitCode::SUCCESS
}

#[instrument]
fn add(a: i32, b: i32) -> Option<i32> {
    a.checked_add(b)
}

#[cfg(test)]
mod test {
    use super::add;

    #[test]
    fn test_add() {
        assert_eq!(add(1, 2), Some(3));
        assert_eq!(add(i32::MAX, 1), None);
    }
}
