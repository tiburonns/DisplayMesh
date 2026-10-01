#include "MftAsyncEventPump.h"

#include <Windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mftransform.h>
#include <wrl.h>

#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <functional>
#include <string>
#include <thread>

using namespace displaymesh::media;
using namespace std::chrono_literals;

namespace {

bool WaitUntil(
    const std::function<bool()>& condition,
    std::chrono::milliseconds timeout =
        2s) {
    const auto deadline =
        std::chrono::steady_clock::now() +
        timeout;

    while (std::chrono::steady_clock::now() <
           deadline) {
        if (condition()) {
            return true;
        }
        std::this_thread::sleep_for(2ms);
    }

    return condition();
}

EncodeWorkItem Item(
    std::uint64_t sequence) {
    return EncodeWorkItem{
        sequence,
        sequence * 1'000,
        16'667,
        1,
        static_cast<std::uint32_t>(
            sequence %
            displaymesh::bridge::kFrameMailboxSlotCount),
        1920,
        1080,
    };
}

class FakeAsyncTransform final
    : public IMFTransform,
      public IMFMediaEventGenerator {
public:
    FakeAsyncTransform() {
        creationResult_ =
            MFCreateEventQueue(
                &queue_);
    }

    ~FakeAsyncTransform() {
        if (queue_ != nullptr) {
            queue_->Shutdown();
        }
    }

    HRESULT CreationResult()
        const noexcept {
        return creationResult_;
    }

    HRESULT Queue(
        MediaEventType type,
        HRESULT status = S_OK) {
        if (queue_ == nullptr) {
            return E_UNEXPECTED;
        }

        PROPVARIANT value;
        PropVariantInit(&value);
        const HRESULT hr =
            queue_->QueueEventParamVar(
                type,
                GUID_NULL,
                status,
                &value);
        PropVariantClear(&value);
        return hr;
    }

    ULONG STDMETHODCALLTYPE AddRef()
        override {
        return ++references_;
    }

    ULONG STDMETHODCALLTYPE Release()
        override {
        const ULONG remaining =
            --references_;
        if (remaining == 0) {
            delete this;
        }
        return remaining;
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(
        REFIID iid,
        void** object)
        override {
        if (object == nullptr) {
            return E_POINTER;
        }

        if (iid == __uuidof(IUnknown) ||
            iid == __uuidof(IMFTransform)) {
            *object =
                static_cast<IMFTransform*>(
                    this);
            AddRef();
            return S_OK;
        }

        if (iid ==
            __uuidof(IMFMediaEventGenerator)) {
            *object =
                static_cast<
                    IMFMediaEventGenerator*>(
                        this);
            AddRef();
            return S_OK;
        }

        *object = nullptr;
        return E_NOINTERFACE;
    }

    HRESULT STDMETHODCALLTYPE
    GetEvent(
        DWORD flags,
        IMFMediaEvent** event)
        override {
        return queue_->GetEvent(
            flags,
            event);
    }

    HRESULT STDMETHODCALLTYPE
    BeginGetEvent(
        IMFAsyncCallback* callback,
        IUnknown* state)
        override {
        return queue_->BeginGetEvent(
            callback,
            state);
    }

    HRESULT STDMETHODCALLTYPE
    EndGetEvent(
        IMFAsyncResult* result,
        IMFMediaEvent** event)
        override {
        return queue_->EndGetEvent(
            result,
            event);
    }

    HRESULT STDMETHODCALLTYPE
    QueueEvent(
        MediaEventType type,
        REFGUID extendedType,
        HRESULT status,
        const PROPVARIANT* value)
        override {
        return queue_->QueueEventParamVar(
            type,
            extendedType,
            status,
            value);
    }

    HRESULT STDMETHODCALLTYPE
    GetStreamLimits(
        DWORD*, DWORD*, DWORD*, DWORD*)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetStreamCount(
        DWORD*, DWORD*)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetStreamIDs(
        DWORD, DWORD*, DWORD, DWORD*)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetInputStreamInfo(
        DWORD, MFT_INPUT_STREAM_INFO*)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetOutputStreamInfo(
        DWORD, MFT_OUTPUT_STREAM_INFO*)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetAttributes(
        IMFAttributes**)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetInputStreamAttributes(
        DWORD, IMFAttributes**)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetOutputStreamAttributes(
        DWORD, IMFAttributes**)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    DeleteInputStream(
        DWORD)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    AddInputStreams(
        DWORD, DWORD*)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetInputAvailableType(
        DWORD, DWORD, IMFMediaType**)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetOutputAvailableType(
        DWORD, DWORD, IMFMediaType**)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    SetInputType(
        DWORD, IMFMediaType*, DWORD)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    SetOutputType(
        DWORD, IMFMediaType*, DWORD)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetInputCurrentType(
        DWORD, IMFMediaType**)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetOutputCurrentType(
        DWORD, IMFMediaType**)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetInputStatus(
        DWORD, DWORD*)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    GetOutputStatus(
        DWORD*)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    SetOutputBounds(
        LONGLONG, LONGLONG)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    ProcessEvent(
        DWORD, IMFMediaEvent*)
        override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE
    ProcessMessage(
        MFT_MESSAGE_TYPE,
        ULONG_PTR)
        override { return S_OK; }
    HRESULT STDMETHODCALLTYPE
    ProcessInput(
        DWORD, IMFSample*, DWORD)
        override { return S_OK; }
    HRESULT STDMETHODCALLTYPE
    ProcessOutput(
        DWORD,
        DWORD,
        MFT_OUTPUT_DATA_BUFFER*,
        DWORD*)
        override { return E_NOTIMPL; }

private:
    std::atomic<ULONG>
        references_{1};
    HRESULT creationResult_{E_FAIL};
    Microsoft::WRL::ComPtr<
        IMFMediaEventQueue> queue_;
};

void TestNullTransformFails() {
    LiveEncodeCoordinator coordinator(
        [](const EncodeWorkItem&,
           std::string&) {
            return true;
        },
        [](std::string&) {
            return true;
        });

    std::string error;
    assert(coordinator.Start(error));

    auto pump =
        Microsoft::WRL::Make<
            MftAsyncEventPump>(
                coordinator);

    assert(pump != nullptr);
    assert(
        pump->Start(nullptr) ==
        E_POINTER);
    assert(!pump->IsRunning());

    coordinator.Stop();
}

void TestAsyncEventsDriveCoordinator() {
    std::atomic<int> inputCalls{0};
    std::atomic<int> outputCalls{0};

    LiveEncodeCoordinator coordinator(
        [&](const EncodeWorkItem&,
            std::string&) {
            ++inputCalls;
            return true;
        },
        [&](std::string&) {
            ++outputCalls;
            return true;
        });

    std::string error;
    assert(coordinator.Start(error));
    assert(
        coordinator.OfferFrame(
            Item(1),
            error));

    auto* raw =
        new FakeAsyncTransform();
    assert(SUCCEEDED(
        raw->CreationResult()));

    Microsoft::WRL::ComPtr<
        IMFTransform> transform;
    transform.Attach(
        static_cast<IMFTransform*>(raw));

    auto pump =
        Microsoft::WRL::Make<
            MftAsyncEventPump>(
                coordinator);
    assert(pump != nullptr);
    assert(SUCCEEDED(
        pump->Start(
            transform.Get())));
    assert(pump->IsRunning());

    assert(SUCCEEDED(
        raw->Queue(
            METransformNeedInput)));
    assert(WaitUntil([&] {
        return inputCalls.load() == 1;
    }));

    assert(SUCCEEDED(
        raw->Queue(
            METransformHaveOutput)));
    assert(WaitUntil([&] {
        return outputCalls.load() == 1;
    }));

    assert(
        coordinator.BeginDrain(
            error));
    assert(
        coordinator.PumpPhase() ==
        MftPumpPhase::Draining);

    assert(SUCCEEDED(
        raw->Queue(
            METransformDrainComplete)));

    assert(WaitUntil([&] {
        return coordinator
            .PumpPhase() ==
            MftPumpPhase::Stopped;
    }));

    assert(pump->IsRunning());
    assert(pump->LastError().empty());

    pump->Stop();
    coordinator.Stop();
}

void TestEventFailureStopsPump() {
    LiveEncodeCoordinator coordinator(
        [](const EncodeWorkItem&,
           std::string&) {
            return true;
        },
        [](std::string&) {
            return true;
        });

    std::string error;
    assert(coordinator.Start(error));

    auto* raw =
        new FakeAsyncTransform();
    assert(SUCCEEDED(
        raw->CreationResult()));

    Microsoft::WRL::ComPtr<
        IMFTransform> transform;
    transform.Attach(
        static_cast<IMFTransform*>(raw));

    auto pump =
        Microsoft::WRL::Make<
            MftAsyncEventPump>(
                coordinator);
    assert(SUCCEEDED(
        pump->Start(
            transform.Get())));

    assert(SUCCEEDED(
        raw->Queue(
            MEError,
            E_FAIL)));

    assert(WaitUntil([&] {
        return !pump->IsRunning();
    }));
    assert(!pump->LastError().empty());

    coordinator.Stop();
}

}  // namespace

int main() {
    assert(SUCCEEDED(
        MFStartup(
            MF_VERSION,
            MFSTARTUP_FULL)));

    TestNullTransformFails();
    TestAsyncEventsDriveCoordinator();
    TestEventFailureStopsPump();

    MFShutdown();
    return 0;
}
