#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_DIR="${BB_THREAD_STORAGE:-$ROOT/.build}"
mkdir -p "$ROOT/.build/module-cache" "$REPORT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
clang -fobjc-arc -O2 -mmacosx-version-min=14.0 -framework Foundation -larchive "$ROOT/Sources/DeviceBridge.m" -o "$ROOT/.build/device-bridge-test"
python3 "$ROOT/Tests/test_packages.py" "$ROOT/.build/device-bridge-test" "$REPORT_DIR/packages-tests.json"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$ROOT/.build/module-cache" \
  "$ROOT/Sources/Models.swift" "$ROOT/Tests/ModelTests.swift" -o "$ROOT/.build/model-tests"
"$ROOT/.build/model-tests" "$REPORT_DIR/models-tests.json"
swiftc -swift-version 5 -parse-as-library -module-cache-path "$ROOT/.build/module-cache" \
  "$ROOT/Sources/Models.swift" "$ROOT/Sources/Services.swift" "$ROOT/Tests/ServiceTests.swift" -o "$ROOT/.build/service-tests"
SERVICE_ROOT="$(mktemp -d "$ROOT/.build/service-test.XXXXXX")"
trap 'rm -rf "$SERVICE_ROOT"' EXIT
python3 - "$SERVICE_ROOT/fixture.ipa" <<'PY'
import plistlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    archive.writestr('Payload/Test.app/Info.plist', plistlib.dumps({'CFBundleIdentifier': 'test.example.app', 'CFBundleDisplayName': 'Тест', 'CFBundleShortVersionString': '1.0', 'MinimumOSVersion': '16.0', 'UIDeviceFamily': [1]}))
PY
mkdir -p "$SERVICE_ROOT/bin"
cp "$ROOT/.build/device-bridge-test" "$SERVICE_ROOT/bin/device-bridge"
"$ROOT/.build/service-tests" "$SERVICE_ROOT/data" "$SERVICE_ROOT/bin" "$SERVICE_ROOT/fixture.ipa" "$REPORT_DIR/services-tests.json"
python3 - "$REPORT_DIR" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
results = json.loads((root / 'packages-tests.json').read_text()) + json.loads((root / 'models-tests.json').read_text()) + json.loads((root / 'services-tests.json').read_text())
(root / 'tests.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
print(f"All checks: {len(results)} passed")
PY
