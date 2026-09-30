#include "MftEncoderPumpState.h"

#include <limits>

namespace displaymesh::media {

const char* MftPumpPhaseName(
    MftPumpPhase phase) noexcept {
    switch (phase) {
    case MftPumpPhase::Stopped:
        return "stopped";
    case MftPumpPhase::Starting:
        return "starting";
    case MftPumpPhase::Running:
        return "running";
    case MftPumpPhase::Draining:
        return "draining";
    case MftPumpPhase::Failed:
        return "failed";
    }

    return "unknown";
}

bool MftEncoderPumpState::Begin(
    std::string& error) noexcept {
    if (phase_ != MftPumpPhase::Stopped) {
        return Reject("begin", error);
    }

    phase_ = MftPumpPhase::Starting;
    inputCredits_ = 0;
    outputSignals_ = 0;
    error.clear();
    return true;
}

bool MftEncoderPumpState::MarkStreamingReady(
    std::string& error) noexcept {
    if (phase_ != MftPumpPhase::Starting) {
        return Reject(
            "mark streaming ready",
            error);
    }

    phase_ = MftPumpPhase::Running;
    error.clear();
    return true;
}

bool MftEncoderPumpState::OnNeedInput(
    std::string& error) noexcept {
    if (phase_ != MftPumpPhase::Running) {
        return Reject(
            "accept NeedInput",
            error);
    }

    if (inputCredits_ ==
        std::numeric_limits<
            std::uint32_t>::max()) {
        return Reject(
            "accumulate NeedInput",
            error);
    }

    ++inputCredits_;
    ++stats_.needInputEvents;
    error.clear();
    return true;
}

bool MftEncoderPumpState::CanProcessInput()
    const noexcept {
    return phase_ == MftPumpPhase::Running &&
        inputCredits_ > 0;
}

bool MftEncoderPumpState::MarkInputSubmitted(
    std::string& error) noexcept {
    if (!CanProcessInput()) {
        return Reject(
            "submit input sample",
            error);
    }

    --inputCredits_;
    ++stats_.inputSamplesSubmitted;
    error.clear();
    return true;
}

bool MftEncoderPumpState::OnHaveOutput(
    std::string& error) noexcept {
    if (phase_ != MftPumpPhase::Running &&
        phase_ != MftPumpPhase::Draining) {
        return Reject(
            "accept HaveOutput",
            error);
    }

    if (outputSignals_ ==
        std::numeric_limits<
            std::uint32_t>::max()) {
        return Reject(
            "accumulate HaveOutput",
            error);
    }

    ++outputSignals_;
    ++stats_.haveOutputEvents;
    error.clear();
    return true;
}

bool MftEncoderPumpState::CanProcessOutput()
    const noexcept {
    return (phase_ == MftPumpPhase::Running ||
            phase_ == MftPumpPhase::Draining) &&
        outputSignals_ > 0;
}

bool MftEncoderPumpState::MarkOutputProduced(
    std::string& error) noexcept {
    if (!CanProcessOutput()) {
        return Reject(
            "produce output sample",
            error);
    }

    --outputSignals_;
    ++stats_.outputSamplesProduced;
    error.clear();
    return true;
}

bool MftEncoderPumpState::BeginDrain(
    std::string& error) noexcept {
    if (phase_ != MftPumpPhase::Running) {
        return Reject("begin drain", error);
    }

    phase_ = MftPumpPhase::Draining;

    // Any unused NeedInput credit becomes invalid once draining begins.
    inputCredits_ = 0;
    error.clear();
    return true;
}

bool MftEncoderPumpState::MarkDrainComplete(
    std::string& error) noexcept {
    if (phase_ != MftPumpPhase::Draining ||
        outputSignals_ != 0) {
        return Reject(
            "complete drain",
            error);
    }

    phase_ = MftPumpPhase::Stopped;
    inputCredits_ = 0;
    outputSignals_ = 0;
    error.clear();
    return true;
}

void MftEncoderPumpState::Fail() noexcept {
    phase_ = MftPumpPhase::Failed;
    inputCredits_ = 0;
    outputSignals_ = 0;
}

void MftEncoderPumpState::Reset() noexcept {
    phase_ = MftPumpPhase::Stopped;
    inputCredits_ = 0;
    outputSignals_ = 0;
    stats_ = {};
}

MftPumpPhase
MftEncoderPumpState::Phase() const noexcept {
    return phase_;
}

MftPumpStats
MftEncoderPumpState::Stats() const noexcept {
    return stats_;
}

std::uint32_t
MftEncoderPumpState::InputCredits()
    const noexcept {
    return inputCredits_;
}

std::uint32_t
MftEncoderPumpState::OutputSignals()
    const noexcept {
    return outputSignals_;
}

bool MftEncoderPumpState::Reject(
    const char* operation,
    std::string& error) noexcept {
    ++stats_.rejectedTransitions;
    error =
        std::string(operation) +
        " is invalid while MFT pump is " +
        MftPumpPhaseName(phase_);
    return false;
}

}  // namespace displaymesh::media
