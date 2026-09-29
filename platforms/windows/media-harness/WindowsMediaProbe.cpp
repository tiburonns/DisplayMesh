#include "WindowsMediaProbe.h"

#include <codecapi.h>
#include <d3d10.h>
#include <mfapi.h>
#include <mferror.h>
#include <mftransform.h>
#include <OleAuto.h>

#include <algorithm>
#include <memory>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace displaymesh::media {
namespace {

class MfStartupGuard {
public:
    HRESULT Start() noexcept {
        const HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
        started_ = SUCCEEDED(hr);
        return hr;
    }

    ~MfStartupGuard() {
        if (started_) {
            MFShutdown();
        }
    }

private:
    bool started_{};
};

class ActivationArray {
public:
    ~ActivationArray() {
        for (UINT32 index = 0; index < count_; ++index) {
            if (items_[index] != nullptr) {
                items_[index]->Release();
            }
        }
        CoTaskMemFree(items_);
    }

    IMFActivate*** OutItems() noexcept { return &items_; }
    UINT32* OutCount() noexcept { return &count_; }
    IMFActivate** Items() const noexcept { return items_; }
    UINT32 Count() const noexcept { return count_; }

private:
    IMFActivate** items_{};
    UINT32 count_{};
};

HRESULT SetVideoTypeCommon(
    IMFMediaType* type,
    const GUID& subtype,
    const ProbeConfig& config) noexcept {
    HRESULT hr = type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    if (FAILED(hr)) return hr;

    hr = type->SetGUID(MF_MT_SUBTYPE, subtype);
    if (FAILED(hr)) return hr;

    hr = MFSetAttributeSize(
        type,
        MF_MT_FRAME_SIZE,
        config.width,
        config.height);
    if (FAILED(hr)) return hr;

    hr = MFSetAttributeRatio(
        type,
        MF_MT_FRAME_RATE,
        config.framesPerSecond,
        1);
    if (FAILED(hr)) return hr;

    hr = MFSetAttributeRatio(
        type,
        MF_MT_PIXEL_ASPECT_RATIO,
        1,
        1);
    if (FAILED(hr)) return hr;

    return type->SetUINT32(
        MF_MT_INTERLACE_MODE,
        MFVideoInterlace_Progressive);
}

std::wstring ActivationName(IMFActivate* activation) {
    WCHAR* name = nullptr;
    UINT32 length = 0;

    if (FAILED(activation->GetAllocatedString(
            MFT_FRIENDLY_NAME_Attribute,
            &name,
            &length)) ||
        name == nullptr) {
        return L"<unnamed hardware H.264 encoder>";
    }

    std::wstring result(name, length);
    CoTaskMemFree(name);
    return result;
}

}  // namespace

HRESULT WindowsMediaProbe::Run(
    const ProbeConfig& config,
    ProbeReport& report) noexcept {
    report = {};

    if (config.width == 0 ||
        config.height == 0 ||
        config.framesPerSecond == 0 ||
        config.bitrateBitsPerSecond == 0) {
        return E_INVALIDARG;
    }

    MfStartupGuard mf;
    HRESULT hr = mf.Start();
    if (FAILED(hr)) return hr;

    hr = CreateDevice();
    if (FAILED(hr)) return hr;

    hr = CreateDeviceManager();
    if (FAILED(hr)) return hr;

    ComPtr<ID3D11Texture2D> bgra;
    ComPtr<ID3D11Texture2D> nv12;

    hr = CreateGpuConversionSurfaces(
        config,
        bgra,
        nv12);
    if (FAILED(hr)) return hr;

    hr = ConvertBgraToNv12(
        config,
        bgra.Get(),
        nv12.Get());
    if (FAILED(hr)) return hr;
    report.gpuBgraToNv12Ready = true;

    hr = ActivateHardwareH264Encoder(
        config,
        report);
    if (FAILED(hr)) return hr;

    hr = CreateDxgiSample(
        nv12.Get(),
        config);
    if (FAILED(hr)) return hr;

    report.dxgiSampleReady = true;
    return S_OK;
}

HRESULT WindowsMediaProbe::CreateDevice() noexcept {
    constexpr UINT flags =
        D3D11_CREATE_DEVICE_BGRA_SUPPORT |
        D3D11_CREATE_DEVICE_VIDEO_SUPPORT;

    D3D_FEATURE_LEVEL selected{};
    const D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_12_1,
        D3D_FEATURE_LEVEL_12_0,
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
    };

    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        flags,
        levels,
        ARRAYSIZE(levels),
        D3D11_SDK_VERSION,
        &device_,
        &selected,
        &context_);
    if (FAILED(hr)) {
        return hr;
    }

    ComPtr<ID3D10Multithread> multithread;
    if (SUCCEEDED(device_.As(&multithread))) {
        multithread->SetMultithreadProtected(TRUE);
    }

    return S_OK;
}

