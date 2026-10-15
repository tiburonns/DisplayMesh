#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

cargo = (ROOT / "Cargo.toml").read_text(encoding="utf-8")
readme_en = (ROOT / "README.md").read_text(encoding="utf-8")
readme_es = (ROOT / "README.es.md").read_text(encoding="utf-8")
protocol = (ROOT / "protocol/DMPv1.md").read_text(encoding="utf-8")
security = (ROOT / "SECURITY.md").read_text(encoding="utf-8")
testing_en = (ROOT / "docs/TESTING.md").read_text(encoding="utf-8")
testing_es = (ROOT / "docs/TESTING.es.md").read_text(encoding="utf-8")

match = re.search(
    r'^version = "([0-9]+\.[0-9]+\.[0-9]+)"',
    cargo,
    re.MULTILINE,
)
if not match:
    raise SystemExit("release contract failed: workspace version is missing")
version = match.group(1)

if f"**Current `main`: {version}.**" not in readme_en:
    raise SystemExit("release contract failed: English README version is stale")
if f"**`main` actual: {version}.**" not in readme_es:
    raise SystemExit("release contract failed: Spanish README version is stale")

if not testing_en.startswith(f"# DisplayMesh {version} "):
    raise SystemExit("release contract failed: English native test plan is stale")
if not testing_es.startswith(f"# DisplayMesh {version} "):
    raise SystemExit("release contract failed: Spanish native test plan is stale")

if "Status: **draft**" not in protocol:
    raise SystemExit(
        "protocol contract failed: DMPv1 must remain explicitly draft "
        "until interoperability is implemented"
    )

required_security_terms = [
    "First pairing requires explicit user confirmation.",
    "Remote input is rejected until the peer is authenticated and authorized.",
    "must fail explicitly rather than silently downgrade",
]
for term in required_security_terms:
    if term not in security:
        raise SystemExit(
            f"security contract failed: missing invariant: {term}"
        )

if not (ROOT / "platforms/macos/harness/Makefile").exists():
    raise SystemExit("native contract failed: macOS harness is missing")
if not (ROOT / "platforms/windows/bootstrap/CMakeLists.txt").exists():
    raise SystemExit("native contract failed: Windows bootstrap is missing")

framing = (ROOT / "crates/displaymesh-core/src/framing.rs").read_text(encoding="utf-8")
for token in [
    "maximum_payload_len",
    "PayloadTooLargeForType",
    "InvalidPayloadLength",
    "Ping = 0x32",
    "Pong = 0x33",
]:
    if token not in framing:
        raise SystemExit(f"protocol hardening contract failed: framing missing {token}")

input_source = (ROOT / "crates/displaymesh-core/src/input.rs").read_text(encoding="utf-8")
if "UnsupportedFlags" not in input_source:
    raise SystemExit("protocol hardening contract failed: reserved input flags are not rejected")

receiver_gate = ROOT / "platforms/apple-receiver/Sources/ReceiverProtocolGate.swift"
if not receiver_gate.exists():
    raise SystemExit("receiver admission contract failed: ReceiverProtocolGate.swift is missing")
gate_source = receiver_gate.read_text(encoding="utf-8")
for token in [".pairing", ".video", "authorized"]:
    if token not in gate_source:
        raise SystemExit(f"receiver admission contract failed: gate missing {token}")

identity_store = ROOT / "platforms/macos/media-harness/Sources/DisplayMeshMacMediaHarness/HostIdentityStore.swift"
if not identity_store.exists():
    raise SystemExit("security contract failed: macOS host identity store is missing")
identity_text = identity_store.read_text(encoding="utf-8")
for token in ["P256.Signing.PrivateKey", "SecItemCopyMatching", "SecItemAdd"]:
    if token not in identity_text:
        raise SystemExit(f"security contract failed: host identity store missing {token}")

session_model = (ROOT / "crates/displaymesh-core/src/session.rs").read_text(encoding="utf-8")
capability_model = (ROOT / "crates/displaymesh-core/src/model.rs").read_text(encoding="utf-8")
for token in [
    "pub const fn development_scaffold() -> Self",
    "encryption_required: false",
]:
    if token not in session_model:
        raise SystemExit(f"security contract failed: session development scaffold missing {token}")
for token in [
    "connection_media: vec![ConnectionMedium::Wifi]",
    "wire_protocols: vec![WireProtocol::Tcp]",
    "encryption_supported: false",
]:
    if token not in capability_model:
        raise SystemExit(f"security contract failed: development capabilities missing {token}")

adaptive_controller = ROOT / "platforms/macos/media-harness/Sources/DisplayMeshMacMediaHarness/ReceiverAdaptiveController.swift"
adaptive_tests = ROOT / "platforms/macos/media-harness/Tests/DisplayMeshMacMediaHarnessTests/ReceiverAdaptiveControllerTests.swift"
if not adaptive_controller.exists() or not adaptive_tests.exists():
    raise SystemExit("adaptive contract failed: macOS receiver adaptation source/tests are missing")

