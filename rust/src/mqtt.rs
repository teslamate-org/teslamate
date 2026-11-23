//! Source (and sink) for MQTT data.

use rumqttc::Transport;
use rumqttc::tokio_rustls::rustls::{self, ClientConfig, RootCertStore};
use rumqttc::v5::mqttbytes::QoS;
use rumqttc::v5::mqttbytes::v5::{Packet, Publish};
use rumqttc::v5::{AsyncClient, Event, Incoming, MqttOptions};
use serde::Serialize;
use std::collections::VecDeque;
use std::convert::Infallible;
use std::fmt;
use std::str;
use std::str::Utf8Error;
use thiserror::Error;

use tokio::select;
use tokio::sync::mpsc;
use tokio::time::Duration;
use tracing::{debug, error, info};

use crate::config::Mqtt as Config;

// use robotica_common::mqtt::{topic_matches, Json, MqttMessage, MqttSerializer, QoS, Retain};

// use crate::pipes::{generic, stateful, stateless};
// use crate::spawn;

const NUMBER_OF_STARTUP_MESSAGES: usize = 100;
const NUMBER_OF_STARTUP_SUBSCRIPTIONS: usize = 100;
const OFFLINE_BUFFER_SIZE: usize = 1000;

/// The retain flag for a MQTT message.
#[derive(Debug, Clone, Copy)]
pub enum Retain {
    /// The message should be retained.
    Retain,

    /// The message should not be retained.
    NoRetain,
}

pub struct MqttMessage {
    /// MQTT topic to send the message to.
    pub topic: String,

    /// MQTT message to send.
    pub payload: Vec<u8>,

    /// Was/Is this message retained?
    pub retain: Retain,

    /// What is the `QoS` of this message?
    pub qos: QoS,
}

impl MqttMessage {
    /// Create a new message.
    #[must_use]
    pub fn new(
        topic: impl Into<String>,
        payload: impl Into<String>,
        retain: Retain,
        qos: QoS,
    ) -> Self {
        Self {
            topic: topic.into(),
            payload: payload.into().bytes().collect(),
            retain,
            qos,
        }
    }

    /// Create a new message from a Mqtt Serializer
    ///
    /// # Errors
    ///
    /// If the payload cannot be serialized.
    #[cfg(test)]
    pub fn from_serializer<T: MqttSerializer>(
        topic: impl Into<String>,
        payload: &T,
        retain: Retain,
        qos: QoS,
    ) -> Result<Self, T::Error> {
        payload.serialize(topic, retain, qos)
    }
}

// fn truncate(s: &str, max_chars: usize) -> &str {
//     match s.char_indices().nth(max_chars) {
//         None => s,
//         Some((idx, _)) => &s[..idx],
//     }
// }

impl std::fmt::Debug for MqttMessage {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let payload = String::from_utf8(self.payload.clone())
            .unwrap_or_else(|_| format!("{:?}", self.payload));
        // let payload = truncate(&payload, 40);

        f.debug_struct("MqttMessage")
            .field("topic", &self.topic)
            .field("payload", &payload)
            .field("retain", &self.retain)
            .field("qos", &self.qos)
            .finish()
    }
}

/// A JSON MQTT message.
#[allow(dead_code)]
pub struct Json<T>(pub T);

// impl<T> Json<T> {
//     /// Unwrap the inner value
//     pub fn into_inner(self) -> T {
//         self.0
//     }
// }

// impl<T: Clone> Clone for Json<T> {
//     fn clone(&self) -> Self {
//         Self(self.0.clone())
//     }
// }

// impl<T: std::fmt::Debug> std::fmt::Debug for Json<T> {
//     fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
//         self.0.fmt(f)
//     }
// }

// impl<T: std::fmt::Display> std::fmt::Display for Json<T> {
//     fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
//         self.0.fmt(f)
//     }
// }

// impl<T: PartialEq> PartialEq for Json<T> {
//     fn eq(&self, other: &Self) -> bool {
//         self.0.eq(&other.0)
//     }
// }

// impl<T> Deref for Json<T> {
//     type Target = T;

//     fn deref(&self) -> &Self::Target {
//         &self.0
//     }
// }

