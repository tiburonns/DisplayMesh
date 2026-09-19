use crate::{Codec, DisplayMode, DisplayPreset, Role, Transport};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionPhase {
    Idle,
    Discovering,
    Pairing,
    Connecting,
    Streaming,
    Stopping,
    Failed,
}

impl SessionPhase {
    pub const fn label(self) -> &'static str {
        match self {
            Self::Idle => "Idle",
            Self::Discovering => "Discovering",
            Self::Pairing => "Pairing",
            Self::Connecting => "Connecting",
            Self::Streaming => "Streaming",
            Self::Stopping => "Stopping",
            Self::Failed => "Failed",
        }
    }
}

#[derive(Debug, Clone)]
pub struct SessionConfig {
    pub role: Role,
    pub mode: DisplayMode,
    pub codec: Codec,
    pub transport: Transport,
    pub preset: DisplayPreset,
    pub bitrate_mbps: u16,
    pub encryption_required: bool,
}

impl Default for SessionConfig {
    fn default() -> Self {
        Self {
            role: Role::Host,
            mode: DisplayMode::Extend,
            codec: Codec::H264,
            transport: Transport::Quic,
            preset: DisplayPreset::PRESETS[1],
            bitrate_mbps: 24,
            encryption_required: true,
        }
    }
}

impl SessionConfig {
    pub fn validate(&self) -> Result<(), SessionValidationError> {
        if self.bitrate_mbps == 0 {
            return Err(SessionValidationError::ZeroBitrate);
        }

        if self.preset.width < 640 || self.preset.height < 480 {
            return Err(SessionValidationError::ResolutionTooSmall);
        }

        if self.preset.refresh_hz == 0 {
            return Err(SessionValidationError::ZeroRefreshRate);
        }

        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionValidationError {
    ZeroBitrate,
    ResolutionTooSmall,
    ZeroRefreshRate,
}

impl std::fmt::Display for SessionValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ZeroBitrate => f.write_str("bitrate must be greater than zero"),
            Self::ResolutionTooSmall => f.write_str("resolution is below the supported minimum"),
            Self::ZeroRefreshRate => f.write_str("refresh rate must be greater than zero"),
        }
    }
}

impl std::error::Error for SessionValidationError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_session_is_valid() {
        assert!(SessionConfig::default().validate().is_ok());
    }

    #[test]
    fn zero_bitrate_is_rejected() {
        let mut config = SessionConfig::default();
        config.bitrate_mbps = 0;
        assert_eq!(
            config.validate(),
            Err(SessionValidationError::ZeroBitrate)
        );
    }
}
