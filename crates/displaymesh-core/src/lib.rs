//! Shared DisplayMesh domain model.
//!
//! Platform-specific display creation, capture, encoding and rendering live
//! outside this crate. Keeping those boundaries explicit prevents the shared
//! UI from depending on private macOS APIs or Windows driver code.

mod backend;
mod model;
mod session;

pub use backend::{
    BackendError, DisplayBackend, NativeBackendStatus, NativeProofLevel,
};
pub use model::{
    BackendCapabilities, Codec, Device, DisplayMode, DisplayPreset, OperatingSystem, PeerCapabilities,
    Role, Transport,
};
pub use session::{
    NegotiatedSession, SessionConfig, SessionNegotiationError, SessionPhase, SessionValidationError,
};