// impl<T: Eq> Eq for Json<T> {}

/// The error type for JSON conversion
#[derive(Error, Debug)]
#[allow(dead_code)]
pub enum JsonError {
    /// The payload was not a valid JSON string.
    #[error("Invalid JSON: {0}")]
    InvalidJson(#[from] serde_json::Error),

    /// The payload was not a valid UTF-8 string.
    #[error("Invalid UTF-8: {0}")]
    InvalidUtf8(#[from] Utf8Error),
}

/// Serialize an object to a MQTT message.
pub trait MqttSerializer {
    /// The error type for serialization.
    type Error: std::error::Error;

    /// Serialize an object to a MQTT message.
    ///
    /// # Errors
    ///
    /// If the object cannot be serialized.
    fn serialize(
        &self,
        topic: impl Into<String>,
        retain: Retain,
        qos: QoS,
    ) -> Result<MqttMessage, Self::Error>;
}

impl<T: Serialize> MqttSerializer for Json<T> {
    type Error = JsonError;

    fn serialize(
        &self,
        topic: impl Into<String>,
        retain: Retain,
        qos: QoS,
    ) -> Result<MqttMessage, Self::Error> {
        let payload = serde_json::to_string(&self.0)?;
        Ok(MqttMessage::new(topic, payload, retain, qos))
    }
}

impl MqttSerializer for String {
    type Error = Infallible;
    fn serialize(
        &self,
        topic: impl Into<Self>,
        retain: Retain,
        qos: QoS,
    ) -> Result<MqttMessage, Self::Error> {
        Ok(MqttMessage::new(topic, self, retain, qos))
    }
}

// const fn qos_to_rumqttc(qos: QoS) -> rumqttc::v5::mqttbytes::QoS {
//     match qos {
//         QoS::AtMostOnce => rumqttc::v5::mqttbytes::QoS::AtMostOnce,
//         QoS::AtLeastOnce => rumqttc::v5::mqttbytes::QoS::AtLeastOnce,
//         QoS::ExactlyOnce => rumqttc::v5::mqttbytes::QoS::ExactlyOnce,
//     }
// }

// const fn qos_from_rumqttc(qos: rumqttc::v5::mqttbytes::QoS) -> QoS {
//     match qos {
//         rumqttc::v5::mqttbytes::QoS::AtMostOnce => QoS::AtMostOnce,
//         rumqttc::v5::mqttbytes::QoS::AtLeastOnce => QoS::AtLeastOnce,
//         rumqttc::v5::mqttbytes::QoS::ExactlyOnce => QoS::ExactlyOnce,
//     }
// }

fn publish_to_mqtt_message(msg: &Publish) -> Result<MqttMessage, Utf8Error> {
    let topic = str::from_utf8(&msg.topic)?.to_string();
    let payload = msg.payload.to_vec();
    Ok(MqttMessage {
        topic,
        payload,
        retain: if msg.retain {
            Retain::Retain
        } else {
            Retain::NoRetain
        },
        qos: msg.qos,
    })
}

// /// An error occurred during a `Mqtt` subscribe operation.
// #[derive(Error, Debug)]
// pub enum SubscribeError {
//     /// Send error
//     #[error("Send error")]
//     SendError(),

//     /// Receive error
//     #[error("Receive error: {0}")]
//     ReceiveError(#[from] oneshot::error::RecvError),

//     /// Client error
//     #[error("Client error: {0}")]
//     ClientError(Box<ClientError>),
// }

// impl From<ClientError> for SubscribeError {
//     fn from(value: ClientError) -> Self {
//         Self::ClientError(Box::new(value))
//     }
// }

#[derive(Debug)]
enum MqttCommand {
    MqttOut(MqttMessage),
    // Subscribe(
    //     String,
    //     oneshot::Sender<Result<generic::Receiver<MqttMessage>, SubscribeError>>,
    // ),
    // Unsubscribe(String),
}

/// Struct used to send outgoing MQTT messages.
#[derive(Clone)]
pub struct MqttTx(mpsc::Sender<MqttCommand>);

impl MqttTx {
    /// Send a message to the MQTT broker.
    pub fn try_send(&self, msg: MqttMessage) {
        let _ = self
            .0
            .try_send(MqttCommand::MqttOut(msg))
            .map_err(|e| error!("MQTT send error: {}", e));
    }

    /// Serialize and send a message to the MQTT broker.
    pub fn try_serialize_send<T: MqttSerializer>(
        &self,
        topic: impl Into<String>,
        payload: &T,
        retain: Retain,
        qos: QoS,
    ) {
        let msg = payload.serialize(topic, retain, qos);

        match msg {
            Ok(msg) => self.try_send(msg),
            Err(err) => error!("Failed to serialize message: {:?}", err),
        }
    }

    // /// Serialize and send
    // ///
    // /// Subscribe to a topic and return a receiver for the messages.
    // /// The receiver will be closed when the MQTT connection is closed.
    // ///
    // /// # Errors
    // ///
    // /// Returns an error if the subscribe request could not be sent.
    // pub async fn subscribe(
    //     &self,
    //     topic: impl Into<String> + Send,
    // ) -> Result<generic::Receiver<MqttMessage>, SubscribeError> {
    //     let (tx, rx) = oneshot::channel();
    //     self.0
    //         .send(MqttCommand::Subscribe(topic.into(), tx))
    //         .await
    //         .map_err(|_| SubscribeError::SendError())?;
    //     rx.await?
    // }

    // /// Add new subscription and parse incoming data as type T
    // ///
    // /// # Errors
    // ///
    // /// Returns an error if the subscribe request could not be sent.
    // pub async fn subscribe_into_stateless<U>(
    //     &self,
    //     topic: impl Into<String> + Send,
    // ) -> Result<stateless::Receiver<U>, SubscribeError>
    // where
    //     // U: Data,
    //     // T::Sent: Send + 'static,
    //     U: TryFrom<MqttMessage> + Clone + Send + 'static,
    //     <U as TryFrom<MqttMessage>>::Error: Send + std::error::Error,
    //     // T::Received: Send + 'static,
    // {
    //     Ok(self
    //         .subscribe(topic)
    //         .await?
    //         .into_stateless()
    //         .translate::<U>())
    // }

    // /// Add new subscription and parse incoming data as type T
    // ///
    // /// # Errors
    // ///
    // /// Returns an error if the subscribe request could not be sent.
    // pub async fn subscribe_into_stateful<U>(
    //     &self,
    //     topic: impl Into<String> + Send,
    // ) -> Result<stateful::Receiver<U>, SubscribeError>
    // where
    //     // U: Data,
    //     // T::Sent: Send + 'static,
    //     U: TryFrom<MqttMessage> + Clone + Send + PartialEq + 'static,
    //     <U as TryFrom<MqttMessage>>::Error: Send + std::error::Error,
    //     // T::Received: Send + 'static,
    // {
    //     Ok(self
    //         .subscribe(topic)
    //         .await?
    //         .into_stateful()
    //         .translate::<U>())
    // }
}

// /// An error loading the Config.
// #[derive(Error, Debug)]
// pub enum MqttClientError {
//     /// Environment variable set but invalid.
//     #[error("Environment variable {0} invalid {1}")]
//     VarInvalid(String, String, ParseIntError),
// }

/// Client struct used to connect to MQTT.
pub struct MqttRx {
    // tx: mpsc::Sender<MqttCommand>,
    rx: mpsc::Receiver<MqttCommand>,
}

struct OfflineBuffer {
    messages: VecDeque<MqttMessage>,
}

impl OfflineBuffer {
    fn new() -> Self {
        Self {
            messages: VecDeque::with_capacity(OFFLINE_BUFFER_SIZE),
        }
    }

    fn push(&mut self, msg: MqttMessage) {
        if self.messages.len() >= OFFLINE_BUFFER_SIZE {
            self.messages.pop_front();
        }
        self.messages.push_back(msg);
    }

    fn drain(&mut self) -> impl Iterator<Item = MqttMessage> + '_ {
        self.messages.drain(..)
    }
}

impl Default for OfflineBuffer {
    fn default() -> Self {
        Self::new()
    }
}

/// Create a new MQTT client.
#[must_use]
pub fn mqtt_channel() -> (MqttTx, MqttRx) {
    // Outgoing MQTT queue.
    let (tx, rx) = mpsc::channel(NUMBER_OF_STARTUP_MESSAGES);
    (MqttTx(tx), MqttRx { rx })
}

// /// Credentials for MQTT
// #[derive(Deserialize, Default)]
// #[serde(tag = "type")]
// pub enum Credentials {
//     /// Username and password
//     UsernamePassword {
//         /// Username
//         username: String,

//         /// Password
//         password: String,
//     },

//     /// No credentials
//     #[default]
//     None,
// }

// /// MQTT configuration
// pub struct Config {
//     /// MQTT host
//     pub host: String,

//     /// MQTT port
//     pub port: u16,

//     /// MQTT username
//     pub credentials: Credentials,
// }

/// Connect to the MQTT broker and send/receive messages.
///
/// # Errors
///
/// Returns an error if there is a problem with the configuration.
#[allow(clippy::too_many_lines)]
pub fn run_client(
    // mut subscriptions: Subscriptions,
    channel: MqttRx,
    config: Config,
) {
    let hostname = gethostname::gethostname();
    let hostname = hostname.to_str().unwrap_or("unknown");
    let client_id = format!("teslamate-{hostname}");

    let root_store = get_root_store();
    let client_config = ClientConfig::builder()
        .with_root_certificates(root_store)
        .with_no_client_auth();

    let mut mqtt_options = MqttOptions::new(client_id, config.host, config.port);
    mqtt_options.set_keep_alive(Duration::from_secs(30));

    if config.tls {
        mqtt_options.set_transport(Transport::tls_with_config(client_config.into()));
    }

    if config.tls_accept_invalid_certs {
        // insert magic here.
    }

    if let (Some(username), Some(password)) = (config.username, config.password) {
        mqtt_options.set_credentials(username, password);
    }
    mqtt_options.set_max_packet_size(Some(100 * 10 * 1024));
    // mqtt_options.set_clean_session(false);

    let (client, mut event_loop) = AsyncClient::new(mqtt_options, NUMBER_OF_STARTUP_SUBSCRIPTIONS);

    // let trust_store = env::var("MQTT_CA_CERT_FILE").unwrap();

    // error!("Number of subscriptions: {}", subscriptions.0.len());

    // for subscription in &subscriptions.0 {
    //     watch_tx_closed(
    //         subscription.tx.clone(),
    //         channel.tx.clone(),
    //         subscription.topic.clone(),
    //     );
    // }

    tokio::spawn(async move {
        let mut rx = channel.rx;
        let mut offline_buffer = OfflineBuffer::new();
        let mut is_connected = false;
        let mut backoff_deadline: Option<tokio::time::Instant> = None;

        loop {
            let now = tokio::time::Instant::now();
            let can_poll = backoff_deadline.is_none_or(|d| now >= d);

            select! {
                event = event_loop.poll(), if can_poll => {
                    match event {
                        Ok(Event::Incoming(i)) => {
                            if matches!(i, Incoming::ConnAck(_)) {
                                info!("MQTT connected, flushing offline buffer");
                                is_connected = true;
                                backoff_deadline = None;
                                let mut failed = Vec::new();
                                for msg in offline_buffer.drain() {
                                    let retain = matches!(msg.retain, Retain::Retain);
                                    if let Err(err) = client.try_publish(
                                        msg.topic.clone(),
                                        msg.qos,
                                        retain,
                                        msg.payload.clone(),
                                    ) {
                                        error!("Failed to publish buffered message: {:?}.", err);
                                        failed.push(msg);
                                        break;
                                    }
                                }
                                for msg in failed {
                                    offline_buffer.push(msg);
                                }
                            }
                            incoming_event(/*&client,*/ i);
                        },
                        Ok(Event::Outgoing(_)) => {
                        },
                        Err(err) => {
                            error!("MQTT Error: {:?}", err);
                            is_connected = false;
                            backoff_deadline = Some(now + Duration::from_secs(10));
                        }
                    }
                },
                () = tokio::time::sleep_until(backoff_deadline.unwrap_or(now + Duration::from_secs(10))), if backoff_deadline.is_some() => {
                    backoff_deadline = None;
                },
                Some(msg) = rx.recv() => {
                    match msg {
                        MqttCommand::MqttOut(msg) => {
                            // let subscription_list = subscriptions.get_as_iter(&msg.topic);
                            // for subscription in subscription_list {
                            //     debug!("Looping message: {:?}", msg);
                            //     subscription.tx.try_send(msg.clone());
                            // }

                            let retain = matches!(msg.retain, Retain::Retain);

                            if is_connected {
                                if let Err(err) = client.try_publish(
                                    msg.topic.clone(),
                                    msg.qos,
                                    retain,
                                    msg.payload.clone(),
                                ) {
                                    error!("Failed to publish message: {:?}.", err);
                                    is_connected = false;
                                    offline_buffer.push(msg);
                                }
                            } else {
                                offline_buffer.push(msg);
                            }
                        },
                        // MqttCommand::Subscribe(topic, tx) => {
                        //     process_subscribe(&client, &mut subscriptions, &topic, tx, channel.tx.clone(), is_connected);
                        // }
                        // MqttCommand::Unsubscribe(topic) => {
                        //     debug!("Unsubscribing from topic: {}.", topic);
                        //     if subscriptions.unsubscribe(&topic).is_ok() && is_connected {
                        //         if let Err(err) = client.try_unsubscribe(&topic) {
                        //             error!("Failed to unsubscribe from topic: {:?}.", err);
                        //         }
                        //     }
                        // }
                    }
                }
                else => { break; }
            };
        }
    });
}

fn get_root_store() -> RootCertStore {
    let mut root_store = rustls::RootCertStore::empty();

    let result = rustls_native_certs::load_native_certs();
    if !result.errors.is_empty() {
        error!("Failed to load native certs: {:?}", result.errors);
        return root_store;
    }

    // Add all certificates to the root store.
    for cert in result.certs {
        _ = root_store.add(cert).map_err(|err| {
            error!("Failed to add certificate: {:?}", err);
        });
    }

    root_store
}

// #[allow(clippy::cognitive_complexity)]
// fn process_subscribe(
//     client: &AsyncClient,
//     subscriptions: &mut Subscriptions,
//     topic: impl Into<String>,
//     tx: oneshot::Sender<Result<generic::Receiver<MqttMessage>, SubscribeError>>,
//     channel_tx: mpsc::Sender<MqttCommand>,
//     is_connected: bool,
// ) {
//     let topic: String = topic.into();

//     debug!("Subscribing to topic: {}.", topic);
//     let subscription = subscriptions.0.iter().find(|s| s.topic == topic);
//     let maybe_rx = subscription.and_then(|s| s.rx.upgrade());

//     let response = if let Some(rx) = maybe_rx {
//         Ok(rx)
//     } else {
//         let (tx, rx) = generic::create_pipe(&topic);

//         let subscription = Subscription {
//             topic: topic.clone(),
//             tx: tx.clone(),
//             rx: rx.downgrade(),
//         };

//         if is_connected {
//             let filter = topic_to_filter(&topic);
//             match client.try_subscribe_many([filter]) {
//                 Ok(()) => {
//                     debug!("Subscribed to topic: {:?}.", topic);
//                     subscriptions.0.push(subscription);
//                     watch_tx_closed(tx, channel_tx, topic);
//                     Ok(rx)
//                 }
//                 Err(err) => {
//                     error!("Failed to subscribe to topics: {:?}.", err);
//                     Err(err.into())
//                 }
//             }
//         } else {
//             debug!(
//                 "Skipping broker subscribe for topic: {:?} (offline).",
//                 topic
//             );
//             subscriptions.0.push(subscription);
//             watch_tx_closed(tx, channel_tx, topic);
//             Ok(rx)
//         }
//     };

//     if let Err(err) = tx.send(response) {
//         error!("Failed to send subscribe response: {:?}.", err);
//     }
// }

// fn watch_tx_closed(
//     tx: generic::Sender<MqttMessage>,
//     channel_tx: mpsc::Sender<MqttCommand>,
//     topic: String,
// ) {
//     spawn(async move {
//         tx.closed().await;
//         debug!("Entity for subscription closed: {:?}.", topic);
//         channel_tx
//             .send(MqttCommand::Unsubscribe(topic))
//             .await
//             .unwrap_or_else(|err| {
//                 error!("Failed to send unsubscribe command: {:?}.", err);
//             });
//     });
// }

fn incoming_event(/* client: &AsyncClient,*/ pkt: Packet, /*, subscriptions: &Subscriptions */) {
    match pkt {
        Incoming::Publish(p) => match publish_to_mqtt_message(&p) {
            Ok(msg) => {
                let msg: MqttMessage = msg;
                let topic = &msg.topic;
                debug!("Received message: {topic} {msg:?}.");
                // let subscription_list = subscriptions.get_as_iter(topic);
                // for subscription in subscription_list {
                //     subscription.tx.try_send(msg.clone());
                // }
            }
            Err(err) => error!("Invalid message received: {err}"),
        },
        Incoming::ConnAck(_) => {
            debug!("MQTT connected");
            //     debug!("Resubscribe topics.");
            //     subscribe_topics(client, subscriptions);
        }
        _ => {}
    }
}

// struct Subscription {
//     #[allow(dead_code)]
//     topic: String,
//     tx: generic::Sender<MqttMessage>,
//     rx: generic::WeakReceiver<MqttMessage>,
// }

// /// List of all required subscriptions.
// pub struct Subscriptions(Vec<Subscription>);

// impl Subscriptions {
//     /// Create a new set of subscriptions.
//     #[must_use]
//     pub const fn new() -> Self {
//         Subscriptions(Vec::new())
//     }

//     fn get_as_iter<'a>(&'a self, topic: &'a str) -> impl Iterator<Item = &'a Subscription> + 'a {
//         self.0.iter().filter(|s| topic_matches(topic, &s.topic))
//     }

//     /// Add a new subscription.
//     pub fn subscribe(&mut self, topic: impl Into<String>) -> generic::Receiver<MqttMessage> {
//         // Per subscription incoming MQTT queue.
//         let topic = topic.into();
//         let subscription = self.0.iter().find(|s| s.topic == topic);
//         let maybe_rx = subscription.and_then(|s| s.rx.upgrade());

//         if let Some(rx) = maybe_rx {
//             rx
//         } else {
//             let (tx, rx) = generic::create_pipe(topic.clone());

//             let subscription = Subscription {
//                 topic: topic.clone(),
//                 tx,
//                 rx: rx.downgrade(),
//             };

//             self.0.push(subscription);
//             rx
//         }
//     }

//     /// Add new subscription and parse incoming data as type T
//     pub fn subscribe_into_stateless<T>(
//         &mut self,
//         topic: impl Into<String>,
//     ) -> stateless::Receiver<T>
//     where
//         T: TryFrom<MqttMessage> + Clone + Send + 'static,
//         <T as TryFrom<MqttMessage>>::Error: Send + std::error::Error,
//     {
//         self.subscribe(topic).into_stateless().translate()
//     }

//     /// Add new subscription and parse incoming data as type T
//     pub fn subscribe_into_stateful<T>(&mut self, topic: impl Into<String>) -> stateful::Receiver<T>
//     where
//         T: TryFrom<MqttMessage> + Clone + PartialEq + Send + 'static,
//         <T as TryFrom<MqttMessage>>::Error: Send + std::error::Error,
//     {
//         self.subscribe(topic).into_stateful().translate()
//     }

//     /// Remove a subscription using exact match from the list.
//     fn unsubscribe(&mut self, topic: &str) -> Result<(), ()> {
//         let old_len = self.0.len();
//         self.0.retain(|s| s.topic != topic);
//         if self.0.len() == old_len {
//             Err(())
//         } else {
//             Ok(())
//         }
//     }
// }

// impl Default for Subscriptions {
//     fn default() -> Self {
//         Self::new()
//     }
// }

// fn topic_to_filter(topic: &str) -> Filter {
//     Filter {
//         path: topic.to_string(),
//         qos: rumqttc::v5::mqttbytes::QoS::ExactlyOnce,
//         nolocal: true,
//         // retain_forward_rule: rumqttc::RetainForwardRule::Forward,
//         ..Default::default()
//     }
// }

// fn subscribe_topics(client: &AsyncClient, subscriptions: &Subscriptions) {
//     if subscriptions.0.is_empty() {
//         return;
//     }

//     let topics = subscriptions.0.iter().map(|s| topic_to_filter(&s.topic));
//     if let Err(e) = client.try_subscribe_many(topics) {
//         error!("Error subscribing to topics: {:?}", e);
//     }
// }

// /// Options for sending a message.
// pub struct SendOptions {
//     qos: Option<QoS>,
//     retain: Option<Retain>,
// }

// impl Default for SendOptions {
//     fn default() -> Self {
//         Self::new()
//     }
// }

// impl SendOptions {
//     /// Create a new set of send options.
//     #[must_use]
//     pub const fn new() -> Self {
//         Self {
//             qos: None,
//             retain: None,
//         }
//     }

//     /// Set the `QoS` level.
//     #[must_use]
//     pub const fn qos(mut self, qos: QoS) -> Self {
//         self.qos = Some(qos);
//         self
//     }

//     /// Set the `Retain` flag.
//     #[must_use]
//     pub const fn retain(mut self, retain: Retain) -> Self {
//         self.retain = Some(retain);
//         self
//     }
// }

// impl<T: MqttSerializer + 'static + Send + Clone> stateful::Receiver<T> {
//     /// Serialize and send incoming data to MQTT.
//     pub fn send_to_mqtt(self, mqtt: &MqttTx, topic: impl Into<String>, options: &SendOptions) {
//         let qos = options.qos.unwrap_or(QoS::AtLeastOnce);
//         let retain = options.retain.unwrap_or(Retain::Retain);
//         let mqtt = mqtt.clone();
//         let topic = topic.into();
//         self.for_each(move |(_, data)| {
//             mqtt.try_serialize_send(&topic, &data, retain, qos);
//         });
//     }
// }

// impl<T: serde::Serialize + 'static + Send + Clone> stateful::Receiver<T> {
//     /// Serialize and send incoming data to MQTT.
//     pub fn send_to_mqtt_json(self, mqtt: &MqttTx, topic: impl Into<String>, options: &SendOptions) {
//         let qos = options.qos.unwrap_or(QoS::AtLeastOnce);
//         let retain = options.retain.unwrap_or(Retain::Retain);
//         let mqtt = mqtt.clone();
//         let topic = topic.into();
//         self.for_each(move |(_, data)| {
//             mqtt.try_serialize_send(&topic, &Json(data), retain, qos);
//         });
//     }
// }

// impl<T: Into<String> + 'static + Send + Clone> stateful::Receiver<T> {
//     /// Serialize and send incoming data to MQTT.
//     pub fn send_to_mqtt_string(
//         self,
//         mqtt: &MqttTx,
//         topic: impl Into<String>,
//         options: &SendOptions,
//     ) {
//         let qos = options.qos.unwrap_or(QoS::AtLeastOnce);
//         let retain = options.retain.unwrap_or(Retain::Retain);
//         let mqtt = mqtt.clone();
//         let topic = topic.into();
//         self.for_each(move |(_, data)| {
//             mqtt.try_serialize_send(&topic, &data.into(), retain, qos);
//         });
//     }
// }

// impl<T: MqttSerializer + 'static + Send + Clone> stateless::Receiver<T> {
//     /// Serialize and send incoming data to MQTT.
//     pub fn send_to_mqtt(self, mqtt: &MqttTx, topic: impl Into<String>, options: &SendOptions) {
//         let qos = options.qos.unwrap_or(QoS::ExactlyOnce);
//         let retain = options.retain.unwrap_or(Retain::NoRetain);
//         let mqtt = mqtt.clone();
//         let topic = topic.into();
//         self.for_each(move |data| {
//             mqtt.try_serialize_send(&topic, &data, retain, qos);
//         });
//     }
// }

// impl<T: serde::Serialize + 'static + Send + Clone> stateless::Receiver<T> {
//     /// Serialize and send incoming data to MQTT.
//     pub fn send_to_mqtt_json(self, mqtt: &MqttTx, topic: impl Into<String>, options: &SendOptions) {
//         let qos = options.qos.unwrap_or(QoS::ExactlyOnce);
//         let retain = options.retain.unwrap_or(Retain::NoRetain);
//         let mqtt = mqtt.clone();
//         let topic = topic.into();
//         self.for_each(move |data| {
//             mqtt.try_serialize_send(&topic, &Json(data), retain, qos);
//         });
//     }
// }

// impl<T: Into<String> + 'static + Send + Clone> stateless::Receiver<T> {
//     /// Serialize and send incoming data to MQTT.
//     pub fn send_to_mqtt_string(
//         self,
//         mqtt: &MqttTx,
//         topic: impl Into<String>,
//         options: &SendOptions,
//     ) {
//         let qos = options.qos.unwrap_or(QoS::ExactlyOnce);
//         let retain = options.retain.unwrap_or(Retain::NoRetain);
//         let mqtt = mqtt.clone();
//         let topic = topic.into();
//         self.for_each(move |data| {
//             mqtt.try_serialize_send(&topic, &data.into(), retain, qos);
//         });
//     }
// }
//
#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use serde_json::json;

