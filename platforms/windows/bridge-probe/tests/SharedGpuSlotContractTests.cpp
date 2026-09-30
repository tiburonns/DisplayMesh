#include <cassert>
#include <cstdint>

#include "../bridge/SharedGpuSlotContract.h"

using namespace displaymesh::bridge;

int main() {
    SharedGpuSlotContract contract;

    const SharedGpuSurfaceDescriptor first{
        1,
        1,
        1920,
        1080,
        87,
    };

    assert(first.IsValid());
    assert(contract.Register(first));
    assert(!contract.Register(first));

    FrameAnnouncement frame{};
    frame.sequence = 1;
    frame.timestampMicros = 1'000;
    frame.surfaceGeneration = 1;
    frame.slotIndex = 1;
    frame.width = 1920;
    frame.height = 1080;

    assert(contract.Matches(frame));

    // A resize/recreation must advance the surface generation.
    const SharedGpuSurfaceDescriptor resized{
        1,
        2,
        2560,
        1440,
        87,
    };
    assert(contract.Register(resized));

    // Old announcements can never consume the newly recreated slot.
    assert(!contract.Matches(frame));

    frame.surfaceGeneration = 2;
    frame.width = 2560;
    frame.height = 1440;
    assert(contract.Matches(frame));

    const auto descriptor =
        contract.Descriptor(1);
    assert(descriptor.has_value());
    assert(descriptor->generation == 2);

    assert(!contract.Register(
        SharedGpuSurfaceDescriptor{
            1,
            1,
            2560,
            1440,
            87,
        }));

    assert(!contract.Register(
        SharedGpuSurfaceDescriptor{
            3,
            3,
            2560,
            1440,
            87,
        }));

    contract.Reset();
    assert(!contract.Matches(frame));

    return 0;
}
