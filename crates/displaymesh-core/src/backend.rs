use crate::{BackendCapabilities, OperatingSystem};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NativeProofLevel {
    None,
    VirtualDisplayHarness,
    DriverBootstrap,
}

impl NativeProofLevel {
    pub const fn label(self) -> &'static str {
        match self {
            Self::None => "No native proof available",
            Self::VirtualDisplayHarness => "Virtual-display proof harness available",
            Self::DriverBootstrap => "Driver bootstrap proof available",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NativeBackendStatus {
    pub os: OperatingSystem,
    pub proof_level: NativeProofLevel,
    pub integrated_with_control_app: bool,
    pub capabilities: BackendCapabilities,
}

impl NativeBackendStatus {
    pub const fn development_for(os: OperatingSystem) -> Self {
        match os {
            OperatingSystem::MacOS => Self {
                os,
                proof_level: NativeProofLevel::VirtualDisplayHarness,
                integrated_with_control_app: false,
                capabilities: BackendCapabilities::scaffold(),
            },
            OperatingSystem::Windows => Self {
                os,
                proof_level: NativeProofLevel::DriverBootstrap,
                integrated_with_control_app: false,
                capabilities: BackendCapabilities::scaffold(),
            },
            OperatingSystem::Unknown => Self {
                os,
                proof_level: NativeProofLevel::None,
                integrated_with_control_app: false,
                capabilities: BackendCapabilities::scaffold(),
            },
        }
    }

    pub const fn current_development() -> Self {
        Self::development_for(OperatingSystem::current())
    }

    pub const fn can_start_real_session(self) -> bool {
        self.integrated_with_control_app
            && self.capabilities.can_create_virtual_display
            && self.capabilities.can_capture
            && self.capabilities.can_render
    }
}

pub trait DisplayBackend: Send + Sync {
    fn operating_system(&self) -> OperatingSystem;
    fn capabilities(&self) -> BackendCapabilities;
    fn create_virtual_display(&mut self) -> Result<(), BackendError>;
    fn destroy_virtual_display(&mut self) -> Result<(), BackendError>;
    fn start_capture(&mut self) -> Result<(), BackendError>;
    fn stop_capture(&mut self) -> Result<(), BackendError>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackendError {
    NotIntegrated,
    UnsupportedPlatform,
    NativeFailure,
}

impl std::fmt::Display for BackendError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotIntegrated => {
                f.write_str("native backend exists only as a proof harness and is not integrated")
            }
            Self::UnsupportedPlatform => {
                f.write_str("DisplayMesh does not support this operating system")
            }
            Self::NativeFailure => f.write_str("native display backend reported a failure"),
        }
    }
}

impl std::error::Error for BackendError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn development_backends_never_claim_real_session_readiness() {
        for os in [
            OperatingSystem::MacOS,
            OperatingSystem::Windows,
            OperatingSystem::Unknown,
        ] {
            let status = NativeBackendStatus::development_for(os);
            assert!(!status.can_start_real_session());
            assert!(!status.integrated_with_control_app);
        }
    }

    #[test]
    fn proof_levels_match_current_native_scaffolds() {
        assert_eq!(
            NativeBackendStatus::development_for(OperatingSystem::MacOS).proof_level,
            NativeProofLevel::VirtualDisplayHarness
        );
        assert_eq!(
            NativeBackendStatus::development_for(OperatingSystem::Windows).proof_level,
            NativeProofLevel::DriverBootstrap
        );
    }
}
