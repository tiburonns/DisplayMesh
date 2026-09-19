use crate::{Codec, DisplayMode, DisplayPreset, PeerCapabilities, Role, Transport};

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

    pub fn negotiate(
        &self,
        local: &PeerCapabilities,
        remote: &PeerCapabilities,
    ) -> Result<NegotiatedSession, SessionNegotiationError> {
        self.validate().map_err(SessionNegotiationError::InvalidConfig)?;

        let compatible = local.intersection(remote);

        if !compatible.supports_codec(self.codec) {
            return Err(SessionNegotiationError::UnsupportedCodec(self.codec));
        }

        if !compatible.supports_transport(self.transport) {
            return Err(SessionNegotiationError::UnsupportedTransport(self.transport));
        }

        if !compatible.supports_preset(self.preset) {
            return Err(SessionNegotiationError::UnsupportedPreset(self.preset));
        }

        if self.encryption_required && !compatible.encryption_supported {
            return Err(SessionNegotiationError::EncryptionUnavailable);
        }

        Ok(NegotiatedSession {
            role: self.role,
            mode: self.mode,
            codec: self.codec,
            transport: self.transport,
            preset: self.preset,
            bitrate_mbps: self.bitrate_mbps,
            encrypted: self.encryption_required,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NegotiatedSession {
    pub role: Role,
    pub mode: DisplayMode,
    pub codec: Codec,
    pub transport: Transport,
    pub preset: DisplayPreset,
    pub bitrate_mbps: u16,
    pub encrypted: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionNegotiationError {
    InvalidConfig(SessionValidationError),
    UnsupportedCodec(Codec),
    UnsupportedTransport(Transport),
    UnsupportedPreset(DisplayPreset),
    EncryptionUnavailable,
}

impl std::fmt::Display for SessionNegotiationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidConfig(error) => write!(f, "invalid session configuration: {error}"),
            Self::UnsupportedCodec(codec) => {
                write!(f, "selected codec is not supported by both peers: {codec}")
            }
            Self::UnsupportedTransport(transport) => {
                write!(
                    f,
                    "selected transport is not supported by both peers: {transport}"
                )
            }
            Self::UnsupportedPreset(preset) => write!(
                f,
                "selected display mode is not supported by both peers: {}x{}@{}",
                preset.width, preset.height, preset.refresh_hz
            ),
            Self::EncryptionUnavailable => {
                f.write_str("encrypted sessions are required but one peer cannot provide them")
            }
        }
    }
}

impl std::error::Error for SessionNegotiationError {}

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
        assert_eq!(config.validate(), Err(SessionValidationError::ZeroBitrate));
    }

    #[test]
    fn matching_peers_negotiate_requested_session() {
        let config = SessionConfig::default();
        let local = PeerCapabilities::development_scaffold();
        let remote = PeerCapabilities::development_scaffold();

        let negotiated = config.negotiate(&local, &remote).unwrap();

        assert_eq!(negotiated.codec, Codec::H264);
        assert_eq!(negotiated.transport, Transport::Quic);
        assert_eq!(negotiated.preset, DisplayPreset::PRESETS[1]);
        assert!(negotiated.encrypted);
    }

    #[test]
    fn unsupported_codec_is_rejected_instead_of_silently_falling_back() {
        let mut config = SessionConfig::default();
        config.codec = Codec::Hevc;

        let local = PeerCapabilities::development_scaffold();
        let remote = PeerCapabilities::development_scaffold();

        assert_eq!(
            config.negotiate(&local, &remote),
            Err(SessionNegotiationError::UnsupportedCodec(Codec::Hevc))
        );
    }

    #[test]
    fn unsupported_transport_is_rejected() {
        let mut config = SessionConfig::default();
        config.transport = Transport::Usb;

        let local = PeerCapabilities::development_scaffold();
        let remote = PeerCapabilities::development_scaffold();

        assert_eq!(
            config.negotiate(&local, &remote),
            Err(SessionNegotiationError::UnsupportedTransport(Transport::Usb))
        );
    }

    #[test]
    fn encryption_requirement_is_enforced() {
        let config = SessionConfig::default();
        let local = PeerCapabilities::development_scaffold();
        let mut remote = PeerCapabilities::development_scaffold();
        remote.encryption_supported = false;

        assert_eq!(
            config.negotiate(&local, &remote),
            Err(SessionNegotiationError::EncryptionUnavailable)
        );
    }

    #[test]
    fn capability_intersection_preserves_only_common_values() {
        let local = PeerCapabilities {
            codecs: vec![Codec::H264, Codec::Hevc],
            transports: vec![Transport::Quic, Transport::Tcp],
            presets: vec![DisplayPreset::PRESETS[0], DisplayPreset::PRESETS[1]],
            encryption_supported: true,
        };
        let remote = PeerCapabilities {
            codecs: vec![Codec::H264, Codec::Av1],
            transports: vec![Transport::Tcp],
            presets: vec![DisplayPreset::PRESETS[1]],
            encryption_supported: true,
        };

        let common = local.intersection(&remote);

        assert_eq!(common.codecs, vec![Codec::H264]);
        assert_eq!(common.transports, vec![Transport::Tcp]);
        assert_eq!(common.presets, vec![DisplayPreset::PRESETS[1]]);
        assert!(common.encryption_supported);
    }
}
