mod cli;
mod config;
mod database;
mod logging;
mod version;
// Compiled into build.rs; part of the crate only for its tests.
#[cfg(test)]
mod version_file;

use std::process::ExitCode;

use clap::Parser;
use tracing::{info, instrument};

use crate::database::connection::{get_migrations, init};

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
