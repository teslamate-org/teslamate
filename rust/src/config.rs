#[derive(clap::Args, Debug)]
pub struct OtlpConfig {
    #[arg(long = "otlp-endpoint", env = "OTLP_ENDPOINT")]
    pub endpoint: Option<String>,

    #[arg(long = "otlp-username", env = "OTLP_USERNAME")]
    pub username: Option<String>,

    #[arg(long = "otlp-password", env = "OTLP_PASSWORD")]
    pub password: Option<String>,

    #[arg(long = "otlp-organization", env = "OTLP_ORGANIZATION")]
    pub organization: Option<String>,

    #[arg(long = "otlp-stream-name", env = "OTLP_STREAM_NAME")]
    pub stream_name: Option<String>,
}

impl OtlpConfig {
    pub const fn is_configured(&self) -> bool {
        self.endpoint.is_some()
    }
}

#[derive(clap::Args, Debug)]
pub struct Config {
    #[arg(long, env = "ADD_OPERAND_A", default_value_t = 1)]
    pub operand_a: i32,

    #[arg(long, env = "ADD_OPERAND_B", default_value_t = 2)]
    pub operand_b: i32,

    #[arg(long, env = "DEPLOYMENT_ENVIRONMENT", default_value_t = String::from("development"))]
    pub deployment_environment: String,

    #[command(flatten)]
    pub otlp: OtlpConfig,
}

#[cfg(test)]
mod tests {
    use clap::{error::ErrorKind, CommandFactory, Parser};

    use super::Config;

    #[derive(Parser)]
    struct Cli {
        #[command(flatten)]
        config: Config,
    }

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
            declared("deployment_environment"),
            Some((
                "DEPLOYMENT_ENVIRONMENT".to_owned(),
                "development".to_owned()
            ))
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
