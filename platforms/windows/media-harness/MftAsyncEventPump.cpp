#include "MftAsyncEventPump.h"

#include <mferror.h>

#include <cstdio>

namespace displaymesh::media {
namespace {

std::string HrMessage(
    const char* operation,
    HRESULT hr) {
    char buffer[160]{};
    sprintf_s(
        buffer,
        "%s failed: 0x%08lX",
        operation,
        static_cast<unsigned long>(hr));
    return buffer;
}

}  // namespace

MftAsyncEventPump::
MftAsyncEventPump(
    LiveEncodeCoordinator& coordinator)
    noexcept
    : coordinator_(coordinator) {}

HRESULT MftAsyncEventPump::Start(
    IMFTransform* transform) noexcept {
    if (transform == nullptr) {
        return E_POINTER;
    }

    Microsoft::WRL::ComPtr<
        IMFMediaEventGenerator> generator;
    HRESULT hr =
        transform->QueryInterface(
            IID_PPV_ARGS(&generator));
    if (FAILED(hr)) {
        Fail(
            HrMessage(
                "Query IMFMediaEventGenerator",
                hr));
        return hr;
    }

    {
        std::lock_guard lock(mutex_);
        if (running_) {
            return MF_E_INVALIDREQUEST;
        }

        generator_ =
            std::move(generator);
        lastError_.clear();
        running_ = true;
    }

    hr = ArmNext();
    if (FAILED(hr)) {
        Fail(
            HrMessage(
                "BeginGetEvent",
                hr));
    }
    return hr;
}

void MftAsyncEventPump::Stop()
    noexcept {
    std::lock_guard lock(mutex_);
    running_ = false;
    generator_.Reset();
}

bool MftAsyncEventPump::IsRunning()
    const noexcept {
    std::lock_guard lock(mutex_);
    return running_;
}

std::string
MftAsyncEventPump::LastError()
    const {
    std::lock_guard lock(mutex_);
    return lastError_;
}

STDMETHODIMP
MftAsyncEventPump::GetParameters(
    DWORD*,
    DWORD*) {
    return E_NOTIMPL;
}

STDMETHODIMP
MftAsyncEventPump::Invoke(
    IMFAsyncResult* result) {
    if (result == nullptr) {
        Fail(
            "Media Foundation event callback received null result");
        return E_POINTER;
    }

    Microsoft::WRL::ComPtr<
        IMFMediaEventGenerator> generator;
    {
        std::lock_guard lock(mutex_);
        if (!running_ ||
            generator_ == nullptr) {
            return S_OK;
        }
        generator = generator_;
    }

    Microsoft::WRL::ComPtr<
        IMFMediaEvent> event;
    HRESULT hr =
        generator->EndGetEvent(
            result,
            &event);
    if (FAILED(hr)) {
        Fail(
            HrMessage(
                "EndGetEvent",
                hr));
        return hr;
    }

    MediaEventType type = MEUnknown;
    hr = event->GetType(&type);
    if (FAILED(hr)) {
        Fail(
            HrMessage(
                "IMFMediaEvent::GetType",
                hr));
        return hr;
    }

    HRESULT eventStatus = S_OK;
    hr = event->GetStatus(
        &eventStatus);
    if (FAILED(hr)) {
        Fail(
            HrMessage(
                "IMFMediaEvent::GetStatus",
                hr));
        return hr;
    }

    if (FAILED(eventStatus)) {
        Fail(
            HrMessage(
                "Media Foundation transform event",
                eventStatus));
        return eventStatus;
    }

    std::string coordinatorError;
    bool accepted = true;

    switch (type) {
    case METransformNeedInput:
        accepted =
            coordinator_.OnNeedInput(
                coordinatorError);
        break;

    case METransformHaveOutput:
        accepted =
            coordinator_.OnHaveOutput(
                coordinatorError);
        break;

    case METransformDrainComplete:
        accepted =
            coordinator_.MarkDrainComplete(
                coordinatorError);
        break;

    case MEError:
        accepted = false;
        coordinatorError =
            "Media Foundation transform emitted MEError";
        break;

    default:
        break;
    }

    if (!accepted) {
        Fail(
            coordinatorError.empty()
                ? "Media Foundation event was rejected by live encode coordinator"
                : coordinatorError);
        return E_FAIL;
    }

    hr = ArmNext();
    if (FAILED(hr)) {
        Fail(
            HrMessage(
                "BeginGetEvent",
                hr));
    }
    return hr;
}

HRESULT MftAsyncEventPump::ArmNext()
    noexcept {
    Microsoft::WRL::ComPtr<
        IMFMediaEventGenerator> generator;

    {
        std::lock_guard lock(mutex_);
        if (!running_ ||
            generator_ == nullptr) {
            return MF_E_SHUTDOWN;
        }
        generator = generator_;
    }

    return generator->BeginGetEvent(
        this,
        nullptr);
}

void MftAsyncEventPump::Fail(
    const std::string& message)
    noexcept {
    std::lock_guard lock(mutex_);
    lastError_ = message;
    running_ = false;
    generator_.Reset();
}

}  // namespace displaymesh::media
