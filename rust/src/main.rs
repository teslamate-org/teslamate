mod cli;
mod config;
mod logging;
mod mqtt;
mod version;
// Compiled into build.rs; part of the crate only for its tests.
#[cfg(test)]
mod version_file;

use std::process::ExitCode;

use clap::Parser;
use rumqttc::tokio_rustls::rustls;
use tracing::{debug, info, instrument};

#[tokio::main]
async fn main() -> ExitCode {
    if let Err(e) = rustls::crypto::aws_lc_rs::default_provider().install_default() {
        eprintln!("Failed to install rustls crypto provider: {e:?}");
        std::process::exit(1);
    }

    let args = cli::Args::parse();

    let _otel_guard = match logging::init_tracing_subscriber() {
        Ok(guard) => guard,
        Err(err) => {
            eprintln!("Failed to initialize tracing subscriber: {err}");
            return ExitCode::FAILURE;
        }
    };

    info!("Starting teslamate-rust version {}", version::VERSION);

    let config = args.config;
    let Some(result) = add(config.operand_a, config.operand_b) else {
        eprintln!(
            "error: add({}, {}) overflows",
            config.operand_a, config.operand_b
        );
        return ExitCode::FAILURE;
    };
    println!("add({}, {}) = {result}", config.operand_a, config.operand_b);

    let (tx, rx) = mqtt::mqtt_channel();

    mqtt::run_client(rx, args.mqtt);

    tx.try_serialize_send(
        "test",
        &"Ants eat tigers".to_string(),
        mqtt::Retain::NoRetain,
        rumqttc::v5::mqttbytes::QoS::AtLeastOnce,
    );

    loop {
        debug!("I haven't crashed yet!");
        tokio::time::sleep(std::time::Duration::from_mins(5)).await;
    }

    // drop(otel_guard);
    // ExitCode::SUCCESS
}

#[instrument]
fn add(a: i32, b: i32) -> Option<i32> {
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
