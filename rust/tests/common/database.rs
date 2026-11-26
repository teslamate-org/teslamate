//! The test database: a Postgres database migrated to the current schema
//! (the Ecto migrations in `elixir/priv/repo/migrations`), configured like
//! the app via `DATABASE_USER`, `DATABASE_PASS`, `DATABASE_HOST`,
//! `DATABASE_PORT` and `DATABASE_NAME`. The tests that need it are ignored
//! by default; run them with `cargo test -- --ignored`.
//!
//! A module of its own, so a test that needs only the database includes
//! just this file (`#[path = "common/database.rs"] mod database;`).

use std::error::Error;

use clap::Parser;
use sqlx::{Postgres, Transaction};
use teslamate_rust::{config, db};

pub type Result<T> = std::result::Result<T, Box<dyn Error>>;

/// The database settings, read from the environment like the app does.
#[derive(Parser)]
struct Env {
    #[command(flatten)]
    database: config::Database,
}

/// A transaction on the configured database. Dropping it, e.g. when an
/// assertion fails, rolls it back, so the database is unchanged afterwards.
pub async fn transaction() -> Result<Transaction<'static, Postgres>> {
    let database = Env::try_parse_from(["test"])
        .map_err(|e| format!("configure the test database with DATABASE_*: {e}"))?
        .database;
    let pool = db::connect(&database).await.map_err(|e| {
        format!(
            "cannot connect to database {:?} on {}:{}: {e}",
            database.name, database.host, database.port
        )
    })?;
    Ok(pool.begin().await?)
}
