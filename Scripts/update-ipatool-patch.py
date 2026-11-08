#!/usr/bin/env python3
"""Record only intentional changes relative to the pinned source archive."""
import difflib
import pathlib
import tarfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PATHS = [
    'main.go', 'internal/sap/assets/assets.go', 'internal/sap/assets/remote.go',
    'internal/sap/assets/kernel.go', 'internal/sap/assets/bridge_prepare.go',
    'internal/sap/assets/bridge_prepare_test.go', 'cmd/auth.go', 'cmd/prompt.go',
    'cmd/bridge_auth_input.go', 'cmd/bridge_auth_input_test.go',
    'pkg/appstore/appstore_login.go', 'pkg/appstore/bridge_auth_code_test.go',
    'pkg/appstore/appstore_bag.go', 'pkg/appstore/bridge_prepare_bag.go',
    'internal/sap/protocol.go', 'internal/sap/signer_local.go',
    'internal/sap/bridge_transport.go', 'internal/sap/bridge_transport_test.go',
]
patch = []
with tarfile.open(ROOT / 'Vendor/ipatool/source-001d889.tar.gz') as archive:
    prefix = archive.getmembers()[0].name.split('/')[0]
    for name in PATHS:
        try:
            previous = archive.extractfile(prefix + '/' + name).read().decode()
        except KeyError:
            previous = ''
        current = (ROOT / '.build/ipatool-upstream' / name).read_text()
        patch.extend(difflib.unified_diff(previous.splitlines(keepends=True), current.splitlines(keepends=True),
                     fromfile='a/' + name if previous else '/dev/null', tofile='b/' + name))
(ROOT / 'Vendor/ipatool/bridge-preparation.patch').write_text(''.join(patch))
