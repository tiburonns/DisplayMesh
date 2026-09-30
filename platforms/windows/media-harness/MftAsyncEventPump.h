#pragma once

#define NOMINMAX
#include <Windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mftransform.h>
#include <wrl/client.h>
#include <wrl/implements.h>

#include <mutex>
#include <string>

#include "LiveEncodeCoordinator.h"

namespace displaymesh::media {

class MftAsyncEventPump final
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<
              Microsoft::WRL::ClassicCom>,
          IMFAsyncCallback> {
public:
    explicit MftAsyncEventPump(
        LiveEncodeCoordinator& coordinator)
        noexcept;

    HRESULT Start(
        IMFTransform* transform) noexcept;

    void Stop() noexcept;

    bool IsRunning() const noexcept;

    std::string LastError() const;

    STDMETHODIMP GetParameters(
        DWORD* flags,
        DWORD* queue) override;

    STDMETHODIMP Invoke(
        IMFAsyncResult* result) override;

private:
    HRESULT ArmNext() noexcept;

    void Fail(
        const std::string& message) noexcept;

    LiveEncodeCoordinator& coordinator_;

    mutable std::mutex mutex_;
    Microsoft::WRL::ComPtr<
        IMFMediaEventGenerator> generator_;
    std::string lastError_;
    bool running_{};
};

}  // namespace displaymesh::media
