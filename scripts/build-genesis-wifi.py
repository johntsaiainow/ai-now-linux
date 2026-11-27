#!/usr/bin/env python3
"""Build and verify Wi-Fi packages in a disconnected Genesis VM."""

import hashlib
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require_host():
    if os.uname().machine != "x86_64" or os.confstr("CS_GNU_LIBC_VERSION") != "glibc 2.44":
        raise SystemExit("Run this bundle inside x86_64 Genesis with glibc 2.44.")
    for name in ("gcc", "make", "flex", "bison", "pkg-config", "zstd"):
        if shutil.which(name) is None:
            raise SystemExit(f"Missing Genesis build tool: {name}")
    subprocess.run(["pkg-config", "--exists", "--print-errors", "dbus-1", "openssl"], check=True)


def main():
    require_host()
    bundle = Path(__file__).resolve().parent
    subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=bundle, check=True)
    output = Path(tempfile.mkdtemp(prefix="ainow-wifi-", dir="/tmp"))
    identity = {}
    if os.geteuid() == 0:
        account = pwd.getpwnam("nobody")
        os.chown(output, account.pw_uid, account.pw_gid)
        identity = dict(user=account.pw_uid, group=account.pw_gid, extra_groups=())
    print(f"Build output: {output}", flush=True)
    cli = [sys.executable, str(bundle / "ainpkg")]
    jobs = str(min(4, os.cpu_count() or 1))
    packages = []
    for name in ("libnl", "wpa-supplicant"):
        recipe = bundle / f"{name}-recipe.tar"
        package = output / f"{name}.ainpkg"
        command = cli + [
            "build", name, "--recipe-archive", str(recipe), "--recipe-sha256", digest(recipe),
            "--source", str(bundle / f"{name}-source.tar.gz"), "--jobs", jobs,
            "--output", str(package),
        ]
        for dependency in packages:
            command += ["--build-dependency", str(dependency)]
        subprocess.run(command, cwd=output, check=True, **identity)
        packages.append(package)

    with tempfile.TemporaryDirectory(prefix="verify-", dir=output) as target:
        target_cli = cli + ["--root", target]
        subprocess.run(target_cli + [
            "init", "--arch", "x86_64", "--abi", "glibc-2.44", "--cpu", "x86-64-v1",
        ], check=True)
        for package in packages:
            subprocess.run(target_cli + ["install", str(package)], check=True)
        subprocess.run(target_cli + ["verify"], check=True)
        env = dict(os.environ, LD_LIBRARY_PATH=str(Path(target) / "usr/lib"))
        for name in ("wpa_supplicant", "wpa_cli"):
            subprocess.run([str(Path(target) / "usr/sbin" / name), "-v"], env=env, check=True)

    sums = "".join(f"{digest(package)}  {package.name}\n" for package in packages)
    (output / "SHA256SUMS").write_text(sums, encoding="ascii")
    print(sums, end="")
    print(f"PASS: Genesis native Wi-Fi package build and verification\nPACKAGES={output}")


if __name__ == "__main__":
    main()
