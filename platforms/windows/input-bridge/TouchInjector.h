#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>

#include <cstdint>
#include <string>
#include <unordered_map>

#include "DmpInput.h"

namespace displaymesh {

class TouchInjector {
public:
    TouchInjector() = default;

    bool Initialize(
        const RECT& targetRect,
        std::uint32_t maximumContacts,
        std::string& error);

    bool Inject(const InputSample& sample, std::string& error);
    void CancelAll();

private:
    struct ContactState {
        InputSample sample;
        POINT location{};
    };

    RECT targetRect_{};
    std::uint32_t maximumContacts_{};
    bool initialized_{};
    std::unordered_map<std::uint32_t, ContactState> activeContacts_;

    POINT MapToDesktop(float normalizedX, float normalizedY) const;

    POINTER_TOUCH_INFO BuildTouchInfo(
        std::uint32_t contactId,
        const ContactState& state,
        POINTER_FLAGS flags) const;

    bool InjectFrame(
        std::uint32_t changedContactId,
        POINTER_FLAGS changedFlags,
        bool cancelled,
        std::string& error);
};

}  // namespace displaymesh
