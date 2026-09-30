use crate::{
    Codec, ConnectionMedium, DisplayPreset, PeerCapabilities, PerformanceProfile, SessionConfig,
    WireProtocol,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OptimizationError {
    NoCommonConnection,
    NoCommonProtocol,
    NoCommonCodec,
    NoCommonDisplayMode,
}

impl std::fmt::Display for OptimizationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoCommonConnection => f.write_str("peers share no supported connection medium"),
            Self::NoCommonProtocol => f.write_str("peers share no valid wire-protocol binding"),
            Self::NoCommonCodec => f.write_str("peers share no supported video codec"),
            Self::NoCommonDisplayMode => f.write_str("peers share no supported display mode"),
        }
    }
}

impl std::error::Error for OptimizationError {}

pub struct SessionOptimizer;

impl SessionOptimizer {
    pub fn recommend(
        base: &SessionConfig,
        local: &PeerCapabilities,
        remote: &PeerCapabilities,
        profile: PerformanceProfile,
    ) -> Result<SessionConfig, OptimizationError> {
        let common = local.intersection(remote);

        let connection_medium = choose_connection(&common)?;
        let wire_protocol = choose_protocol(&common, connection_medium)?;
        let codec = choose_codec(&common, profile)?;
        let preset = choose_preset(&common, profile)?;

        let mut recommendation = base.clone();
        recommendation.connection_medium = connection_medium;
        recommendation.wire_protocol = wire_protocol;
        recommendation.codec = codec;
        recommendation.preset = preset;
        recommendation.bitrate_mbps = recommended_bitrate(profile, connection_medium, preset);

        Ok(recommendation)
    }
}

fn choose_connection(
    capabilities: &PeerCapabilities,
) -> Result<ConnectionMedium, OptimizationError> {
    [
        ConnectionMedium::Usb,
        ConnectionMedium::Ethernet,
        ConnectionMedium::Wifi,
    ]
    .into_iter()
    .find(|medium| capabilities.supports_connection_medium(*medium))
    .ok_or(OptimizationError::NoCommonConnection)
}

fn choose_protocol(
    capabilities: &PeerCapabilities,
    medium: ConnectionMedium,
) -> Result<WireProtocol, OptimizationError> {
    let priorities = match medium {
        ConnectionMedium::Usb => [WireProtocol::Tcp, WireProtocol::Quic],
        ConnectionMedium::Wifi | ConnectionMedium::Ethernet => {
            [WireProtocol::Quic, WireProtocol::Tcp]
        }
    };

    priorities
        .into_iter()
        .find(|protocol| capabilities.supports_binding(medium, *protocol))
        .ok_or(OptimizationError::NoCommonProtocol)
}

fn choose_codec(
    capabilities: &PeerCapabilities,
    profile: PerformanceProfile,
) -> Result<Codec, OptimizationError> {
    let priorities = match profile {
        PerformanceProfile::Responsive | PerformanceProfile::Balanced => {
            [Codec::H264, Codec::Hevc, Codec::Av1]
        }
        PerformanceProfile::Quality => [Codec::Hevc, Codec::H264, Codec::Av1],
    };

    priorities
        .into_iter()
        .find(|codec| capabilities.supports_codec(*codec))
        .ok_or(OptimizationError::NoCommonCodec)
}

fn choose_preset(
    capabilities: &PeerCapabilities,
    profile: PerformanceProfile,
) -> Result<DisplayPreset, OptimizationError> {
    capabilities
        .presets
        .iter()
        .copied()
        .max_by_key(|preset| preset_score(*preset, profile))
        .ok_or(OptimizationError::NoCommonDisplayMode)
}

fn preset_score(preset: DisplayPreset, profile: PerformanceProfile) -> u64 {
    let pixels = u64::from(preset.width) * u64::from(preset.height);
    let refresh = u64::from(preset.refresh_hz);

    match profile {
        PerformanceProfile::Responsive => {
            // Refresh dominates. At the same refresh rate, prefer less work.
            refresh * 10_000_000 + (10_000_000_000_u64.saturating_sub(pixels))
        }
        PerformanceProfile::Balanced => {
            // Prefer up to 1440p before chasing more pixels, while still
            // rewarding refresh rate. Higher resolutions remain valid when
            // they are the only common modes.
            let target_pixels = 2560_u64 * 1440;
            let distance = pixels.abs_diff(target_pixels);
            20_000_000_000_u64.saturating_sub(distance) + refresh * 1_000_000
        }
        PerformanceProfile::Quality => {
            pixels * 1_000 + refresh + if preset.hidpi { 100_000 } else { 0 }
        }
    }
}

