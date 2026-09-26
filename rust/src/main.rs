mod cli;
mod config;
mod version;
// Compiled into build.rs; part of the crate only for its tests.
#[cfg(test)]
mod version_file;

use std::process::ExitCode;

use clap::Parser;

#[tokio::main]
async fn main() -> ExitCode {
    let config = cli::Args::parse().config;
    let Some(result) = add(config.operand_a, config.operand_b) else {
        eprintln!(
            "error: add({}, {}) overflows",
            config.operand_a, config.operand_b
        );
        return ExitCode::FAILURE;
    };
    println!("add({}, {}) = {result}", config.operand_a, config.operand_b);
    ExitCode::SUCCESS
}

const fn add(a: i32, b: i32) -> Option<i32> {
    a.checked_add(b)
}

#[cfg(test)]
mod test {
    use super::add;

    #[test]
    fn test_add() {
        assert_eq!(add(1, 2), Some(3));
        assert_eq!(add(i32::MAX, 1), None);
    }
}
