use std::fmt;

pub const DMP_VIDEO_HEADER_LEN: usize = 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum DmpVideoCodec {
    H264 = 0x01,
    Hevc = 0x02,
    Av1 = 0x03,
}

impl TryFrom<u8> for DmpVideoCodec {
    type Error = DmpVideoPacketError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0x01 => Ok(Self::H264),
            0x02 => Ok(Self::Hevc),
            0x03 => Ok(Self::Av1),
            _ => Err(DmpVideoPacketError::UnsupportedCodec(value)),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct DmpVideoFlags(u8);

impl DmpVideoFlags {
    pub const KEYFRAME: u8 = 1 << 0;

    pub const fn new(raw: u8) -> Self {
        Self(raw)
    }

    pub const fn raw(self) -> u8 {
        self.0
    }

    pub const fn is_keyframe(self) -> bool {
        self.0 & Self::KEYFRAME != 0
    }

    pub const fn with_keyframe(mut self, enabled: bool) -> Self {
        if enabled {
            self.0 |= Self::KEYFRAME;
        } else {
            self.0 &= !Self::KEYFRAME;
        }
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DmpVideoPacket {
    pub codec: DmpVideoCodec,
    pub flags: DmpVideoFlags,
    pub pts_micros: u64,
    pub duration_micros: u32,
    pub bitstream: Vec<u8>,
}

impl DmpVideoPacket {
    pub fn encode(&self) -> Result<Vec<u8>, DmpVideoPacketError> {
        if self.bitstream.is_empty() {
            return Err(DmpVideoPacketError::EmptyBitstream);
        }

        let mut encoded = Vec::with_capacity(DMP_VIDEO_HEADER_LEN + self.bitstream.len());
        encoded.push(self.codec as u8);
        encoded.push(self.flags.raw());
        encoded.extend_from_slice(&0_u16.to_be_bytes());
        encoded.extend_from_slice(&self.pts_micros.to_be_bytes());
        encoded.extend_from_slice(&self.duration_micros.to_be_bytes());
        encoded.extend_from_slice(&self.bitstream);
        Ok(encoded)
    }

    pub fn decode(payload: &[u8]) -> Result<Self, DmpVideoPacketError> {
        if payload.len() < DMP_VIDEO_HEADER_LEN {
            return Err(DmpVideoPacketError::HeaderTooShort(payload.len()));
        }

        let codec = DmpVideoCodec::try_from(payload[0])?;
        if payload[1] & !DmpVideoFlags::KEYFRAME != 0 {
            return Err(DmpVideoPacketError::UnsupportedFlags(payload[1]));
        }
        if payload[2] != 0 || payload[3] != 0 {
            return Err(DmpVideoPacketError::ReservedHeaderNonZero(
                u16::from_be_bytes([payload[2], payload[3]]),
            ));
        }
        let flags = DmpVideoFlags::new(payload[1]);
        let pts_micros = u64::from_be_bytes([
            payload[4],
            payload[5],
            payload[6],
            payload[7],
            payload[8],
            payload[9],
            payload[10],
            payload[11],
        ]);
        let duration_micros =
            u32::from_be_bytes([payload[12], payload[13], payload[14], payload[15]]);
        let bitstream = payload[DMP_VIDEO_HEADER_LEN..].to_vec();

        if bitstream.is_empty() {
            return Err(DmpVideoPacketError::EmptyBitstream);
        }

        Ok(Self {
            codec,
            flags,
            pts_micros,
            duration_micros,
            bitstream,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DmpVideoPacketError {
    HeaderTooShort(usize),
    UnsupportedCodec(u8),
    UnsupportedFlags(u8),
    ReservedHeaderNonZero(u16),
    EmptyBitstream,
}

impl fmt::Display for DmpVideoPacketError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::HeaderTooShort(size) => {
                write!(f, "DMP video header is too short: {size} bytes")
            }
            Self::UnsupportedCodec(codec) => {
                write!(f, "unsupported DMP video codec: {codec:#04x}")
            }
            Self::UnsupportedFlags(flags) => {
                write!(f, "unsupported DMP video flags: {flags:#04x}")
            }
            Self::ReservedHeaderNonZero(value) => {
                write!(f, "DMP video reserved header must be zero: {value:#06x}")
            }
            Self::EmptyBitstream => f.write_str("DMP video packet has an empty bitstream"),
        }
    }
}

impl std::error::Error for DmpVideoPacketError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn video_packet_round_trips() {
        let source = DmpVideoPacket {
            codec: DmpVideoCodec::H264,
            flags: DmpVideoFlags::default().with_keyframe(true),
            pts_micros: 1_234_567,
            duration_micros: 16_667,
            bitstream: vec![0, 0, 0, 1, 0x65, 1, 2, 3],
        };

        let encoded = source.encode().unwrap();
        let decoded = DmpVideoPacket::decode(&encoded).unwrap();

        assert_eq!(decoded, source);
        assert!(decoded.flags.is_keyframe());
    }

    #[test]
    fn empty_video_payload_is_rejected() {
        let payload = [
            DmpVideoCodec::H264 as u8,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
        ];

        assert_eq!(
            DmpVideoPacket::decode(&payload),
            Err(DmpVideoPacketError::EmptyBitstream)
        );
    }

    #[test]
    fn unsupported_video_flags_are_rejected() {
        let mut payload = vec![0_u8; DMP_VIDEO_HEADER_LEN + 1];
        payload[0] = DmpVideoCodec::H264 as u8;
        payload[1] = 0b1000_0000;
        payload[DMP_VIDEO_HEADER_LEN] = 1;

        assert_eq!(
            DmpVideoPacket::decode(&payload),
            Err(DmpVideoPacketError::UnsupportedFlags(0b1000_0000))
        );
    }

    #[test]
    fn nonzero_reserved_video_header_is_rejected() {
        let mut payload = vec![0_u8; DMP_VIDEO_HEADER_LEN + 1];
        payload[0] = DmpVideoCodec::H264 as u8;
        payload[2] = 0x12;
        payload[3] = 0x34;
        payload[DMP_VIDEO_HEADER_LEN] = 1;

        assert_eq!(
            DmpVideoPacket::decode(&payload),
            Err(DmpVideoPacketError::ReservedHeaderNonZero(0x1234))
        );
    }

    #[test]
    fn unsupported_codec_is_rejected() {
        let mut payload = vec![0_u8; DMP_VIDEO_HEADER_LEN + 1];
        payload[0] = 0xff;
        payload[DMP_VIDEO_HEADER_LEN] = 1;

        assert_eq!(
            DmpVideoPacket::decode(&payload),
            Err(DmpVideoPacketError::UnsupportedCodec(0xff))
        );
    }
}