fn recommended_bitrate(
    profile: PerformanceProfile,
    medium: ConnectionMedium,
    preset: DisplayPreset,
) -> u16 {
    let base: u64 = match (profile, medium) {
        (PerformanceProfile::Responsive, ConnectionMedium::Wifi) => 12,
        (PerformanceProfile::Responsive, ConnectionMedium::Ethernet) => 16,
        (PerformanceProfile::Responsive, ConnectionMedium::Usb) => 18,
        (PerformanceProfile::Balanced, ConnectionMedium::Wifi) => 24,
        (PerformanceProfile::Balanced, ConnectionMedium::Ethernet) => 32,
        (PerformanceProfile::Balanced, ConnectionMedium::Usb) => 36,
        (PerformanceProfile::Quality, ConnectionMedium::Wifi) => 40,
        (PerformanceProfile::Quality, ConnectionMedium::Ethernet) => 55,
        (PerformanceProfile::Quality, ConnectionMedium::Usb) => 60,
    };

    let pixels = u64::from(preset.width) * u64::from(preset.height);
    let reference = 2560_u64 * 1440;
    let scaled = (base * pixels.max(reference)) / reference;

    scaled.clamp(6, 120) as u16
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{DisplayMode, Role};

    fn capabilities(
        media: Vec<ConnectionMedium>,
        protocols: Vec<WireProtocol>,
        codecs: Vec<Codec>,
        presets: Vec<DisplayPreset>,
    ) -> PeerCapabilities {
        PeerCapabilities {
            codecs,
            connection_media: media,
            wire_protocols: protocols,
            presets,
            encryption_supported: true,
            touch: crate::TouchCapabilities::none(),
        }
    }

    #[test]
    fn optimizer_prefers_usb_and_uses_tcp_binding() {
        let peers = capabilities(
            vec![ConnectionMedium::Wifi, ConnectionMedium::Usb],
            vec![WireProtocol::Quic, WireProtocol::Tcp],
            vec![Codec::H264],
            vec![DisplayPreset::PRESETS[0], DisplayPreset::PRESETS[1]],
        );

        let recommendation = SessionOptimizer::recommend(
            &SessionConfig::default(),
            &peers,
            &peers,
            PerformanceProfile::Balanced,
        )
        .unwrap();

        assert_eq!(recommendation.connection_medium, ConnectionMedium::Usb);
        assert_eq!(recommendation.wire_protocol, WireProtocol::Tcp);
        assert_eq!(recommendation.preset, DisplayPreset::PRESETS[1]);
    }

    #[test]
    fn responsive_profile_prefers_refresh_over_resolution() {
        let peers = capabilities(
            vec![ConnectionMedium::Wifi],
            vec![WireProtocol::Quic],
            vec![Codec::H264],
            vec![
                DisplayPreset::PRESETS[0],
                DisplayPreset::PRESETS[2],
                DisplayPreset::PRESETS[4],
            ],
        );

        let recommendation = SessionOptimizer::recommend(
            &SessionConfig::default(),
            &peers,
            &peers,
            PerformanceProfile::Responsive,
        )
        .unwrap();

        assert_eq!(recommendation.preset, DisplayPreset::PRESETS[2]);
    }

    #[test]
    fn quality_profile_prefers_hevc_and_highest_pixel_mode() {
        let peers = capabilities(
            vec![ConnectionMedium::Ethernet],
            vec![WireProtocol::Quic, WireProtocol::Tcp],
            vec![Codec::H264, Codec::Hevc],
            vec![DisplayPreset::PRESETS[1], DisplayPreset::PRESETS[4]],
        );

        let recommendation = SessionOptimizer::recommend(
            &SessionConfig::default(),
            &peers,
            &peers,
            PerformanceProfile::Quality,
        )
        .unwrap();

        assert_eq!(recommendation.codec, Codec::Hevc);
        assert_eq!(recommendation.preset, DisplayPreset::PRESETS[4]);
        assert!(recommendation.bitrate_mbps > 55);
    }

    #[test]
    fn optimizer_preserves_user_role_mode_and_security_intent() {
        let peers = capabilities(
            vec![ConnectionMedium::Wifi],
            vec![WireProtocol::Quic],
            vec![Codec::H264],
            vec![DisplayPreset::PRESETS[0]],
        );
        let base = SessionConfig {
            role: Role::Receiver,
            mode: DisplayMode::Mirror,
            encryption_required: false,
            ..SessionConfig::default()
        };

        let recommendation =
            SessionOptimizer::recommend(&base, &peers, &peers, PerformanceProfile::Balanced)
                .unwrap();

        assert_eq!(recommendation.role, Role::Receiver);
        assert_eq!(recommendation.mode, DisplayMode::Mirror);
        assert!(!recommendation.encryption_required);
    }

    #[test]
    fn optimizer_never_invents_a_connection() {
        let local = capabilities(
            vec![ConnectionMedium::Usb],
            vec![WireProtocol::Tcp],
            vec![Codec::H264],
            vec![DisplayPreset::PRESETS[0]],
        );
        let remote = capabilities(
            vec![ConnectionMedium::Wifi],
            vec![WireProtocol::Quic],
            vec![Codec::H264],
            vec![DisplayPreset::PRESETS[0]],
        );

        assert!(matches!(
            SessionOptimizer::recommend(
                &SessionConfig::default(),
                &local,
                &remote,
                PerformanceProfile::Balanced,
            ),
            Err(OptimizationError::NoCommonConnection)
        ));
    }
}
