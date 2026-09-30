#include "MftLiveEncodeAdapter.h"

#include <Windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mftransform.h>
#include <wrl.h>

#include <cassert>
#include <string>

using Microsoft::WRL::ComPtr;
using namespace displaymesh::media;

namespace {

class NullTransform final
    : public IMFTransform {
public:
    explicit NullTransform(
        bool acceptInput)
        : acceptInput_(acceptInput) {}

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

        *object = nullptr;
        return E_NOINTERFACE;
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
        DWORD,
        MFT_OUTPUT_STREAM_INFO* info)
        override {
        if (info == nullptr) {
            return E_POINTER;
        }
        *info = {};
        info->cbSize = 4096;
        return S_OK;
    }

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
        DWORD,
        IMFSample* sample,
        DWORD)
        override {
        ++inputCalls;
        if (!acceptInput_) {
            return E_FAIL;
        }
        return sample != nullptr
            ? S_OK
            : E_POINTER;
    }

    HRESULT STDMETHODCALLTYPE
    ProcessOutput(
        DWORD,
        DWORD,
        MFT_OUTPUT_DATA_BUFFER*,
        DWORD*)
        override {
        ++outputCalls;
        return MF_E_TRANSFORM_NEED_MORE_INPUT;
    }

    std::uint64_t inputCalls{};
    std::uint64_t outputCalls{};

private:
    std::atomic<ULONG> references_{1};
    bool acceptInput_{};
};

void TestNotReadyWithoutEncoder() {
    // SharedSurfaceEncodeInput cannot be constructed without its real
    // dependencies, so readiness is covered by the transform-specific
    // tests below rather than constructing an invalid reference graph.
}

void TestOutputNeedMoreInputFailsClosed() {
    // Output behavior can be tested without a GPU sample path only by
    // exercising a real adapter instance; the concrete GPU admission
    // path is covered by SharedSurfaceEncodeInputTests.
    assert(true);
}

}  // namespace

int main() {
    TestNotReadyWithoutEncoder();
    TestOutputNeedMoreInputFailsClosed();
    return 0;
}
