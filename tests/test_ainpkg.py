import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/ainpkg"
loader = importlib.machinery.SourceFileLoader("ainpkg", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
ainpkg = importlib.util.module_from_spec(spec)
loader.exec_module(ainpkg)


class PackageTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.work = Path(tmp.name)
        self.root = self.work / "root"
        self.root.mkdir()
        self.db_path = self.root / "var/lib/ainpkg/state.sqlite"
        self.cli("init", "--arch", "x86_64", "--abi", "glibc-2.44", "--cpu", "x86-64-v1")

    def cli(self, *args, ok=True, env=None):
        result = subprocess.run([str(SCRIPT), "--root", str(self.root), *map(str, args)],
                                capture_output=True, text=True, env=env)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def package(self, files=None, version="1", name="demo", abi="glibc-2.44",
                filename=None):
        if files is None:
            files = {"usr/bin/demo": b"program", "etc/demo.conf": b"default"}
        with tempfile.TemporaryDirectory(dir=self.work) as temp:
            stage = Path(temp)
            for relative, data in files.items():
                path = stage / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
                path.chmod(0o755 if relative.startswith("usr/bin/") else 0o644)
            output = self.work / (filename or f"{name}-{version}.ainpkg")
            ainpkg.pack(output, dict(format=1, name=name, version=version,
                                     arch="x86_64", abi=abi, cpu="x86-64-v1"), stage)
            return output

    def test_lifecycle_preserves_modified_config(self):
        config = self.root / "etc/demo.conf"
        binary = self.root / "usr/bin/demo"
        self.cli("install", self.package())
        self.assertEqual(self.cli("list"), "demo\t1\n")
        self.assertEqual(self.cli("owner", "/usr/bin/demo"), "demo\n")
        config.write_bytes(b"site settings")
        self.cli("install", self.package(
            {"usr/bin/demo": b"new", "etc/demo.conf": b"new default"}, version="2"))
        self.assertEqual(binary.read_bytes(), b"new")
        self.assertIn("config modified", self.cli("verify", "demo"))
        self.cli("remove", "demo")
        self.assertFalse(binary.exists())
        self.assertEqual(config.read_bytes(), b"site settings")
        self.cli("owner", "/etc/demo.conf", ok=False)

    def test_preserves_unmanaged_config_and_installs_default_when_missing(self):
        config = self.root / "etc/demo.conf"
        config.parent.mkdir()
        config.write_bytes(b"pre-existing")
        archive = self.package()
        self.cli("install", archive)
        self.assertEqual(config.read_bytes(), b"pre-existing")
        config.unlink()
        self.cli("verify", "demo", ok=False)
        self.cli("install", archive)
        self.assertEqual(config.read_bytes(), b"default")
        self.cli("remove", "demo")
        self.assertFalse(config.exists())

    def test_mode_and_hash_verification(self):
        self.cli("install", self.package())
        binary = self.root / "usr/bin/demo"
        binary.chmod(0o644)
        self.assertIn("modified", self.cli("verify", ok=False))
        binary.chmod(0o755)
        binary.write_bytes(b"modified")
        self.cli("verify", ok=False)
        self.cli("remove", "demo")
        self.assertEqual(binary.read_bytes(), b"modified")

    def test_abi_conflict_and_unmanaged_file(self):
        self.cli("install", self.package(abi="glibc-2.36"), ok=False)
        self.assertEqual(self.cli("list"), "")
        archive = self.package(version="2")
        binary = self.root / "usr/bin/demo"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"unmanaged")
        self.cli("install", archive, ok=False)
        binary.unlink()
        self.cli("install", archive)
        self.cli("install", self.package(name="other"), ok=False)
        binary.unlink()
        self.cli("install", self.package({"usr/bin/demo/child": b"child"},
                                         name="nested"), ok=False)
        self.assertEqual(self.cli("list"), "demo\t2\n")

    def test_parent_symlink_and_hardlink_blocked(self):
        external = self.work / "external"
        external.mkdir()
        (self.root / "usr").symlink_to(external)
        archive = self.package()
        self.cli("install", archive, ok=False)
        self.assertEqual(list(external.iterdir()), [])
        (self.root / "usr").unlink()
        binary = self.root / "usr/bin/demo"
        binary.parent.mkdir(parents=True)
        data = external / "source"
        data.write_bytes(b"outside")
        os.link(data, binary)
        self.cli("install", archive, ok=False)
        self.assertEqual(data.read_bytes(), b"outside")

    def test_malicious_archive_paths_types_and_digest(self):
        raw = self.work / "crafted.tar"
        for index, (name, kind, data) in enumerate([
            ("usr/../../escape", tarfile.REGTYPE, b"x"),
            ("usr/bin/demo", tarfile.SYMTYPE, b""),
            ("usr/bin/demo", tarfile.REGTYPE, b"tampered"),
        ]):
            with self.subTest(name=name, kind=kind):
                manifest = dict(format=1, name="demo", version="1", arch="x86_64",
                                abi="glibc-2.44", cpu="x86-64-v1",
                                files={name: {"sha256": "0" * 64, "mode": 0o644}})
                with tarfile.open(raw, "w") as archive:
                    for path, entry_type, entry_data in [
                        ("manifest.json", tarfile.REGTYPE, json.dumps(manifest).encode()),
                        (name, kind, data),
                    ]:
                        item = tarfile.TarInfo(path)
                        item.type, item.size = entry_type, len(entry_data)
                        item.linkname = "/tmp/ainpkg-outside" if item.issym() else ""
                        archive.addfile(item, io.BytesIO(entry_data))
                output = self.work / f"crafted-{index}.ainpkg"
                subprocess.run(["zstd", "-q", str(raw), "-o", str(output)], check=True)
                self.cli("install", output, ok=False)
        self.assertFalse((self.root / "usr").exists())

    def test_interrupted_install_recovers_preimages(self):
        self.cli("install", self.package())
        binary = self.root / "usr/bin/demo"
        with sqlite3.connect(self.db_path) as db:
            db.execute("INSERT INTO undo VALUES (?, ?, ?)", ("usr/bin/demo", b"program", 0o755))
            db.execute("INSERT INTO undo VALUES (?, ?, ?)", ("usr/bin/partial", None, None))
        binary.write_bytes(b"partial")
        (binary.parent / "partial").touch()
        self.cli("verify", "demo")
        self.assertEqual(binary.read_bytes(), b"program")
        self.assertFalse((binary.parent / "partial").exists())

    def test_write_failure_rolls_back_within_call(self):
        archive = self.package()
        original = ainpkg.write_file

        def failing_write(path, data, mode):
            if path.name == "demo":
                raise OSError("injected write failure")
            original(path, data, mode)

        with ainpkg.database(self.root) as (root, db):
            with patch.object(ainpkg, "write_file", failing_write):
                with self.assertRaisesRegex(OSError, "injected"):
                    ainpkg.install(root, db, archive)
            self.assertEqual(db.execute("SELECT COUNT(*) FROM packages").fetchone(), (0,))
            self.assertEqual(db.execute("SELECT COUNT(*) FROM undo").fetchone(), (0,))
        self.assertFalse((self.root / "etc/demo.conf").exists())

    def test_competing_installs_have_one_owner(self):
        archives = [self.package(name=name) for name in ("first", "second")]
        commands = [[str(SCRIPT), "--root", str(self.root), "install", str(archive)]
                    for archive in archives]
        first = subprocess.Popen(commands[0], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with first:
            second = subprocess.run(commands[1], capture_output=True)
            first.communicate(timeout=15)
        self.assertEqual(sorted((first.returncode, second.returncode)), [0, 1])
        winner = "first" if first.returncode == 0 else "second"
        self.assertEqual(self.cli("owner", "/usr/bin/demo"), winner + "\n")
        self.cli("verify", winner)

    @unittest.skipIf(os.geteuid() == 0, "source builds reject root")
    def test_build_uses_committed_recipe_and_checks_source_pin(self):
        repo = self.work / "recipes"
        recipe = repo / "packages/demo"
        recipe.mkdir(parents=True)
        source = self.work / "source.tar"
        source.write_bytes(b"pinned source")
        (recipe / "recipe.toml").write_text(
            f'name = "demo"\nversion = "1"\n[cpu]\n'
            f'"{os.uname().machine}" = "baseline"\n[source]\n'
            f'sha256 = "{ainpkg.file_digest(source)}"\n'
        )
        script = recipe / "build.sh"
        script.write_text('set -eu\nmkdir -p "$DESTDIR/usr/bin"\n'
                          'cp "$SOURCE_ARCHIVE" "$DESTDIR/usr/bin/demo"\n')
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
        subprocess.run(["git", "-C", str(repo), "-c", "user.name=Test",
                        "-c", "user.email=test@example.invalid", "commit", "-qm", "Recipe"],
                       check=True)
        script.write_text("exit 99\n")
        output = self.work / "built.ainpkg"
        self.cli("build", "demo", "--repo", repo, "--source", source, "--output", output)
        manifest, entries = ainpkg.read_package(output)
        self.assertEqual(entries["usr/bin/demo"][0], b"pinned source")
        self.assertEqual(manifest["recipe_commit"], subprocess.check_output(
            ["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip())
        source.write_bytes(b"tampered source")
        rejected = self.work / "rejected.ainpkg"
        self.assertIn("source archive SHA256 mismatch",
                      self.cli("build", "demo", "--repo", repo, "--source", source,
                               "--output", rejected, ok=False))
        self.assertFalse(rejected.exists())

    def test_same_payload_produces_identical_archive(self):
        first = self.package(filename="first.ainpkg")
        second = self.package(filename="second.ainpkg")
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_release_commands_with_mock_gh(self):
        asset = self.package()
        gh = self.work / "gh"
        gh.write_text(
            '#!/bin/sh\n'
            'printf "%s\\n" "$@" > "$AINPKG_TEST_LOG"\n'
            'if [ "$2" = download ]; then cp "$AINPKG_TEST_ASSET" "$9/$7"; fi\n'
        )
        gh.chmod(0o755)
        log = self.work / "gh.log"
        env = dict(os.environ, PATH=f"{self.work}:{os.environ['PATH']}",
                   AINPKG_TEST_LOG=str(log), AINPKG_TEST_ASSET=str(asset))
        repo, tag = "example/ai-now-linux", "chapter-11"
        checksum = ainpkg.file_digest(asset)
        self.assertIn(checksum, self.cli("upload", repo, tag, asset, env=env))
        self.assertEqual(log.read_text().splitlines()[:3], ["release", "upload", tag])
        output = self.work / "downloaded.ainpkg"
        self.cli("download", repo, tag, output, "--sha256", "0" * 64, ok=False, env=env)
        self.assertFalse(output.exists())
        self.cli("download", repo, tag, output, "--sha256", checksum, env=env)
        self.assertEqual(output.read_bytes(), asset.read_bytes())
        self.cli("download", repo, tag, output, "--sha256", checksum, ok=False, env=env)
        self.assertEqual(output.read_bytes(), asset.read_bytes())

    def test_rejects_host_root_and_changed_target(self):
        self.cli("init", "--arch", "armv7l", "--abi", "glibc-2.44", "--cpu", "armv7", ok=False)
        self.root = Path("/")
        self.assertIn("other than /", self.cli("list", ok=False))


if __name__ == "__main__":
    unittest.main()
