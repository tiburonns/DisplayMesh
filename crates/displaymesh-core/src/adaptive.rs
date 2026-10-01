#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PerformanceProfile {
    Responsive,
    Balanced,
    Quality,
}

impl PerformanceProfile {
    pub const fn queue_budget_ms(self) -> f32 {
        match self {
            Self::Responsive => 18.0,
            Self::Balanced => 30.0,
            Self::Quality => 45.0,
        }
    }

    pub const fn stable_samples_before_upshift(self) -> u8 {
        match self {
            Self::Responsive => 8,
            Self::Balanced => 6,
            Self::Quality => 4,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LinkTelemetry {
    pub round_trip_ms: f32,
    pub packet_loss_percent: f32,
    pub send_queue_ms: f32,
    pub decode_ms: f32,
    pub rendered_fps: f32,
}

impl LinkTelemetry {
    pub fn is_valid(self) -> bool {
        self.round_trip_ms.is_finite()
            && self.packet_loss_percent.is_finite()
            && self.send_queue_ms.is_finite()
            && self.decode_ms.is_finite()
            && self.rendered_fps.is_finite()
            && self.round_trip_ms >= 0.0
            && (0.0..=100.0).contains(&self.packet_loss_percent)
            && self.send_queue_ms >= 0.0
            && self.decode_ms >= 0.0
            && self.rendered_fps >= 0.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AdaptationDecision {
    pub bitrate_mbps: u16,
    pub stream_scale_percent: u8,
    pub request_keyframe: bool,
}

#[derive(Debug, Clone)]
pub struct AdaptiveController {
    profile: PerformanceProfile,
    bitrate_mbps: u16,
    minimum_bitrate_mbps: u16,
    maximum_bitrate_mbps: u16,
    stream_scale_percent: u8,
    stable_samples: u8,
    stressed_samples: u8,
}

impl AdaptiveController {
    pub fn new(
        profile: PerformanceProfile,
        initial_bitrate_mbps: u16,
        minimum_bitrate_mbps: u16,
        maximum_bitrate_mbps: u16,
    ) -> Self {
        assert!(minimum_bitrate_mbps > 0);
        assert!(minimum_bitrate_mbps <= maximum_bitrate_mbps);

        Self {
            profile,
            bitrate_mbps: initial_bitrate_mbps.clamp(minimum_bitrate_mbps, maximum_bitrate_mbps),
            minimum_bitrate_mbps,
            maximum_bitrate_mbps,
            stream_scale_percent: 100,
            stable_samples: 0,
            stressed_samples: 0,
        }
    }

    pub const fn profile(&self) -> PerformanceProfile {
        self.profile
    }

    pub fn set_profile(&mut self, profile: PerformanceProfile) {
        self.profile = profile;
        self.stable_samples = 0;
        self.stressed_samples = 0;
    }

    pub fn update(&mut self, telemetry: LinkTelemetry, target_fps: u16) -> AdaptationDecision {
        if !telemetry.is_valid() || target_fps == 0 {
            return self.current(false);
        }

        let queue_budget = self.profile.queue_budget_ms();
        let fps_ratio = telemetry.rendered_fps / target_fps as f32;

        let severe_stress = telemetry.send_queue_ms > queue_budget * 2.0
            || telemetry.packet_loss_percent >= 5.0
            || telemetry.round_trip_ms >= 140.0;

        let stressed = severe_stress
            || telemetry.send_queue_ms > queue_budget
            || telemetry.packet_loss_percent >= 1.5
            || telemetry.round_trip_ms >= 80.0
            || telemetry.decode_ms > (1_000.0 / target_fps as f32) * 0.85
            || fps_ratio < 0.88;

        let healthy = telemetry.send_queue_ms < queue_budget * 0.35
            && telemetry.packet_loss_percent < 0.35
            && telemetry.round_trip_ms < 45.0
            && telemetry.decode_ms < (1_000.0 / target_fps as f32) * 0.55
            && fps_ratio >= 0.97;

        if stressed {
            self.stable_samples = 0;
            self.stressed_samples = self.stressed_samples.saturating_add(1);

            let reduction = if severe_stress { 25 } else { 12 };
            let reduced = self.bitrate_mbps.saturating_mul(100 - reduction) / 100;
            self.bitrate_mbps = reduced.max(self.minimum_bitrate_mbps);

            let mut request_keyframe = false;
            if severe_stress || self.stressed_samples >= 3 {
                let previous_scale = self.stream_scale_percent;
                self.stream_scale_percent = match self.stream_scale_percent {
                    100 => 85,
                    85 => 75,
                    75 => 67,
                    value => value,
                };

                request_keyframe = previous_scale != self.stream_scale_percent;
                self.stressed_samples = 0;
            }

            return self.current(request_keyframe);
        }

        if healthy {
            self.stressed_samples = 0;
            self.stable_samples = self.stable_samples.saturating_add(1);

            if self.stable_samples >= self.profile.stable_samples_before_upshift() {
                self.stable_samples = 0;

                if self.stream_scale_percent < 100 {
                    self.stream_scale_percent = match self.stream_scale_percent {
                        0..=67 => 75,
                        68..=75 => 85,
                        _ => 100,
                    };
                    return self.current(true);
                }

                let increase = (self.bitrate_mbps / 12).max(1);
                self.bitrate_mbps = self
                    .bitrate_mbps
                    .saturating_add(increase)
                    .min(self.maximum_bitrate_mbps);
            }

            return self.current(false);
        }

        self.stable_samples = 0;
        self.stressed_samples = 0;
        self.current(false)
    }

    fn current(&self, request_keyframe: bool) -> AdaptationDecision {
        AdaptationDecision {
            bitrate_mbps: self.bitrate_mbps,
            stream_scale_percent: self.stream_scale_percent,
            request_keyframe,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn healthy() -> LinkTelemetry {
        LinkTelemetry {
            round_trip_ms: 12.0,
            packet_loss_percent: 0.0,
            send_queue_ms: 2.0,
            decode_ms: 3.0,
            rendered_fps: 60.0,
        }
    }

    #[test]
    fn stressed_link_reduces_bitrate_before_quality_scale() {
        let mut controller = AdaptiveController::new(PerformanceProfile::Balanced, 30, 6, 60);

        let decision = controller.update(
            LinkTelemetry {
                send_queue_ms: 45.0,
                ..healthy()
            },
            60,
        );

        assert!(decision.bitrate_mbps < 30);
        assert_eq!(decision.stream_scale_percent, 100);
        assert!(!decision.request_keyframe);
    }

    #[test]
    fn persistent_stress_reduces_stream_scale_and_requests_keyframe() {
        let mut controller = AdaptiveController::new(PerformanceProfile::Balanced, 30, 6, 60);

        let stressed = LinkTelemetry {
            send_queue_ms: 40.0,
            packet_loss_percent: 2.0,
            ..healthy()
        };

        controller.update(stressed, 60);
        controller.update(stressed, 60);
        let decision = controller.update(stressed, 60);

        assert_eq!(decision.stream_scale_percent, 85);
        assert!(decision.request_keyframe);
    }

    #[test]
    fn stable_link_recovers_resolution_before_chasing_bitrate() {
        let mut controller = AdaptiveController::new(PerformanceProfile::Quality, 24, 6, 60);

        let severe = LinkTelemetry {
            send_queue_ms: 100.0,
            packet_loss_percent: 5.0,
            ..healthy()
        };

        let down = controller.update(severe, 60);
        assert_eq!(down.stream_scale_percent, 85);

        let mut recovered = down;
        for _ in 0..controller.profile().stable_samples_before_upshift() {
            recovered = controller.update(healthy(), 60);
        }

        assert_eq!(recovered.stream_scale_percent, 100);
        assert!(recovered.request_keyframe);
    }

    #[test]
    fn invalid_telemetry_does_not_change_controller() {
        let mut controller = AdaptiveController::new(PerformanceProfile::Responsive, 20, 4, 40);

        let decision = controller.update(
            LinkTelemetry {
                round_trip_ms: f32::NAN,
                ..healthy()
            },
            60,
        );

        assert_eq!(decision.bitrate_mbps, 20);
        assert_eq!(decision.stream_scale_percent, 100);
    }
}
