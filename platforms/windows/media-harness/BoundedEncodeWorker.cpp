#include "BoundedEncodeWorker.h"

#include <utility>

namespace displaymesh::media {

BoundedEncodeWorker::BoundedEncodeWorker(
    Handler handler)
    : handler_(std::move(handler)) {}

BoundedEncodeWorker::~BoundedEncodeWorker() {
    Stop();
}

bool BoundedEncodeWorker::Start() {
    std::lock_guard lock(mutex_);

    if (running_ || !handler_) {
        return false;
    }

    pending_.reset();
    stats_ = {};
    highestSubmittedSequence_ = 0;
    stopRequested_ = false;
    running_ = true;

    try {
        worker_ =
            std::thread([this] { Run(); });
    } catch (...) {
        running_ = false;
        stopRequested_ = false;
        throw;
    }

    return true;
}

void BoundedEncodeWorker::Stop() noexcept {
    {
        std::lock_guard lock(mutex_);

        if (!running_) {
            return;
        }

        stopRequested_ = true;

        if (pending_.has_value()) {
            pending_.reset();
            ++stats_.discardedOnStop;
        }
    }

    wake_.notify_all();

    if (worker_.joinable()) {
        worker_.join();
    }

    std::lock_guard lock(mutex_);
    running_ = false;
    stopRequested_ = false;
    pending_.reset();
}

bool BoundedEncodeWorker::Submit(
    const EncodeWorkItem& item) noexcept {
    std::lock_guard lock(mutex_);

    if (!running_ || stopRequested_) {
        ++stats_.rejectedInvalid;
        return false;
    }

    if (item.sequence == 0 ||
        item.width == 0 ||
        item.height == 0) {
        ++stats_.rejectedInvalid;
        return false;
    }

    if (item.sequence <=
        highestSubmittedSequence_) {
        ++stats_.rejectedStale;
        return false;
    }

    highestSubmittedSequence_ =
        item.sequence;
    ++stats_.submitted;

    if (pending_.has_value()) {
        ++stats_.droppedPending;
    }

    pending_ = item;
    wake_.notify_one();
    return true;
}

bool BoundedEncodeWorker::IsRunning()
    const noexcept {
    std::lock_guard lock(mutex_);
    return running_ && !stopRequested_;
}

EncodeWorkerStats
BoundedEncodeWorker::Stats() const noexcept {
    std::lock_guard lock(mutex_);
    return stats_;
}

void BoundedEncodeWorker::Run() noexcept {
    for (;;) {
        EncodeWorkItem item{};

        {
            std::unique_lock lock(mutex_);
            wake_.wait(
                lock,
                [this] {
                    return stopRequested_ ||
                        pending_.has_value();
                });

            if (stopRequested_) {
                break;
            }

            item = *pending_;
            pending_.reset();
        }

        bool failed = false;

        try {
            handler_(item);
        } catch (...) {
            failed = true;
        }

        std::lock_guard lock(mutex_);
        if (failed) {
            ++stats_.handlerFailures;
        } else {
            ++stats_.encoded;
        }
    }
}

}  // namespace displaymesh::media
