//! Logs to stderr and, once a collector is configured, exports logs, traces
//! and metrics to it over OTLP/gRPC.
//!
//! Only the standard OpenTelemetry environment variables configure the
//! export, and the SDK reads them itself: `OTEL_EXPORTER_OTLP_ENDPOINT` (or a
//! signal's own `OTEL_EXPORTER_OTLP_{TRACES,METRICS,LOGS}_ENDPOINT`),
//! `OTEL_EXPORTER_OTLP_HEADERS` for credentials, `OTEL_SERVICE_NAME` and
//! `OTEL_RESOURCE_ATTRIBUTES`, e.g. `deployment.environment.name=production`.
//! `RUST_LOG` sets the log filter.

use opentelemetry::{InstrumentationScope, Key, KeyValue, global, trace::TracerProvider};
use opentelemetry_appender_tracing::layer::OpenTelemetryTracingBridge;
use opentelemetry_otlp::{
    ExporterBuildError, LogExporter, MetricExporter, OTEL_EXPORTER_OTLP_ENDPOINT,
    OTEL_EXPORTER_OTLP_LOGS_ENDPOINT, OTEL_EXPORTER_OTLP_METRICS_ENDPOINT,
    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT, SpanExporter, WithTonicConfig,
    tonic_types::transport::ClientTlsConfig,
};
use opentelemetry_sdk::{
    Resource,
    logs::SdkLoggerProvider,
    metrics::{PeriodicReader, SdkMeterProvider},
    trace::SdkTracerProvider,
};
use opentelemetry_semantic_conventions::resource::{SERVICE_NAME, SERVICE_VERSION};
use thiserror::Error;
use tracing_opentelemetry::{MetricsLayer, OpenTelemetryLayer};
use tracing_subscriber::{EnvFilter, layer::SubscriberExt, util::SubscriberInitExt};

use crate::version::VERSION;

#[derive(Error, Debug)]
pub enum Error {
    #[error("Exporter build error: {0}")]
    Exporter(#[from] ExporterBuildError),

    #[error("TryInitError error: {0}")]
    TryInit(#[from] tracing_subscriber::util::TryInitError),
}

/// Whether the signal whose endpoint variable is `signal_endpoint` is
/// exported: only when that variable or `OTEL_EXPORTER_OTLP_ENDPOINT` is set.
/// Otherwise the exporter would send to its default, `http://localhost:4317`,
/// and every export would fail where no collector runs. Like the SDK, an
/// empty value counts as unset.
fn exports(signal_endpoint: &str, var: impl Fn(&str) -> Option<String>) -> bool {
    [signal_endpoint, OTEL_EXPORTER_OTLP_ENDPOINT]
        .into_iter()
        .any(|name| var(name).is_some_and(|value| !value.is_empty()))
}

fn env_var(name: &str) -> Option<String> {
    std::env::var(name).ok()
}

/// The `detected` resource with this program's version and, unless
/// `OTEL_SERVICE_NAME` or `OTEL_RESOURCE_ATTRIBUTES` name the service, its
/// name in place of the SDK's fallback `unknown_service:<executable>`.
fn resource(detected: &Resource) -> Resource {
    let named = detected
        .get(&Key::from_static_str(SERVICE_NAME))
        .is_some_and(|name| !name.as_str().starts_with("unknown_service"));
    let builder = Resource::builder_empty()
        .with_attributes(
            detected
                .iter()
                .map(|(key, value)| KeyValue::new(key.clone(), value.clone())),
        )
        .with_attribute(KeyValue::new(SERVICE_VERSION, VERSION));
    if named {
        builder
    } else {
        builder.with_service_name(env!("CARGO_PKG_NAME"))
    }
    .build()
}

/// For `https://` endpoints the exporter's own TLS default trusts no root
/// certificate, so every handshake would fail; this trusts the `WebPKI` roots.
/// `http://` endpoints ignore it.
fn tls_config() -> ClientTlsConfig {
    ClientTlsConfig::new().with_enabled_roots()
}

fn tracer_provider(resource: &Resource) -> Result<SdkTracerProvider, ExporterBuildError> {
    let exporter = SpanExporter::builder()
        .with_tonic()
        .with_tls_config(tls_config())
        .build()?;

    Ok(SdkTracerProvider::builder()
        .with_batch_exporter(exporter)
        .with_resource(resource.clone())
        .build())
}

fn meter_provider(resource: &Resource) -> Result<SdkMeterProvider, ExporterBuildError> {
    let exporter = MetricExporter::builder()
        .with_tonic()
        .with_tls_config(tls_config())
        .build()?;

    Ok(SdkMeterProvider::builder()
        .with_reader(PeriodicReader::builder(exporter).build())
        .with_resource(resource.clone())
        .build())
}

fn logger_provider(resource: &Resource) -> Result<SdkLoggerProvider, ExporterBuildError> {
    let exporter = LogExporter::builder()
        .with_tonic()
        .with_tls_config(tls_config())
        .build()?;

    Ok(SdkLoggerProvider::builder()
        .with_resource(resource.clone())
        .with_batch_exporter(exporter)
        .build())
}

pub fn init_tracing_subscriber() -> Result<OtelGuard, Error> {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        EnvFilter::new("info,opentelemetry_sdk=warn,h2=error,hyper=error,tonic=error")
    });

