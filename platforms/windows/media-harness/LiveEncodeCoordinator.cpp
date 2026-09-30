#include "LiveEncodeCoordinator.h"

#include <utility>

namespace displaymesh::media {

LiveEncodeCoordinator::
LiveEncodeCoordinator(
    InputHandler inputHandler,
    OutputHandler outputHandler)
    : inputHandler_(std::move(inputHandler)),
      outputHandler_(std::move(outputHandler)),
      worker_(
          [this](
              const EncodeWorkItem& item) {
              ProcessInput(item);
          }) {}

LiveEncodeCoordinator::
~LiveEncodeCoordinator() {
    Stop();
}

bool LiveEncodeCoordinator::Start(
    std::string& error) {
    std::lock_guard lock(mutex_);

    if (running_) {
        error =
            "live encode coordinator is already running";
        return false;
    }

    if (!inputHandler_ ||
        !outputHandler_) {
        error =
            "live encode coordinator handlers are missing";
        return false;
    }

    pump_.Reset();
    waitingForCredit_.reset();
    stats_ = {};
    lastWorkerError_.clear();

    if (!pump_.Begin(error) ||
        !pump_.MarkStreamingReady(error)) {
        pump_.Fail();
        return false;
    }

    try {
        if (!worker_.Start()) {
            pump_.Fail();
            error =
                "bounded encode worker could not start";
            return false;
        }
    } catch (...) {
        pump_.Fail();
        error =
            "bounded encode worker threw while starting";
        return false;
    }

    running_ = true;
    error.clear();
    return true;
}

void LiveEncodeCoordinator::Stop() noexcept {
    worker_.Stop();

    std::lock_guard lock(mutex_);
    running_ = false;
    waitingForCredit_.reset();
    pump_.Reset();
    lastWorkerError_.clear();
}

bool LiveEncodeCoordinator::OfferFrame(
    const EncodeWorkItem& item,
    std::string& error) noexcept {
    std::lock_guard lock(mutex_);

    if (!running_) {
        error =
            "live encode coordinator is not running";
        return false;
    }

    if (!item.IsValid()) {
        error =
            "live encode coordinator rejected invalid frame";
        return false;
    }

    ++stats_.framesOffered;

    if (waitingForCredit_.has_value()) {
        if (item.sequence <=
            waitingForCredit_->sequence) {
            error =
                "live encode coordinator rejected stale waiting frame";
            return false;
        }
        ++stats_
            .framesReplacedWaitingForCredit;
    }

    waitingForCredit_ = item;

    return ScheduleLatestLocked(error);
}

bool LiveEncodeCoordinator::OnNeedInput(
    std::string& error) noexcept {
    std::lock_guard lock(mutex_);

    if (!running_) {
        error =
            "NeedInput received while coordinator is stopped";
        return false;
    }

    if (!pump_.OnNeedInput(error)) {
        return false;
    }

    return ScheduleLatestLocked(error);
}

bool LiveEncodeCoordinator::OnHaveOutput(
    std::string& error) noexcept {
    OutputHandler output;

    {
        std::lock_guard lock(mutex_);

        if (!running_) {
            error =
                "HaveOutput received while coordinator is stopped";
            return false;
        }

        if (!pump_.OnHaveOutput(error)) {
            return false;
        }

        output = outputHandler_;
    }

    std::string handlerError;
    const bool succeeded =
        output(handlerError);

    std::lock_guard lock(mutex_);

    if (!running_) {
        error =
            "coordinator stopped while processing output";
        return false;
    }

    if (!succeeded) {
        ++stats_.outputHandlerFailures;
        pump_.Fail();
        error = handlerError.empty()
            ? "Media Foundation output handler failed"
            : handlerError;
        return false;
    }

    if (!pump_.MarkOutputProduced(error)) {
        return false;
    }

    ++stats_.outputsProcessed;
    error.clear();
    return true;
}

bool LiveEncodeCoordinator::BeginDrain(
    std::string& error) noexcept {
    std::lock_guard lock(mutex_);

    if (!running_) {
        error =
            "cannot drain a stopped encode coordinator";
        return false;
    }

    waitingForCredit_.reset();
    return pump_.BeginDrain(error);
}

bool LiveEncodeCoordinator::
MarkDrainComplete(
    std::string& error) noexcept {
    std::lock_guard lock(mutex_);

    if (!running_) {
        error =
            "cannot complete drain on a stopped coordinator";
        return false;
    }

    return pump_.MarkDrainComplete(error);
}

bool LiveEncodeCoordinator::IsRunning()
    const noexcept {
    std::lock_guard lock(mutex_);
    return running_;
}

LiveEncodeCoordinatorStats
LiveEncodeCoordinator::Stats()
    const noexcept {
    std::lock_guard lock(mutex_);
    return stats_;
}

EncodeWorkerStats
LiveEncodeCoordinator::WorkerStats()
    const noexcept {
    return worker_.Stats();
}

MftPumpStats
LiveEncodeCoordinator::PumpStats()
    const noexcept {
    std::lock_guard lock(mutex_);
    return pump_.Stats();
}

bool LiveEncodeCoordinator::
ScheduleLatestLocked(
    std::string& error) noexcept {
    if (!pump_.CanProcessInput() ||
        !waitingForCredit_.has_value()) {
        error.clear();
        return true;
    }

    const auto item =
        *waitingForCredit_;

    if (!worker_.Submit(item)) {
        error =
            "bounded encode worker rejected frame";
        return false;
    }

    waitingForCredit_.reset();
    ++stats_.framesScheduled;
    error.clear();
    return true;
}

void LiveEncodeCoordinator::ProcessInput(
    const EncodeWorkItem& item) {
    std::string handlerError;

    if (!inputHandler_(
            item,
            handlerError)) {
        std::lock_guard lock(mutex_);
        ++stats_.inputHandlerFailures;
        lastWorkerError_ =
            handlerError.empty()
                ? "Media Foundation input handler failed"
                : handlerError;
        pump_.Fail();
        return;
    }

    std::lock_guard lock(mutex_);

    if (!running_) {
        return;
    }

    std::string transitionError;
    if (!pump_.MarkInputSubmitted(
            transitionError)) {
        ++stats_.inputHandlerFailures;
        lastWorkerError_ =
            transitionError;
        pump_.Fail();
    }
}

}  // namespace displaymesh::media
