# DisplayMesh IddCx Driver

Windows UMDF/IddCx virtual display foundation.

Implemented:
- one DisplayMesh virtual monitor
- stable monitor identity
- monitor arrival/departure lifecycle
- 1080p60/120, 1440p60/120 and 4K60 modes
- D3D11 render device using the adapter selected by Windows
- IddCx swap-chain assignment/unassignment
- bounded swap-chain consumer thread
- no normal-path CPU readback

The consumer currently proves the real desktop-frame lifecycle and releases each GPU surface. The next M2 step connects the acquired D3D11 texture to Media Foundation H.264.

Build with Visual Studio 2022 + Windows SDK + WDK:
msbuild platforms\windows\idd\DisplayMeshIdd.vcxproj /p:Configuration=Debug /p:Platform=x64

Install only on a dedicated development PC/VM using Microsoft's test-signing workflow. Install the generated INF with pnputil, then run the existing DisplayMesh bootstrap. Production distribution requires Microsoft's production driver-signing flow.

Not yet validated on physical Windows hardware: install/uninstall, Driver Verifier/HLK behavior, sustained 60/120 Hz delivery, Media Foundation encode, dynamic receiver-native modes, production signing.
