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
    return EncodeWorkItem{
        sequence,
        sequence * 1'000,
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
            1920,
            1080,
        }));

    assert(worker.Submit(Item(2)));
    assert(!worker.Submit(Item(1)));

    assert(WaitUntil([&] {
        return worker.Stats().encoded == 1;
    }));

    worker.Stop();

    const auto stats = worker.Stats();
    assert(stats.submitted == 1);
    assert(stats.encoded == 1);
    assert(stats.rejectedInvalid == 1);
    assert(stats.rejectedStale == 1);
    assert(!worker.IsRunning());
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
    TestLatestFrameWinsWhileEncoding();
    TestStopDiscardsPendingWork();
    TestHandlerFailureDoesNotKillWorker();
    return 0;
}
