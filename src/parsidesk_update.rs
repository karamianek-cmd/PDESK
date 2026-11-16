// Staff auto-update via desk.parsipol.com ("parsidesk-*" keys); GitHub update flow untouched.

use crate::{
    common::PARSIDESK_VERSION,
    hbbs_http::{
        create_http_client_with_url_strict,
        downloader::{self, DownloadOptions},
    },
    updater::{current_update_arch, current_update_platform},
};
use hbb_common::{anyhow::anyhow, bail, ResultType};
use serde_derive::Deserialize;
use std::{
    collections::HashMap,
    io::Read,
    path::{Component, Path, PathBuf},
    sync::Mutex,
    time::Duration,
};

const MANIFEST_URL: &str = "https://desk.parsipol.com/update/staff.json";
const UPDATE_HOST: &str = "desk.parsipol.com";
const MANIFEST_MAX_BYTES: u64 = 256 * 1024;
const MANIFEST_TIMEOUT: Duration = Duration::from_secs(30);
const ALLOWED_PATH_PREFIXES: &[&str] = &["/members/files/", "/update/"];

lazy_static::lazy_static! {
    static ref AVAILABLE: Mutex<Option<AvailableUpdate>> = Mutex::new(None);
}

#[derive(Deserialize)]
struct StaffManifest {
    version: String,
    #[serde(default)]
    notes: String,
    artifacts: Vec<StaffArtifact>,
}

#[derive(Deserialize, Clone)]
struct StaffArtifact {
    platform: String,
    arch: String,
    format: String,
    url: String,
    file_name: String,
    size: u64,
    sha256: String,
}

#[derive(Clone)]
struct AvailableUpdate {
    version: String,
    notes: String,
    artifact: StaffArtifact,
}

fn update_format() -> &'static str {
    #[cfg(target_os = "windows")]
    {
        "exe"
    }
    #[cfg(target_os = "macos")]
    {
        "dmg"
    }
    #[cfg(target_os = "android")]
    {
        "apk"
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "android")))]
    {
        "unknown"
    }
}

fn normalize_version(raw: &str) -> ResultType<String> {
    let version = raw.trim().trim_start_matches('v').to_owned();
    if version.split('.').count() != 3
        || !version.chars().all(|c| c.is_ascii_digit() || c == '.')
    {
        bail!("Unexpected update version format: {}", raw);
    }
    Ok(version)
}

fn fetch_manifest() -> ResultType<StaffManifest> {
    let client = create_http_client_with_url_strict(MANIFEST_URL)?;
    let response = client
        .get(MANIFEST_URL)
        .timeout(MANIFEST_TIMEOUT)
        .send()?;
    if !response.status().is_success() {
        bail!("Update manifest request failed: {}", response.status());
    }
    let mut bytes = Vec::new();
    response
        .take(MANIFEST_MAX_BYTES.saturating_add(1))
        .read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MANIFEST_MAX_BYTES {
        bail!("Update manifest exceeds maximum allowed size");
    }
    Ok(serde_json::from_slice(&bytes)?)
}

fn select_artifact<'a>(
    manifest: &'a StaffManifest,
    platform: &str,
    arch: &str,
    format: &str,
) -> ResultType<&'a StaffArtifact> {
    let matches: Vec<&StaffArtifact> = manifest
        .artifacts
        .iter()
        .filter(|a| a.platform == platform && a.format == format)
        .collect();
    if matches.is_empty() {
        bail!("No matching update artifact for {platform}/{arch}/{format}");
    }
    if let Some(artifact) = matches.iter().copied().find(|a| a.arch == arch) {
        return Ok(artifact);
    }
    if let Some(artifact) = matches.iter().copied().find(|a| a.arch == "universal") {
        return Ok(artifact);
    }
    if matches.len() == 1 {
        return Ok(matches[0]);
    }
    bail!("Multiple matching update artifacts for {platform}/{format}");
}

fn is_plain_update_filename(filename: &str) -> bool {
    if filename.is_empty()
        || filename.contains('/')
        || filename.contains('\\')
        || filename.contains(':')
    {
        return false;
    }
    let mut components = Path::new(filename).components();
    matches!(
        components.next(),
        Some(Component::Normal(name)) if name.to_str() == Some(filename)
    ) && components.next().is_none()
}

