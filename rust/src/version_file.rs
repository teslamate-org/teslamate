/// The version held by the VERSION file. Surrounding whitespace, such as a
/// final newline or CRLF, is ignored. Anything but one version made of semver
/// characters is an error, so a malformed file fails the build instead of
/// producing a wrong version.
pub fn parse(content: &str) -> Result<&str, String> {
    let version = content.trim();
    let valid = !version.is_empty()
        && version
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '+'));
    if valid {
        Ok(version)
    } else {
        Err(format!(
            "expected one version such as 4.3.0, found {content:?}"
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::parse;

    #[test]
    fn ignores_surrounding_whitespace() {
        for content in ["4.3.0", "4.3.0\n", "4.3.0\r\n", "\n4.3.0", " 4.3.0 \n\n"] {
            assert_eq!(parse(content), Ok("4.3.0"), "{content:?}");
        }
        assert_eq!(parse("4.3.0-dev\n"), Ok("4.3.0-dev"));
    }

    #[test]
    fn rejects_anything_but_one_version() {
        for content in ["", " \n", "4.3.0\n4.4.0", "4.3 .0", "\u{feff}4.3.0"] {
            assert!(parse(content).is_err(), "{content:?}");
        }
    }
}
