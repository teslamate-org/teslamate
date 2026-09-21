mod cli;
mod config;
mod version;

use clap::Parser;
use config::Config;
use envconfig::Envconfig;

#[tokio::main]
async fn main() {
    let args = cli::Args::parse();
    if args.verbose {
        println!("verbose mode enabled");
    }
    let config = Config::init_from_env().expect("failed to load configuration from environment");
    let result = add(config.operand_a, config.operand_b);
    println!("add({}, {}) = {result}", config.operand_a, config.operand_b);
}

const fn add(a: i32, b: i32) -> i32 {
    a + b
}

#[cfg(test)]
mod test {
    use super::add;

    #[test]
    fn test_add() {
        assert_eq!(add(1, 2), 3);
    }
}
