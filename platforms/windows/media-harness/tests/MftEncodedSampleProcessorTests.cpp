#include "MftEncodedSampleProcessor.h"

#include <Windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <wrl.h>

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <cstring>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;
using namespace displaymesh::media;

namespace {

void Require(bool condition) {
    if (!condition) {
        std::cerr << "DisplayMesh MFT sample processor requirement failed\n";
        std::exit(EXIT_FAILURE);
    }
}

class MfGuard {
public:
    MfGuard() {
        result = MFStartup(
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

ComPtr<IMFSample> MakeSample(
    const std::vector<std::uint8_t>& bytes,
    LONGLONG timeHundredNanoseconds,
    LONGLONG durationHundredNanoseconds) {
    ComPtr<IMFMediaBuffer> buffer;
    Require(SUCCEEDED(
        MFCreateMemoryBuffer(
            static_cast<DWORD>(bytes.size()),
            &buffer)));

    BYTE* destination = nullptr;
    DWORD maximumLength = 0;
    DWORD currentLength = 0;
    Require(SUCCEEDED(
        buffer->Lock(
            &destination,
            &maximumLength,
            &currentLength)));

    Require(maximumLength >= bytes.size());
    std::memcpy(
        destination,
        bytes.data(),
        bytes.size());

    buffer->Unlock();
    Require(SUCCEEDED(
        buffer->SetCurrentLength(
            static_cast<DWORD>(bytes.size()))));

    ComPtr<IMFSample> sample;
    Require(SUCCEEDED(
        MFCreateSample(&sample)));
    Require(SUCCEEDED(
        sample->AddBuffer(buffer.Get())));
    Require(SUCCEEDED(
        sample->SetSampleTime(
            timeHundredNanoseconds)));
    Require(SUCCEEDED(
        sample->SetSampleDuration(
            durationHundredNanoseconds)));
    return sample;
}

void TestLengthPrefixedMftSamplesReachDmpPacketizer() {
    MftEncodedSampleProcessor processor;
    H264NormalizeReport normalizeReport;
    H264PacketizeReport packetizeReport;
    std::vector<std::uint8_t> payload;
    std::string error;

    const std::vector<std::uint8_t> parameterSets{
        0x00, 0x00, 0x00, 0x04,
        0x67, 0x64, 0x00, 0x1f,
        0x00, 0x00, 0x00, 0x04,
        0x68, 0xee, 0x3c, 0x80,
    };

    auto config = MakeSample(
        parameterSets,
        10'000,
        166'670);

    Require(SUCCEEDED(
        processor.Process(
            config.Get(),
            payload,
            normalizeReport,
            packetizeReport,
            error)));
    Require(normalizeReport.inputFormat ==
        H264AccessUnitFormat::AvccLengthPrefixed);

    const std::vector<std::uint8_t> idr{
        0x00, 0x00, 0x00, 0x03,
        0x65, 0x88, 0x84,
    };

    auto frame = MakeSample(
        idr,
        20'000,
        166'670);

    Require(SUCCEEDED(
        processor.Process(
            frame.Get(),
            payload,
            normalizeReport,
            packetizeReport,
            error)));

    Require(packetizeReport.keyframe);
    Require(packetizeReport.insertedSps);
    Require(packetizeReport.insertedPps);
    Require(payload.size() > 16);

    // DMP video header: codec H.264 + keyframe.
    Require(payload[0] == 0x01);
    Require(payload[1] == 0x01);

    // 20,000 x 100ns = 2,000 microseconds.
    Require(payload[4] == 0);
    Require(payload[5] == 0);
    Require(payload[6] == 0);
    Require(payload[7] == 0);
    Require(payload[8] == 0);
    Require(payload[9] == 0);
    Require(payload[10] == 0x07);
    Require(payload[11] == 0xD0);
}

void TestMissingTimingFailsClosed() {
    MftEncodedSampleProcessor processor;
    H264NormalizeReport normalizeReport;
    H264PacketizeReport packetizeReport;
    std::vector<std::uint8_t> payload;
    std::string error;

    const std::vector<std::uint8_t> bytes{
        0x00, 0x00, 0x00, 0x01,
        0x67, 0x64, 0x00, 0x1f,
    };

    ComPtr<IMFMediaBuffer> buffer;
    Require(SUCCEEDED(
        MFCreateMemoryBuffer(
            static_cast<DWORD>(bytes.size()),
            &buffer)));

    BYTE* destination = nullptr;
    DWORD maxLength = 0;
    DWORD currentLength = 0;
    Require(SUCCEEDED(
        buffer->Lock(
            &destination,
            &maxLength,
            &currentLength)));
    std::memcpy(
        destination,
        bytes.data(),
        bytes.size());
    buffer->Unlock();
    Require(SUCCEEDED(
        buffer->SetCurrentLength(
            static_cast<DWORD>(bytes.size()))));

    ComPtr<IMFSample> sample;
    Require(SUCCEEDED(
        MFCreateSample(&sample)));
    Require(SUCCEEDED(
        sample->AddBuffer(buffer.Get())));

    Require(FAILED(
        processor.Process(
            sample.Get(),
            payload,
            normalizeReport,
            packetizeReport,
            error)));
    Require(payload.empty());
    Require(!error.empty());
}

void TestEmptySampleFailsClosed() {
    MftEncodedSampleProcessor processor;
    H264NormalizeReport normalizeReport;
    H264PacketizeReport packetizeReport;
    std::vector<std::uint8_t> payload;
    std::string error;

    ComPtr<IMFSample> sample;
    Require(SUCCEEDED(
        MFCreateSample(&sample)));
    Require(FAILED(
        processor.Process(
            sample.Get(),
            payload,
            normalizeReport,
            packetizeReport,
            error)));
}

}  // namespace

int main() {
    MfGuard mf;
    Require(SUCCEEDED(mf.result));

    TestLengthPrefixedMftSamplesReachDmpPacketizer();
    TestMissingTimingFailsClosed();
    TestEmptySampleFailsClosed();
    return 0;
}
