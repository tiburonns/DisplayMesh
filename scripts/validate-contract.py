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
for token in ["maximum_payload_len", "PayloadTooLargeForType", "InvalidPayloadLength"]:
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

receiver_pairing = ROOT / "platforms/apple-receiver/Protocol/PairingMessage.swift"
pairing_text = receiver_pairing.read_text(encoding="utf-8")
for token in ["ReceiverHello", "P256.Signing.PublicKey", "isAuthentic"]:
    if token not in pairing_text:
        raise SystemExit(f"security contract failed: signed receiver pairing missing {token}")

print(
    f"PASS: DisplayMesh {version} documentation, protocol status, "
    "security, and native harness contract"
)
