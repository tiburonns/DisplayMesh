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

print(
    f"PASS: DisplayMesh {version} documentation, protocol status, "
    "security, and native harness contract"
)
