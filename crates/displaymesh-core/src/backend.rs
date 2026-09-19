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


#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackendLifecycleState {
    Idle,
    DisplayCreated,
    Capturing,
    Failed,
}

pub struct ManagedDisplayBackend<B: DisplayBackend> {
    backend: B,
    state: BackendLifecycleState,
}

impl<B: DisplayBackend> ManagedDisplayBackend<B> {
    pub fn new(backend: B) -> Self {
        Self {
            backend,
            state: BackendLifecycleState::Idle,
        }
    }

    pub const fn state(&self) -> BackendLifecycleState {
        self.state
    }

    pub fn backend(&self) -> &B {
        &self.backend
    }

    pub fn backend_mut(&mut self) -> &mut B {
        &mut self.backend
    }

    pub fn start(&mut self) -> Result<(), BackendError> {
        if self.state != BackendLifecycleState::Idle {
            return Err(BackendError::InvalidState);
        }

        self.backend.create_virtual_display()?;
        self.state = BackendLifecycleState::DisplayCreated;

        if let Err(error) = self.backend.start_capture() {
            self.state = match self.backend.destroy_virtual_display() {
                Ok(()) => BackendLifecycleState::Idle,
                Err(_) => BackendLifecycleState::Failed,
            };
            return Err(error);
        }

        self.state = BackendLifecycleState::Capturing;
        Ok(())
    }

    pub fn stop(&mut self) -> Result<(), BackendError> {
        match self.state {
            BackendLifecycleState::Idle => Ok(()),
            BackendLifecycleState::DisplayCreated => {
                let result = self.backend.destroy_virtual_display();
                self.state = if result.is_ok() {
                    BackendLifecycleState::Idle
                } else {
                    BackendLifecycleState::Failed
                };
                result
            }
            BackendLifecycleState::Capturing => {
                let stop_result = self.backend.stop_capture();
                let destroy_result = self.backend.destroy_virtual_display();

                self.state = if destroy_result.is_ok() {
                    BackendLifecycleState::Idle
                } else {
                    BackendLifecycleState::Failed
                };

                match (stop_result, destroy_result) {
                    (Err(error), _) => Err(error),
                    (Ok(()), Err(error)) => Err(error),
                    (Ok(()), Ok(())) => Ok(()),
                }
            }
            BackendLifecycleState::Failed => {
                let _ = self.backend.stop_capture();
                let result = self.backend.destroy_virtual_display();
                self.state = if result.is_ok() {
                    BackendLifecycleState::Idle
                } else {
                    BackendLifecycleState::Failed
                };
                result
            }
        }
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
    InvalidState,
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
            Self::InvalidState => f.write_str("backend lifecycle operation is invalid in the current state"),
        }
    }
}

impl std::error::Error for BackendError {}

#[cfg(test)]
mod tests {
    use super::*;


    #[derive(Default)]
    struct FakeBackend {
        calls: Vec<&'static str>,
        fail_capture_start: bool,
        fail_destroy: bool,
    }

    impl DisplayBackend for FakeBackend {
        fn operating_system(&self) -> OperatingSystem {
            OperatingSystem::MacOS
        }

        fn capabilities(&self) -> BackendCapabilities {
            BackendCapabilities {
                can_create_virtual_display: true,
                can_capture: true,
                can_render: true,
                can_inject_pointer: false,
                can_inject_keyboard: false,
                supports_hidpi: true,
                max_refresh_hz: 120,
            }
        }

        fn create_virtual_display(&mut self) -> Result<(), BackendError> {
            self.calls.push("create");
            Ok(())
        }

        fn destroy_virtual_display(&mut self) -> Result<(), BackendError> {
            self.calls.push("destroy");
            if self.fail_destroy {
                Err(BackendError::NativeFailure)
            } else {
                Ok(())
            }
        }

        fn start_capture(&mut self) -> Result<(), BackendError> {
            self.calls.push("start_capture");
            if self.fail_capture_start {
                Err(BackendError::NativeFailure)
            } else {
                Ok(())
            }
        }

        fn stop_capture(&mut self) -> Result<(), BackendError> {
            self.calls.push("stop_capture");
            Ok(())
        }
    }

    #[test]
    fn managed_backend_enforces_start_stop_order() {
        let backend = FakeBackend::default();
        let mut managed = ManagedDisplayBackend::new(backend);

        assert_eq!(managed.state(), BackendLifecycleState::Idle);
        managed.start().unwrap();
        assert_eq!(managed.state(), BackendLifecycleState::Capturing);

        managed.stop().unwrap();
        assert_eq!(managed.state(), BackendLifecycleState::Idle);
        assert_eq!(
            managed.backend().calls,
            vec!["create", "start_capture", "stop_capture", "destroy"]
        );

        managed.stop().unwrap();
        assert_eq!(
            managed.backend().calls,
            vec!["create", "start_capture", "stop_capture", "destroy"]
        );
    }

    #[test]
    fn capture_start_failure_rolls_back_virtual_display() {
        let backend = FakeBackend {
            fail_capture_start: true,
            ..FakeBackend::default()
        };
        let mut managed = ManagedDisplayBackend::new(backend);

        assert_eq!(managed.start(), Err(BackendError::NativeFailure));
        assert_eq!(managed.state(), BackendLifecycleState::Idle);
        assert_eq!(
            managed.backend().calls,
            vec!["create", "start_capture", "destroy"]
        );
    }

    #[test]
    fn cleanup_failure_is_visible_and_leaves_failed_state() {
        let backend = FakeBackend {
            fail_capture_start: true,
            fail_destroy: true,
            ..FakeBackend::default()
        };
        let mut managed = ManagedDisplayBackend::new(backend);

        assert_eq!(managed.start(), Err(BackendError::NativeFailure));
        assert_eq!(managed.state(), BackendLifecycleState::Failed);
        assert_eq!(managed.stop(), Err(BackendError::NativeFailure));
        assert_eq!(managed.state(), BackendLifecycleState::Failed);
    }

    #[test]
    fn duplicate_start_is_rejected() {
        let backend = FakeBackend::default();
        let mut managed = ManagedDisplayBackend::new(backend);
        managed.start().unwrap();

        assert_eq!(managed.start(), Err(BackendError::InvalidState));
    }

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
