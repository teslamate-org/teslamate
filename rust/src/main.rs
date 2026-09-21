mod config;
mod version;

use envconfig::Envconfig;
use config::Config;

#[tokio::main]
async fn main() {
    println!("teslamate-rust v{}", version::VERSION);
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
