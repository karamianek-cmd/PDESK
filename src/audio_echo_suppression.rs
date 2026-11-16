// Half-duplex echo suppression: mute local capture while the remote party is audible.

use base::config::keys;
use hbb_common::config::Config;
use std::{
    sync::atomic::{AtomicU64, Ordering},
    time::Instant,
};

const SUPPRESSION_HOLD_MS: u64 = 500;
const SIGNAL_EPSILON: f32 = 1.0e-4;

lazy_static::lazy_static! {
    static ref EPOCH: Instant = Instant::now();
}
static LAST_REMOTE_AUDIO_MS: AtomicU64 = AtomicU64::new(0);

fn now_ms() -> u64 {
    EPOCH.elapsed().as_millis() as u64
}

fn has_signal(pcm: &[f32]) -> bool {
    pcm.iter().any(|sample| sample.abs() > SIGNAL_EPSILON)
}

fn enabled() -> bool {
    Config::get_option(keys::OPTION_ENABLE_AUDIO_ECHO_SUPPRESSION) != "N"
}

fn suppression_active(last_ms: u64, now_ms: u64, enabled: bool) -> bool {
    enabled && last_ms != 0 && now_ms.saturating_sub(last_ms) < SUPPRESSION_HOLD_MS
}

pub fn note_remote_audio(pcm: &[f32]) {
    if has_signal(pcm) {
        LAST_REMOTE_AUDIO_MS.store(now_ms(), Ordering::Relaxed);
    }
}

pub fn suppress_capture() -> bool {
    suppression_active(
        LAST_REMOTE_AUDIO_MS.load(Ordering::Relaxed),
        now_ms(),
        enabled(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gates_only_within_hold_after_remote_signal() {
        assert!(!suppression_active(0, 1000, true));
        assert!(suppression_active(1000, 1200, true));
        assert!(suppression_active(1000, 1499, true));
        assert!(!suppression_active(1000, 1500, true));
        assert!(!suppression_active(1000, 1200, false));
    }

    #[test]
    fn detects_audible_remote_frames_only() {
        assert!(!has_signal(&[0.0; 480]));
        assert!(!has_signal(&[1.0e-6; 480]));
        assert!(has_signal(&[0.0, 0.2, 0.0]));
        assert!(has_signal(&[-0.3]));
    }
}