    use super::*;

    // #[test]
    // fn test_message_to_string() {
    //     let msg = MqttMessage {
    //         topic: "test".to_string(),
    //         payload: "test".into(),
    //         qos: QoS::AtLeastOnce,
    //         retain: Retain::NoRetain,
    //     };

    //     let data: String = msg.try_into().unwrap();
    //     assert_eq!(data, "test");
    // }

    #[test]
    fn test_string_to_message() {
        let msg = MqttMessage::from_serializer(
            "test",
            &"test".to_string(),
            Retain::NoRetain,
            QoS::AtLeastOnce,
        )
        .unwrap();
        assert_eq!(msg.topic, "test");
        assert_eq!(msg.payload, b"test");
        assert_eq!(msg.qos, QoS::AtLeastOnce);
        assert!(matches!(msg.retain, Retain::NoRetain));
    }

    #[test]
    fn test_json_to_message() {
        let msg = MqttMessage::from_serializer(
            "test",
            &Json(json!({
                "code": 200,
                "success": true,
                "payload": {
                    "features": [
                        "serde",
                        "json"
                    ],
                    "homepage": null
                }
            })),
            Retain::NoRetain,
            QoS::AtLeastOnce,
        )
        .unwrap();
        println!("{msg:?}");
        assert_eq!(msg.topic, "test");
        assert_eq!(msg.payload, b"{\"code\":200,\"payload\":{\"features\":[\"serde\",\"json\"],\"homepage\":null},\"success\":true}");
        assert_eq!(msg.qos, QoS::AtLeastOnce);
        assert!(matches!(msg.retain, Retain::NoRetain));
    }
    // #[test]
    // fn test_message_to_bool() {
    //     let msg = MqttMessage {
    //         topic: "test".to_string(),
    //         payload: "true".into(),
    //         qos: QoS::AtLeastOnce,
    //         retain: Retain::NoRetain,
    //     };

    //     let data: bool = msg.try_into().unwrap();
    //     assert!(data);
    // }

    // #[test]
    // fn test_deserialize_username_password_config() {
    //     let config = r#"
    //         host: "test"
    //         port: 1234
    //         credentials:
    //             type: "UsernamePassword"
    //             username: "test"
    //             password: "test"
    //     "#;

    //     let config = serde_yaml_ng::from_str::<Config>(config).unwrap();
    //     assert_eq!(config.host, "test");
    //     assert_eq!(config.port, 1234);
    //     if let Credentials::UsernamePassword { username, password } = config.credentials {
    //         assert_eq!(username, "test");
    //         assert_eq!(password, "test");
    //     } else {
    //         panic!("Invalid credentials");
    //     }
    // }

    // #[test]
    // fn test_deserialize_anonymous_config() {
    //     let config = r#"
    //         host: "test"
    //         port: 1234
    //     "#;

    //     let config = serde_yaml_ng::from_str::<Config>(config).unwrap();
    //     assert_eq!(config.host, "test");
    //     assert_eq!(config.port, 1234);
    //     assert!(matches!(config.credentials, Credentials::None));
    // }
}
