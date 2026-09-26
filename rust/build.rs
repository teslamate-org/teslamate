use std::{env, error::Error, fs, path::PathBuf};

fn main() -> Result<(), Box<dyn Error>> {
    let path = PathBuf::from(env::var("CARGO_MANIFEST_DIR")?).join("../VERSION");
    println!("cargo::rerun-if-changed={}", path.display());
    let version = fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    println!("cargo::rustc-env=TESLAMATE_VERSION={}", version.trim());
    Ok(())
}
