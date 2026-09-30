#include "LiveEncodeCoordinator.h"

#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

using namespace displaymesh::media;
using namespace std::chrono_literals;

namespace {

EncodeWorkItem Item(
    std::uint64_t sequence) {
    return EncodeWorkItem{
        sequence,
        sequence * 1'000,
        16'667,
        1,
        static_cast<std::uint32_t>(
            sequence %
            bridge::kFrameMailboxSlotCount),
        1920,
        1080,
    };
}

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

void TestLatestFrameWaitsForNeedInput() {
    std::mutex mutex;
    std::vector<std::uint64_t> submitted;

    LiveEncodeCoordinator coordinator(
        [&](const EncodeWorkItem& item,
            std::string&) {
            std::lock_guard lock(mutex);
            submitted.push_back(item.sequence);
            return true;
        },
        [](std::string&) {
            return true;
        });

    std::string error;
    assert(coordinator.Start(error));

    assert(coordinator.OfferFrame(
        Item(1),
        error));
    assert(coordinator.OfferFrame(
        Item(2),
        error));
    assert(coordinator.OfferFrame(
        Item(3),
        error));

    assert(coordinator.Stats().framesOffered == 3);
    assert(
        coordinator.Stats()
            .framesReplacedWaitingForCredit == 2);
    assert(
        coordinator.Stats().framesScheduled == 0);

    assert(coordinator.OnNeedInput(error));

    assert(WaitUntil([&] {
        return coordinator
            .WorkerStats().encoded == 1;
    }));

    {
        std::lock_guard lock(mutex);
        assert(submitted.size() == 1);
        assert(submitted[0] == 3);
    }

    assert(
        coordinator.PumpStats()
            .inputSamplesSubmitted == 1);

    coordinator.Stop();
}

void TestOneNeedInputConsumesOneFrame() {
    std::atomic<int> calls{0};

    LiveEncodeCoordinator coordinator(
        [&](const EncodeWorkItem&,
            std::string&) {
            ++calls;
            return true;
        },
        [](std::string&) {
            return true;
        });

    std::string error;
    assert(coordinator.Start(error));
    assert(coordinator.OnNeedInput(error));
    assert(coordinator.OfferFrame(
        Item(4),
        error));

    assert(WaitUntil([&] {
        return calls.load() == 1;
    }));

    assert(coordinator.OfferFrame(
        Item(5),
        error));

    std::this_thread::sleep_for(30ms);
    assert(calls.load() == 1);

    assert(coordinator.OnNeedInput(error));
    assert(WaitUntil([&] {
        return calls.load() == 2;
    }));

    coordinator.Stop();
}

void TestHaveOutputMustBeBackedByEvent() {
    std::atomic<int> outputs{0};

    LiveEncodeCoordinator coordinator(
        [](const EncodeWorkItem&,
           std::string&) {
            return true;
        },
        [&](std::string&) {
            ++outputs;
            return true;
        });

    std::string error;
    assert(coordinator.Start(error));
    assert(coordinator.OnHaveOutput(error));
    assert(outputs.load() == 1);
    assert(
        coordinator.PumpStats()
            .outputSamplesProduced == 1);
    assert(
        coordinator.Stats()
            .outputsProcessed == 1);

    coordinator.Stop();
}

void TestInputFailureFailsClosed() {
    LiveEncodeCoordinator coordinator(
        [](const EncodeWorkItem&,
           std::string& error) {
            error = "ProcessInput failed";
            return false;
        },
        [](std::string&) {
            return true;
        });

    std::string error;
    assert(coordinator.Start(error));
    assert(coordinator.OnNeedInput(error));
    assert(coordinator.OfferFrame(
        Item(7),
        error));

    assert(WaitUntil([&] {
        return coordinator
            .Stats()
            .inputHandlerFailures == 1;
    }));

    assert(
        coordinator.PumpStats()
            .rejectedTransitions == 0);
    assert(WaitUntil([&] {
        return coordinator
            .WorkerStats()
            .handlerFailures == 1;
    }));
    assert(
        coordinator.WorkerStats().encoded == 0);
    assert(
        coordinator.LastError() ==
        "ProcessInput failed");

    coordinator.Stop();
}

void TestOutputFailureFailsClosed() {
    LiveEncodeCoordinator coordinator(
        [](const EncodeWorkItem&,
           std::string&) {
            return true;
        },
        [](std::string& error) {
            error = "ProcessOutput failed";
            return false;
        });

    std::string error;
    assert(coordinator.Start(error));
    assert(!coordinator.OnHaveOutput(error));
    assert(!error.empty());
    assert(
        coordinator.Stats()
            .outputHandlerFailures == 1);

    coordinator.Stop();
}

void TestDrainDropsWaitingFrame() {
    std::atomic<int> calls{0};

    LiveEncodeCoordinator coordinator(
        [&](const EncodeWorkItem&,
            std::string&) {
            ++calls;
            return true;
        },
        [](std::string&) {
            return true;
        });

    std::string error;
    assert(coordinator.Start(error));
    assert(coordinator.OfferFrame(
        Item(9),
        error));
    assert(coordinator.BeginDrain(error));

    assert(!coordinator.OnNeedInput(error));
    std::this_thread::sleep_for(20ms);
    assert(calls.load() == 0);

    assert(
        coordinator.MarkDrainComplete(
            error));
    coordinator.Stop();
}

}  // namespace

int main() {
    TestLatestFrameWaitsForNeedInput();
    TestOneNeedInputConsumesOneFrame();
    TestHaveOutputMustBeBackedByEvent();
    TestInputFailureFailsClosed();
    TestOutputFailureFailsClosed();
    TestDrainDropsWaitingFrame();
    return 0;
}
