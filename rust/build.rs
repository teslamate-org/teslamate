use std::{env, fs, path::Path};

fn main() {
    let version_file = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("VERSION");

    let version_from_file = fs::read_to_string(&version_file)
        .unwrap_or_else(|e| panic!("Failed to read {}: {}", version_file.display(), e));

    let version_from_file = version_from_file.trim();
    let version_from_cargo = env!("CARGO_PKG_VERSION");

    if version_from_file != version_from_cargo {
        eprintln!(
            "Version mismatch! VERSION file has '{}' but Cargo.toml has '{}'",
            version_from_file, version_from_cargo
        );
        std::process::exit(1);
    }

    let out_dir = env::var("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("version.rs");

    fs::write(
        &dest_path,
        format!("pub const VERSION: &str = \"{}\";\n", version_from_file),
    )
    .unwrap();

    println!("cargo:rerun-if-changed={}", version_file.display());
}
