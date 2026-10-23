use sqlx::{
    PgPool,
    postgres::{PgConnectOptions, PgPoolOptions, PgSslMode},
};

use crate::config;

/// Opens a connection pool to the database in `config` and checks that it
/// can connect.
///
/// # Errors
///
/// Fails if no connection to the database can be established.
pub async fn connect(config: &config::Database) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .connect_with(connect_options(config))
        .await
}

/// TLS is off, like in the Elixir app while `DATABASE_SSL` is unset; sqlx is
/// built without a TLS backend until that variable is supported. Neither it
/// nor the other `DATABASE_*` variables missing from [`config::Database`]
/// are supported yet.
fn connect_options(config: &config::Database) -> PgConnectOptions {
    // sqlx has no constructor that ignores the libpq `PG*` environment
    // variables; every option set here overrides its variable.
    PgConnectOptions::new_without_pgpass()
        .host(&config.host)
        .port(config.port)
        .username(&config.user)
        .password(config.pass.as_str())
        .database(&config.name)
        .ssl_mode(PgSslMode::Disable)
}

#[cfg(test)]
mod tests {
    use sqlx::postgres::PgSslMode;

    use super::{config, connect_options};

    #[test]
    fn connects_as_configured_without_tls() {
        let options = connect_options(&config::Database {
            user: "user".to_owned(),
            pass: "pass".to_owned().into(),
            host: "host".to_owned(),
            port: 7000,
            name: "name".to_owned(),
        });
        assert_eq!(options.get_host(), "host");
        assert_eq!(options.get_port(), 7000);
        assert_eq!(options.get_username(), "user");
        assert_eq!(options.get_database(), Some("name"));
        assert!(matches!(options.get_ssl_mode(), PgSslMode::Disable));
    }
}
