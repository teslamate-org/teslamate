use clap::Parser;

const VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Parser, Debug)]
#[command(version = VERSION, about)]
pub struct Args {
    #[arg(short, long, default_value_t = false)]
    pub verbose: bool,
}
