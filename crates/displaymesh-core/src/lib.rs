//! Shared DisplayMesh domain model.
//!
//! Platform-specific display creation, capture, encoding and rendering live
//! outside this crate. Keeping those boundaries explicit prevents the shared
//! UI from depending on private macOS APIs or Windows driver code.

mod backend;
mod framing;
mod model;
mod session;

pub use backend::{BackendError, DisplayBackend, NativeBackendStatus, NativeProofLevel};
pub use framing::{
    DMP_HEADER_LEN, DMP_MAGIC, DMP_MAX_PAYLOAD_LEN, DMP_VERSION, DmpFrame, DmpFrameError,
    DmpMessageType,
};
pub use model::{
    BackendCapabilities, Codec, ConnectionMedium, Device, DisplayMode, DisplayPreset,
    OperatingSystem, PeerCapabilities, Role, TouchCapabilities, TouchPhase, TouchPoint,
    WireProtocol,
};
pub use session::{
    NegotiatedSession, SessionConfig, SessionNegotiationError, SessionPhase, SessionValidationError,
};
