#pragma once

#include <cstdint>
#include <functional>
#include <mutex>
#include <optional>
#include <string>

#include "BoundedEncodeWorker.h"
#include "MftEncoderPumpState.h"

namespace displaymesh::media {

struct LiveEncodeCoordinatorStats {
    std::uint64_t framesOffered{};
    std::uint64_t framesScheduled{};
    std::uint64_t framesReplacedWaitingForCredit{};
    std::uint64_t inputHandlerFailures{};
    std::uint64_t outputHandlerFailures{};
    std::uint64_t outputsProcessed{};
};

class LiveEncodeCoordinator {
public:
    using InputHandler =
        std::function<bool(
            const EncodeWorkItem&,
            std::string&)>;
    using OutputHandler =
        std::function<bool(std::string&)>;

    LiveEncodeCoordinator(
        InputHandler inputHandler,
        OutputHandler outputHandler);

    ~LiveEncodeCoordinator();

    LiveEncodeCoordinator(
        const LiveEncodeCoordinator&) = delete;
    LiveEncodeCoordinator& operator=(
        const LiveEncodeCoordinator&) = delete;

    bool Start(std::string& error);
    void Stop() noexcept;

    bool OfferFrame(
        const EncodeWorkItem& item,
        std::string& error) noexcept;

    bool OnNeedInput(
        std::string& error) noexcept;

    bool OnHaveOutput(
        std::string& error) noexcept;

    bool BeginDrain(
        std::string& error) noexcept;

    bool MarkDrainComplete(
        std::string& error) noexcept;

    bool IsRunning() const noexcept;

    LiveEncodeCoordinatorStats
    Stats() const noexcept;

    EncodeWorkerStats
    WorkerStats() const noexcept;

    MftPumpStats
    PumpStats() const noexcept;

    MftPumpPhase
    PumpPhase() const noexcept;

    std::string
    LastError() const;

private:
    void ProcessInput(
        const EncodeWorkItem& item);

    bool ScheduleLatestLocked(
        std::string& error) noexcept;

    mutable std::mutex mutex_;
    InputHandler inputHandler_;
    OutputHandler outputHandler_;
    MftEncoderPumpState pump_;
    std::optional<EncodeWorkItem>
        waitingForCredit_;
    LiveEncodeCoordinatorStats stats_{};
    std::string lastWorkerError_;
    bool running_{};

    BoundedEncodeWorker worker_;
};

}  // namespace displaymesh::media
