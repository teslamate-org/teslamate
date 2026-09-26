#[derive(clap::Args, Debug)]
pub struct Config {
    #[arg(long, env = "ADDOperandA", default_value_t = 1)]
    pub operand_a: i32,

    #[arg(long, env = "ADDOperandB", default_value_t = 2)]
    pub operand_b: i32,
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
            Some(("ADDOperandA".to_owned(), "1".to_owned()))
        );
        assert_eq!(
            declared("operand_b"),
            Some(("ADDOperandB".to_owned(), "2".to_owned()))
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
