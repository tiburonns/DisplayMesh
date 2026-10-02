#include "../../bridge/ReceiverModePolicy.h"

#include <cassert>

using namespace displaymesh::bridge;

int main() {
    {
        ReceiverModeRequest request{};
        request.width = 2556;
        request.height = 1179;
        request.refreshHz = 120;

        const auto normalized =
            NormalizeReceiverMode(request);
        assert(normalized.has_value());
        assert(normalized->width == 2556);
        assert(normalized->height == 1178);
        assert(normalized->refreshHz == 120);
    }

    {
        ReceiverModeRequest request{};
        request.width = 2732;
        request.height = 2048;
        request.refreshHz = 120;

        const auto normalized =
            NormalizeReceiverMode(request);
        assert(normalized.has_value());
        assert(
            SameReceiverMode(
                *normalized,
                request));
    }

    {
        ReceiverModeRequest request{};
        request.width = 1921;
        request.height = 1081;
        request.refreshHz = 60;

        const auto normalized =
            NormalizeReceiverMode(request);
        assert(normalized.has_value());
        assert(normalized->width == 1920);
        assert(normalized->height == 1080);
    }

    {
        ReceiverModeRequest request{};
        request.protocolVersion =
            kProtocolVersion + 1;
        request.width = 1920;
        request.height = 1080;
        request.refreshHz = 60;
        assert(
            !NormalizeReceiverMode(request)
                 .has_value());
    }

    {
        ReceiverModeRequest request{};
        request.width = 639;
        request.height = 1080;
        request.refreshHz = 60;
        assert(
            !NormalizeReceiverMode(request)
                 .has_value());
    }

    {
        ReceiverModeRequest request{};
        request.width = 1920;
        request.height = 1080;
        request.refreshHz = 241;
        assert(
            !NormalizeReceiverMode(request)
                 .has_value());
    }

    {
        ReceiverModeRequest request{};
        request.width = 8192;
        request.height = 8192;
        request.refreshHz = 240;
        assert(
            NormalizeReceiverMode(request)
                .has_value());
    }

    return 0;
}
