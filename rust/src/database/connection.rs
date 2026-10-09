use diesel::prelude::*;
use diesel_async::RunQueryDsl;
use diesel_async::pooled_connection::AsyncDieselConnectionManager;
use diesel_async::pooled_connection::PoolError;
use diesel_async::pooled_connection::bb8::Pool;
use diesel_async::pooled_connection::bb8::PooledConnection;
use thiserror::Error;

use crate::database::schema::schema_migrations::table as schema_migrations_table;

use std::env;

#[derive(Debug, Clone)]
pub struct DatabasePool(Pool<diesel_async::AsyncPgConnection>);
pub type DatabaseConnection = PooledConnection<'static, diesel_async::AsyncPgConnection>;

impl DatabasePool {
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

    #[error("DATABASE_URL environment variable not set")]
    MissingDatabaseUrl,

    #[error("failed to build database pool")]
    PoolInit,
}

pub async fn init() -> Result<DatabasePool, Error> {
    let database_url = env::var("DATABASE_URL").map_err(|_| Error::MissingDatabaseUrl)?;
    let config = AsyncDieselConnectionManager::<diesel_async::AsyncPgConnection>::new(database_url);

    let pool = Pool::builder()
        .build(config)
        .await
        .map_err(|_| Error::PoolInit)?;

    Ok(DatabasePool(pool))
}

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
