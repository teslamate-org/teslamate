use diesel::prelude::*;
use diesel_async::RunQueryDsl;
use diesel_async::pooled_connection::AsyncDieselConnectionManager;
use diesel_async::pooled_connection::PoolError;
use diesel_async::pooled_connection::bb8::Pool;
use diesel_async::pooled_connection::bb8::PooledConnection;
use thiserror::Error;

use crate::config;
use crate::database::schema::schema_migrations::table as schema_migrations_table;

#[derive(Debug, Clone)]
pub struct DatabasePool(Pool<diesel_async::AsyncPgConnection>);
pub type DatabaseConnection = PooledConnection<'static, diesel_async::AsyncPgConnection>;

impl DatabasePool {
    /// Checks out a connection from the pool.
    ///
    /// # Errors
    ///
    /// Fails if the pool cannot provide a connection.
    pub async fn get(&self) -> Result<DatabaseConnection, bb8::RunError<PoolError>> {
        self.0.get_owned().await
    }
}

#[derive(Error, Debug)]
pub enum Error {
    #[error(transparent)]
    Diesel(#[from] diesel::result::Error),

    #[error(transparent)]
    Bb8(#[from] bb8::RunError<PoolError>),

    #[error("failed to build database pool")]
    PoolInit,
}

/// Opens the connection pool to `database` and checks that it can connect.
///
/// # Errors
///
/// Fails if no connection to the database can be established.
pub async fn init(database: &config::Database) -> Result<DatabasePool, Error> {
    let manager =
        AsyncDieselConnectionManager::<diesel_async::AsyncPgConnection>::new(url(database));

    let pool = Pool::builder()
        .build(manager)
        .await
        .map_err(|_| Error::PoolInit)?;

    Ok(DatabasePool(pool))
}

/// The connection URL for `database`: diesel-async connects by URL, unlike
/// the Elixir app's structured repo config. User and password are
/// percent-encoded, so characters that delimit a URL cannot break it; the
/// other components are host names and identifiers, which hold none.
fn url(database: &config::Database) -> String {
    format!(
        "postgresql://{}:{}@{}:{}/{}",
        percent_encode(&database.user),
        percent_encode(database.pass.as_str()),
        database.host,
        database.port,
        database.name,
    )
}

/// Percent-encodes everything outside the URL unreserved set.
fn percent_encode(value: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                encoded.push(byte as char);
            }
            _ => {
                encoded.push('%');
                encoded.push(HEX[usize::from(byte >> 4)] as char);
                encoded.push(HEX[usize::from(byte & 0xf)] as char);
            }
        }
    }
    encoded
}

/// Reads the applied migrations from the `schema_migrations` table, as
/// `(version, inserted_at)` pairs.
///
/// # Errors
///
/// Fails if the table cannot be read.
pub async fn get_migrations(
    pool: &DatabasePool,
) -> Result<Vec<(i64, Option<chrono::NaiveDateTime>)>, Error> {
    use crate::database::schema::schema_migrations::dsl;
    let mut conn = pool.get().await?;
    let results = schema_migrations_table
        .select((dsl::version, dsl::inserted_at))
        .load(&mut conn)
        .await?;
    Ok(results)
}

#[cfg(test)]
mod tests {
    use super::{config, url};

    fn database(user: &str, pass: &str) -> config::Database {
        config::Database {
            user: user.to_owned(),
            pass: pass.to_owned().into(),
            host: "localhost".to_owned(),
            port: 7000,
            name: "teslamate".to_owned(),
        }
    }

    #[test]
    fn builds_the_url_from_the_settings() {
        assert_eq!(
            url(&database("teslamate", "secret")),
            "postgresql://teslamate:secret@localhost:7000/teslamate"
        );
    }

    #[test]
    fn percent_encodes_the_user_and_password() {
        assert_eq!(
            url(&database("user@x", "p:a/s%s+w")),
            "postgresql://user%40x:p%3Aa%2Fs%25s%2Bw@localhost:7000/teslamate"
        );
    }
}
