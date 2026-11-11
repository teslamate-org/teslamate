#[derive(clap::Args)]
pub struct Config {
    #[command(flatten)]
    pub database: Database,

    #[arg(long, env = "ADD_OPERAND_A", default_value_t = 1)]
    pub operand_a: i32,

    #[arg(long, env = "ADD_OPERAND_B", default_value_t = 2)]
    pub operand_b: i32,

    /// Car to run the vampire drain test query for.
    #[arg(long, env = "CAR_ID", default_value_t = 1)]
    pub car_id: i16,
}

/// Connection to the Postgres database, read from the same environment
/// variables as the Elixir app (`elixir/config/runtime.exs`). As there in
/// production, every variable but the port is required.
// No `Debug`: the struct holds the password.
#[derive(clap::Args)]
pub struct Database {
    #[arg(long = "database-user", env = "DATABASE_USER")]
    pub user: String,

    #[command(flatten)]
    pub pass: Password,

    #[arg(long = "database-host", env = "DATABASE_HOST")]
    pub host: String,

    #[arg(long = "database-port", env = "DATABASE_PORT", default_value_t = 5432)]
    pub port: u16,

    #[arg(long = "database-name", env = "DATABASE_NAME")]
    pub name: String,
}

/// `DATABASE_PASS`, accepted from the environment only: on the command line
/// it would show up in the process list.
///
/// The check lives in this type's own [`clap::FromArgMatches`], so every
/// parser that flattens [`Database`] applies it; the derive offers no hook
/// to check where a value came from.
///
/// The argument still has a flag: without one clap makes it positional, and
/// hiding it would drop `DATABASE_PASS` from `--help`. Its help text says
/// the flag is rejected.
pub struct Password(String);

impl Password {
    const ID: &str = "pass";

    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }

    fn arg() -> clap::Arg {
        clap::Arg::new(Self::ID)
            .long("database-pass")
            .env("DATABASE_PASS")
            .value_name("PASS")
            .required(true)
            .help("Read from the environment only; rejected on the command line")
    }
}

impl From<String> for Password {
    fn from(password: String) -> Self {
        Self(password)
    }
}

impl clap::FromArgMatches for Password {
    fn from_arg_matches(matches: &clap::ArgMatches) -> Result<Self, clap::Error> {
        if matches.value_source(Self::ID) == Some(clap::parser::ValueSource::CommandLine) {
            return Err(clap::Error::raw(
                clap::error::ErrorKind::ValueValidation,
                "DATABASE_PASS must be set in the environment, not on the command line",
            ));
        }
        matches
            .get_one::<String>(Self::ID)
            .map(|password| Self(password.clone()))
            .ok_or_else(|| {
                clap::Error::raw(
                    clap::error::ErrorKind::MissingRequiredArgument,
                    "DATABASE_PASS is not set",
                )
            })
    }

    fn update_from_arg_matches(&mut self, matches: &clap::ArgMatches) -> Result<(), clap::Error> {
        if matches.contains_id(Self::ID) {
            *self = Self::from_arg_matches(matches)?;
        }
        Ok(())
    }
}

impl clap::Args for Password {
    fn augment_args(command: clap::Command) -> clap::Command {
        command.arg(Self::arg())
    }

    fn augment_args_for_update(command: clap::Command) -> clap::Command {
        command.arg(Self::arg().required(false))
    }
}

#[cfg(test)]
mod tests {
    use clap::{ArgMatches, Command, CommandFactory, FromArgMatches, Parser, error::ErrorKind};

    use super::Config;

    // As in `database_tests` below, parsing never depends on the environment:
    // every argument but the password is given as a flag, and the password,
    // which must come from the environment, is read from the variable `env`
    // instead of `DATABASE_PASS` (or from none), so the tests set no variable.
    #[derive(Parser)]
    struct Cli {
        #[command(flatten)]
        config: Config,
    }

    fn command(env: Option<&'static str>) -> Command {
        Cli::command().mut_arg("pass", |arg| arg.env(env))
    }

    fn parse(
        env: Option<&'static str>,
        operand_a: &str,
        extra: &[&str],
    ) -> Result<Config, clap::Error> {
        let args = [
            "test",
            "--database-user",
            "user",
            "--database-host",
            "host",
            "--database-name",
            "name",
            "--operand-a",
            operand_a,
            "--operand-b",
            "0",
        ];
        let matches: ArgMatches = command(env).try_get_matches_from(args.iter().chain(extra))?;
        Cli::from_arg_matches(&matches).map(|cli| cli.config)
    }

