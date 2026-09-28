#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECEIVER = ROOT / "platforms" / "apple-receiver"
KEY_PATTERN = re.compile(r'^"([^"]+)"\s*=')

required_files = [
    RECEIVER / "project.yml",
    RECEIVER / "App" / "DisplayMeshReceiverApp.swift",
    RECEIVER / "App" / "ReceiverRootView.swift",
    RECEIVER / "App" / "ReceiverViewModel.swift",
    RECEIVER / "Protocol" / "DMPFrame.swift",
    RECEIVER / "Protocol" / "DMPVideoPacket.swift",
    RECEIVER / "Protocol" / "DMPInputPacket.swift",
    RECEIVER / "Protocol" / "PairingMessage.swift",
    RECEIVER / "Protocol" / "ReceiverCapabilities.swift",
    RECEIVER / "Resources" / "en.lproj" / "Localizable.strings",
    RECEIVER / "Resources" / "es.lproj" / "Localizable.strings",
    RECEIVER / "Resources" / "en.lproj" / "InfoPlist.strings",
    RECEIVER / "Resources" / "es.lproj" / "InfoPlist.strings",
    RECEIVER / "Resources" / "PrivacyInfo.xcprivacy",
    RECEIVER / "Tests" / "DMPFrameTests.swift",
    RECEIVER / "Tests" / "DMPVideoPacketTests.swift",
    RECEIVER / "Tests" / "DMPInputPacketTests.swift",
    RECEIVER / "Tests" / "PairingIdentityTests.swift",
    RECEIVER / "Tests" / "PanelDescriptorTests.swift",
    RECEIVER / "Sources" / "TrustedPeerStore.swift",
    RECEIVER / "Sources" / "ReceiverProtocolGate.swift",
    RECEIVER / "Tests" / "ReceiverProtocolGateTests.swift",
]

errors: list[str] = []

for path in required_files:
    if not path.is_file():
        errors.append(f"missing required receiver file: {path.relative_to(ROOT)}")


def string_keys(path: Path) -> tuple[set[str], set[str]]:
    keys: set[str] = set()
    duplicates: set[str] = set()

    if not path.is_file():
        return keys, duplicates

    for raw in path.read_text(encoding="utf-8").splitlines():
        match = KEY_PATTERN.match(raw.strip())
        if not match:
            continue

        key = match.group(1)
        if key in keys:
            duplicates.add(key)
        keys.add(key)

    return keys, duplicates


en_path = RECEIVER / "Resources" / "en.lproj" / "Localizable.strings"
es_path = RECEIVER / "Resources" / "es.lproj" / "Localizable.strings"
en_keys, en_duplicates = string_keys(en_path)
es_keys, es_duplicates = string_keys(es_path)

if en_duplicates:
    errors.append("duplicate English localization keys: " + ", ".join(sorted(en_duplicates)))
if es_duplicates:
    errors.append("duplicate Spanish localization keys: " + ", ".join(sorted(es_duplicates)))

missing_es = en_keys - es_keys
missing_en = es_keys - en_keys

if missing_es:
    errors.append("missing Spanish localization keys: " + ", ".join(sorted(missing_es)))
if missing_en:
    errors.append("missing English localization keys: " + ", ".join(sorted(missing_en)))

project = RECEIVER / "project.yml"
if project.is_file():
    project_text = project.read_text(encoding="utf-8")
    for required_token in (
        "DisplayMeshReceiverTests",
        "Resources",
        "NSBonjourServices",
        "_displaymesh._tcp",
        "NSLocalNetworkUsageDescription",
        "MARKETING_VERSION: 0.2.2",
        "CURRENT_PROJECT_VERSION: 3",
        "SWIFT_STRICT_CONCURRENCY: targeted",
        "ITSAppUsesNonExemptEncryption: false",
    ):
        if required_token not in project_text:
            errors.append(f"project.yml is missing required token: {required_token}")

privacy = RECEIVER / "Resources" / "PrivacyInfo.xcprivacy"
if privacy.is_file():
    import plistlib
    with privacy.open("rb") as handle:
        manifest = plistlib.load(handle)
    if manifest.get("NSPrivacyTracking") is not False:
        errors.append("receiver privacy manifest must declare tracking=false")
    reasons = {
        item.get("NSPrivacyAccessedAPIType"): set(item.get("NSPrivacyAccessedAPITypeReasons", []))
        for item in manifest.get("NSPrivacyAccessedAPITypes", [])
    }
    if "CA92.1" not in reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", set()):
        errors.append("receiver privacy manifest is missing UserDefaults reason CA92.1")

