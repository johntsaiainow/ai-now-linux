import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import ainow_kernel


class KernelTests(unittest.TestCase):
    def test_download_and_install_keep_bundled_entry(self):
        release = "7.1.8-ainow-test"
        image = bytearray(1024)
        image[0x202:0x206] = b"HdrS"
        image[0x20e:0x210] = b"\x80\x00"
        image[0x236] = 1
        image[0x280:0x280 + len(release)] = release.encode()
        payload = io.BytesIO()
        with tarfile.open(fileobj=payload, mode="w:gz") as archive:
            for name, contents in (
                ("bzImage", image),
                (f"lib/modules/{release}/modules.dep", b""),
            ):
                header = tarfile.TarInfo(name)
                header.size = len(contents)
                archive.addfile(header, io.BytesIO(contents))
        compressed = payload.getvalue()
        entry = dict(name="Custom kernel", arch="x86_64", release=release,
                     sha256=hashlib.sha256(compressed).hexdigest(),
                     size=len(compressed), url="https://example.com/kernel.tar.gz")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            catalog = root / "catalog.json"
            catalog.write_text(json.dumps([dict(entry, arch="i686"), entry]))
            self.assertEqual(ainow_kernel.read_catalog(catalog, "x86_64"), [entry])

            class Response(io.BytesIO):
                def geturl(self):
                    return entry["url"]

            with (patch("ainow_kernel.urlopen", return_value=Response(compressed)),
                  patch("ainow_kernel.architecture", return_value="x86_64"),
                  patch("builtins.input", return_value="1")):
                kernel = ainow_kernel.prepare_kernel(catalog, root)

            target = root / "target"
            grub = target / "boot/grub/grub.cfg"
            grub.parent.mkdir(parents=True)
            original = ("set default=graphics\nmenuentry 'Console' --id graphics {\n"
                        "    search --fs-uuid --set=root fixture\n"
                        "    linux /boot/vmlinuz root=PARTUUID=abcd1234-01\n"
                        "    initrd /boot/initrd.img\n}\n")
            grub.write_text(original)
            fallback = target / "boot/vmlinuz"
            fallback.write_text("bundled")
            with patch("subprocess.run", side_effect=[None, subprocess.CalledProcessError(1, "depmod")]):
                with self.assertRaises(subprocess.CalledProcessError):
                    ainow_kernel.install_kernel(target, kernel)
            self.assertEqual(grub.read_text(), original)
            self.assertFalse((target / f"lib/modules/{release}").exists())
            with patch("subprocess.run") as commands:
                ainow_kernel.install_kernel(target, kernel)
            self.assertEqual(commands.call_count, 2)
            self.assertIn("set default=selected-kernel", grub.read_text())
            self.assertIn(original.split("\n", 1)[1], grub.read_text())
            self.assertEqual(fallback.read_text(), "bundled")

    def test_download_rejects_wrong_checksum(self):
        class Response(io.BytesIO):
            def geturl(self):
                return "https://example.com/kernel.tar.gz"

        entry = dict(size=6, sha256="0" * 64, url="https://example.com/kernel.tar.gz")
        with tempfile.TemporaryDirectory() as root:
            with patch("ainow_kernel.urlopen", return_value=Response(b"kernel")):
                with self.assertRaisesRegex(ValueError, "SHA256"):
                    ainow_kernel.download(entry, Path(root) / "kernel.tar.gz")


if __name__ == "__main__":
    unittest.main()
