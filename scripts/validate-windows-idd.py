#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDD = ROOT / "platforms" / "windows" / "idd"

required = [
    IDD / "Driver.h",
    IDD / "Driver.cpp",
    IDD / "DisplayMeshIdd.inf",
    IDD / "DisplayMeshIdd.vcxproj",
    IDD / "README.md",
    ROOT / "platforms" / "windows" / "bridge" / "DisplayMeshBridgeProtocol.h",
    ROOT / "platforms" / "windows" / "bridge" / "ReceiverModePolicy.h",
    ROOT / "platforms" / "windows" / "bridge-probe" / "main.cpp",
]

errors: list[str] = []
for path in required:
    if not path.is_file():
        errors.append(f"missing required Windows IDD file: {path.relative_to(ROOT)}")

driver = (IDD / "Driver.cpp").read_text(encoding="utf-8") if (IDD / "Driver.cpp").is_file() else ""
inf = (IDD / "DisplayMeshIdd.inf").read_text(encoding="utf-8") if (IDD / "DisplayMeshIdd.inf").is_file() else ""
project = (IDD / "DisplayMeshIdd.vcxproj").read_text(encoding="utf-8") if (IDD / "DisplayMeshIdd.vcxproj").is_file() else ""
bootstrap = (ROOT / "platforms" / "windows" / "bootstrap" / "main.cpp").read_text(encoding="utf-8")

for token in (
    "IddCxAdapterInitAsync",
    "IddCxMonitorCreate",
    "IddCxMonitorArrival",
    "IddCxMonitorDeparture",
    "IddCxSwapChainSetDevice",
    "IddCxSwapChainReleaseAndAcquireBuffer",
    "IddCxSwapChainFinishedProcessingFrame",
    "D3D11CreateDevice",
    "EvtIddCxDeviceIoControl",
    "WdfDeviceCreateDeviceInterface",
    "kIoctlQueryStatus",
    "kIoctlSetReceiverMode",
    "NormalizeReceiverMode",
):
    if token not in driver:
        errors.append(f"Driver.cpp is missing required IddCx/D3D token: {token}")

for width, height, refresh in (
    (1920, 1080, 60),
    (1920, 1080, 120),
    (2560, 1440, 60),
    (2560, 1440, 120),
    (3840, 2160, 60),
):
    pattern = rf"\{{\s*{width}\s*,\s*{height}\s*,\s*{refresh}\s*\}}"
    if not re.search(pattern, driver):
        errors.append(f"missing advertised display mode: {width}x{height}@{refresh}")

for token in (
    'Class=Display',
    'DisplayMeshIdd',
    '"IndirectKmd"',
    'UmdfExtensions=IddCx0102',
):
    if token not in inf:
        errors.append(f"DisplayMeshIdd.inf is missing required token: {token}")

for token in (
    "WindowsUserModeDriver10.0",
    "<IndirectDisplayDriver>true</IndirectDisplayDriver>",
    "IDDCX_VERSION_MAJOR",
    "IDDCX_VERSION_MINOR",
):
    if token not in project:
        errors.append(f"DisplayMeshIdd.vcxproj is missing required token: {token}")

if 'L"DisplayMeshIdd"' not in bootstrap:
    errors.append("bootstrap hardware ID no longer matches DisplayMeshIdd INF")

for forbidden in (
    "D3D11_MAP_READ",
    "D3D11_USAGE_STAGING",
    "GetData(",
):
    if forbidden in driver:
        errors.append(
            f"IDD hot path contains CPU-readback token that requires review: {forbidden}"
        )

policy = (ROOT / "platforms" / "windows" / "bridge" / "ReceiverModePolicy.h").read_text(encoding="utf-8")
for token in (
    "kMinimumReceiverWidth",
    "kMaximumReceiverDimension",
    "normalized.width &= ~1U",
    "normalized.height &= ~1U",
):
    if token not in policy:
        errors.append(f"receiver mode policy is missing required token: {token}")

if errors:
    print("Windows IDD contract validation failed:")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

print(
    "Windows IDD contract validation passed: "
    "bootstrap/INF identity aligned, receiver mode normalization present, "
    "5 baseline modes present, IddCx lifecycle/swap-chain APIs present, "
    "no CPU readback/staging tokens."
)