    let resource = resource(&Resource::builder().build());
    let tracer = exports(OTEL_EXPORTER_OTLP_TRACES_ENDPOINT, env_var)
        .then(|| tracer_provider(&resource))
        .transpose()?;
    let meter = exports(OTEL_EXPORTER_OTLP_METRICS_ENDPOINT, env_var)
        .then(|| meter_provider(&resource))
        .transpose()?;
    let logger = exports(OTEL_EXPORTER_OTLP_LOGS_ENDPOINT, env_var)
        .then(|| logger_provider(&resource))
        .transpose()?;

    if let Some(provider) = &tracer {
        global::set_tracer_provider(provider.clone());
    }
    if let Some(provider) = &meter {
        global::set_meter_provider(provider.clone());
    }

    let scope = InstrumentationScope::builder(env!("CARGO_PKG_NAME"))
        .with_version(VERSION)
        .build();

    tracing_subscriber::registry()
        .with(filter)
        .with(tracing_subscriber::fmt::layer())
        .with(meter.clone().map(MetricsLayer::new))
        .with(
            tracer
                .as_ref()
                .map(|provider| OpenTelemetryLayer::new(provider.tracer_with_scope(scope))),
        )
        .with(logger.as_ref().map(OpenTelemetryTracingBridge::new))
        .try_init()?;

    Ok(OtelGuard {
        tracer,
        meter,
        logger,
    })
}

pub struct OtelGuard {
    tracer: Option<SdkTracerProvider>,
    meter: Option<SdkMeterProvider>,
    logger: Option<SdkLoggerProvider>,
}

impl Drop for OtelGuard {
    fn drop(&mut self) {
        if let Some(provider) = self.tracer.take()
            && let Err(err) = provider.shutdown()
        {
            eprintln!("{err:?}");
        }
        if let Some(provider) = self.meter.take()
            && let Err(err) = provider.shutdown()
        {
            eprintln!("{err:?}");
        }
        if let Some(provider) = self.logger.take()
            && let Err(err) = provider.shutdown()
        {
            eprintln!("{err:?}");
        }
    }
}

#[cfg(test)]
mod tests {
    use opentelemetry::{Key, KeyValue, Value};
    use opentelemetry_otlp::{OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_EXPORTER_OTLP_TRACES_ENDPOINT};
    use opentelemetry_sdk::Resource;
    use opentelemetry_semantic_conventions::resource::{SERVICE_NAME, SERVICE_VERSION};

    use super::{VERSION, exports, resource};

    // Both helpers take their input as arguments, so the tests never touch
    // the process environment.
    fn env(vars: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let vars: Vec<(String, String)> = vars
            .iter()
            .map(|(name, value)| ((*name).to_owned(), (*value).to_owned()))
            .collect();
        move |name| {
            vars.iter()
                .find(|(var, _)| var == name)
                .map(|(_, value)| value.clone())
        }
    }

    #[test]
    fn exports_only_with_an_endpoint() {
        let traces = OTEL_EXPORTER_OTLP_TRACES_ENDPOINT;
        assert!(!exports(traces, env(&[])));
        assert!(!exports(traces, env(&[(OTEL_EXPORTER_OTLP_ENDPOINT, "")])));
        assert!(exports(
            traces,
            env(&[(OTEL_EXPORTER_OTLP_ENDPOINT, "http://collector:4317")])
        ));
        assert!(exports(traces, env(&[(traces, "http://collector:4317")])));
        assert!(!exports(
            traces,
            env(&[("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT", "http://collector:4317")])
        ));
    }

    fn attribute(resource: &Resource, key: &'static str) -> Option<Value> {
        resource.get(&Key::from_static_str(key))
    }

    #[test]
    fn names_the_service_after_the_crate_unless_configured() {
        let fallback = Resource::builder_empty()
            .with_service_name("unknown_service:teslamate-rust")
            .build();
        assert_eq!(
            attribute(&resource(&fallback), SERVICE_NAME),
            Some(Value::from("teslamate-rust"))
        );

        let configured = Resource::builder_empty()
            .with_service_name("garage")
            .build();
        assert_eq!(
            attribute(&resource(&configured), SERVICE_NAME),
            Some(Value::from("garage"))
        );
    }

    #[test]
    fn keeps_the_detected_attributes_and_adds_the_version() {
        let detected = Resource::builder_empty()
            .with_attribute(KeyValue::new("deployment.environment.name", "production"))
            .build();
        let resource = resource(&detected);
        assert_eq!(
            attribute(&resource, "deployment.environment.name"),
            Some(Value::from("production"))
        );
        assert_eq!(
            attribute(&resource, SERVICE_VERSION),
            Some(Value::from(VERSION))
        );
    }
}
