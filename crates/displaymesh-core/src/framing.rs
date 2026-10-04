use std::fmt;

pub const DMP_MAGIC: [u8; 4] = *b"DMP1";
pub const DMP_VERSION: u8 = 1;
pub const DMP_HEADER_LEN: usize = 16;
pub const DMP_MAX_PAYLOAD_LEN: usize = 16 * 1024 * 1024;
pub const DMP_AUTHENTICATED_ENCRYPTION_OVERHEAD: usize = 28;
pub const DMP_ENCRYPTED_PAYLOAD_FLAG: u16 = 0x0001;
pub const DMP_MAX_WIRE_PAYLOAD_LEN: usize =
    DMP_MAX_PAYLOAD_LEN + DMP_AUTHENTICATED_ENCRYPTION_OVERHEAD;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum DmpMessageType {
    Hello = 0x01,
    Capabilities = 0x02,
    PanelDescriptor = 0x03,
    Pairing = 0x04,
    Video = 0x10,
    Input = 0x20,
    Telemetry = 0x30,
    KeyframeRequest = 0x31,
    Ping = 0x32,
    Pong = 0x33,
    Error = 0x7f,
}

impl DmpMessageType {
    pub const fn maximum_payload_len(self) -> usize {
        match self {
            Self::Hello => 4 * 1024,
            Self::Capabilities => 64 * 1024,
            Self::PanelDescriptor => 16 * 1024,
            Self::Pairing => 16 * 1024,
            Self::Video => DMP_MAX_PAYLOAD_LEN,
            Self::Input => 40,
            Self::Telemetry => 16 * 1024,
            Self::KeyframeRequest => 0,
            Self::Ping | Self::Pong => 8,
            Self::Error => 8 * 1024,
        }
    }

    pub const fn exact_payload_len(self) -> Option<usize> {
        match self {
            Self::Input => Some(40),
            Self::KeyframeRequest => Some(0),
            Self::Ping | Self::Pong => Some(8),
            _ => None,
        }
    }

    pub fn validate_payload_len(self, size: usize, flags: u16) -> Result<(), DmpFrameError> {
        let encrypted = flags & DMP_ENCRYPTED_PAYLOAD_FLAG != 0;
        let overhead = if encrypted {
            DMP_AUTHENTICATED_ENCRYPTION_OVERHEAD
        } else {
            0
        };

        if let Some(exact) = self.exact_payload_len() {
            let expected = exact + overhead;
            if size != expected {
                return Err(DmpFrameError::InvalidPayloadLength {
                    message_type: self,
                    size,
                    expected,
                });
            }
            return Ok(());
        }

        let maximum = self.maximum_payload_len() + overhead;
        if size > maximum {
            return Err(DmpFrameError::PayloadTooLargeForType {
                message_type: self,
                size,
                maximum,
            });
        }

        Ok(())
    }
}

impl TryFrom<u8> for DmpMessageType {
    type Error = DmpFrameError;