    /// The environment variable and default value declared for `id`.
    fn declared(id: &str) -> Option<(String, String)> {
        let command = Cli::command();
        let arg = command.get_arguments().find(|arg| arg.get_id() == id)?;
        Some((
            arg.get_env()?.to_str()?.to_owned(),
            arg.get_default_values().first()?.to_str()?.to_owned(),
        ))
    }

    #[test]
    fn declares_the_environment_variables_and_defaults() {
        assert_eq!(
            declared("operand_a"),
            Some(("ADD_OPERAND_A".to_owned(), "1".to_owned()))
        );
        assert_eq!(
            declared("operand_b"),
            Some(("ADD_OPERAND_B".to_owned(), "2".to_owned()))
        );
        assert_eq!(
            declared("car_id"),
            Some(("CAR_ID".to_owned(), "1".to_owned()))
        );
    }

    #[test]
    fn parses_operands_as_integers() {
        let parse = |value: &str| parse(Some("PATH"), value, &[]).map(|config| config.operand_a);
        assert_eq!(parse("5").ok(), Some(5));
        assert_eq!(
            parse("abc").map_err(|error| error.kind()).err(),
            Some(ErrorKind::ValueValidation)
        );
    }
}

#[cfg(test)]
mod database_tests {
    use clap::{ArgMatches, Command, CommandFactory, FromArgMatches, Parser, error::ErrorKind};

    use super::Database;

    // As in `tests` above, parsing never depends on the environment: every
    // argument but the password is given as a flag, and the password, which
    // must come from the environment, is read from the variable `env` instead
    // of `DATABASE_PASS` (or from none), so the tests set no variable.
    #[derive(Parser)]
    struct Cli {
        #[command(flatten)]
        database: Database,
    }

    fn command(env: Option<&'static str>) -> Command {
        Cli::command().mut_arg("pass", |arg| arg.env(env))
    }

    fn parse(
        env: Option<&'static str>,
        port: &str,
        extra: &[&str],
    ) -> Result<Database, clap::Error> {
        let args = [
            "test",
            "--database-user",
            "user",
            "--database-host",
            "host",
            "--database-port",
            port,
            "--database-name",
            "name",
        ];
        let matches: ArgMatches = command(env).try_get_matches_from(args.iter().chain(extra))?;
        Cli::from_arg_matches(&matches).map(|cli| cli.database)
    }

    /// The environment variable declared for `id` and whether it is required.
    fn declared(id: &str) -> Option<(String, bool)> {
        let command = Cli::command();
        let arg = command.get_arguments().find(|arg| arg.get_id() == id)?;
        Some((arg.get_env()?.to_str()?.to_owned(), arg.is_required_set()))
    }

    #[test]
    fn requires_every_variable_but_the_port() {
        for (id, env) in [
            ("user", "DATABASE_USER"),
            ("pass", "DATABASE_PASS"),
            ("host", "DATABASE_HOST"),
            ("name", "DATABASE_NAME"),
        ] {
            assert_eq!(declared(id), Some((env.to_owned(), true)), "{id}");
        }
        assert_eq!(declared("port"), Some(("DATABASE_PORT".to_owned(), false)));
    }

    #[test]
    fn defaults_the_port_to_5432() {
        let command = Cli::command();
        let default = command
            .get_arguments()
            .find(|arg| arg.get_id() == "port")
            .and_then(|arg| arg.get_default_values().first()?.to_str());
        assert_eq!(default, Some("5432"));
    }

    #[test]
    fn parses_the_settings() {
        // PATH stands in for DATABASE_PASS: every test process has it.
        let path = std::env::var("PATH").ok();
        assert_eq!(
            parse(Some("PATH"), "7000", &[]).ok().map(|d| (
                d.user,
                d.pass.as_str().to_owned(),
                d.host,
                d.port,
                d.name
            )),
            path.map(|path| (
                "user".to_owned(),
                path,
                "host".to_owned(),
                7000,
                "name".to_owned()
            ))
        );
    }

    #[test]
    fn rejects_the_password_on_the_command_line() {
        let error = parse(Some("PATH"), "7000", &["--database-pass", "secret"]).err();
        assert_eq!(
            error.map(|error| (error.kind(), error.to_string())),
            Some((
                ErrorKind::ValueValidation,
                "error: DATABASE_PASS must be set in the environment, not on the command line"
                    .to_owned()
            ))
        );
    }

    #[test]
    fn requires_the_password() {
        assert_eq!(
            parse(None, "7000", &[]).map_err(|error| error.kind()).err(),
            Some(ErrorKind::MissingRequiredArgument)
        );
    }

    #[test]
    fn parses_the_port_as_a_port_number() {
        assert_eq!(
            parse(Some("PATH"), "65536", &[])
                .map_err(|error| error.kind())
                .err(),
            Some(ErrorKind::ValueValidation)
        );
    }
}