HRESULT WindowsMediaProbe::CreateDeviceManager() noexcept {
    HRESULT hr = MFCreateDXGIDeviceManager(
        &deviceManagerResetToken_,
        &deviceManager_);
    if (FAILED(hr)) return hr;

    return deviceManager_->ResetDevice(
        device_.Get(),
        deviceManagerResetToken_);
}

HRESULT WindowsMediaProbe::CreateGpuConversionSurfaces(
    const ProbeConfig& config,
    ComPtr<ID3D11Texture2D>& bgra,
    ComPtr<ID3D11Texture2D>& nv12) noexcept {
    D3D11_TEXTURE2D_DESC input{};
    input.Width = config.width;
    input.Height = config.height;
    input.MipLevels = 1;
    input.ArraySize = 1;
    input.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    input.SampleDesc.Count = 1;
    input.Usage = D3D11_USAGE_DEFAULT;
    input.BindFlags =
        D3D11_BIND_RENDER_TARGET |
        D3D11_BIND_SHADER_RESOURCE;

    HRESULT hr = device_->CreateTexture2D(
        &input,
        nullptr,
        &bgra);
    if (FAILED(hr)) return hr;

    D3D11_TEXTURE2D_DESC output = input;
    output.Format = DXGI_FORMAT_NV12;

    return device_->CreateTexture2D(
        &output,
        nullptr,
        &nv12);
}

HRESULT WindowsMediaProbe::ConvertBgraToNv12(
    const ProbeConfig& config,
    ID3D11Texture2D* bgra,
    ID3D11Texture2D* nv12) noexcept {
    ComPtr<ID3D11VideoDevice> videoDevice;
    HRESULT hr = device_.As(&videoDevice);
    if (FAILED(hr)) return hr;

    ComPtr<ID3D11VideoContext> videoContext;
    hr = context_.As(&videoContext);
    if (FAILED(hr)) return hr;

    D3D11_VIDEO_PROCESSOR_CONTENT_DESC content{};
    content.InputFrameFormat =
        D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
    content.InputFrameRate.Numerator =
        config.framesPerSecond;
    content.InputFrameRate.Denominator = 1;
    content.InputWidth = config.width;
    content.InputHeight = config.height;
    content.OutputFrameRate.Numerator =
        config.framesPerSecond;
    content.OutputFrameRate.Denominator = 1;
    content.OutputWidth = config.width;
    content.OutputHeight = config.height;
    content.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;

    ComPtr<ID3D11VideoProcessorEnumerator> enumerator;
    hr = videoDevice->CreateVideoProcessorEnumerator(
        &content,
        &enumerator);
    if (FAILED(hr)) return hr;

    ComPtr<ID3D11VideoProcessor> processor;
    hr = videoDevice->CreateVideoProcessor(
        enumerator.Get(),
        0,
        &processor);
    if (FAILED(hr)) return hr;

    D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC inputViewDesc{};
    inputViewDesc.ViewDimension =
        D3D11_VPIV_DIMENSION_TEXTURE2D;
    inputViewDesc.Texture2D.MipSlice = 0;
    inputViewDesc.Texture2D.ArraySlice = 0;

    ComPtr<ID3D11VideoProcessorInputView> inputView;
    hr = videoDevice->CreateVideoProcessorInputView(
        bgra,
        enumerator.Get(),
        &inputViewDesc,
        &inputView);
    if (FAILED(hr)) return hr;

    D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC outputViewDesc{};
    outputViewDesc.ViewDimension =
        D3D11_VPOV_DIMENSION_TEXTURE2D;
    outputViewDesc.Texture2D.MipSlice = 0;

    ComPtr<ID3D11VideoProcessorOutputView> outputView;
    hr = videoDevice->CreateVideoProcessorOutputView(
        nv12,
        enumerator.Get(),
        &outputViewDesc,
        &outputView);
    if (FAILED(hr)) return hr;

    const RECT source{
        0,
        0,
        static_cast<LONG>(config.width),
        static_cast<LONG>(config.height),
    };
    const RECT destination = source;

    videoContext->VideoProcessorSetStreamSourceRect(
        processor.Get(),
        0,
        TRUE,
        &source);
    videoContext->VideoProcessorSetStreamDestRect(
        processor.Get(),
        0,
        TRUE,
        &destination);
    videoContext->VideoProcessorSetOutputTargetRect(
        processor.Get(),
        TRUE,
        &destination);

    D3D11_VIDEO_PROCESSOR_STREAM stream{};
    stream.Enable = TRUE;
    stream.pInputSurface = inputView.Get();

    return videoContext->VideoProcessorBlt(
        processor.Get(),
        outputView.Get(),
        0,
        1,
        &stream);
}

