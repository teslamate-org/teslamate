use data_encoding::BASE64;
use opentelemetry::{InstrumentationScope, KeyValue, global, trace::TracerProvider};
use opentelemetry_appender_tracing::layer::OpenTelemetryTracingBridge;
use opentelemetry_otlp::{
    ExporterBuildError, LogExporter, MetricExporter, SpanExporter, WithExportConfig,
    WithTonicConfig,
};
use opentelemetry_sdk::{
    Resource,
    logs::SdkLoggerProvider,
    metrics::{PeriodicReader, SdkMeterProvider},
    trace::SdkTracerProvider,
};
use opentelemetry_semantic_conventions::resource::{DEPLOYMENT_ENVIRONMENT_NAME, SERVICE_VERSION};
use std::sync::OnceLock;
use tap::Pipe;
use thiserror::Error;
use tonic::metadata::{MetadataMap, errors::InvalidMetadataValue};
use tracing_opentelemetry::{MetricsLayer, OpenTelemetryLayer};
use tracing_subscriber::{EnvFilter, layer::SubscriberExt, util::SubscriberInitExt};

use crate::config::{Config, OtlpConfigError, OtlpSettings};
use crate::version::VERSION;

fn otlp_metadata(settings: &OtlpSettings) -> Result<MetadataMap, InvalidMetadataValue> {
    let mut map = MetadataMap::with_capacity(3);
    let authorization_value =
        BASE64.encode(format!("{}:{}", settings.username, settings.password).as_bytes());
    map.insert(
        "authorization",
        format!("Basic {authorization_value}").parse()?,
    );
    if let Some(ref org) = settings.organization {
        map.insert("organization", org.parse()?);
    }
    if let Some(ref stream) = settings.stream_name {
        map.insert("stream-name", stream.parse()?);
    }

    Ok(map)
}

fn resource(config: &Config) -> Resource {
    static RESOURCE: OnceLock<Resource> = OnceLock::new();
    RESOURCE
        .get_or_init(|| {
            Resource::builder()
                .with_service_name(env!("CARGO_PKG_NAME"))
                .with_attributes([
                    KeyValue::new(SERVICE_VERSION, VERSION),
                    KeyValue::new(
                        DEPLOYMENT_ENVIRONMENT_NAME,
                        config.deployment_environment.clone(),
                    ),
                ])
                .build()
        })
        .clone()
}

#[derive(Error, Debug)]
pub enum Error {
    #[error("Invalid metadata value: {0}")]
    InvalidMetadataValue(#[from] InvalidMetadataValue),

    #[error("Exporter build error: {0}")]
    Exporter(#[from] ExporterBuildError),

    #[error("TryInitError error: {0}")]
    TryInit(#[from] tracing_subscriber::util::TryInitError),

    #[error("OTLP config error: {0}")]
    Config(#[from] OtlpConfigError),
}

fn init_tracer_provider(
    resource: &Resource,
    settings: &OtlpSettings,
) -> Result<SdkTracerProvider, Error> {
    let exporter = SpanExporter::builder()
        .with_tonic()
        .with_tls_config(tonic::transport::ClientTlsConfig::new().with_enabled_roots())
        .with_endpoint(settings.endpoint.clone())
        .with_metadata(otlp_metadata(settings)?)
        .build()?;
    SdkTracerProvider::builder()
        .with_batch_exporter(exporter)
        .with_resource(resource.clone())
        .build()
        .pipe(Ok)
}

fn init_metrics(
    resource: &Resource,
    settings: &OtlpSettings,
) -> Result<opentelemetry_sdk::metrics::SdkMeterProvider, Error> {
    let exporter = MetricExporter::builder()
        .with_tonic()
        .with_tls_config(tonic::transport::ClientTlsConfig::new().with_enabled_roots())
        .with_endpoint(settings.endpoint.clone())
        .with_metadata(otlp_metadata(settings)?)
        .build()?;

    let reader = PeriodicReader::builder(exporter).build();

    SdkMeterProvider::builder()
        .with_reader(reader)
        .with_resource(resource.clone())
        .build()
        .pipe(Ok)
}

fn init_logs(resource: &Resource, settings: &OtlpSettings) -> Result<SdkLoggerProvider, Error> {
    let exporter = LogExporter::builder()
        .with_tonic()
        .with_tls_config(tonic::transport::ClientTlsConfig::new().with_enabled_roots())
        .with_endpoint(settings.endpoint.clone())
        .with_metadata(otlp_metadata(settings)?)
        .build()?;

    SdkLoggerProvider::builder()
        .with_resource(resource.clone())
        .with_batch_exporter(exporter)
        .build()
        .pipe(Ok)
}

pub fn init_tracing_subscriber(config: &Config) -> Result<OtelGuard, Error> {
    log::set_max_level(log::LevelFilter::Info);

    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        EnvFilter::new("info,opentelemetry_sdk=warn,h2=error,hyper=error,tonic=error,reqwest=error")
    });

    let layer = tracing_subscriber::registry()
        .with(filter)
        .with(tracing_subscriber::fmt::layer());

    match config.otlp.to_settings() {
        Ok(settings) => {
            let resource = resource(config);
            let meter_provider = init_metrics(&resource, &settings)?;
            let logger_provider = init_logs(&resource, &settings)?;
            let tracer_provider = init_tracer_provider(&resource, &settings)?;

            global::set_tracer_provider(tracer_provider.clone());
            global::set_meter_provider(meter_provider.clone());

            let scope = InstrumentationScope::builder(env!("CARGO_PKG_NAME"))
                .with_version(VERSION)
                .build();

            let tracer = tracer_provider.tracer_with_scope(scope);

            layer
                .with(MetricsLayer::new(meter_provider.clone()))
                .with(OpenTelemetryLayer::new(tracer))
                .with(OpenTelemetryTracingBridge::new(&logger_provider))
                .try_init()?;

            Ok(OtelGuard {
                tracer: Some(tracer_provider),
                meter: Some(meter_provider),
                logger: Some(logger_provider),
            })
        }
        Err(OtlpConfigError::NotConfigured) => {
            layer.init();

            Ok(OtelGuard {
                tracer: None,
                meter: None,
                logger: None,
            })
        }
        Err(err) => Err(err.into()),
    }
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
