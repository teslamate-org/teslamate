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
    const fn is_partially_configured(&self) -> bool {
        self.endpoint.is_some()
            || self.username.is_some()
            || self.password.is_some()
            || self.organization.is_some()
            || self.stream_name.is_some()
    }

    pub fn to_settings(&self) -> Result<OtlpSettings, OtlpConfigError> {
        if self.is_partially_configured() {
            Ok(OtlpSettings {
                endpoint: self
                    .endpoint
                    .clone()
                    .ok_or(OtlpConfigError::MissingEndpoint)?,
                username: self
                    .username
                    .clone()
                    .ok_or(OtlpConfigError::MissingUsername)?,
                password: self
                    .password
                    .clone()
                    .ok_or(OtlpConfigError::MissingPassword)?,
                organization: self.organization.clone(),
                stream_name: self.stream_name.clone(),
            })
        } else {
            Err(OtlpConfigError::NotConfigured)
        }
    }
}

#[derive(Debug)]
pub enum OtlpConfigError {
    NotConfigured,
    MissingEndpoint,
    MissingUsername,
    MissingPassword,
}

impl std::fmt::Display for OtlpConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotConfigured => write!(f, "OTLP not configured"),
            Self::MissingEndpoint => write!(f, "OTLP endpoint not configured"),
            Self::MissingUsername => write!(f, "OTLP username not configured"),
            Self::MissingPassword => write!(f, "OTLP password not configured"),
        }
    }
}

impl std::error::Error for OtlpConfigError {}

pub struct OtlpSettings {
    pub endpoint: String,
    pub username: String,
    pub password: String,
    pub organization: Option<String>,
    pub stream_name: Option<String>,
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
    use clap::{CommandFactory, Parser, error::ErrorKind};

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
