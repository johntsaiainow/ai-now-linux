#!/usr/bin/env python3
"""Build the Fluxbox add-on using previously built Genesis X11 packages."""

import hashlib
import os
from pathlib import Path
import pwd
import subprocess
import sys
import tempfile
import tomllib

ABI = "glibc-2.44"


def main():
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {sys.argv[0]} EXTRACTED_GENESIS_X11_PACKAGES")
    if os.uname().machine != "x86_64" or os.confstr("CS_GNU_LIBC_VERSION") != "glibc 2.44":
        sys.exit("Build inside x86_64 Genesis with glibc 2.44.")
    bundle = Path(__file__).resolve().parent
    inputs = Path(sys.argv[1]).resolve(strict=True)
    subprocess.run(["sha256sum", "--strict", "-c", "SHA256SUMS"], cwd=bundle, check=True)
    subprocess.run(["sha256sum", "--strict", "-c", "SHA256SUMS"], cwd=inputs, check=True)
    with (bundle / "recipe.toml").open("rb") as stream:
        spec = tomllib.load(stream)
    recipe = bundle / "fluxbox-recipe.tar"
    with recipe.open("rb") as stream:
        recipe_hash = hashlib.file_digest(stream, "sha256").hexdigest()

    output = Path(tempfile.mkdtemp(prefix="ainow-fluxbox-", dir="/tmp"))
    identity = {}
    if os.geteuid() == 0:
        account = pwd.getpwnam("nobody")
        os.chown(output, account.pw_uid, account.pw_gid)
        identity = dict(user=account.pw_uid, group=account.pw_gid, extra_groups=())
    archive = output / "fluxbox.ainpkg"
    command = [sys.executable, str(bundle / "ainpkg"), "build", "fluxbox",
               "--recipe-archive", str(recipe), "--recipe-sha256", recipe_hash,
               "--source", str(bundle / "fluxbox-source.tar.xz"), "--output", str(archive),
               "--jobs", str(min(4, os.cpu_count() or 1))]
    for dependency in spec["build_requires"]:
        command += ["--build-dependency", str(inputs / f"{dependency}.ainpkg")]
    print(f"BUILD_DIR={output}", flush=True)
    with (output / "build.log").open("wb") as log:
        subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT,
                       check=True, **identity)
    cli = [sys.executable, str(bundle / "ainpkg")]
    with tempfile.TemporaryDirectory(prefix="verify-", dir=output) as target:
        install = cli + ["--root", target]
        subprocess.run(install + ["init", "--arch", "x86_64", "--abi", ABI,
                                  "--cpu", "x86-64-v1"], check=True)
        subprocess.run(install + ["install", str(archive)], check=True)
        subprocess.run(install + ["verify", "fluxbox"], check=True)
    sums = subprocess.check_output(["sha256sum", archive.name], cwd=output)
    (output / "SHA256SUMS").write_bytes(sums)
    print(f"PACKAGE={archive}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"Fluxbox build failed: {error}")