root_readme = ROOT / "README.md"
if root_readme.is_file() and "Current `main`: 0.2.2" not in root_readme.read_text(encoding="utf-8"):
    errors.append("root README version does not match receiver 0.2.2")

settings = RECEIVER / "App" / "SettingsView.swift"
if settings.is_file():
    settings_text = settings.read_text(encoding="utf-8")
    forbidden_claims = ("TLS 1.3 enabled", "Encrypted transport active")
    for claim in forbidden_claims:
        if claim in settings_text:
            errors.append(f"development receiver makes unsupported security claim: {claim}")

frame_source = RECEIVER / "Protocol" / "DMPFrame.swift"
if frame_source.is_file():
    frame_text = frame_source.read_text(encoding="utf-8")
    for required_token in (
        "DMPSequenceTracker",
        "ReceiverTelemetry",
        "unexpectedSequence",
        "maximumPayloadSize",
        "invalidPayloadLength",
        "payloadTooLargeForMessage",
    ):
        if required_token not in frame_text:
            errors.append(f"receiver protocol hardening is missing token: {required_token}")

view_model = RECEIVER / "App" / "ReceiverViewModel.swift"
if view_model.is_file():
    view_model_text = view_model.read_text(encoding="utf-8")
    for required_token in (
        "admissionTimeoutTask",
        "scheduleAdmissionTimeout",
        "PairingValidationError.admissionExpired",
        "pairingTimeoutTask",
        "sendTelemetryIfNeeded",
        "PairingValidationError.expired",
        "sendReceiverHello",
        "trustedPeerStore",
        "maximumInvalidPairingAttempts",
        "ReceiverProtocolGate.permits",
        "disconnectCurrent",
    ):
        if required_token not in view_model_text:
            errors.append(f"receiver lifecycle hardening is missing token: {required_token}")

trust_store = RECEIVER / "Sources" / "TrustedPeerStore.swift"
if trust_store.is_file():
    trust_text = trust_store.read_text(encoding="utf-8")
    for required_token in (
        "KeychainTrustedPeerPersistence",
        "SecItemCopyMatching",
        "SecItemUpdate",
        "SecItemAdd",
        "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly",
    ):
        if required_token not in trust_text:
            errors.append(f"receiver trust-store hardening is missing token: {required_token}")

pairing_source = RECEIVER / "Protocol" / "PairingMessage.swift"
if pairing_source.is_file():
    pairing_text = pairing_source.read_text(encoding="utf-8")
    for required_token in (
        "P256.Signing.PublicKey",
        "isAuthentic",
        "ReceiverHello",
        "identityFingerprint",
        "challenge: Data",
        "isValid(expectedChallenge:",
    ):
        if required_token not in pairing_text:
            errors.append(f"signed pairing contract is missing token: {required_token}")

listener_source = (RECEIVER / "Sources" / "ReceiverListener.swift").read_text(encoding="utf-8")
if 'name: UIDevice.current.name' in listener_source:
    errors.append("privacy contract failed: Bonjour service must not expose UIDevice.current.name")
if 'guard connection == nil else' not in listener_source:
    errors.append("transport contract failed: active receiver connection must reject replacement peers")

panel_source = (RECEIVER / "Sources" / "PanelDescriptor.swift").read_text(encoding="utf-8")
if "var isValid: Bool" not in panel_source:
    errors.append("panel contract failed: receiver panel descriptor validation is missing")

capabilities_source = (RECEIVER / "Protocol" / "ReceiverCapabilities.swift").read_text(encoding="utf-8")
for required_token in (
    'codecs: [Self.h264]',
    'connectionBindings: [Self.tcp]',
    'encryptedTransport: false',
    'supportsDevelopmentHost',
):
    if required_token not in capabilities_source:
        errors.append(f"receiver capabilities contract is missing token: {required_token}")

workflow = ROOT / ".github" / "workflows" / "ci.yml"
if workflow.is_file():
    workflow_text = workflow.read_text(encoding="utf-8")
    for required_token in (
        "Build Release receiver for iOS Simulator",
        "Build Release receiver for iPhoneOS",
        "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES",
    ):
        if required_token not in workflow_text:
            errors.append(f"receiver CI is missing required token: {required_token}")

if errors:
    print("Apple receiver validation failed:")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

print(
    "Apple receiver validation passed: "
    f"{len(en_keys)} localized UI keys, EN/ES parity, required project/test files present."
)
