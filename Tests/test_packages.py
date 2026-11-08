"""Exercise archive parsing without device or Apple Account access."""
import json
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

HELPER = pathlib.Path(sys.argv[1]).resolve()
REPORT = pathlib.Path(sys.argv[2])
sys.argv = sys.argv[:1]


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="iphone-bridge-test-")
        self.root = pathlib.Path(self.folder.name)

    def tearDown(self):
        self.folder.cleanup()

    def manifest(self, **changes):
        value = {"CFBundleIdentifier": "test.example.app", "CFBundleDisplayName": "Тестовое приложение",
                 "CFBundleShortVersionString": "1.2.3", "MinimumOSVersion": "16.0", "UIDeviceFamily": [1, 2]}
        value.update(changes)
        return value

    def package(self, manifest=None, entries=None, binary=False):
        path = self.root / "пакет с пробелом.ipa"
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            if manifest is not None:
                archive.writestr("Payload/Example.app/Info.plist", plistlib.dumps(manifest, fmt=plistlib.FMT_BINARY if binary else plistlib.FMT_XML))
            for key, value in (entries or {}).items():
                archive.writestr(key, value)
        return path

    def command(self, *args):
        process = subprocess.run([str(HELPER), *map(str, args)], capture_output=True, text=True, timeout=15)
        result = json.loads(process.stdout.splitlines()[-1])
        self.assertEqual(process.returncode == 0, result["ok"])
        return result

    def test_xml_manifest_with_unicode_path(self):
        result = self.command("ipa-info", self.package(self.manifest()))
        self.assertTrue(result["ok"])
        self.assertEqual(result["app"]["bundleID"], "test.example.app")
        self.assertEqual(result["app"]["name"], "Тестовое приложение")
        self.assertEqual(result["app"]["minimumOS"], "16.0")

    def test_binary_manifest_and_numeric_store_id(self):
        package = self.package(self.manifest(), {"iTunesMetadata.plist": plistlib.dumps({"itemId": 123456789})}, binary=True)
        result = self.command("ipa-info", package)
        self.assertTrue(result["ok"])
        self.assertEqual(result["app"]["storeID"], "123456789")

    def test_missing_manifest_is_rejected(self):
        self.assertFalse(self.command("ipa-info", self.package(entries={"hello.txt": b"hello"}))["ok"])

    def test_duplicate_main_apps_are_rejected(self):
        package = self.package(self.manifest(), {"Payload/Second.app/Info.plist": plistlib.dumps(self.manifest())})
        self.assertFalse(self.command("ipa-info", package)["ok"])

    def test_ipad_only_package_is_rejected(self):
        self.assertFalse(self.command("ipa-info", self.package(self.manifest(UIDeviceFamily=[2])))["ok"])

    def test_invalid_bundle_id_is_rejected(self):
        self.assertFalse(self.command("ipa-info", self.package(self.manifest(CFBundleIdentifier="../../escape")))["ok"])

    def test_oversized_plist_is_rejected(self):
        package = self.package(entries={"Payload/Example.app/Info.plist": b"x" * (2 * 1024 * 1024 + 1)})
        self.assertFalse(self.command("ipa-info", package)["ok"])

    def test_invalid_plist_is_rejected(self):
        self.assertFalse(self.command("ipa-info", self.package(entries={"Payload/Example.app/Info.plist": b"not a plist"}))["ok"])

    def test_traversal_entries_are_not_extracted(self):
        marker = self.root / "outside.txt"
        package = self.package(self.manifest(), {"../../outside.txt": b"do not write"})
        self.assertTrue(self.command("ipa-info", package)["ok"])
        self.assertFalse(marker.exists())
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), [package.name])

    def test_corrupt_archive_is_rejected(self):
        path = self.root / "corrupt.ipa"
        path.write_bytes(b"this is not an ipa")
        self.assertFalse(self.command("ipa-info", path)["ok"])

    def test_same_source_and_target_rejected_before_device_access(self):
        result = self.command("install", "same-phone", "/missing.ipa", "test.example.app", "same-phone")
        self.assertFalse(result["ok"])
        self.assertIn("совпадают", result["error"])

    def test_incomplete_install_request_rejected(self):
        self.assertFalse(self.command("install", "target")["ok"])


class JsonResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.rows = []

    def addSuccess(self, test):
        super().addSuccess(test)
        self.rows.append({"name": test.id(), "status": "passed"})

    def addFailure(self, test, err):
        super().addFailure(test, err)
        self.rows.append({"name": test.id(), "status": "failed", "message": self._exc_info_to_string(err, test)})

    def addError(self, test, err):
        super().addError(test, err)
        self.rows.append({"name": test.id(), "status": "failed", "message": self._exc_info_to_string(err, test)})


suite = unittest.defaultTestLoader.loadTestsFromTestCase(PackageTests)
result = unittest.TextTestRunner(verbosity=2, resultclass=JsonResult).run(suite)
REPORT.write_text(json.dumps(result.rows, ensure_ascii=False, indent=2))
sys.exit(0 if result.wasSuccessful() else 1)
