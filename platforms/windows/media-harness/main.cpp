#include "WindowsMediaProbe.h"

#include <Windows.h>
#include <objbase.h>

#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>

namespace {

struct ComGuard {
    HRESULT result{CoInitializeEx(
        nullptr,
        COINIT_MULTITHREADED)};

    ~ComGuard() {
        if (SUCCEEDED(result)) {
            CoUninitialize();
        }
    }
};

void PrintUsage() {
    std::wcout
        << L"DisplayMesh Windows media probe\n"
        << L"Usage: displaymesh-media-probe "
           L"[width height fps bitrate_mbps]\n";
}

bool Parse(
    int argc,
    wchar_t** argv,
    displaymesh::media::ProbeConfig& config) {
    if (argc == 1) return true;
    if (argc != 5) return false;

    try {
        config.width =
            static_cast<std::uint32_t>(
                std::stoul(argv[1]));
        config.height =
            static_cast<std::uint32_t>(
                std::stoul(argv[2]));
        config.framesPerSecond =
            static_cast<std::uint32_t>(
                std::stoul(argv[3]));

        const auto bitrateMbps =
            static_cast<std::uint32_t>(
                std::stoul(argv[4]));

        config.bitrateBitsPerSecond =
            bitrateMbps * 1'000'000;
        return bitrateMbps > 0;
    } catch (...) {
        return false;
    }
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    displaymesh::media::ProbeConfig config;
    if (!Parse(argc, argv, config)) {
        PrintUsage();
        return 1;
    }

    ComGuard com;
    if (FAILED(com.result)) {
        std::wcerr
            << L"COM initialization failed: 0x"
            << std::hex
            << static_cast<unsigned long>(com.result)
            << L"\n";
        return 2;
    }

    displaymesh::media::WindowsMediaProbe probe;
    displaymesh::media::ProbeReport report;

    const HRESULT hr = probe.Run(
        config,
        report);

    if (FAILED(hr)) {
        std::wcerr
            << L"Media probe failed: 0x"
            << std::hex
            << static_cast<unsigned long>(hr)
            << L"\n";
        return 3;
    }

    std::wcout
        << L"Encoder: " << report.encoderName << L"\n"
        << L"Hardware H.264: "
        << (report.hardwareEncoderFound ? L"yes" : L"no")
        << L"\n"
        << L"Async MFT: "
        << (report.asynchronous ? L"yes" : L"no")
        << L"\n"
        << L"D3D11-aware: "
        << (report.d3d11Aware ? L"yes" : L"no")
        << L"\n"
        << L"Low-latency accepted: "
        << (report.lowLatencyAccepted ? L"yes" : L"no")
        << L"\n"
        << L"GPU BGRA->NV12: "
        << (report.gpuBgraToNv12Ready ? L"yes" : L"no")
        << L"\n"
        << L"DXGI sample wrapping: "
        << (report.dxgiSampleReady ? L"yes" : L"no")
        << L"\n";

    return 0;
}