fn validate_artifact_url(url: &str) -> ResultType<()> {
    let parsed = url::Url::parse(url).map_err(|_| anyhow!("Invalid update artifact URL"))?;
    if parsed.scheme() != "https"
        || parsed.host_str() != Some(UPDATE_HOST)
        || !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.port().is_some()
        || parsed.query().is_some()
        || parsed.fragment().is_some()
    {
        bail!("Update artifact URL is not a trusted {UPDATE_HOST} HTTPS URL: {url}");
    }
    let path = parsed.path();
    if !ALLOWED_PATH_PREFIXES
        .iter()
        .any(|prefix| path.starts_with(prefix))
    {
        bail!("Update artifact URL path is not allowed: {url}");
    }
    let filename = path
        .rsplit('/')
        .next()
        .ok_or_else(|| anyhow!("Update artifact URL has no file name"))?;
    if !is_plain_update_filename(filename) {
        bail!("Update artifact URL has an invalid file name: {url}");
    }
    Ok(())
}

fn download_path(file_name: &str) -> Option<PathBuf> {
    if !is_plain_update_filename(file_name) {
        return None;
    }
    Some(std::env::temp_dir().join(file_name))
}

fn check_available() -> ResultType<Option<AvailableUpdate>> {
    let manifest = fetch_manifest()?;
    let version = normalize_version(&manifest.version)?;
    if hbb_common::get_version_number(&version)
        <= hbb_common::get_version_number(PARSIDESK_VERSION)
    {
        *AVAILABLE.lock().unwrap() = None;
        return Ok(None);
    }
    let artifact = select_artifact(
        &manifest,
        current_update_platform(),
        current_update_arch(),
        update_format(),
    )?
    .clone();
    validate_artifact_url(&artifact.url)?;
    if !is_plain_update_filename(&artifact.file_name) {
        bail!("Update artifact has an invalid file name: {}", artifact.file_name);
    }
    let update = AvailableUpdate {
        version,
        notes: manifest.notes.clone(),
        artifact,
    };
    *AVAILABLE.lock().unwrap() = Some(update.clone());
    Ok(Some(update))
}

fn cached_artifact_for_url(url: &str) -> ResultType<StaffArtifact> {
    AVAILABLE
        .lock()
        .unwrap()
        .as_ref()
        .filter(|update| update.artifact.url == url)
        .map(|update| update.artifact.clone())
        .ok_or_else(|| anyhow!("Update artifact was not verified"))
}

pub(crate) fn available_update_json() -> String {
    match check_available() {
        Ok(Some(update)) => {
            let mut m = HashMap::new();
            m.insert("version", update.version);
            m.insert("notes", update.notes);
            m.insert("url", update.artifact.url);
            m.insert("file_name", update.artifact.file_name);
            m.insert("size", update.artifact.size.to_string());
            m.insert("sha256", update.artifact.sha256);
            serde_json::to_string(&m).unwrap_or_default()
        }
        Ok(None) => String::new(),
        Err(e) => format!("error:{e}"),
    }
}

pub(crate) fn verified_download_url() -> String {
    match check_available() {
        Ok(Some(update)) => update.artifact.url,
        Ok(None) => "error:no-update".to_owned(),
        Err(e) => format!("error:{e}"),
    }
}

pub(crate) fn start_download(url: &str) -> ResultType<String> {
    let artifact = cached_artifact_for_url(url)?;
    let path = download_path(&artifact.file_name)
        .ok_or_else(|| anyhow!("Invalid update file name: {}", artifact.file_name))?;
    let options = DownloadOptions {
        expected_size: artifact.size,
        artifact_sha256: artifact.sha256,
    };
    downloader::download_file(artifact.url, Some(path), options)
}

