#pragma once

#include <cstdint>
#include <string>

namespace displaymesh::media {

enum class MftPumpPhase {
    Stopped,
    Starting,
    Running,
    Draining,
    Failed,
};

const char* MftPumpPhaseName(
    MftPumpPhase phase) noexcept;

struct MftPumpStats {
    std::uint64_t needInputEvents{};
    std::uint64_t inputSamplesSubmitted{};
    std::uint64_t haveOutputEvents{};
    std::uint64_t outputSamplesProduced{};
    std::uint64_t rejectedTransitions{};
};

class MftEncoderPumpState {
public:
    bool Begin(std::string& error) noexcept;
    bool MarkStreamingReady(
        std::string& error) noexcept;

    bool OnNeedInput(
        std::string& error) noexcept;
    bool CanProcessInput() const noexcept;
    bool MarkInputSubmitted(
        std::string& error) noexcept;

    bool OnHaveOutput(
        std::string& error) noexcept;
    bool CanProcessOutput() const noexcept;
    bool MarkOutputProduced(
        std::string& error) noexcept;

    bool BeginDrain(
        std::string& error) noexcept;
    bool MarkDrainComplete(
        std::string& error) noexcept;

    void Fail() noexcept;
    void Reset() noexcept;

    MftPumpPhase Phase() const noexcept;
    MftPumpStats Stats() const noexcept;
    std::uint32_t InputCredits() const noexcept;
    std::uint32_t OutputSignals() const noexcept;

private:
    bool Reject(
        const char* operation,
        std::string& error) noexcept;

    MftPumpPhase phase_{MftPumpPhase::Stopped};
    MftPumpStats stats_{};
    std::uint32_t inputCredits_{};
    std::uint32_t outputSignals_{};
};

}  // namespace displaymesh::media
