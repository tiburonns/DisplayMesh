use std::fmt;

pub const DMP_MAGIC: [u8; 4] = *b"DMP1";
pub const DMP_VERSION: u8 = 1;
pub const DMP_HEADER_LEN: usize = 16;
pub const DMP_MAX_PAYLOAD_LEN: usize = 16 * 1024 * 1024;

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
            Self::Error => 8 * 1024,
        }
    }

    pub const fn exact_payload_len(self) -> Option<usize> {
        match self {
            Self::Input => Some(40),
            Self::KeyframeRequest => Some(0),
            _ => None,
        }
    }

    pub fn validate_payload_len(self, size: usize) -> Result<(), DmpFrameError> {
        if let Some(expected) = self.exact_payload_len() {
            if size != expected {
                return Err(DmpFrameError::InvalidPayloadLength {
                    message_type: self,
                    size,
                    expected,
                });
            }
            return Ok(());
        }

        let maximum = self.maximum_payload_len();
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

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0x01 => Ok(Self::Hello),
            0x02 => Ok(Self::Capabilities),
            0x03 => Ok(Self::PanelDescriptor),
            0x04 => Ok(Self::Pairing),
            0x10 => Ok(Self::Video),
            0x20 => Ok(Self::Input),
            0x30 => Ok(Self::Telemetry),
            0x31 => Ok(Self::KeyframeRequest),
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
        if self.payload.len() > DMP_MAX_PAYLOAD_LEN {
            return Err(DmpFrameError::PayloadTooLarge(self.payload.len()));
        }
        self.message_type.validate_payload_len(self.payload.len())?;

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

        if payload_len > DMP_MAX_PAYLOAD_LEN {
            return Err(DmpFrameError::PayloadTooLarge(payload_len));
        }
        message_type.validate_payload_len(payload_len)?;

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
}

impl Default for DmpSequenceTracker {
    fn default() -> Self {
        Self { expected: 1 }
    }
}

impl DmpSequenceTracker {
    pub const fn expected(&self) -> u32 {
        self.expected
    }

    pub fn accept(&mut self, sequence: u32) -> Result<(), DmpFrameError> {
        if sequence != self.expected {
            return Err(DmpFrameError::UnexpectedSequence {
                expected: self.expected,
                received: sequence,
            });
        }

        self.expected = self.expected.wrapping_add(1);
        Ok(())
    }

    pub fn reset(&mut self) {
        self.expected = 1;
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
    UnexpectedSequence { expected: u32, received: u32 },
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
                0x44, 0x4d, 0x50, 0x31,
                0x01, 0x30, 0x01, 0x02,
                0x00, 0x00, 0x00, 0x2a,
                0x00, 0x00, 0x00, 0x05,
                b'h', b'e', b'l', b'l', b'o',
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
    fn sequence_tracker_wraps_without_panicking() {
        let mut tracker = DmpSequenceTracker { expected: u32::MAX };
        tracker.accept(u32::MAX).unwrap();
        assert_eq!(tracker.expected(), 0);
        tracker.accept(0).unwrap();
        assert_eq!(tracker.expected(), 1);
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
