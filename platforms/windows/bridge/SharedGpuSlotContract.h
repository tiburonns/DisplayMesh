#pragma once

#include <array>
#include <cstdint>
#include <optional>

#include "LatestFrameMailbox.h"

namespace displaymesh::bridge {

struct SharedGpuSurfaceDescriptor {
    std::uint32_t slotIndex{};
    std::uint64_t generation{};
    std::uint32_t width{};
    std::uint32_t height{};
    std::uint32_t dxgiFormat{};

    bool IsValid() const noexcept {
        return slotIndex < kFrameMailboxSlotCount &&
            generation != 0 &&
            width != 0 &&
            height != 0 &&
            dxgiFormat != 0;
    }
};

class SharedGpuSlotContract {
public:
    bool Register(
        const SharedGpuSurfaceDescriptor& descriptor) noexcept {
        if (!descriptor.IsValid()) {
            return false;
        }

        auto& current =
            slots_[descriptor.slotIndex];

        if (current.has_value() &&
            descriptor.generation <=
                current->generation) {
            return false;
        }

        current = descriptor;
        return true;
    }

    bool Matches(
        const FrameAnnouncement& frame) const noexcept {
        if (frame.slotIndex >=
            kFrameMailboxSlotCount ||
            frame.surfaceGeneration == 0) {
            return false;
        }

        const auto& descriptor =
            slots_[frame.slotIndex];
        if (!descriptor.has_value()) {
            return false;
        }

        return
            descriptor->generation ==
                frame.surfaceGeneration &&
            descriptor->width ==
                frame.width &&
            descriptor->height ==
                frame.height;
    }

    std::optional<
        SharedGpuSurfaceDescriptor>
    Descriptor(
        std::uint32_t slotIndex) const noexcept {
        if (slotIndex >=
            kFrameMailboxSlotCount) {
            return std::nullopt;
        }

        return slots_[slotIndex];
    }

    void Reset() noexcept {
        for (auto& slot : slots_) {
            slot.reset();
        }
    }

private:
    std::array<
        std::optional<
            SharedGpuSurfaceDescriptor>,
        kFrameMailboxSlotCount>
        slots_{};
};

}  // namespace displaymesh::bridge
