#[cfg(feature = "flutter")]
use base::{
    config::keys,
    message_proto::{message, LoginRequest, Message},
};
use base::message_proto::PeerInfo;
use hbb_common::{config::LocalConfig, log, rendezvous_proto::ConnType};
use serde_json::{json, Map, Value};

const PASSWORD_KIND: &str = "parsidesk_permanent_password";

pub(crate) fn set_password_kind(pi: &mut PeerInfo, permanent: bool) {
    let mut additions: Map<String, Value> =
        serde_json::from_str(&pi.platform_additions).unwrap_or_default();
    additions.insert(PASSWORD_KIND.into(), json!(permanent));
    match serde_json::to_string(&additions) {
        Ok(value) => pi.platform_additions = value,
        Err(error) => log::error!("Failed to serialize staff authentication metadata: {error}"),
    }
}

fn password_preference(staff: bool, id: &str, conn_type: ConnType, pi: &PeerInfo) -> Option<bool> {
    if !staff || conn_type != ConnType::DEFAULT_CONN || !numeric_peer(id) {
        return None;
    }
    let additions: Value = serde_json::from_str(&pi.platform_additions).ok()?;
    additions.get(PASSWORD_KIND)?.as_bool()
}

pub(crate) fn remember_password(id: &str, conn_type: ConnType, pi: &PeerInfo) -> Option<bool> {
    let staff = !LocalConfig::get_option("staff-username").is_empty()
        && LocalConfig::get_option("staff-mode") != "lab"
        && !LocalConfig::get_option("staff-help-token").is_empty();
    password_preference(staff, id, conn_type, pi)
}

fn numeric_peer(id: &str) -> bool {
    (6..=10).contains(&id.len()) && id.bytes().all(|c| c.is_ascii_digit())
}

#[cfg(feature = "flutter")]
pub(crate) fn session_connected(id: &str, session_id: u64, pi: &PeerInfo) {
    if numeric_peer(id) {
        crate::flutter::push_global_event(
            crate::flutter::APP_TYPE_MAIN,
            json!({
                "name": "staff-support-connected",
                "id": id,
                "session_id": session_id.to_string(),
                "hostname": pi.hostname,
            })
            .to_string(),
        );
    }
}

#[cfg(feature = "flutter")]
pub(crate) fn session_disconnected(id: &str, session_id: u64) {
    if numeric_peer(id) {
        crate::flutter::push_global_event(
            crate::flutter::APP_TYPE_MAIN,
            json!({
                "name": "staff-support-disconnected",
                "id": id,
                "session_id": session_id.to_string(),
            })
            .to_string(),
        );
    }
}

#[cfg(feature = "flutter")]
async fn approval_request(path: &str, body: Value, token: Option<&str>) -> Option<Value> {
    use hbb_common::bail;
    use std::time::Duration;

    let request = async {
        let builder = reqwest::Client::builder()
            .use_rustls_tls()
            .https_only(true)
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(3));
        #[cfg(any(target_os = "android", target_os = "ios"))]
        let builder = builder.use_preconfigured_tls(hbb_common::verifier::client_config(false)?);
        let client = builder.build()?;
        let mut request = client
            .post(format!("https://desk.parsipol.com/help/api/support/{path}"))
            .json(&body);
        if let Some(token) = token {
            request = request.bearer_auth(token);
        }
        let mut response = request.send().await?;
        if !response.status().is_success() {
            return Ok(None);
        }
        let mut bytes = Vec::new();
        while let Some(chunk) = response.chunk().await? {
            if bytes.len() + chunk.len() > 4096 {
                bail!("Staff approval response is too large");
            }
            bytes.extend_from_slice(&chunk);
        }
        Ok::<Option<Value>, hbb_common::anyhow::Error>(Some(serde_json::from_slice(&bytes)?))
    };
    match hbb_common::tokio::time::timeout(Duration::from_secs(3), request).await {
        Ok(Ok(data)) => data,
        _ => {
            hbb_common::throttled_log!(
                Duration::from_secs(60),
                warn,
                "Staff approval server unavailable; keeping normal approval"
            );
            None
        }
    }
}

fn valid_ticket(ticket: &str) -> bool {
    ticket.len() == 64
        && ticket
            .bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}

#[cfg(feature = "flutter")]
pub(crate) async fn add_login_ticket(mut message: Message, challenge: &str) -> Message {
    if let Some(message::Union::LoginRequest(lr)) = message.union.as_mut() {
        let token = LocalConfig::get_option("staff-help-token");
        if lr.union.is_none()
            && !lr.password.is_empty()
            && numeric_peer(&lr.username)
            && !LocalConfig::get_option("staff-username").is_empty()
            && LocalConfig::get_option("staff-mode") != "lab"
            && !token.is_empty()
        {
            if let Some(response) = approval_request(
                "authorize",
                json!({"id": lr.username, "challenge": challenge}),
                Some(&token),
            )
            .await
            {
                if response["ok"] == true {
                    if let Some(ticket) = response["ticket"].as_str().filter(|t| valid_ticket(t)) {
                        lr.staff_support_ticket = ticket.into();
                    }
                }
            }
        }
    }
    message
}

#[cfg(feature = "flutter")]
pub(crate) async fn verify_login_ticket(lr: &LoginRequest, challenge: &str) -> bool {
    let Some(lab_id) = hbb_common::config::Config::get_option(keys::OPTION_STAFF_LAB_ID)
        .parse::<u32>()
        .ok()
        .filter(|id| *id > 0)
    else {
        return false;
    };
    if lr.union.is_some()
        || lr.password.is_empty()
        || !numeric_peer(&lr.username)
        || !valid_ticket(&lr.staff_support_ticket)
    {
        return false;
    }
    approval_request(
        "verify",
        json!({"id": lr.username, "challenge": challenge, "ticket": lr.staff_support_ticket, "lab_id": lab_id}),
        None,
    )
    .await
    .map(|response| response["ok"] == true)
    .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn staff_remembers_only_host_confirmed_permanent_passwords() {
        let mut pi = PeerInfo::new();
        assert_eq!(
            password_preference(true, "123456789", ConnType::DEFAULT_CONN, &pi),
            None
        );
        set_password_kind(&mut pi, true);
        assert_eq!(
            password_preference(true, "123456789", ConnType::DEFAULT_CONN, &pi),
            Some(true)
        );
        set_password_kind(&mut pi, false);
        assert_eq!(
            password_preference(true, "123456789", ConnType::DEFAULT_CONN, &pi),
            Some(false)
        );
        assert_eq!(
            password_preference(false, "123456789", ConnType::DEFAULT_CONN, &pi),
            None
        );
        assert_eq!(
            password_preference(true, "192.168.1.1", ConnType::DEFAULT_CONN, &pi),
            None
        );
    }

    #[test]
    fn staff_approval_requires_an_opaque_ticket() {
        assert!(valid_ticket(&"a1".repeat(32)));
        assert!(!valid_ticket("staff"));
        assert!(!valid_ticket(&"G".repeat(64)));
        assert!(!valid_ticket(&"a".repeat(63)));
    }

    #[test]
    fn authentication_metadata_preserves_existing_capabilities() {
        let mut pi = PeerInfo::new();
        pi.platform_additions = json!({"is_installed": true}).to_string();
        set_password_kind(&mut pi, true);
        let additions: Value = serde_json::from_str(&pi.platform_additions).unwrap();
        assert_eq!(additions["is_installed"], true);
        assert_eq!(additions[PASSWORD_KIND], true);
    }
}
