/// Version from the repository's VERSION file, set by build.rs.
pub const VERSION: &str = env!("TESLAMATE_VERSION");

#[cfg(test)]
mod tests {
    use super::VERSION;

    #[test]
    fn version_is_the_version_file() {
        assert_eq!(VERSION, include_str!("../../VERSION").trim());
    }
}
