//! The versioned documentation site: each version of the book lives in its
//! own folder (`<site>/0.1.0/`, `<site>/dev/`), and nothing ever removes one,
//! so the docs of every release stay available. `versions.json` lists the
//! folders, newest first, for the version picker on every page; `index.html`
//! sends visitors to the newest release.

use std::cmp::Ordering;
use std::path::Path;

/// The version name of unreleased docs built from `main`.
pub const DEV: &str = "dev";

/// A semantic version: `MAJOR.MINOR.PATCH` with an optional `-prerelease`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Version {
    pub major: u64,
    pub minor: u64,
    pub patch: u64,
    pub prerelease: Option<String>,
}

impl Version {
    /// Parse `1.2.3` or `1.2.3-beta.1` (a leading `v` is accepted, as in a
    /// `v1.2.3` tag).
    pub fn parse(text: &str) -> Result<Version, String> {
        let text = text.strip_prefix('v').unwrap_or(text);
        let bad = || format!("'{}' is not a semantic version (MAJOR.MINOR.PATCH[-PRERELEASE])", text);
        let (core, prerelease) = match text.split_once('-') {
            Some((core, pre)) if !pre.is_empty() => (core, Some(pre.to_string())),
            Some(_) => return Err(bad()),
            None => (text, None),
        };
        let parts: Vec<&str> = core.split('.').collect();
        if parts.len() != 3 {
            return Err(bad());
        }
        let number = |s: &str| -> Result<u64, String> {
            if s.is_empty() || (s.len() > 1 && s.starts_with('0')) || !s.bytes().all(|b| b.is_ascii_digit()) {
                return Err(bad());
            }
            s.parse().map_err(|_| bad())
        };
        Ok(Version { major: number(parts[0])?, minor: number(parts[1])?, patch: number(parts[2])?, prerelease })
    }
}

impl std::fmt::Display for Version {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)?;
        if let Some(pre) = &self.prerelease {
            write!(f, "-{}", pre)?;
        }
        Ok(())
    }
}

impl Ord for Version {
    fn cmp(&self, other: &Self) -> Ordering {
        (self.major, self.minor, self.patch)
            .cmp(&(other.major, other.minor, other.patch))
            // A prerelease sorts before its release.
            .then_with(|| match (&self.prerelease, &other.prerelease) {
                (None, None) => Ordering::Equal,
                (None, Some(_)) => Ordering::Greater,
                (Some(_), None) => Ordering::Less,
                (Some(a), Some(b)) => a.cmp(b),
            })
    }
}

impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// The version folders in `site`, newest release first, `dev` last.
pub fn versions_in(site: &Path) -> Vec<String> {
    let mut releases: Vec<Version> = vec![];
    let mut dev = false;
    if let Ok(entries) = std::fs::read_dir(site) {
        for entry in entries.flatten() {
            if !entry.path().join("index.html").is_file() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            if name == DEV {
                dev = true;
            } else if let Ok(v) = Version::parse(&name) {
                if v.to_string() == name {
                    releases.push(v);
                }
            }
        }
    }
    releases.sort_by(|a, b| b.cmp(a));
    let mut out: Vec<String> = releases.iter().map(|v| v.to_string()).collect();
    if dev {
        out.push(DEV.to_string());
    }
    out
}

/// The version `index.html` opens: the newest release that is not a
/// prerelease, else the newest release, else `dev`.
pub fn default_version(versions: &[String]) -> Option<&String> {
    versions
        .iter()
        .find(|v| Version::parse(v).is_ok_and(|v| v.prerelease.is_none()))
        .or_else(|| versions.iter().find(|v| v.as_str() != DEV))
        .or_else(|| versions.first())
}

/// Rewrite `versions.json` and `index.html` in `site` from its folders.
pub fn write_index(site: &Path) -> Result<(), String> {
    let versions = versions_in(site);
    let latest = default_version(&versions).cloned();
    let json = serde_json::json!({ "versions": versions, "latest": latest });
    let write = |name: &str, text: String| {
        std::fs::write(site.join(name), text).map_err(|e| format!("cannot write {}: {}", site.join(name).display(), e))
    };
    write("versions.json", format!("{}\n", serde_json::to_string_pretty(&json).unwrap()))?;
    let target = latest.unwrap_or_else(|| DEV.to_string());
    write(
        "index.html",
        format!(
            "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>Pepper documentation</title>\n\
             <meta http-equiv=\"refresh\" content=\"0; url={0}/\">\n<link rel=\"canonical\" href=\"{0}/\">\n</head>\n\
             <body><p><a href=\"{0}/\">Pepper documentation {0}</a></p></body>\n</html>\n",
            target
        ),
    )?;
    // GitHub Pages would otherwise run Jekyll, which drops mdBook's
    // underscore-prefixed files.
    write(".nojekyll", String::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_and_orders_versions() {
        assert_eq!(Version::parse("v1.2.3").unwrap().to_string(), "1.2.3");
        assert_eq!(Version::parse("0.1.0-beta.1").unwrap().prerelease.as_deref(), Some("beta.1"));
        for bad in ["1.2", "1.2.x", "01.2.3", "1.2.3-", "dev"] {
            assert!(Version::parse(bad).is_err(), "{}", bad);
        }
        let mut v: Vec<Version> = ["0.10.0", "0.2.0", "1.0.0-rc.1", "1.0.0"].iter().map(|s| Version::parse(s).unwrap()).collect();
        v.sort();
        let names: Vec<String> = v.iter().map(|v| v.to_string()).collect();
        assert_eq!(names, ["0.2.0", "0.10.0", "1.0.0-rc.1", "1.0.0"]);
    }

    #[test]
    fn index_keeps_every_version_and_opens_the_newest_release() {
        let site = std::env::temp_dir().join(format!("pepper_docgen_site_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&site);
        for v in ["0.1.0", "0.2.0", "0.3.0-beta.1", "dev", "not-a-version"] {
            std::fs::create_dir_all(site.join(v)).unwrap();
            std::fs::write(site.join(v).join("index.html"), "").unwrap();
        }
        write_index(&site).unwrap();
        let json: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(site.join("versions.json")).unwrap()).unwrap();
        assert_eq!(json["versions"], serde_json::json!(["0.3.0-beta.1", "0.2.0", "0.1.0", "dev"]));
        assert_eq!(json["latest"], "0.2.0");
        assert!(std::fs::read_to_string(site.join("index.html")).unwrap().contains("url=0.2.0/"));
    }
}