media_main_path = ROOT / "platforms/macos/media-harness/Sources/DisplayMeshMacMediaHarness/DisplayMeshMacMediaHarnessMain.swift"
if not media_main_path.exists():
    raise SystemExit("macOS media contract failed: @main entry point source is missing")
media_main = media_main_path.read_text(encoding="utf-8")
if "@main" not in media_main:
    raise SystemExit("macOS media contract failed: entry point must use @main")
for token in [
    "ReceiverAdaptiveController(",
    "encoder?.setBitrate",
    "decision.requestKeyframe",
]:
    if token not in media_main:
        raise SystemExit(f"adaptive contract failed: macOS media harness missing {token}")

receiver_pairing = ROOT / "platforms/apple-receiver/Protocol/PairingMessage.swift"
pairing_text = receiver_pairing.read_text(encoding="utf-8")
for token in ["ReceiverHello", "P256.Signing.PublicKey", "isAuthentic"]:
    if token not in pairing_text:
        raise SystemExit(f"security contract failed: signed receiver pairing missing {token}")

connection_source = (ROOT / "platforms/macos/media-harness/Sources/DisplayMeshMacMediaHarness/ReceiverConnection.swift").read_text(encoding="utf-8")
for token in [
    "HostProtocolGate.permits",
    "invalidReceiverTelemetry",
    "invalidPairingResponse",
    "roundTripTracker",
    "DMPMessageType.pong",
]:
    if token not in connection_source:
        raise SystemExit(f"host protocol gate contract failed: missing {token}")

encoder_source = (ROOT / "platforms/macos/media-harness/Sources/DisplayMeshMacMediaHarness/DisplayCaptureEncoder.swift").read_text(encoding="utf-8")
for token in ["alreadyRunning", "setBitrate(mbps:", "didStopWithError"]:
    if token not in encoder_source:
        raise SystemExit(f"media lifecycle contract failed: missing {token}")

if "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" not in identity_text:
    raise SystemExit("security contract failed: host identity must remain device-only in Keychain")

for token in ["waitForReceiverCapabilities()", "supportsDevelopmentHost"]:
    if token not in media_main:
        raise SystemExit(f"capability negotiation contract failed: macOS harness missing {token}")

windows_protocol = ROOT / "platforms/windows/protocol"
for relative in [
    "DmpFrame.h",
    "DmpFrame.cpp",
    "CMakeLists.txt",
    "tests/DmpFrameTests.cpp",
]:
    if not (windows_protocol / relative).exists():
        raise SystemExit(f"windows protocol contract failed: missing {relative}")

windows_frame = (windows_protocol / "DmpFrame.cpp").read_text(encoding="utf-8")
for token in ["ValidatePayloadSize", "DmpSequenceTracker::Accept", "kDmpMaximumPayloadSize"]:
    if token not in windows_frame:
        raise SystemExit(f"windows protocol contract failed: missing {token}")

windows_gate = windows_protocol / "DmpHostSessionGate.cpp"
windows_gate_header = windows_protocol / "DmpHostSessionGate.h"
windows_gate_tests = windows_protocol / "tests/DmpHostSessionGateTests.cpp"
for path in [windows_gate, windows_gate_header, windows_gate_tests]:
    if not path.exists():
        raise SystemExit(f"windows session gate contract failed: missing {path.relative_to(ROOT)}")

gate_source = windows_gate.read_text(encoding="utf-8")
gate_header = windows_gate_header.read_text(encoding="utf-8")
for token in [
    "AwaitingHello",
    "AwaitingPairingResponse",
    "AwaitingCapabilities",
    "AwaitingPanel",
    "Streaming",
    "CanRouteInput",
    "CanSendVideo",
]:
    if token not in gate_source and token not in gate_header:
        raise SystemExit(f"windows session gate contract failed: missing {token}")

windows_input = (ROOT / "platforms/windows/input-bridge/DmpInput.cpp").read_text(encoding="utf-8")
if 'payload[3] != 0' not in windows_input:
    raise SystemExit("windows input contract failed: reserved DMP flags are not rejected")

windows_input_router = ROOT / "platforms/windows/input-bridge/DmpInputRouter.cpp"
windows_input_router_tests = ROOT / "platforms/windows/input-bridge/tests/DmpInputRouterTests.cpp"
for path in [windows_input_router, windows_input_router_tests]:
    if not path.exists():
        raise SystemExit(f"windows input routing contract failed: missing {path.relative_to(ROOT)}")

input_router_source = windows_input_router.read_text(encoding="utf-8")
for token in [
    "CanRouteInput",
    "DmpMessageType::Input",
    "DecodeInputSample",
]:
    if token not in input_router_source:
        raise SystemExit(f"windows input routing contract failed: missing {token}")

