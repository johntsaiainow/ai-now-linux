from contextlib import contextmanager
import hashlib
import importlib.machinery
import importlib.util
import io
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/ainstall"
loader = importlib.machinery.SourceFileLoader("ainstall", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
ainstall = importlib.util.module_from_spec(spec)
loader.exec_module(ainstall)


class InstallTests(unittest.TestCase):
    def setUp(self):
        workspace = tempfile.TemporaryDirectory()
        self.addCleanup(workspace.cleanup)
        root = Path(workspace.name)
        self.image = root / "payload.img"
        self.output = root / "installed.img"
        # A synthetic partition layout for the installer, not a bootable OS.
        self.payload = bytearray(2 * 1024 * 1024)
        self.payload[0:2] = b"\xeb\xfe"
        self.payload[510:512] = b"\x55\xaa"
        self.payload[446] = 0x80
        self.payload[450] = 0x83
        struct.pack_into("<II", self.payload, 454, 2048, 2048)
        self.image.write_bytes(self.payload)

    def cli(self, *options, expected=None, target=None):
        if expected is None:
            expected = hashlib.sha256(self.image.read_bytes()).hexdigest()
        target = target or ("--output", str(self.output))
        return subprocess.run(
            [str(SCRIPT), "--image", str(self.image), "--sha256", expected, *target, *options],
            capture_output=True, text=True,
        )

    def test_preview_does_not_create_file(self):
        result = self.cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No data written", result.stdout)
        self.assertFalse(self.output.exists())

    def test_rehearsal_matches_verified_input(self):
        result = self.cli("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_bytes(), self.payload)
        self.assertIn("Installation verified", result.stdout)

    def test_wrong_sha256_leaves_no_destination(self):
        result = self.cli("--apply", expected="0" * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SHA256 mismatch", result.stderr)
        self.assertFalse(self.output.exists())

    def test_guided_setup_requires_an_applied_disk_install(self):
        result = self.cli("--apply", "--configure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--configure requires --disk and --apply", result.stderr)
        self.assertFalse(self.output.exists())

    def test_boot_layout_validated_before_writing(self):
        for offset, value in [(512, b"EFI PART"), (450, b"\xee"), (454, b"\x01\x00")]:
            with self.subTest(offset=offset):
                bad = self.payload.copy()
                bad[offset:offset + len(value)] = value
                self.image.write_bytes(bad)
                result = self.cli("--apply")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.output.exists())

    def test_rehearsal_never_overwrites_existing_file_or_symlink(self):
        self.output.write_bytes(b"keep")
        self.assertNotEqual(self.cli("--apply").returncode, 0)
        self.assertEqual(self.output.read_bytes(), b"keep")
        self.output.unlink()
        self.output.symlink_to(self.image)
        self.assertNotEqual(self.cli("--apply").returncode, 0)
        self.assertTrue(self.output.is_symlink())
        self.assertEqual(self.image.read_bytes(), self.payload)

    def test_disk_requires_stable_device_identifier(self):
        result = self.cli("--apply", target=("--disk", str(self.output)))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("/dev/disk/by-id/", result.stderr)
        self.assertFalse(self.output.exists())

    def test_disk_refuses_to_write_before_interactive_confirmation(self):
        size = len(self.payload)
        path = Path("/dev/disk/by-id/ata-test")
        initial = b"x" * (size + 512)
        device = io.BytesIO(initial)
        details = {"model": "test", "serial": "123"}

        @contextmanager
        def exclusive_disk(*args):
            yield device, details, len(initial)

        with patch.object(ainstall, "exclusive_disk", exclusive_disk):
            with patch.object(ainstall.sys.stdin, "isatty", return_value=False):
                with self.assertRaisesRegex(ainstall.InstallError, "interactive"):
                    ainstall.disk_target(io.BytesIO(self.payload), path, size, "0" * 64, True)
            with patch.object(ainstall.sys.stdin, "isatty", return_value=True):
                with patch("builtins.input", return_value="yes"):
                    with self.assertRaisesRegex(ainstall.InstallError, "confirmation"):
                        ainstall.disk_target(io.BytesIO(self.payload), path, size, "0" * 64, True)
        self.assertEqual(device.getvalue(), initial)


class BuildImagePreflightTests(unittest.TestCase):
    def setUp(self):
        workspace = tempfile.TemporaryDirectory()
        self.addCleanup(workspace.cleanup)
        self.work = Path(workspace.name)
        self.rootfs = self.work / "rootfs"
        for directory in ("etc", "usr"):
            (self.rootfs / directory).mkdir(parents=True)
        self.kernel = self.work / "bzImage"
        self.kernel.write_bytes(b"kernel fixture")
        self.builder = SCRIPT.with_name("build-bios-image.sh")

    def build(self, size, output):
        return subprocess.run(
            [str(self.builder), str(self.rootfs), str(self.kernel), size, str(output)],
            capture_output=True, text=True,
        )

    def test_reject_existing_image_before_needing_root(self):
        output = self.work / "existing.img"
        output.write_bytes(b"retain")
        result = self.build("128", output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("output must be a new file", result.stderr)
        self.assertEqual(output.read_bytes(), b"retain")

    def test_reject_output_inside_rootfs(self):
        output = self.rootfs / "recursive.img"
        result = self.build("128", output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the staged rootfs", result.stderr)
        self.assertFalse(output.exists())

    def test_reject_bad_size_without_creating_output(self):
        output = self.work / "new.img"
        for size in ("127", "0128", "2097152"):
            with self.subTest(size=size):
                result = self.build(size, output)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("image size", result.stderr)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