    fn try_from(value: u8) -> Result<Self, DmpFrameError> {
        match value {
            0x01 => Ok(Self::Hello),
            0x02 => Ok(Self::Capabilities),
            0x03 => Ok(Self::PanelDescriptor),
            0x04 => Ok(Self::Pairing),
            0x10 => Ok(Self::Video),
            0x20 => Ok(Self::Input),
            0x30 => Ok(Self::Telemetry),
            0x31 => Ok(Self::KeyframeRequest),
            0x32 => Ok(Self::Ping),
            0x33 => Ok(Self::Pong),
            0x7f => Ok(Self::Error),
            _ => Err(DmpFrameError::UnsupportedMessageType(value)),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DmpFrame {
    pub message_type: DmpMessageType,
    pub flags: u16,
    pub sequence: u32,
    pub payload: Vec<u8>,
}

impl DmpFrame {
    pub fn encode(&self) -> Result<Vec<u8>, DmpFrameError> {
        if self.payload.len() > DMP_MAX_WIRE_PAYLOAD_LEN {
            return Err(DmpFrameError::PayloadTooLarge(self.payload.len()));
        }
        self.message_type
            .validate_payload_len(self.payload.len(), self.flags)?;

        let mut encoded = Vec::with_capacity(DMP_HEADER_LEN + self.payload.len());
        encoded.extend_from_slice(&DMP_MAGIC);
        encoded.push(DMP_VERSION);
        encoded.push(self.message_type as u8);
        encoded.extend_from_slice(&self.flags.to_be_bytes());
        encoded.extend_from_slice(&self.sequence.to_be_bytes());
        encoded.extend_from_slice(&(self.payload.len() as u32).to_be_bytes());
        encoded.extend_from_slice(&self.payload);
        Ok(encoded)
    }

    pub fn decode(buffer: &[u8]) -> Result<Option<(Self, usize)>, DmpFrameError> {
        if buffer.len() < DMP_HEADER_LEN {
            return Ok(None);
        }

        if buffer[0..4] != DMP_MAGIC {
            return Err(DmpFrameError::InvalidMagic);
        }

        let version = buffer[4];
        if version != DMP_VERSION {
            return Err(DmpFrameError::UnsupportedVersion(version));
        }

        let message_type = DmpMessageType::try_from(buffer[5])?;
        let flags = u16::from_be_bytes([buffer[6], buffer[7]]);
        let sequence = u32::from_be_bytes([buffer[8], buffer[9], buffer[10], buffer[11]]);
        let payload_len =
            u32::from_be_bytes([buffer[12], buffer[13], buffer[14], buffer[15]]) as usize;

        if payload_len > DMP_MAX_WIRE_PAYLOAD_LEN {
            return Err(DmpFrameError::PayloadTooLarge(payload_len));
        }
        message_type.validate_payload_len(payload_len, flags)?;

        let total_len = DMP_HEADER_LEN + payload_len;
        if buffer.len() < total_len {
            return Ok(None);
        }

        Ok(Some((
            Self {
                message_type,
                flags,
                sequence,
                payload: buffer[DMP_HEADER_LEN..total_len].to_vec(),
            },
            total_len,
        )))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DmpSequenceTracker {
    expected: u32,
    exhausted: bool,
}

impl Default for DmpSequenceTracker {
    fn default() -> Self {
        Self {
            expected: 1,
            exhausted: false,
        }
    }
}

impl DmpSequenceTracker {
    pub const fn expected(&self) -> u32 {
        self.expected
    }

    pub const fn is_exhausted(&self) -> bool {
        self.exhausted
    }

    pub fn accept(&mut self, sequence: u32) -> Result<(), DmpFrameError> {
        if self.exhausted {
            return Err(DmpFrameError::SequenceExhausted);
        }
        if sequence != self.expected {
            return Err(DmpFrameError::UnexpectedSequence {
                expected: self.expected,
                received: sequence,
            });
        }
        if self.expected == u32::MAX {
            self.exhausted = true;
        } else {
            self.expected += 1;
        }
        Ok(())
    }

    pub fn reset(&mut self) {
        self.expected = 1;
        self.exhausted = false;
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DmpFrameError {
    InvalidMagic,
    UnsupportedVersion(u8),
    UnsupportedMessageType(u8),
    PayloadTooLarge(usize),
    PayloadTooLargeForType {
        message_type: DmpMessageType,
        size: usize,
        maximum: usize,
    },
    InvalidPayloadLength {
        message_type: DmpMessageType,
        size: usize,
        expected: usize,
    },
    UnexpectedSequence {
        expected: u32,
        received: u32,
    },
    SequenceExhausted,
}

impl fmt::Display for DmpFrameError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidMagic => f.write_str("invalid DMP frame magic"),
            Self::UnsupportedVersion(version) => {
                write!(f, "unsupported DMP frame version: {version}")
            }
            Self::UnsupportedMessageType(message_type) => {
                write!(f, "unsupported DMP message type: {message_type:#04x}")
            }
            Self::PayloadTooLarge(size) => write!(f, "DMP payload is too large: {size} bytes"),
            Self::PayloadTooLargeForType {
                message_type,
                size,
                maximum,
            } => write!(
                f,
                "DMP {message_type:?} payload is too large: {size} bytes (max {maximum})"
            ),
            Self::InvalidPayloadLength {
                message_type,
                size,
                expected,
            } => write!(
                f,
                "DMP {message_type:?} payload has invalid size: {size} bytes (expected {expected})"
            ),
            Self::UnexpectedSequence { expected, received } => write!(
                f,
                "unexpected DMP sequence: expected {expected}, received {received}"
            ),
            Self::SequenceExhausted => {
                f.write_str("DMP sequence space exhausted; reconnect is required")
            }
        }
    }
}

impl std::error::Error for DmpFrameError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_round_trips() {
        let source = DmpFrame {
            message_type: DmpMessageType::Telemetry,
            flags: 0x0102,
            sequence: 42,
            payload: b"hello".to_vec(),
        };

        let encoded = source.encode().unwrap();
        assert_eq!(
            encoded,
            vec![
                0x44, 0x4d, 0x50, 0x31, 0x01, 0x30, 0x01, 0x02, 0x00, 0x00, 0x00, 0x2a, 0x00, 0x00,
                0x00, 0x05, b'h', b'e', b'l', b'l', b'o',
            ]
        );
        let (decoded, consumed) = DmpFrame::decode(&encoded).unwrap().unwrap();

        assert_eq!(decoded, source);
        assert_eq!(consumed, encoded.len());
    }

    #[test]
    fn fragmented_header_waits_for_more_bytes() {
        let source = DmpFrame {
            message_type: DmpMessageType::Hello,
            flags: 0,
            sequence: 1,
            payload: vec![1, 2, 3],
        };
        let encoded = source.encode().unwrap();

        assert_eq!(DmpFrame::decode(&encoded[..8]).unwrap(), None);
    }

    #[test]
    fn fragmented_payload_waits_for_more_bytes() {
        let source = DmpFrame {
            message_type: DmpMessageType::Hello,
            flags: 0,
            sequence: 1,
            payload: vec![1, 2, 3, 4, 5],
        };
        let encoded = source.encode().unwrap();

        assert_eq!(
            DmpFrame::decode(&encoded[..DMP_HEADER_LEN + 2]).unwrap(),
            None
        );
    }

    #[test]
    fn sequence_tracker_rejects_gaps_and_replays() {
        let mut tracker = DmpSequenceTracker::default();

        tracker.accept(1).unwrap();
        tracker.accept(2).unwrap();

        assert_eq!(
            tracker.accept(2),
            Err(DmpFrameError::UnexpectedSequence {
                expected: 3,
                received: 2,
            })
        );

        tracker.reset();
        assert_eq!(tracker.expected(), 1);
        tracker.accept(1).unwrap();
        assert_eq!(
            tracker.accept(3),
            Err(DmpFrameError::UnexpectedSequence {
                expected: 2,
                received: 3,
            })
        );
    }

    #[test]
    fn sequence_tracker_requires_reconnect_before_wrap() {
        let mut tracker = DmpSequenceTracker {
            expected: u32::MAX,
            exhausted: false,
        };
        tracker.accept(u32::MAX).unwrap();
        assert!(tracker.is_exhausted());
        assert_eq!(tracker.expected(), u32::MAX);
        assert_eq!(tracker.accept(0), Err(DmpFrameError::SequenceExhausted));
        tracker.reset();
        assert!(!tracker.is_exhausted());
        assert_eq!(tracker.expected(), 1);
        tracker.accept(1).unwrap();
    }

    #[test]
    fn control_payload_budget_is_enforced_before_body_arrives() {
        let mut header = Vec::new();
        header.extend_from_slice(&DMP_MAGIC);
        header.push(DMP_VERSION);
        header.push(DmpMessageType::Pairing as u8);
        header.extend_from_slice(&0_u16.to_be_bytes());
        header.extend_from_slice(&1_u32.to_be_bytes());
        header.extend_from_slice(&(32_u32 * 1024).to_be_bytes());

        assert_eq!(
            DmpFrame::decode(&header),
            Err(DmpFrameError::PayloadTooLargeForType {
                message_type: DmpMessageType::Pairing,
                size: 32 * 1024,
                maximum: 16 * 1024,
            })
        );
    }

    #[test]
    fn exact_payload_sizes_are_enforced() {
        let input = DmpFrame {
            message_type: DmpMessageType::Input,
            flags: 0,
            sequence: 1,
            payload: vec![0; 39],
        };
        assert_eq!(
            input.encode(),
            Err(DmpFrameError::InvalidPayloadLength {
                message_type: DmpMessageType::Input,
                size: 39,
                expected: 40,
            })
        );

        let keyframe = DmpFrame {
            message_type: DmpMessageType::KeyframeRequest,
            flags: 0,
            sequence: 1,
            payload: vec![1],
        };
        assert_eq!(
            keyframe.encode(),
            Err(DmpFrameError::InvalidPayloadLength {
                message_type: DmpMessageType::KeyframeRequest,
                size: 1,
                expected: 0,
            })
        );

        for message_type in [DmpMessageType::Ping, DmpMessageType::Pong] {
            let valid = DmpFrame {
                message_type,
                flags: 0,
                sequence: 1,
                payload: vec![0; 8],
            };
            assert!(valid.encode().is_ok());

            let invalid = DmpFrame {
                message_type,
                flags: 0,
                sequence: 1,
                payload: vec![0; 7],
            };
            assert_eq!(
                invalid.encode(),
                Err(DmpFrameError::InvalidPayloadLength {
                    message_type,
                    size: 7,
                    expected: 8,
                })
            );
        }
    }

    #[test]
    fn encrypted_exact_payload_sizes_include_aead_overhead() {
        let encrypted_input = DmpFrame {
            message_type: DmpMessageType::Input,
            flags: DMP_ENCRYPTED_PAYLOAD_FLAG,
            sequence: 1,
            payload: vec![0; 40 + DMP_AUTHENTICATED_ENCRYPTION_OVERHEAD],
        };
        assert!(encrypted_input.encode().is_ok());

        let encrypted_keyframe = DmpFrame {
            message_type: DmpMessageType::KeyframeRequest,
            flags: DMP_ENCRYPTED_PAYLOAD_FLAG,
            sequence: 1,
            payload: vec![0; DMP_AUTHENTICATED_ENCRYPTION_OVERHEAD],
        };
        assert!(encrypted_keyframe.encode().is_ok());

        let encrypted_ping = DmpFrame {
            message_type: DmpMessageType::Ping,
            flags: DMP_ENCRYPTED_PAYLOAD_FLAG,
            sequence: 1,
            payload: vec![0; 8 + DMP_AUTHENTICATED_ENCRYPTION_OVERHEAD],
        };
        assert!(encrypted_ping.encode().is_ok());

        let invalid = DmpFrame {
            message_type: DmpMessageType::Input,
            flags: DMP_ENCRYPTED_PAYLOAD_FLAG,
            sequence: 1,
            payload: vec![0; 40],
        };
        assert_eq!(
            invalid.encode(),
            Err(DmpFrameError::InvalidPayloadLength {
                message_type: DmpMessageType::Input,
                size: 40,
                expected: 40 + DMP_AUTHENTICATED_ENCRYPTION_OVERHEAD,
            })
        );
    }

    #[test]
    fn invalid_magic_is_rejected() {
        let mut encoded = DmpFrame {
            message_type: DmpMessageType::Hello,
            flags: 0,
            sequence: 1,
            payload: Vec::new(),
        }
        .encode()
        .unwrap();
        encoded[0] = b'X';

        assert_eq!(DmpFrame::decode(&encoded), Err(DmpFrameError::InvalidMagic));
    }
}
