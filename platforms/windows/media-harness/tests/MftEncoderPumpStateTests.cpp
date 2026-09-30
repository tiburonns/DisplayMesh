#include "MftEncoderPumpState.h"

#include <cassert>
#include <string>

using namespace displaymesh::media;

namespace {

void TestHappyPathAndCredits() {
    MftEncoderPumpState pump;
    std::string error;

    assert(pump.Phase() ==
        MftPumpPhase::Stopped);
    assert(pump.Begin(error));
    assert(pump.MarkStreamingReady(error));
    assert(pump.OnNeedInput(error));
    assert(pump.CanProcessInput());
    assert(pump.InputCredits() == 1);
    assert(pump.MarkInputSubmitted(error));
    assert(!pump.CanProcessInput());

    assert(pump.OnHaveOutput(error));
    assert(pump.CanProcessOutput());
    assert(pump.MarkOutputProduced(error));
    assert(!pump.CanProcessOutput());

    const auto stats = pump.Stats();
    assert(stats.needInputEvents == 1);
    assert(stats.inputSamplesSubmitted == 1);
    assert(stats.haveOutputEvents == 1);
    assert(stats.outputSamplesProduced == 1);
}

void TestInputRequiresNeedInputCredit() {
    MftEncoderPumpState pump;
    std::string error;

    assert(pump.Begin(error));
    assert(pump.MarkStreamingReady(error));
    assert(!pump.MarkInputSubmitted(error));
    assert(!error.empty());
    assert(pump.Stats().rejectedTransitions == 1);
}

void TestDrainRejectsNewInputButAllowsOutput() {
    MftEncoderPumpState pump;
    std::string error;

    assert(pump.Begin(error));
    assert(pump.MarkStreamingReady(error));
    assert(pump.OnNeedInput(error));
    assert(pump.BeginDrain(error));
    assert(pump.InputCredits() == 0);
    assert(!pump.OnNeedInput(error));
    assert(!pump.MarkInputSubmitted(error));

    assert(pump.OnHaveOutput(error));
    assert(pump.MarkOutputProduced(error));
    assert(pump.MarkDrainComplete(error));
    assert(pump.Phase() ==
        MftPumpPhase::Stopped);
}

void TestDrainCannotCompleteWithPendingOutput() {
    MftEncoderPumpState pump;
    std::string error;

    assert(pump.Begin(error));
    assert(pump.MarkStreamingReady(error));
    assert(pump.BeginDrain(error));
    assert(pump.OnHaveOutput(error));

    assert(!pump.MarkDrainComplete(error));
    assert(pump.Phase() ==
        MftPumpPhase::Draining);

    assert(pump.MarkOutputProduced(error));
    assert(pump.MarkDrainComplete(error));
}

void TestFailureClosesAllCredits() {
    MftEncoderPumpState pump;
    std::string error;

    assert(pump.Begin(error));
    assert(pump.MarkStreamingReady(error));
    assert(pump.OnNeedInput(error));
    assert(pump.OnHaveOutput(error));

    pump.Fail();

    assert(pump.Phase() ==
        MftPumpPhase::Failed);
    assert(pump.InputCredits() == 0);
    assert(pump.OutputSignals() == 0);
    assert(!pump.CanProcessInput());
    assert(!pump.CanProcessOutput());
    assert(!pump.OnNeedInput(error));

    pump.Reset();
    assert(pump.Phase() ==
        MftPumpPhase::Stopped);
    assert(pump.Stats().needInputEvents == 0);
}

void TestRepeatedBeginIsRejected() {
    MftEncoderPumpState pump;
    std::string error;

    assert(pump.Begin(error));
    assert(!pump.Begin(error));
    assert(pump.Stats().rejectedTransitions == 1);
}

}  // namespace

int main() {
    TestHappyPathAndCredits();
    TestInputRequiresNeedInputCredit();
    TestDrainRejectsNewInputButAllowsOutput();
    TestDrainCannotCompleteWithPendingOutput();
    TestFailureClosesAllCredits();
    TestRepeatedBeginIsRejected();
    return 0;
}
