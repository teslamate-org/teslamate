//! The crate's library: the modules the binary in `main.rs` runs and the
//! integration tests in `tests/` link against.

pub mod cli;
pub mod config;
pub mod database;
pub mod logging;
pub mod version;

// Compiled into build.rs; part of the crate only for its tests.
#[cfg(test)]
mod version_file;
