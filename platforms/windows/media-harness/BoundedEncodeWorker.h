#pragma once

#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <optional>
#include <thread>

#include "LatestFrameMailbox.h"

namespace displaymesh::media {

struct EncodeWorkItem {
    std::uint64_t sequence{};
    std::uint64_t timestampMicros{};
    std::uint32_t durationMicros{};
    std::uint64_t surfaceGeneration{};
    std::uint32_t slotIndex{};
    std::uint32_t width{};
    std::uint32_t height{};

    static EncodeWorkItem FromFrame(
        const bridge::FrameAnnouncement& frame,
        std::uint32_t durationMicros) noexcept {
        return EncodeWorkItem{
            frame.sequence,
            frame.timestampMicros,
            durationMicros,
            frame.surfaceGeneration,
            frame.slotIndex,
            frame.width,
            frame.height,
        };
    }

    bool IsValid() const noexcept {
        return sequence != 0 &&
            durationMicros != 0 &&
            surfaceGeneration != 0 &&
            slotIndex <
                bridge::kFrameMailboxSlotCount &&
            slotIndex ==
                static_cast<std::uint32_t>(
                    sequence %
                    bridge::kFrameMailboxSlotCount) &&
            width != 0 &&
            height != 0;
    }

    bridge::FrameAnnouncement
    Announcement() const noexcept {
        return bridge::FrameAnnouncement{
            sequence,
            timestampMicros,
            surfaceGeneration,
            slotIndex,
            width,
            height,
        };
    }
};

struct EncodeWorkerStats {
    std::uint64_t submitted{};
    std::uint64_t encoded{};
    std::uint64_t droppedPending{};
    std::uint64_t discardedOnStop{};
    std::uint64_t rejectedStale{};
    std::uint64_t rejectedInvalid{};
    std::uint64_t handlerFailures{};
};

class BoundedEncodeWorker {
public:
    using Handler =
        std::function<void(const EncodeWorkItem&)>;

    explicit BoundedEncodeWorker(Handler handler);
    ~BoundedEncodeWorker();

    BoundedEncodeWorker(
        const BoundedEncodeWorker&) = delete;
    BoundedEncodeWorker& operator=(
        const BoundedEncodeWorker&) = delete;

    bool Start();
    void Stop() noexcept;

    bool Submit(
        const EncodeWorkItem& item) noexcept;

    bool IsRunning() const noexcept;
    EncodeWorkerStats Stats() const noexcept;

private:
    void Run() noexcept;

    mutable std::mutex mutex_;
    std::condition_variable wake_;
    Handler handler_;
    std::thread worker_;
    std::optional<EncodeWorkItem> pending_;
    EncodeWorkerStats stats_{};
    std::uint64_t highestSubmittedSequence_{};
    bool running_{};
    bool stopRequested_{};
};

}  // namespace displaymesh::media
