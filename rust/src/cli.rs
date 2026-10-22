use clap::Parser;

use crate::{config::Config, version::VERSION};

#[derive(Parser)]
// --help names each environment variable but never shows its value, as some
// hold secrets.
#[command(version = VERSION, about, mut_args(|arg| arg.hide_env_values(true)))]
pub struct Args {
    #[command(flatten)]
    pub config: Config,
}

#[cfg(test)]
mod tests {
    use clap::{Arg, CommandFactory};

    use super::{Args, VERSION};

    #[test]
    fn command_is_valid() {
        Args::command().debug_assert();
    }

    #[test]
    fn reports_the_version_from_the_version_file() {
        assert_eq!(Args::command().get_version(), Some(VERSION));
    }

    #[test]
    fn help_hides_environment_values() {
        let command = Args::command();
        let variables: Vec<&Arg> = command
            .get_arguments()
            .filter(|arg| arg.get_env().is_some())
            .collect();
        assert!(!variables.is_empty());
        assert!(variables.iter().all(|arg| arg.is_hide_env_values_set()));
    }
}
