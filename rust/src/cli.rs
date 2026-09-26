use clap::Parser;

use crate::version::VERSION;

#[derive(Parser, Debug)]
#[command(version = VERSION, about)]
pub struct Args {
    #[arg(short, long, default_value_t = false)]
    pub verbose: bool,
}
