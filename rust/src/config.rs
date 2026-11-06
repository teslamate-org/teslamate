use std::io::Stderr;

#[derive(clap::Args)]
pub struct Config {
    #[arg(long, env = "ADD_OPERAND_A", default_value_t = 1)]
    pub operand_a: i32,

    #[arg(long, env = "ADD_OPERAND_B", default_value_t = 2)]
    pub operand_b: i32,
}

#[derive(clap::Args)]
pub struct Mqtt {
    #[arg(long = "mqtt-username", env = "MQTT_USERNAME")]
    pub username: Option<String>,

    #[arg(long = "mqtt-password", env = "MQTT_PASSWORD")]
    pub password: Option<String>,

    #[arg(long = "mqtt-tls", env = "MQTT_TLS")]
    pub tls: bool,

    #[arg(
        long = "mqtt-tls-accept-invalid-certs",
        env = "MQTT_TLS_ACCEPT_INVALID_CERTS",
        default_value_t = false
    )]
    pub tls_accept_invalid_certs: bool,

    #[arg(long = "mqtt-host", env = "MQTT_HOST")]
    pub host: String,

    #[arg(long = "mqtt-port", env = "MQTT_PORT", default_value_t = 8883)]
    pub port: u16,
}

#[cfg(test)]
mod tests {
    use clap::{CommandFactory, Parser, error::ErrorKind};

    use super::Config;

    // clap reads the process environment whenever an argument is missing on
    // the command line. So the tests check the declarations and parse with
    // every argument given as a flag, which never consults the environment.
    #[derive(Parser)]
    struct Cli {
        #[command(flatten)]
        config: Config,
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
    }

    #[test]
    fn parses_operands_as_integers() {
        let parse = |value: &str| {
            Cli::try_parse_from(["test", "--operand-a", value, "--operand-b", "0"])
                .map(|cli| cli.config.operand_a)
        };
        assert_eq!(parse("5").ok(), Some(5));
        assert_eq!(
            parse("abc").map_err(|error| error.kind()).err(),
            Some(ErrorKind::ValueValidation)
        );
    }
}
