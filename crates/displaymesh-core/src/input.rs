use std::fmt;

pub const DMP_INPUT_SAMPLE_LEN: usize = 40;
pub const DMP_INPUT_VERSION: u8 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum DmpInputKind {
    Touch = 1,
    Pencil = 2,
}

impl TryFrom<u8> for DmpInputKind {
    type Error = DmpInputError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(Self::Touch),
            2 => Ok(Self::Pencil),
            _ => Err(DmpInputError::UnsupportedKind(value)),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum DmpInputPhase {
    Began = 1,
    Moved = 2,
    Ended = 3,
    Cancelled = 4,
    Hover = 5,
}

impl TryFrom<u8> for DmpInputPhase {
    type Error = DmpInputError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(Self::Began),
            2 => Ok(Self::Moved),
            3 => Ok(Self::Ended),
            4 => Ok(Self::Cancelled),
            5 => Ok(Self::Hover),
            _ => Err(DmpInputError::UnsupportedPhase(value)),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DmpInputSample {
    pub kind: DmpInputKind,
    pub phase: DmpInputPhase,
    pub flags: u8,
    pub contact_id: u32,
    pub normalized_x: f32,
    pub normalized_y: f32,
    pub pressure: f32,
    pub altitude: f32,
    pub azimuth: f32,
    pub barrel_roll: f32,
    pub timestamp_micros: u64,
}

impl DmpInputSample {
    pub fn encode(self) -> Result<[u8; DMP_INPUT_SAMPLE_LEN], DmpInputError> {
        self.validate()?;

        let mut output = [0_u8; DMP_INPUT_SAMPLE_LEN];
        output[0] = DMP_INPUT_VERSION;
        output[1] = self.kind as u8;
        output[2] = self.phase as u8;
        output[3] = self.flags;
        output[4..8].copy_from_slice(&self.contact_id.to_be_bytes());
        write_f32(&mut output[8..12], self.normalized_x);
        write_f32(&mut output[12..16], self.normalized_y);
        write_f32(&mut output[16..20], self.pressure);
        write_f32(&mut output[20..24], self.altitude);
        write_f32(&mut output[24..28], self.azimuth);
        write_f32(&mut output[28..32], self.barrel_roll);
        output[32..40].copy_from_slice(&self.timestamp_micros.to_be_bytes());
        Ok(output)
    }

    pub fn decode(payload: &[u8]) -> Result<Self, DmpInputError> {
        if payload.len() != DMP_INPUT_SAMPLE_LEN {
            return Err(DmpInputError::InvalidLength(payload.len()));
        }

        if payload[0] != DMP_INPUT_VERSION {
            return Err(DmpInputError::UnsupportedVersion(payload[0]));
        }

        let sample = Self {
            kind: DmpInputKind::try_from(payload[1])?,
            phase: DmpInputPhase::try_from(payload[2])?,
            flags: payload[3],
            contact_id: u32::from_be_bytes(payload[4..8].try_into().unwrap()),
            normalized_x: read_f32(&payload[8..12]),
            normalized_y: read_f32(&payload[12..16]),
            pressure: read_f32(&payload[16..20]),
            altitude: read_f32(&payload[20..24]),
            azimuth: read_f32(&payload[24..28]),
            barrel_roll: read_f32(&payload[28..32]),
            timestamp_micros: u64::from_be_bytes(payload[32..40].try_into().unwrap()),
        };

        sample.validate()?;
        Ok(sample)
    }

    pub fn validate(self) -> Result<(), DmpInputError> {
        if self.flags != 0 {
            return Err(DmpInputError::UnsupportedFlags(self.flags));
        }

        if !self.normalized_x.is_finite()
            || !self.normalized_y.is_finite()
            || !(0.0..=1.0).contains(&self.normalized_x)
            || !(0.0..=1.0).contains(&self.normalized_y)
        {
            return Err(DmpInputError::InvalidCoordinates);
        }

        if !self.pressure.is_finite() || !(0.0..=1.0).contains(&self.pressure) {
            return Err(DmpInputError::InvalidPressure);
        }

        if !self.altitude.is_finite()
            || !self.azimuth.is_finite()
            || !self.barrel_roll.is_finite()
        {
            return Err(DmpInputError::InvalidStylusData);
        }

        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DmpInputError {
    InvalidLength(usize),
    UnsupportedVersion(u8),
    UnsupportedKind(u8),
    UnsupportedPhase(u8),
    UnsupportedFlags(u8),
    InvalidCoordinates,
    InvalidPressure,
    InvalidStylusData,
}

impl fmt::Display for DmpInputError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidLength(size) => {
                write!(f, "DMP input sample must be 40 bytes, got {size}")
            }
            Self::UnsupportedVersion(version) => {
                write!(f, "unsupported DMP input version: {version}")
            }
            Self::UnsupportedKind(kind) => {
                write!(f, "unsupported DMP input kind: {kind}")
            }
            Self::UnsupportedPhase(phase) => {
                write!(f, "unsupported DMP input phase: {phase}")
            }
            Self::UnsupportedFlags(flags) => {
                write!(f, "unsupported DMP input flags: {flags:#04x}")
            }
            Self::InvalidCoordinates => f.write_str("DMP input coordinates are invalid"),
            Self::InvalidPressure => f.write_str("DMP input pressure is invalid"),
            Self::InvalidStylusData => f.write_str("DMP stylus data contains non-finite values"),
        }
    }
}

impl std::error::Error for DmpInputError {}

fn write_f32(target: &mut [u8], value: f32) {
    target.copy_from_slice(&value.to_bits().to_be_bytes());
}

fn read_f32(source: &[u8]) -> f32 {
    f32::from_bits(u32::from_be_bytes(source.try_into().unwrap()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> DmpInputSample {
        DmpInputSample {
            kind: DmpInputKind::Pencil,
            phase: DmpInputPhase::Moved,
            flags: 0,
            contact_id: 7,
            normalized_x: 0.25,
            normalized_y: 0.75,
            pressure: 0.5,
            altitude: 0.9,
            azimuth: 1.2,
            barrel_roll: 0.0,
            timestamp_micros: 123_456_789,
        }
    }

    #[test]
    fn input_sample_round_trips() {
        let source = sample();
        let encoded = source.encode().unwrap();
        let decoded = DmpInputSample::decode(&encoded).unwrap();
        assert_eq!(decoded, source);
    }

    #[test]
    fn normalized_coordinates_are_required() {
        let mut source = sample();
        source.normalized_x = 1.1;
        assert_eq!(source.encode(), Err(DmpInputError::InvalidCoordinates));
    }

    #[test]
    fn reserved_flags_are_rejected() {
        let mut source = sample();
        source.flags = 0x01;
        assert_eq!(
            source.encode(),
            Err(DmpInputError::UnsupportedFlags(0x01))
        );
    }

    #[test]
    fn malformed_size_is_rejected() {
        assert_eq!(
            DmpInputSample::decode(&[0; 39]),
            Err(DmpInputError::InvalidLength(39))
        );
    }
}
