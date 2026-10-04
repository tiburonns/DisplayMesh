use crate::{ConnectionMedium, WireProtocol};

/// Concrete medium/protocol pair considered by the transport handoff policy.
///
/// This is a control-plane contract only. Platform code still owns discovery,
/// socket/usbmux establishment, authentication and the actual switchover.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TransportBinding {
    pub medium: ConnectionMedium,
    pub protocol: WireProtocol,
}

impl TransportBinding {
    pub const fn new(medium: ConnectionMedium, protocol: WireProtocol) -> Self {
        Self { medium, protocol }
    }

    pub const fn is_supported(self) -> bool {
        match self.medium {
            ConnectionMedium::Usb => matches!(self.protocol, WireProtocol::Tcp),
            ConnectionMedium::Wifi | ConnectionMedium::Ethernet => true,
        }
    }

    const fn preference(self) -> u8 {
        match self.medium {
            ConnectionMedium::Usb => 3,
            ConnectionMedium::Ethernet => 2,
            ConnectionMedium::Wifi => 1,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TransportCandidate {
    pub binding: TransportBinding,
    /// The platform transport reached its usable/connected state.
    pub ready: bool,
    /// The candidate completed DisplayMesh peer authentication.
    pub authenticated: bool,
    /// The authenticated identity matches the peer on the active session.
    pub same_peer_identity: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportHandoffRejection {
    UnsupportedBinding,
    CandidateNotReady,
    CandidateUnauthenticated,
    PeerIdentityMismatch,
    GenerationExhausted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportHandoffDecision {
    Stay {
        active: TransportBinding,
        generation: u64,
    },
    Switch {
        from: TransportBinding,
        to: TransportBinding,
        generation: u64,
    },
    Reject {
        active: TransportBinding,
        candidate: TransportBinding,
        reason: TransportHandoffRejection,
        generation: u64,
    },
}

/// Deterministic policy for future Wi-Fi/Ethernet/USB transport handoff.
///
/// Security invariants:
/// - a cable does not imply trust;
/// - a new binding must authenticate as the same peer before switching;
/// - USB/TCP is the only initial USB wire binding;
/// - a healthy higher-preference transport is never replaced by a lower one;
/// - the monotonically increasing generation lets platform layers discard
///   stale callbacks from a transport that has already been superseded.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TransportHandoffController {
    active: TransportBinding,
    generation: u64,
}

impl TransportHandoffController {
    pub fn new(active: TransportBinding) -> Result<Self, TransportHandoffRejection> {
        if !active.is_supported() {
            return Err(TransportHandoffRejection::UnsupportedBinding);
        }

        Ok(Self {
            active,
            generation: 1,
        })
    }

    pub const fn active(&self) -> TransportBinding {
        self.active
    }

    pub const fn generation(&self) -> u64 {
        self.generation
    }

    pub fn consider(
        &mut self,
        active_healthy: bool,
        candidate: TransportCandidate,
    ) -> TransportHandoffDecision {
        if candidate.binding == self.active {
            return self.stay();
        }

        if !candidate.binding.is_supported() {
            return self.reject(
                candidate.binding,
                TransportHandoffRejection::UnsupportedBinding,
            );
        }

        if !candidate.ready {
            return self.reject(
                candidate.binding,
                TransportHandoffRejection::CandidateNotReady,
            );
        }

        if !candidate.authenticated {
            return self.reject(
                candidate.binding,
                TransportHandoffRejection::CandidateUnauthenticated,
            );
        }

        if !candidate.same_peer_identity {
            return self.reject(
                candidate.binding,
                TransportHandoffRejection::PeerIdentityMismatch,
            );
        }

        let should_switch =
            !active_healthy || candidate.binding.preference() > self.active.preference();

        if !should_switch {
            return self.stay();
        }

        let Some(next_generation) = self.generation.checked_add(1) else {
            return self.reject(
                candidate.binding,
                TransportHandoffRejection::GenerationExhausted,
            );
        };

        let previous = self.active;
        self.active = candidate.binding;
        self.generation = next_generation;

        TransportHandoffDecision::Switch {
            from: previous,
            to: self.active,
            generation: self.generation,
        }
    }

    const fn stay(&self) -> TransportHandoffDecision {
        TransportHandoffDecision::Stay {
            active: self.active,
            generation: self.generation,
        }
    }

    const fn reject(
        &self,
        candidate: TransportBinding,
        reason: TransportHandoffRejection,
    ) -> TransportHandoffDecision {
        TransportHandoffDecision::Reject {
            active: self.active,
            candidate,
            reason,
            generation: self.generation,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const WIFI_TCP: TransportBinding =
        TransportBinding::new(ConnectionMedium::Wifi, WireProtocol::Tcp);
    const USB_TCP: TransportBinding =
        TransportBinding::new(ConnectionMedium::Usb, WireProtocol::Tcp);
    const USB_QUIC: TransportBinding =
        TransportBinding::new(ConnectionMedium::Usb, WireProtocol::Quic);
    const ETHERNET_TCP: TransportBinding =
        TransportBinding::new(ConnectionMedium::Ethernet, WireProtocol::Tcp);

    fn candidate(binding: TransportBinding) -> TransportCandidate {
        TransportCandidate {
            binding,
            ready: true,
            authenticated: true,
            same_peer_identity: true,
        }
    }

    #[test]
    fn invalid_usb_quic_binding_is_rejected() {
        assert_eq!(
            TransportHandoffController::new(USB_QUIC),
            Err(TransportHandoffRejection::UnsupportedBinding)
        );

        let mut controller = TransportHandoffController::new(WIFI_TCP).unwrap();
        assert_eq!(
            controller.consider(true, candidate(USB_QUIC)),
            TransportHandoffDecision::Reject {
                active: WIFI_TCP,
                candidate: USB_QUIC,
                reason: TransportHandoffRejection::UnsupportedBinding,
                generation: 1,
            }
        );
    }

    #[test]
    fn cable_presence_never_bypasses_authentication() {
        let mut controller = TransportHandoffController::new(WIFI_TCP).unwrap();
        let mut usb = candidate(USB_TCP);
        usb.authenticated = false;

        assert_eq!(
            controller.consider(true, usb),
            TransportHandoffDecision::Reject {
                active: WIFI_TCP,
                candidate: USB_TCP,
                reason: TransportHandoffRejection::CandidateUnauthenticated,
                generation: 1,
            }
        );
        assert_eq!(controller.active(), WIFI_TCP);
    }

    #[test]
    fn changed_peer_identity_cannot_take_over_active_session() {
        let mut controller = TransportHandoffController::new(WIFI_TCP).unwrap();
        let mut usb = candidate(USB_TCP);
        usb.same_peer_identity = false;

        assert_eq!(
            controller.consider(true, usb),
            TransportHandoffDecision::Reject {
                active: WIFI_TCP,
                candidate: USB_TCP,
                reason: TransportHandoffRejection::PeerIdentityMismatch,
                generation: 1,
            }
        );
    }

    #[test]
    fn authenticated_usb_can_replace_healthy_wifi() {
        let mut controller = TransportHandoffController::new(WIFI_TCP).unwrap();

        assert_eq!(
            controller.consider(true, candidate(USB_TCP)),
            TransportHandoffDecision::Switch {
                from: WIFI_TCP,
                to: USB_TCP,
                generation: 2,
            }
        );
        assert_eq!(controller.active(), USB_TCP);
        assert_eq!(controller.generation(), 2);
    }

    #[test]
    fn healthy_usb_is_not_downgraded_to_wifi() {
        let mut controller = TransportHandoffController::new(USB_TCP).unwrap();

        assert_eq!(
            controller.consider(true, candidate(WIFI_TCP)),
            TransportHandoffDecision::Stay {
                active: USB_TCP,
                generation: 1,
            }
        );
    }

    #[test]
    fn unhealthy_transport_can_fail_over_to_authenticated_lower_priority_path() {
        let mut controller = TransportHandoffController::new(USB_TCP).unwrap();

        assert_eq!(
            controller.consider(false, candidate(WIFI_TCP)),
            TransportHandoffDecision::Switch {
                from: USB_TCP,
                to: WIFI_TCP,
                generation: 2,
            }
        );
    }

    #[test]
    fn ethernet_sits_between_wifi_and_usb_preference() {
        let mut controller = TransportHandoffController::new(WIFI_TCP).unwrap();

        assert!(matches!(
            controller.consider(true, candidate(ETHERNET_TCP)),
            TransportHandoffDecision::Switch { to, .. } if to == ETHERNET_TCP
        ));
        assert!(matches!(
            controller.consider(true, candidate(USB_TCP)),
            TransportHandoffDecision::Switch { to, .. } if to == USB_TCP
        ));
    }

    #[test]
    fn candidate_must_be_ready_before_switching() {
        let mut controller = TransportHandoffController::new(WIFI_TCP).unwrap();
        let mut usb = candidate(USB_TCP);
        usb.ready = false;

        assert_eq!(
            controller.consider(true, usb),
            TransportHandoffDecision::Reject {
                active: WIFI_TCP,
                candidate: USB_TCP,
                reason: TransportHandoffRejection::CandidateNotReady,
                generation: 1,
            }
        );
    }

    #[test]
    fn repeated_observation_of_active_binding_is_idempotent() {
        let mut controller = TransportHandoffController::new(WIFI_TCP).unwrap();

        assert_eq!(
            controller.consider(true, candidate(WIFI_TCP)),
            TransportHandoffDecision::Stay {
                active: WIFI_TCP,
                generation: 1,
            }
        );
        assert_eq!(controller.generation(), 1);
    }
}
