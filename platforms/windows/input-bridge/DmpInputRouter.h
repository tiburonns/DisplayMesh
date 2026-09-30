#pragma once

#include "DmpInput.h"
#include "DmpFrame.h"
#include "DmpHostSessionGate.h"

#include <string>

namespace displaymesh {

bool DecodeSessionAuthorizedInput(
    const DmpFrame& frame,
    const DmpHostSessionGate& sessionGate,
    InputSample& output,
    std::string& error);

}  // namespace displaymesh