HRESULT WindowsMediaProbe::ActivateHardwareH264Encoder(
    const ProbeConfig& config,
    ProbeReport& report) noexcept {
    MFT_REGISTER_TYPE_INFO inputType{
        MFMediaType_Video,
        MFVideoFormat_NV12,
    };
    MFT_REGISTER_TYPE_INFO outputType{
        MFMediaType_Video,
        MFVideoFormat_H264,
    };

    ActivationArray activations;
    HRESULT hr = MFTEnumEx(
        MFT_CATEGORY_VIDEO_ENCODER,
        MFT_ENUM_FLAG_HARDWARE |
            MFT_ENUM_FLAG_SORTANDFILTER,
        &inputType,
        &outputType,
        activations.OutItems(),
        activations.OutCount());
    if (FAILED(hr)) return hr;

    if (activations.Count() == 0) {
        return MF_E_TOPO_CODEC_NOT_FOUND;
    }

    for (UINT32 index = 0; index < activations.Count(); ++index) {
        ComPtr<IMFTransform> candidate;
        hr = activations.Items()[index]->ActivateObject(
            IID_PPV_ARGS(&candidate));
        if (FAILED(hr)) {
            continue;
        }

        ComPtr<IMFAttributes> attributes;
        hr = candidate->GetAttributes(&attributes);
        if (FAILED(hr)) {
            continue;
        }

        UINT32 d3dAware = FALSE;
        attributes->GetUINT32(
            MF_SA_D3D11_AWARE,
            &d3dAware);
        if (!d3dAware) {
            continue;
        }

        UINT32 asynchronous = FALSE;
        attributes->GetUINT32(
            MF_TRANSFORM_ASYNC,
            &asynchronous);

        if (asynchronous) {
            hr = attributes->SetUINT32(
                MF_TRANSFORM_ASYNC_UNLOCK,
                TRUE);
            if (FAILED(hr)) {
                continue;
            }
        }

        hr = candidate->ProcessMessage(
            MFT_MESSAGE_SET_D3D_MANAGER,
            reinterpret_cast<ULONG_PTR>(
                deviceManager_.Get()));
        if (FAILED(hr)) {
            continue;
        }

        ComPtr<IMFMediaType> encodedType;
        hr = MFCreateMediaType(&encodedType);
        if (FAILED(hr)) return hr;

        hr = SetVideoTypeCommon(
            encodedType.Get(),
            MFVideoFormat_H264,
            config);
        if (FAILED(hr)) return hr;

        hr = encodedType->SetUINT32(
            MF_MT_AVG_BITRATE,
            config.bitrateBitsPerSecond);
        if (FAILED(hr)) return hr;

        hr = candidate->SetOutputType(
            0,
            encodedType.Get(),
            0);
        if (FAILED(hr)) {
            continue;
        }

        ComPtr<IMFMediaType> rawType;
        hr = MFCreateMediaType(&rawType);
        if (FAILED(hr)) return hr;

        hr = SetVideoTypeCommon(
            rawType.Get(),
            MFVideoFormat_NV12,
            config);
        if (FAILED(hr)) return hr;

        hr = candidate->SetInputType(
            0,
            rawType.Get(),
            0);
        if (FAILED(hr)) {
            continue;
        }

        bool lowLatency = false;

        if (SUCCEEDED(attributes->SetUINT32(
                MF_LOW_LATENCY,
                TRUE))) {
            lowLatency = true;
        }

        ComPtr<ICodecAPI> codecApi;
        if (SUCCEEDED(candidate.As(&codecApi))) {
            VARIANT value;
            VariantInit(&value);
            value.vt = VT_BOOL;
            value.boolVal = VARIANT_TRUE;

            if (SUCCEEDED(codecApi->SetValue(
                    &CODECAPI_AVLowLatencyMode,
                    &value))) {
                lowLatency = true;
            }
            VariantClear(&value);
        }

        encoder_ = std::move(candidate);
        report.encoderName =
            ActivationName(activations.Items()[index]);
        report.hardwareEncoderFound = true;
        report.asynchronous = asynchronous != FALSE;
        report.d3d11Aware = true;
        report.lowLatencyAccepted = lowLatency;
        return S_OK;
    }

    return MF_E_TOPO_CODEC_NOT_FOUND;
}

HRESULT WindowsMediaProbe::CreateDxgiSample(
    ID3D11Texture2D* nv12,
    const ProbeConfig& config) noexcept {
    ComPtr<IMFMediaBuffer> buffer;
    HRESULT hr = MFCreateDXGISurfaceBuffer(
        __uuidof(ID3D11Texture2D),
        nv12,
        0,
        FALSE,
        &buffer);
    if (FAILED(hr)) return hr;

    ComPtr<IMFSample> sample;
    hr = MFCreateSample(&sample);
    if (FAILED(hr)) return hr;

    hr = sample->AddBuffer(buffer.Get());
    if (FAILED(hr)) return hr;

    constexpr LONGLONG kHundredNanosecondsPerSecond =
        10'000'000;

    const LONGLONG duration =
        kHundredNanosecondsPerSecond /
        config.framesPerSecond;

    hr = sample->SetSampleTime(0);
    if (FAILED(hr)) return hr;

    return sample->SetSampleDuration(duration);
}

}  // namespace displaymesh::media
