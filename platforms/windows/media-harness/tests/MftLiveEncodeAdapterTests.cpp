#include "MftLiveEncodeAdapter.h"

#include <Windows.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mftransform.h>
#include <wrl.h>

#include <atomic>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;
using namespace displaymesh::media;

namespace {

class MfGuard {
public:
    MfGuard() {
        result =
            MFStartup(
                MF_VERSION,
                MFSTARTUP_FULL);
    }

    ~MfGuard() {
        if (SUCCEEDED(result)) {
            MFShutdown();
        }
    }

    HRESULT result{};
};

class FakeTransform final
    : public IMFTransform {
public:
    enum class OutputMode {
        NeedInput,
        ProduceAnnexB,
        Fail,
    };

    explicit FakeTransform(
        bool acceptInput = true,
        OutputMode outputMode =
            OutputMode::NeedInput)
        : acceptInput_(acceptInput),
          outputMode_(outputMode) {}

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
                static_cast<IMFTransform*>(this);
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
        DWORD outputCount,
        MFT_OUTPUT_DATA_BUFFER* output,
        DWORD* status)
        override {
        ++outputCalls;

        if (outputMode_ ==
            OutputMode::NeedInput) {
            return
                MF_E_TRANSFORM_NEED_MORE_INPUT;
        }

        if (outputMode_ ==
            OutputMode::Fail) {
            return E_FAIL;
        }

        if (outputCount != 1 ||
            output == nullptr ||
            status == nullptr ||
            output->pSample == nullptr) {
            return E_INVALIDARG;
        }

        ComPtr<IMFMediaBuffer> buffer;
        HRESULT hr =
            output->pSample->GetBufferByIndex(
                0,
                &buffer);
        if (FAILED(hr)) {
            return hr;
        }

        const std::vector<std::uint8_t>
            annexB{
                0, 0, 0, 1,
                0x67, 0x64, 0, 0x1f,
                0, 0, 0, 1,
                0x68, 0xee, 0x3c, 0x80,
                0, 0, 0, 1,
                0x65, 0x88, 0x84,
            };

        BYTE* destination = nullptr;
        DWORD maximum = 0;
        DWORD current = 0;
        hr = buffer->Lock(
            &destination,
            &maximum,
            &current);
        if (FAILED(hr)) {
            return hr;
        }

        if (maximum < annexB.size()) {
            buffer->Unlock();
            return E_OUTOFMEMORY;
        }

        std::memcpy(
            destination,
            annexB.data(),
            annexB.size());
        buffer->Unlock();

        hr = buffer->SetCurrentLength(
            static_cast<DWORD>(
                annexB.size()));
        if (FAILED(hr)) {
            return hr;
        }

        hr = output->pSample->SetSampleTime(
            10'000);
        if (FAILED(hr)) {
            return hr;
        }

        hr = output->pSample->SetSampleDuration(
            166'670);
        if (FAILED(hr)) {
            return hr;
        }

        *status = 0;
        return S_OK;
    }

    std::uint64_t inputCalls{};
    std::uint64_t outputCalls{};

private:
    std::atomic<ULONG> references_{1};
    bool acceptInput_{};
    OutputMode outputMode_{};
};

EncodeWorkItem Item() {
    return EncodeWorkItem{
        3,
        1'000,
        16'667,
        1,
        0,
        1920,
        1080,
    };
}

HRESULT MakeInputSample(
    const EncodeWorkItem&,
    ComPtr<IMFSample>& sample) {
    return MFCreateSample(&sample);
}

void TestInputSubmitsConcreteSample() {
    auto* raw =
        new FakeTransform(true);
    ComPtr<IMFTransform> transform;
    transform.Attach(raw);

    MftLiveEncodeAdapter adapter(
        transform.Get(),
        MakeInputSample,
        [](auto, const auto&, const auto&, std::string&) {
            return true;
        });

    std::string error;
    assert(adapter.IsReady());
    assert(adapter.ProcessInput(
        Item(),
        error));
    assert(error.empty());
    assert(raw->inputCalls == 1);
    assert(
        adapter.Stats()
            .inputSamplesSubmitted == 1);
    assert(
        adapter.Stats()
            .inputFailures == 0);
}

void TestInputFailureIsReported() {
    auto* raw =
        new FakeTransform(false);
    ComPtr<IMFTransform> transform;
    transform.Attach(raw);

    MftLiveEncodeAdapter adapter(
        transform.Get(),
        MakeInputSample,
        [](auto, const auto&, const auto&, std::string&) {
            return true;
        });

    std::string error;
    assert(!adapter.ProcessInput(
        Item(),
        error));
    assert(!error.empty());
    assert(raw->inputCalls == 1);
    assert(
        adapter.Stats()
            .inputFailures == 1);
}

void TestUnexpectedNeedMoreInputFailsClosed() {
    auto* raw =
        new FakeTransform(
            true,
            FakeTransform::OutputMode::NeedInput);
    ComPtr<IMFTransform> transform;
    transform.Attach(raw);

    MftLiveEncodeAdapter adapter(
        transform.Get(),
        MakeInputSample,
        [](auto, const auto&, const auto&, std::string&) {
            return true;
        });

    std::string error;
    assert(!adapter.ProcessOutput(error));
    assert(
        error.find("needs more input") !=
        std::string::npos);
    assert(raw->outputCalls == 1);
    assert(
        adapter.Stats()
            .outputFailures == 1);
}

void TestEncodedOutputReachesDmpHandler() {
    auto* raw =
        new FakeTransform(
            true,
            FakeTransform::OutputMode::ProduceAnnexB);
    ComPtr<IMFTransform> transform;
    transform.Attach(raw);

    bool called = false;
    std::vector<std::uint8_t> captured;

    MftLiveEncodeAdapter adapter(
        transform.Get(),
        MakeInputSample,
        [&](std::span<const std::uint8_t> payload,
            const H264NormalizeReport&,
            const H264PacketizeReport& report,
            std::string&) {
            called = true;
            captured.assign(
                payload.begin(),
                payload.end());
            assert(report.keyframe);
            return true;
        });

    std::string error;
    assert(adapter.ProcessOutput(error));
    assert(error.empty());
    assert(called);
    assert(captured.size() > 16);
    assert(captured[0] == 0x01);
    assert(captured[1] == 0x01);
    assert(
        adapter.Stats()
            .outputSamplesProduced == 1);
    assert(
        adapter.Stats()
            .keyframesProduced == 1);
}

void TestPacketHandlerFailureFailsClosed() {
    auto* raw =
        new FakeTransform(
            true,
            FakeTransform::OutputMode::ProduceAnnexB);
    ComPtr<IMFTransform> transform;
    transform.Attach(raw);

    MftLiveEncodeAdapter adapter(
        transform.Get(),
        MakeInputSample,
        [](auto, const auto&, const auto&, std::string& error) {
            error =
                "transport rejected packet";
            return false;
        });

    std::string error;
    assert(!adapter.ProcessOutput(error));
    assert(
        error ==
        "transport rejected packet");
    assert(
        adapter.Stats()
            .outputFailures == 1);
}

}  // namespace

int main() {
    MfGuard mf;
    assert(SUCCEEDED(mf.result));

    TestInputSubmitsConcreteSample();
    TestInputFailureIsReported();
    TestUnexpectedNeedMoreInputFailsClosed();
    TestEncodedOutputReachesDmpHandler();
    TestPacketHandlerFailureFailsClosed();
    return 0;
}
