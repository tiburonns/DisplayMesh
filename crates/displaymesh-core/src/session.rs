use crate::{
    Codec, ConnectionMedium, DisplayMode, DisplayPreset, PeerCapabilities, Role, WireProtocol,
};

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
    pub connection_medium: ConnectionMedium,
    pub wire_protocol: WireProtocol,
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
            connection_medium: ConnectionMedium::Wifi,
            wire_protocol: WireProtocol::Quic,
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
        self.validate()
            .map_err(SessionNegotiationError::InvalidConfig)?;

        let compatible = local.intersection(remote);

        if !compatible.supports_codec(self.codec) {
            return Err(SessionNegotiationError::UnsupportedCodec(self.codec));
        }

        if !compatible.supports_connection_medium(self.connection_medium) {
            return Err(SessionNegotiationError::UnsupportedConnectionMedium(
                self.connection_medium,
            ));
        }

        if !compatible.supports_wire_protocol(self.wire_protocol) {
            return Err(SessionNegotiationError::UnsupportedWireProtocol(
                self.wire_protocol,
            ));
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
            connection_medium: self.connection_medium,
            wire_protocol: self.wire_protocol,
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
    pub connection_medium: ConnectionMedium,
    pub wire_protocol: WireProtocol,
    pub preset: DisplayPreset,
    pub bitrate_mbps: u16,
    pub encrypted: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionNegotiationError {
    InvalidConfig(SessionValidationError),
    UnsupportedCodec(Codec),
    UnsupportedConnectionMedium(ConnectionMedium),
    UnsupportedWireProtocol(WireProtocol),
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
            Self::UnsupportedConnectionMedium(medium) => write!(
                f,
                "selected connection medium is not supported by both peers: {medium}"
            ),
            Self::UnsupportedWireProtocol(protocol) => write!(
                f,
                "selected wire protocol is not supported by both peers: {protocol}"
            ),
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
        assert_eq!(negotiated.connection_medium, ConnectionMedium::Wifi);
        assert_eq!(negotiated.wire_protocol, WireProtocol::Quic);
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
    fn unsupported_connection_medium_is_rejected() {
        let config = SessionConfig::default();
        let local = PeerCapabilities::development_scaffold();
        let mut remote = PeerCapabilities::development_scaffold();
        remote.connection_media = vec![ConnectionMedium::Wifi];

        let mut usb_config = config;
        usb_config.connection_medium = ConnectionMedium::Usb;

        assert_eq!(
            usb_config.negotiate(&local, &remote),
            Err(SessionNegotiationError::UnsupportedConnectionMedium(
                ConnectionMedium::Usb
            ))
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
            connection_media: vec![ConnectionMedium::Wifi, ConnectionMedium::Usb],
            wire_protocols: vec![WireProtocol::Quic, WireProtocol::Tcp],
            presets: vec![DisplayPreset::PRESETS[0], DisplayPreset::PRESETS[1]],
            encryption_supported: true,
            touch: crate::TouchCapabilities::apple_receiver(),
        };
        let remote = PeerCapabilities {
            codecs: vec![Codec::H264, Codec::Av1],
            connection_media: vec![ConnectionMedium::Usb],
            wire_protocols: vec![WireProtocol::Tcp],
            presets: vec![DisplayPreset::PRESETS[1]],
            encryption_supported: true,
            touch: crate::TouchCapabilities::apple_receiver(),
        };

        let common = local.intersection(&remote);

        assert_eq!(common.codecs, vec![Codec::H264]);
        assert_eq!(common.connection_media, vec![ConnectionMedium::Usb]);
        assert_eq!(common.wire_protocols, vec![WireProtocol::Tcp]);
        assert_eq!(common.presets, vec![DisplayPreset::PRESETS[1]]);
        assert!(common.encryption_supported);
        assert!(common.touch.touch);
    }
}
