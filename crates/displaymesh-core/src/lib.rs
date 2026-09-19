//! Shared DisplayMesh domain model.
//!
//! Platform-specific display creation, capture, encoding and rendering live
//! outside this crate. Keeping those boundaries explicit prevents the shared
//! UI from depending on private macOS APIs or Windows driver code.

mod model;
mod session;

pub use model::{
    BackendCapabilities, Codec, Device, DisplayMode, DisplayPreset, OperatingSystem, Role,
    Transport,
};
pub use session::{SessionConfig, SessionPhase, SessionValidationError};
