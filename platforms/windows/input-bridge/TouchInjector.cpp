#include "TouchInjector.h"

#include <algorithm>
#include <cmath>
#include <vector>

namespace displaymesh {

bool TouchInjector::Initialize(
    const RECT& targetRect,
    std::uint32_t maximumContacts,
    std::string& error) {
    if (targetRect.right <= targetRect.left ||
        targetRect.bottom <= targetRect.top) {
        error = "target display rectangle is invalid";
        return false;
    }

    if (maximumContacts == 0 || maximumContacts > MAX_TOUCH_COUNT) {
        error = "maximum contact count is outside the Windows touch limit";
        return false;
    }

    if (!InitializeTouchInjection(maximumContacts, TOUCH_FEEDBACK_NONE)) {
        error = "InitializeTouchInjection failed with Win32 error " +
                std::to_string(GetLastError());
        return false;
    }

    targetRect_ = targetRect;
    maximumContacts_ = maximumContacts;
    activeContacts_.clear();
    initialized_ = true;
    error.clear();
    return true;
}

bool TouchInjector::Inject(
    const InputSample& sample,
    std::string& error) {
    if (!initialized_) {
        error = "touch injector is not initialized";
        return false;
    }

    if (sample.kind != InputKind::Touch &&
        sample.kind != InputKind::Pencil) {
        error = "unsupported pointer kind";
        return false;
    }

    const auto existing = activeContacts_.find(sample.contactId);

    switch (sample.phase) {
    case InputPhase::Began: {
        if (existing != activeContacts_.end()) {
            error = "contact began twice without ending";
            return false;
        }

        if (activeContacts_.size() >= maximumContacts_) {
            error = "active touch contact limit reached";
            return false;
        }

        ContactState state{sample, MapToDesktop(
            sample.normalizedX,
            sample.normalizedY)};
        activeContacts_.emplace(sample.contactId, state);

        if (!InjectFrame(
                sample.contactId,
                POINTER_FLAG_DOWN |
                    POINTER_FLAG_INRANGE |
                    POINTER_FLAG_INCONTACT,
                false,
                error)) {
            activeContacts_.erase(sample.contactId);
            return false;
        }
        return true;
    }

    case InputPhase::Moved:
    case InputPhase::Hover: {
        if (existing == activeContacts_.end()) {
            error = "contact update arrived before contact began";
            return false;
        }

        existing->second.sample = sample;
        existing->second.location = MapToDesktop(
            sample.normalizedX,
            sample.normalizedY);

        const POINTER_FLAGS flags =
            sample.phase == InputPhase::Hover
                ? POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE
                : POINTER_FLAG_UPDATE |
                    POINTER_FLAG_INRANGE |
                    POINTER_FLAG_INCONTACT;

        return InjectFrame(
            sample.contactId,
            flags,
            false,
            error);
    }

    case InputPhase::Ended:
    case InputPhase::Cancelled: {
        if (existing == activeContacts_.end()) {
            error = "contact ended before contact began";
            return false;
        }

        const POINT finalLocation = MapToDesktop(
            sample.normalizedX,
            sample.normalizedY);

        if (finalLocation.x != existing->second.location.x ||
            finalLocation.y != existing->second.location.y) {
            existing->second.sample = sample;
            existing->second.location = finalLocation;

            if (!InjectFrame(
                    sample.contactId,
                    POINTER_FLAG_UPDATE |
                        POINTER_FLAG_INRANGE |
                        POINTER_FLAG_INCONTACT,
                    false,
                    error)) {
                return false;
            }
        }

        const bool cancelled =
            sample.phase == InputPhase::Cancelled;
        const auto flags =
            POINTER_FLAG_UP |
            (cancelled ? POINTER_FLAG_CANCELED : POINTER_FLAG_NONE);

        if (!InjectFrame(
                sample.contactId,
                flags,
                cancelled,
                error)) {
            return false;
        }

        activeContacts_.erase(sample.contactId);
        return true;
    }
    }

    error = "unsupported input phase";
    return false;
}

void TouchInjector::CancelAll() {
    if (!initialized_ || activeContacts_.empty()) {
        activeContacts_.clear();
        return;
    }

    std::vector<POINTER_TOUCH_INFO> contacts;
    contacts.reserve(activeContacts_.size());

    for (const auto& [contactId, state] : activeContacts_) {
        contacts.push_back(
            BuildTouchInfo(
                contactId,
                state,
                POINTER_FLAG_UP | POINTER_FLAG_CANCELED));
    }

    InjectTouchInput(
        static_cast<UINT32>(contacts.size()),
        contacts.data());
    activeContacts_.clear();
}

POINT TouchInjector::MapToDesktop(
    float normalizedX,
    float normalizedY) const {
    const LONG width = targetRect_.right - targetRect_.left;
    const LONG height = targetRect_.bottom - targetRect_.top;

    POINT point{};
    point.x = targetRect_.left + static_cast<LONG>(
        std::lround(
            std::clamp(normalizedX, 0.0F, 1.0F) *
            static_cast<float>(std::max<LONG>(width - 1, 0))));
    point.y = targetRect_.top + static_cast<LONG>(
        std::lround(
            std::clamp(normalizedY, 0.0F, 1.0F) *
            static_cast<float>(std::max<LONG>(height - 1, 0))));
    return point;
}

POINTER_TOUCH_INFO TouchInjector::BuildTouchInfo(
    std::uint32_t contactId,
    const ContactState& state,
    POINTER_FLAGS flags) const {
    POINTER_TOUCH_INFO info{};
    info.pointerInfo.pointerType = PT_TOUCH;
    info.pointerInfo.pointerId = contactId + 1;
    info.pointerInfo.pointerFlags = flags;
    info.pointerInfo.ptPixelLocation = state.location;

    info.touchFlags = TOUCH_FLAG_NONE;
    info.touchMask =
        TOUCH_MASK_CONTACTAREA |
        TOUCH_MASK_ORIENTATION |
        TOUCH_MASK_PRESSURE;

    constexpr LONG radius = 2;
    info.rcContact = {
        state.location.x - radius,
        state.location.y - radius,
        state.location.x + radius,
        state.location.y + radius,
    };
    info.rcContactRaw = info.rcContact;
    info.orientation = 90;

    const float normalizedPressure =
        state.sample.pressure > 0
            ? state.sample.pressure
            : 0.5F;
    info.pressure = static_cast<UINT32>(
        std::lround(
            std::clamp(normalizedPressure, 0.0F, 1.0F) *
            1024.0F));

    return info;
}

bool TouchInjector::InjectFrame(
    std::uint32_t changedContactId,
    POINTER_FLAGS changedFlags,
    bool cancelled,
    std::string& error) {
    std::vector<POINTER_TOUCH_INFO> contacts;
    contacts.reserve(activeContacts_.size());

    for (const auto& [contactId, state] : activeContacts_) {
        POINTER_FLAGS flags =
            POINTER_FLAG_UPDATE |
            POINTER_FLAG_INRANGE |
            POINTER_FLAG_INCONTACT;

        if (contactId == changedContactId) {
            flags = changedFlags;
            if (cancelled) {
                flags |= POINTER_FLAG_CANCELED;
            }
        }

        contacts.push_back(
            BuildTouchInfo(contactId, state, flags));
    }

    if (contacts.empty()) {
        error.clear();
        return true;
    }

    if (!InjectTouchInput(
            static_cast<UINT32>(contacts.size()),
            contacts.data())) {
        error = "InjectTouchInput failed with Win32 error " +
                std::to_string(GetLastError());
        return false;
    }

    error.clear();
    return true;
}

}  // namespace displaymesh
