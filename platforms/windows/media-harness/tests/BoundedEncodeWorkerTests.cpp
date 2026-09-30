#include "BoundedEncodeWorker.h"

#include <atomic>
#include <cassert>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

using namespace displaymesh::media;
using namespace std::chrono_literals;

namespace {

EncodeWorkItem Item(std::uint64_t sequence) {
    const auto slotIndex =
        static_cast<std::uint32_t>(
            sequence %
            displaymesh::bridge::kFrameMailboxSlotCount);

    return EncodeWorkItem{
        sequence,
        sequence * 1'000,
        16'667,
        1,
        slotIndex,
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

void TestValidationAndStaleRejection() {
    std::mutex encodedMutex;
    std::vector<std::uint64_t> encoded;

    BoundedEncodeWorker worker(
        [&](const EncodeWorkItem& item) {
            std::lock_guard lock(encodedMutex);
            encoded.push_back(item.sequence);
        });

    assert(worker.Start());
    assert(!worker.Start());

    assert(!worker.Submit(
        EncodeWorkItem{
            0,
            0,
            16'667,
            1,
            0,
            1920,
            1080,
        }));

    auto invalidDuration = Item(1);
    invalidDuration.durationMicros = 0;
    assert(!worker.Submit(invalidDuration));

    auto invalidGeneration = Item(1);
    invalidGeneration.surfaceGeneration = 0;
    assert(!worker.Submit(invalidGeneration));

    auto invalidSlot = Item(1);
    invalidSlot.slotIndex =
        displaymesh::bridge::kFrameMailboxSlotCount;
    assert(!worker.Submit(invalidSlot));

    auto wrongMappedSlot = Item(1);
    wrongMappedSlot.slotIndex = 0;
    assert(!worker.Submit(wrongMappedSlot));

    assert(worker.Submit(Item(2)));
    assert(!worker.Submit(Item(1)));

    assert(WaitUntil([&] {
        return worker.Stats().encoded == 1;
    }));

    worker.Stop();

    const auto stats = worker.Stats();
    assert(stats.submitted == 1);
    assert(stats.encoded == 1);
    assert(stats.rejectedInvalid == 5);
    assert(stats.rejectedStale == 1);
    assert(!worker.IsRunning());
}

void TestAnnouncementRoundTripPreservesGpuIdentity() {
    displaymesh::bridge::FrameAnnouncement frame{};
    frame.sequence = 42;
    frame.timestampMicros = 123'000;
    frame.surfaceGeneration = 7;
    frame.slotIndex = 0;
    frame.width = 2560;
    frame.height = 1440;

    const auto item =
        EncodeWorkItem::FromFrame(
            frame,
            16'667);

    assert(item.sequence == frame.sequence);
    assert(
        item.timestampMicros ==
        frame.timestampMicros);
    assert(item.durationMicros == 16'667);
    assert(
        item.surfaceGeneration ==
        frame.surfaceGeneration);
    assert(
        item.slotIndex ==
        frame.slotIndex);
    assert(item.width == frame.width);
    assert(item.height == frame.height);
    assert(item.IsValid());

    auto wrongMapping = item;
    wrongMapping.slotIndex = 1;
    assert(!wrongMapping.IsValid());

    const auto roundTrip =
        item.Announcement();
    assert(roundTrip.sequence == frame.sequence);
    assert(
        roundTrip.timestampMicros ==
        frame.timestampMicros);
    assert(
        roundTrip.surfaceGeneration ==
        frame.surfaceGeneration);
    assert(
        roundTrip.slotIndex ==
        frame.slotIndex);
    assert(roundTrip.width == frame.width);
    assert(roundTrip.height == frame.height);
}

void TestLatestFrameWinsWhileEncoding() {
    std::mutex gateMutex;
    std::condition_variable gate;
    bool firstEntered = false;
    bool releaseFirst = false;

    std::mutex encodedMutex;
    std::vector<std::uint64_t> encoded;

    BoundedEncodeWorker worker(
        [&](const EncodeWorkItem& item) {
            {
                std::lock_guard lock(
                    encodedMutex);
                encoded.push_back(
                    item.sequence);
            }

            if (item.sequence == 1) {
                std::unique_lock lock(
                    gateMutex);
                firstEntered = true;
                gate.notify_all();
                gate.wait(
                    lock,
                    [&] {
                        return releaseFirst;
                    });
            }
        });

    assert(worker.Start());
    assert(worker.Submit(Item(1)));

    {
        std::unique_lock lock(gateMutex);
        assert(gate.wait_for(
            lock,
            2s,
            [&] {
                return firstEntered;
            }));
    }

    assert(worker.Submit(Item(2)));
    assert(worker.Submit(Item(3)));
    assert(worker.Submit(Item(4)));

    {
        std::lock_guard lock(gateMutex);
        releaseFirst = true;
    }
    gate.notify_all();

    assert(WaitUntil([&] {
        return worker.Stats().encoded == 2;
    }));

    worker.Stop();

    {
        std::lock_guard lock(encodedMutex);
        assert(encoded.size() == 2);
        assert(encoded[0] == 1);
        assert(encoded[1] == 4);
    }

    const auto stats = worker.Stats();
    assert(stats.submitted == 4);
    assert(stats.encoded == 2);
    assert(stats.droppedPending == 2);
    assert(stats.rejectedStale == 0);
}

void TestStopDiscardsPendingWork() {
    std::mutex gateMutex;
    std::condition_variable gate;
    bool firstEntered = false;
    bool releaseFirst = false;

    std::atomic<int> calls{0};

    BoundedEncodeWorker worker(
        [&](const EncodeWorkItem& item) {
            ++calls;

            if (item.sequence == 10) {
                std::unique_lock lock(
                    gateMutex);
                firstEntered = true;
                gate.notify_all();
                gate.wait(
                    lock,
                    [&] {
                        return releaseFirst;
                    });
            }
        });

    assert(worker.Start());
    assert(worker.Submit(Item(10)));

    {
        std::unique_lock lock(gateMutex);
        assert(gate.wait_for(
            lock,
            2s,
            [&] {
                return firstEntered;
            }));
    }

    assert(worker.Submit(Item(11)));

    std::atomic<bool> stopReturned{false};
    std::thread stopper([&] {
        worker.Stop();
        stopReturned = true;
    });

    assert(WaitUntil([&] {
        return !worker.IsRunning();
    }));

    {
        std::lock_guard lock(gateMutex);
        releaseFirst = true;
    }
    gate.notify_all();

    stopper.join();

    assert(stopReturned);
    assert(calls.load() == 1);

    const auto stats = worker.Stats();
    assert(stats.encoded == 1);
    assert(stats.discardedOnStop == 1);
}

void TestHandlerFailureDoesNotKillWorker() {
    BoundedEncodeWorker worker(
        [](const EncodeWorkItem& item) {
            if (item.sequence == 1) {
                throw 7;
            }
        });

    assert(worker.Start());
    assert(worker.Submit(Item(1)));

    assert(WaitUntil([&] {
        return worker.Stats().handlerFailures == 1;
    }));

    assert(worker.Submit(Item(2)));
    assert(WaitUntil([&] {
        return worker.Stats().encoded == 1;
    }));

    worker.Stop();

    const auto stats = worker.Stats();
    assert(stats.handlerFailures == 1);
    assert(stats.encoded == 1);
}

}  // namespace

int main() {
    TestValidationAndStaleRejection();
    TestAnnouncementRoundTripPreservesGpuIdentity();
    TestLatestFrameWinsWhileEncoding();
    TestStopDiscardsPendingWork();
    TestHandlerFailureDoesNotKillWorker();
    return 0;
}
