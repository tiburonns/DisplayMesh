#pragma once

#include <array>
#include <atomic>
#include <cstdint>
#include <optional>

namespace displaymesh::bridge {

inline constexpr std::uint32_t kFrameMailboxSlotCount = 3;

struct FrameAnnouncement {
    std::uint64_t sequence{};
    std::uint64_t timestampMicros{};
    std::uint64_t surfaceGeneration{};
    std::uint32_t slotIndex{};
    std::uint32_t width{};
    std::uint32_t height{};
};

struct ConsumedFrame {
    FrameAnnouncement frame{};
    std::uint64_t droppedBefore{};
};

class LatestFrameMailbox {
public:
    bool Publish(
        std::uint64_t sequence,
        std::uint64_t timestampMicros,
        std::uint64_t surfaceGeneration,
        std::uint32_t width,
        std::uint32_t height) noexcept {
        if (sequence == 0 ||
            surfaceGeneration == 0 ||
            width == 0 ||
            height == 0) {
            return false;
        }

        const auto slotIndex =
            static_cast<std::uint32_t>(
                sequence % kFrameMailboxSlotCount);
        auto& slot = slots_[slotIndex];

        const std::uint64_t version =
            slot.version.load(
                std::memory_order_relaxed);

        slot.version.store(
            version + 1,
            std::memory_order_release);

        slot.sequence.store(
            sequence,
            std::memory_order_relaxed);
        slot.timestampMicros.store(
            timestampMicros,
            std::memory_order_relaxed);
        slot.surfaceGeneration.store(
            surfaceGeneration,
            std::memory_order_relaxed);
        slot.width.store(
            width,
            std::memory_order_relaxed);
        slot.height.store(
            height,
            std::memory_order_relaxed);

        slot.version.store(
            version + 2,
            std::memory_order_release);

        const std::uint64_t token =
            (sequence << 2) |
            static_cast<std::uint64_t>(
                slotIndex);

        publishedToken_.store(
            token,
            std::memory_order_release);

        return true;
    }

    std::optional<ConsumedFrame>
    TryConsumeAfter(
        std::uint64_t lastSequence) const noexcept {
        for (int attempt = 0;
             attempt < 4;
             ++attempt) {
            const std::uint64_t token =
                publishedToken_.load(
                    std::memory_order_acquire);

            if (token == 0) {
                return std::nullopt;
            }

            const std::uint64_t sequence =
                token >> 2;
            const auto slotIndex =
                static_cast<std::uint32_t>(
                    token & 0x3ULL);

            if (sequence <= lastSequence ||
                slotIndex >= kFrameMailboxSlotCount) {
                return std::nullopt;
            }

            const auto& slot =
                slots_[slotIndex];

            const std::uint64_t before =
                slot.version.load(
                    std::memory_order_acquire);

            if ((before & 1ULL) != 0) {
                continue;
            }

            FrameAnnouncement frame{};
            frame.sequence =
                slot.sequence.load(
                    std::memory_order_relaxed);
            frame.timestampMicros =
                slot.timestampMicros.load(
                    std::memory_order_relaxed);
            frame.surfaceGeneration =
                slot.surfaceGeneration.load(
                    std::memory_order_relaxed);
            frame.slotIndex = slotIndex;
            frame.width =
                slot.width.load(
                    std::memory_order_relaxed);
            frame.height =
                slot.height.load(
                    std::memory_order_relaxed);

            const std::uint64_t after =
                slot.version.load(
                    std::memory_order_acquire);

            if (before != after ||
                (after & 1ULL) != 0 ||
                frame.sequence != sequence) {
                continue;
            }

            const std::uint64_t dropped =
                sequence > lastSequence + 1
                    ? sequence -
                        lastSequence -
                        1
                    : 0;

            return ConsumedFrame{
                frame,
                dropped,
            };
        }

        return std::nullopt;
    }

    std::uint64_t LatestSequence()
        const noexcept {
        return publishedToken_.load(
                   std::memory_order_acquire) >>
            2;
    }

private:
    struct Slot {
        std::atomic<std::uint64_t>
            version{0};
        std::atomic<std::uint64_t>
            sequence{0};
        std::atomic<std::uint64_t>
            timestampMicros{0};
        std::atomic<std::uint64_t>
            surfaceGeneration{0};
        std::atomic<std::uint32_t>
            width{0};
        std::atomic<std::uint32_t>
            height{0};
    };

    static_assert(
        std::atomic<std::uint64_t>::
            is_always_lock_free,
        "DisplayMesh requires lock-free 64-bit atomics on supported Windows targets");

    std::array<
        Slot,
        kFrameMailboxSlotCount>
        slots_{};

    std::atomic<std::uint64_t>
        publishedToken_{0};
};

}  // namespace displaymesh::bridge
