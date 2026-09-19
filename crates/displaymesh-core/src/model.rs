use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OperatingSystem {
    MacOS,
    Windows,
    Unknown,
}

impl OperatingSystem {
    pub const fn current() -> Self {
        if cfg!(target_os = "macos") {
            Self::MacOS
        } else if cfg!(target_os = "windows") {
            Self::Windows
        } else {
            Self::Unknown
        }
    }
}

impl fmt::Display for OperatingSystem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MacOS => f.write_str("macOS"),
            Self::Windows => f.write_str("Windows"),
            Self::Unknown => f.write_str("Unknown"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    Host,
    Receiver,
}

impl fmt::Display for Role {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Host => f.write_str("Host"),
            Self::Receiver => f.write_str("Receiver"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DisplayMode {
    Extend,
    Mirror,
}

impl fmt::Display for DisplayMode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Extend => f.write_str("Extend"),
            Self::Mirror => f.write_str("Mirror"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Codec {
    H264,
    Hevc,
    Av1,
}

impl fmt::Display for Codec {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::H264 => f.write_str("H.264"),
            Self::Hevc => f.write_str("HEVC"),
            Self::Av1 => f.write_str("AV1"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionMedium {
    Wifi,
    Usb,
    Ethernet,
}

impl fmt::Display for ConnectionMedium {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Wifi => f.write_str("Wi-Fi / LAN"),
            Self::Usb => f.write_str("USB"),
            Self::Ethernet => f.write_str("Ethernet"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WireProtocol {
    Quic,
    Tcp,
}

impl fmt::Display for WireProtocol {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Quic => f.write_str("QUIC"),
            Self::Tcp => f.write_str("TCP"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DisplayPreset {
    pub name: &'static str,
    pub width: u32,
    pub height: u32,
    pub refresh_hz: u16,
    pub hidpi: bool,
}

impl DisplayPreset {
    pub const PRESETS: [Self; 5] = [
        Self {
            name: "1080p 60",
            width: 1920,
            height: 1080,
            refresh_hz: 60,
            hidpi: false,
        },
        Self {
            name: "1440p 60",
            width: 2560,
            height: 1440,
            refresh_hz: 60,
            hidpi: false,
        },
        Self {
            name: "1440p 120",
            width: 2560,
            height: 1440,
            refresh_hz: 120,
            hidpi: false,
        },
        Self {
            name: "Retina 1080p",
            width: 3840,
            height: 2160,
            refresh_hz: 60,
            hidpi: true,
        },
        Self {
            name: "4K 60",
            width: 3840,
            height: 2160,
            refresh_hz: 60,
            hidpi: false,
        },
    ];
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Device {
    pub id: String,
    pub name: String,
    pub os: OperatingSystem,
    pub address: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BackendCapabilities {
    pub can_create_virtual_display: bool,
    pub can_capture: bool,
    pub can_render: bool,
    pub can_inject_pointer: bool,
    pub can_inject_keyboard: bool,
    pub supports_hidpi: bool,
    pub max_refresh_hz: u16,
}

impl BackendCapabilities {
    pub const fn scaffold() -> Self {
        Self {
            can_create_virtual_display: false,
            can_capture: false,
            can_render: false,
            can_inject_pointer: false,
            can_inject_keyboard: false,
            supports_hidpi: false,
            max_refresh_hz: 60,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TouchCapabilities {
    pub touch: bool,
    pub pencil: bool,
    pub hover: bool,
    pub max_touch_points: u8,
}

impl TouchCapabilities {
    pub const fn none() -> Self {
        Self {
            touch: false,
            pencil: false,
            hover: false,
            max_touch_points: 0,
        }
    }

    pub const fn apple_receiver() -> Self {
        Self {
            touch: true,
            pencil: true,
            hover: true,
            max_touch_points: 10,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerCapabilities {
    pub codecs: Vec<Codec>,
    pub connection_media: Vec<ConnectionMedium>,
    pub wire_protocols: Vec<WireProtocol>,
    pub presets: Vec<DisplayPreset>,
    pub encryption_supported: bool,
    pub touch: TouchCapabilities,
}

impl PeerCapabilities {
    pub fn supports_codec(&self, codec: Codec) -> bool {
        self.codecs.contains(&codec)
    }

    pub fn supports_connection_medium(&self, medium: ConnectionMedium) -> bool {
        self.connection_media.contains(&medium)
    }

    pub fn supports_wire_protocol(&self, protocol: WireProtocol) -> bool {
        self.wire_protocols.contains(&protocol)
    }

    pub fn supports_binding(
        &self,
        medium: ConnectionMedium,
        protocol: WireProtocol,
    ) -> bool {
        if !self.supports_connection_medium(medium) || !self.supports_wire_protocol(protocol) {
            return false;
        }

        match medium {
            ConnectionMedium::Usb => protocol == WireProtocol::Tcp,
            ConnectionMedium::Wifi | ConnectionMedium::Ethernet => true,
        }
    }

    pub fn supports_preset(&self, preset: DisplayPreset) -> bool {
        self.presets.contains(&preset)
    }

    pub fn intersection(&self, other: &Self) -> Self {
        Self {
            codecs: self
                .codecs
                .iter()
                .copied()
                .filter(|codec| other.codecs.contains(codec))
                .collect(),
            connection_media: self
                .connection_media
                .iter()
                .copied()
                .filter(|medium| other.connection_media.contains(medium))
                .collect(),
            wire_protocols: self
                .wire_protocols
                .iter()
                .copied()
                .filter(|protocol| other.wire_protocols.contains(protocol))
                .collect(),
            presets: self
                .presets
                .iter()
                .copied()
                .filter(|preset| other.presets.contains(preset))
                .collect(),
            encryption_supported: self.encryption_supported && other.encryption_supported,
            touch: TouchCapabilities {
                touch: self.touch.touch && other.touch.touch,
                pencil: self.touch.pencil && other.touch.pencil,
                hover: self.touch.hover && other.touch.hover,
                max_touch_points: self
                    .touch
                    .max_touch_points
                    .min(other.touch.max_touch_points),
            },
        }
    }

    pub fn development_scaffold() -> Self {
        Self {
            codecs: vec![Codec::H264],
            connection_media: vec![
                ConnectionMedium::Wifi,
                ConnectionMedium::Usb,
                ConnectionMedium::Ethernet,
            ],
            wire_protocols: vec![WireProtocol::Quic, WireProtocol::Tcp],
            presets: DisplayPreset::PRESETS[..2].to_vec(),
            encryption_supported: true,
            touch: TouchCapabilities::apple_receiver(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TouchPhase {
    Began,
    Moved,
    Ended,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TouchPoint {
    pub id: u32,
    pub phase: TouchPhase,
    pub normalized_x: f32,
    pub normalized_y: f32,
    pub pressure: f32,
}

impl TouchPoint {
    pub fn is_normalized(&self) -> bool {
        (0.0..=1.0).contains(&self.normalized_x)
            && (0.0..=1.0).contains(&self.normalized_y)
            && (0.0..=1.0).contains(&self.pressure)
    }
}
