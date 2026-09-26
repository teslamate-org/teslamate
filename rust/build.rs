use std::{env, error::Error, fs, path::PathBuf};

#[path = "src/version_file.rs"]
mod version_file;

fn main() -> Result<(), Box<dyn Error>> {
    let path = PathBuf::from(env::var("CARGO_MANIFEST_DIR")?).join("../VERSION");
    println!("cargo::rerun-if-changed={}", path.display());
    let content = fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let version = version_file::parse(&content).map_err(|e| format!("{}: {e}", path.display()))?;
    println!("cargo::rustc-env=TESLAMATE_VERSION={version}");
    Ok(())
}
