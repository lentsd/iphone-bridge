#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$ROOT/Vendor/ipatool/source-001d889.tar.gz"
EXPECTED="8b61a6925409a2fb669be92d83df6bfae7a8ccfbb03f567fe7ec80240934dd11"
ACTUAL="$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)"
if [ "$ACTUAL" != "$EXPECTED" ]; then echo "Unexpected ipatool source checksum" >&2; exit 1; fi
mkdir -p "$ROOT/.build" "$ROOT/Vendor/ipatool/bin"
SOURCE_DIR="$(mktemp -d "$ROOT/.build/ipatool-source.XXXXXX")"
trap 'rm -rf "$SOURCE_DIR"' EXIT
tar -xzf "$ARCHIVE" -C "$SOURCE_DIR" --strip-components=1
patch -s -p1 -d "$SOURCE_DIR" < "$ROOT/Vendor/ipatool/bridge-preparation.patch"
cd "$SOURCE_DIR"
python3 "$ROOT/Scripts/go-with-curl.py" go build -mod=readonly -trimpath \
  -ldflags '-s -w -X github.com/majd/ipatool/v2/cmd.version=2.7.0+001d889.bridge6' \
  -o "$ROOT/Vendor/ipatool/bin/ipatool.next" .
mv -f "$ROOT/Vendor/ipatool/bin/ipatool.next" "$ROOT/Vendor/ipatool/bin/ipatool"
chmod 755 "$ROOT/Vendor/ipatool/bin/ipatool"
python3 - "$ROOT" <<'PY'
import hashlib,json,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1])/'Vendor/ipatool'
metadata={'tool':'ipatool','version':'2.7.0+001d889.bridge6','source_commit':'001d889896fcb118546443c5dfe0997d11b74f56','source_url':'https://github.com/majd/ipatool/commit/001d889896fcb118546443c5dfe0997d11b74f56','source_archive_sha256':hashlib.sha256((root/'source-001d889.tar.gz').read_bytes()).hexdigest(),'local_patch':'bridge-preparation.patch','local_patch_sha256':hashlib.sha256((root/'bridge-preparation.patch').read_bytes()).hexdigest(),'local_source_modifications':True,'binary_sha256_before_app_signing':hashlib.sha256((root/'bin/ipatool').read_bytes()).hexdigest(),'compiler':subprocess.check_output(['go','version'],text=True).strip()}
(root/'PROVENANCE.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
PY
