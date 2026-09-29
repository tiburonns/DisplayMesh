#include <cassert>
#include <cstdint>

#include "../bridge/LatestFrameMailbox.h"

using displaymesh::bridge::LatestFrameMailbox;

int main() {
    LatestFrameMailbox mailbox;

    assert(!mailbox.TryConsumeAfter(0).has_value());
    assert(!mailbox.Publish(0, 0, 1920, 1080));
    assert(!mailbox.Publish(1, 0, 0, 1080));

    assert(mailbox.Publish(
        1,
        1'000,
        1920,
        1080));

    auto first =
        mailbox.TryConsumeAfter(0);
    assert(first.has_value());
    assert(first->frame.sequence == 1);
    assert(first->frame.timestampMicros == 1'000);
    assert(first->frame.width == 1920);
    assert(first->frame.height == 1080);
    assert(first->droppedBefore == 0);

    assert(
        !mailbox.TryConsumeAfter(1)
             .has_value());

    assert(mailbox.Publish(
        2,
        2'000,
        1920,
        1080));
    assert(mailbox.Publish(
        3,
        3'000,
        1920,
        1080));
    assert(mailbox.Publish(
        4,
        4'000,
        2560,
        1440));

    auto newest =
        mailbox.TryConsumeAfter(1);
    assert(newest.has_value());
    assert(newest->frame.sequence == 4);
    assert(newest->frame.width == 2560);
    assert(newest->frame.height == 1440);
    assert(newest->droppedBefore == 2);

    assert(mailbox.LatestSequence() == 4);

    assert(mailbox.Publish(
        5,
        5'000,
        2560,
        1440));

    auto next =
        mailbox.TryConsumeAfter(4);
    assert(next.has_value());
    assert(next->frame.sequence == 5);
    assert(next->droppedBefore == 0);

    return 0;
}
