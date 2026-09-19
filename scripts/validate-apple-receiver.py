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
    RECEIVER / "Protocol" / "PairingMessage.swift",
    RECEIVER / "Resources" / "en.lproj" / "Localizable.strings",
    RECEIVER / "Resources" / "es.lproj" / "Localizable.strings",
    RECEIVER / "Resources" / "en.lproj" / "InfoPlist.strings",
    RECEIVER / "Resources" / "es.lproj" / "InfoPlist.strings",
    RECEIVER / "Tests" / "DMPFrameTests.swift",
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
    ):
        if required_token not in project_text:
            errors.append(f"project.yml is missing required token: {required_token}")

settings = RECEIVER / "App" / "SettingsView.swift"
if settings.is_file():
    settings_text = settings.read_text(encoding="utf-8")
    forbidden_claims = ("TLS 1.3 enabled", "Encrypted transport active")
    for claim in forbidden_claims:
        if claim in settings_text:
            errors.append(f"development receiver makes unsupported security claim: {claim}")

if errors:
    print("Apple receiver validation failed:")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

print(
    "Apple receiver validation passed: "
    f"{len(en_keys)} localized UI keys, EN/ES parity, required project/test files present."
)
