use clap::Parser;

use crate::{config::Config, version::VERSION};

#[derive(Parser, Debug)]
#[command(version = VERSION, about)]
pub struct Args {
    #[arg(short, long, default_value_t = false)]
    pub verbose: bool,

    #[command(flatten)]
    pub config: Config,
}

#[cfg(test)]
mod tests {
    use clap::CommandFactory;

    use super::Args;

    #[test]
    fn command_is_valid() {
        Args::command().debug_assert();
    }
}