pub(crate) fn install_downloaded(url: &str) -> ResultType<()> {
    let artifact = cached_artifact_for_url(url)?;
    let path = download_path(&artifact.file_name)
        .ok_or_else(|| anyhow!("Invalid update file name: {}", artifact.file_name))?;
    #[cfg(target_os = "windows")]
    {
        let path_str = path
            .to_str()
            .ok_or_else(|| anyhow!("Invalid UTF-8 update file path"))?;
        crate::platform::update_to_verified(path_str, &artifact.sha256, artifact.size)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (path, artifact);
        bail!("In-app update installation is only supported on Windows")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest(artifacts: Vec<StaffArtifact>) -> StaffManifest {
        StaffManifest {
            version: "9.9.9".to_owned(),
            notes: String::new(),
            artifacts,
        }
    }

    fn artifact(platform: &str, arch: &str, format: &str) -> StaffArtifact {
        StaffArtifact {
            platform: platform.to_owned(),
            arch: arch.to_owned(),
            format: format.to_owned(),
            url: format!(
                "https://desk.parsipol.com/members/files/9.9.9/ParsiDesk-{platform}-{arch}.{format}"
            ),
            file_name: format!("ParsiDesk-{platform}-{arch}.{format}"),
            size: 10,
            sha256: "abc".to_owned(),
        }
    }

    #[test]
    fn selects_exact_arch_then_universal() {
        let m = manifest(vec![
            artifact("android", "universal", "apk"),
            artifact("android", "aarch64", "apk"),
        ]);
        assert_eq!(
            select_artifact(&m, "android", "aarch64", "apk").unwrap().arch,
            "aarch64"
        );
        assert_eq!(
            select_artifact(&m, "android", "armv7", "apk").unwrap().arch,
            "universal"
        );
        let win = manifest(vec![artifact("windows", "x86_64", "exe")]);
        assert_eq!(
            select_artifact(&win, "windows", "x86_64", "exe").unwrap().arch,
            "x86_64"
        );
        assert!(select_artifact(&win, "windows", "x86_64", "msi").is_err());
    }

    #[test]
    fn rejects_ambiguous_artifacts() {
        let m = manifest(vec![
            artifact("windows", "x86_64", "exe"),
            artifact("windows", "x86", "exe"),
        ]);
        assert!(select_artifact(&m, "windows", "aarch64", "exe").is_err());
    }

    #[test]
    fn validates_trusted_artifact_urls() {
        assert!(validate_artifact_url(
            "https://desk.parsipol.com/members/files/1.5.2/ParsiDesk-Setup-Windows-x64-1.5.2.exe"
        )
        .is_ok());
        assert!(validate_artifact_url(
            "https://desk.parsipol.com/update/staff/1.5.2/ParsiDesk.exe"
        )
        .is_ok());
        for url in [
            "http://desk.parsipol.com/members/files/1/x.exe",
            "https://evil.com/members/files/1/x.exe",
            "https://desk.parsipol.com.evil.com/members/files/1/x.exe",
            "https://user@desk.parsipol.com/members/files/1/x.exe",
            "https://desk.parsipol.com:8443/members/files/1/x.exe",
            "https://desk.parsipol.com/members/files/1/x.exe?a=1",
            "https://desk.parsipol.com/members/files/1/x.exe#f",
            "https://desk.parsipol.com/other/1/x.exe",
            "https://desk.parsipol.com/members/files/../../other/x.exe",
            "https://desk.parsipol.com/members/files/1/C:x.exe",
        ] {
            assert!(validate_artifact_url(url).is_err(), "{url}");
        }
    }

    #[test]
    fn version_compare_and_filename_safety() {
        assert!(
            hbb_common::get_version_number(&normalize_version("v1.5.2").unwrap())
                > hbb_common::get_version_number("1.1.0")
        );
        assert!(
            hbb_common::get_version_number(&normalize_version("1.1.0").unwrap())
                <= hbb_common::get_version_number("1.1.0")
        );
        assert!(normalize_version("1.5").is_err());
        assert!(normalize_version("1.5.x").is_err());
        assert!(is_plain_update_filename("ParsiDesk-Setup.exe"));
        assert!(!is_plain_update_filename("../evil.exe"));
        assert!(!is_plain_update_filename("a/b.exe"));
        assert!(!is_plain_update_filename("C:evil.exe"));
        assert!(download_path("../evil.exe").is_none());
        assert!(download_path("ParsiDesk-Setup.exe").is_some());
    }
}