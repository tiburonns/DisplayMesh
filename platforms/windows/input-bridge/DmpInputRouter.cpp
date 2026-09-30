#include "DmpInputRouter.h"

namespace displaymesh {

bool DecodeSessionAuthorizedInput(
    const DmpFrame& frame,
    const DmpHostSessionGate& sessionGate,
    InputSample& output,
    std::string& error) {
    if (!sessionGate.CanRouteInput()) {
        error =
            "DMP input is blocked until the host session is streaming";
        return false;
    }

    if (frame.type != DmpMessageType::Input) {
        error =
            "DMP input router received a non-input frame";
        return false;
    }

    if (frame.flags != 0) {
        error =
            "DMP input frame flags are reserved and must be zero";
        return false;
    }

    return DecodeInputSample(
        frame.payload,
        output,
        error);
}

}  // namespace displaymesh
