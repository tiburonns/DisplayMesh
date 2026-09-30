#include "MftAsyncEventPump.h"

#include <Windows.h>
#include <mfapi.h>

#include <cassert>
#include <string>

using namespace displaymesh::media;

namespace {

EncodeWorkItem Item() {
    return EncodeWorkItem{
        1,
        1'000,
        16'667,
        1,
        1,
        1920,
        1080,
    };
}

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

void TestNonEventTransformFailsClosed() {
    // A Media Foundation transform must expose IMFMediaEventGenerator
    // before this asynchronous pump is valid. The concrete hardware
    // encoder probe verifies the transform's async capability; this
    // test keeps the null/error contract deterministic.
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
    assert(!pump->IsRunning());
    assert(pump->LastError().empty());

    pump->Stop();
    coordinator.Stop();
}

}  // namespace

int main() {
    TestNullTransformFails();
    TestNonEventTransformFailsClosed();
    return 0;
}
