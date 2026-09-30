#include "SharedSurfaceEncodeInput.h"

namespace displaymesh::media {

HRESULT SharedSurfaceEncodeInput::CreateSample(
    const EncodeWorkItem& item,
    Microsoft::WRL::ComPtr<IMFSample>&
        sample) noexcept {
    sample.Reset();

    const auto announcement =
        item.Announcement();

    if (item.durationMicros == 0 ||
        !pool_.Matches(announcement)) {
        return E_INVALIDARG;
    }

    const auto* slot =
        pool_.Slot(item.slotIndex);
    if (slot == nullptr ||
        slot->Descriptor().generation !=
            item.surfaceGeneration) {
        return E_INVALIDARG;
    }

    return factory_.CreateFromSharedHandle(
        slot->SharedHandle(),
        slot->Descriptor(),
        item.timestampMicros,
        item.durationMicros,
        sample);
}

}  // namespace displaymesh::media
