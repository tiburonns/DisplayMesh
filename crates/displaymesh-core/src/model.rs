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
pub enum Transport {
    Quic,
    Tcp,
    Usb,
}

impl fmt::Display for Transport {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Quic => f.write_str("QUIC"),
            Self::Tcp => f.write_str("TCP"),
            Self::Usb => f.write_str("USB"),
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