windows_worker = ROOT / "platforms/windows/media-harness/BoundedEncodeWorker.cpp"
windows_worker_header = ROOT / "platforms/windows/media-harness/BoundedEncodeWorker.h"
windows_worker_tests = ROOT / "platforms/windows/media-harness/tests/BoundedEncodeWorkerTests.cpp"
for path in [windows_worker, windows_worker_header, windows_worker_tests]:
    if not path.exists():
        raise SystemExit(f"windows encode scheduling contract failed: missing {path.relative_to(ROOT)}")

worker_source = windows_worker.read_text(encoding="utf-8")
for token in ["pending_", "droppedPending", "discardedOnStop", "handlerFailures"]:
    if token not in worker_source and token not in windows_worker_header.read_text(encoding="utf-8"):
        raise SystemExit(f"windows encode scheduling contract failed: missing {token}")

windows_packetizer = ROOT / "platforms/windows/media-harness/H264AnnexBPacketizer.cpp"
windows_packetizer_header = ROOT / "platforms/windows/media-harness/H264AnnexBPacketizer.h"
windows_packetizer_tests = ROOT / "platforms/windows/media-harness/tests/H264AnnexBPacketizerTests.cpp"
windows_packetizer_integration = ROOT / "platforms/windows/media-harness/tests/H264DmpFrameIntegrationTests.cpp"
for path in [
    windows_packetizer,
    windows_packetizer_header,
    windows_packetizer_tests,
    windows_packetizer_integration,
]:
    if not path.exists():
        raise SystemExit(f"windows H.264 packetizer contract failed: missing {path.relative_to(ROOT)}")

packetizer_source = windows_packetizer.read_text(encoding="utf-8")
packetizer_integration_source = windows_packetizer_integration.read_text(encoding="utf-8")
for token in ["EncodeDmpFrame", "DecodeDmpFrame", "DmpMessageType::Video"]:
    if token not in packetizer_integration_source:
        raise SystemExit(f"windows H.264/DMP integration contract failed: missing {token}")
for token in [
    "kNalSps",
    "kNalPps",
    "kNalIdr",
    "kDmpMaximumPayloadSize",
    "insertedSps",
    "insertedPps",
]:
    if token not in packetizer_source and token not in windows_packetizer_header.read_text(encoding="utf-8"):
        raise SystemExit(f"windows H.264 packetizer contract failed: missing {token}")

workflow_source = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
for token in [
    "windows-protocol:",
    "Test DMP framing contract",
    "Test bounded encode worker",
    "windows-media-harness",
]:
    if token not in workflow_source:
        raise SystemExit(f"windows CI contract failed: missing {token}")

secure_session_paths = [
    ROOT / "platforms/apple-receiver/Sources/DMPSecureSession.swift",
    ROOT / "platforms/macos/media-harness/Sources/DisplayMeshMacMediaHarness/DMPSecureSession.swift",
]
for path in secure_session_paths:
    if not path.exists():
        raise SystemExit(
            f"security contract failed: missing {path.relative_to(ROOT)}"
        )
    content = path.read_text(encoding="utf-8")
    for token in [
        "ChaChaPoly",
        "DMP1-HOST-TO-RECEIVER",
        "DMP1-RECEIVER-TO-HOST",
        "additionalAuthenticatedData",
    ]:
        if token not in content:
            raise SystemExit(
                f"security contract failed: {path.relative_to(ROOT)} missing {token}"
            )

print(
    f"PASS: DisplayMesh {version} protocol/session/media contracts, "
    "Windows framing, adaptive transport, secure-session primitive, "
    "and native harness scaffolds"
)


# Windows adaptive quality parity.
windows_adaptive = ROOT / "platforms/windows/media-harness/ReceiverAdaptiveController.cpp"
windows_adaptive_tests = ROOT / "platforms/windows/media-harness/tests/ReceiverAdaptiveControllerTests.cpp"
for path in [windows_adaptive, windows_adaptive_tests]:
    if not path.exists():
        raise SystemExit(
            f"windows adaptive contract failed: missing {path.relative_to(ROOT)}"
        )
adaptive_source = windows_adaptive.read_text(encoding="utf-8")
for token in [
    "0.85",
    "0.75",
    "0.67",
    "severeRasterStressSamples_",
    "rasterRecoverySamples_",
    "decodeQueueDepth",
]:
    if token not in adaptive_source:
        raise SystemExit(
            f"windows adaptive contract failed: missing {token}"
        )


# Windows Release test targets must keep assert() active.
for relative in [
    "platforms/windows/input-bridge/CMakeLists.txt",
    "platforms/windows/bridge-probe/CMakeLists.txt",
    "platforms/windows/media-harness/CMakeLists.txt",
]:
    content = (ROOT / relative).read_text(encoding="utf-8")
    if "add_compile_options(/UNDEBUG)" not in content:
        raise SystemExit(
            f"windows test contract failed: {relative} disables assert() in Release CI"
        )
