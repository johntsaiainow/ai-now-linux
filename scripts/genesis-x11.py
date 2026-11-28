#!/usr/bin/env python3
"""Export and build a pinned, offline Genesis X11 package set."""

import argparse
import hashlib
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import tomllib
from graphlib import TopologicalSorter

ABI = "glibc-2.44"
ARCH = "x86_64"
CPU = "x86-64-v1"
PACKAGES = """
util-macros xorgproto libxau libxdmcp xcb-proto xtrans libxcb libx11
libxext libxfixes libxrender libxkbfile xkbcomp
font-util xkeyboard-config libxcvt pixman
freetype libfontenc libxfont2 libxshmfence xorg-xvfb
libpciaccess libdrm libevdev mtdev xorg-server xf86-input-evdev
libice libsm libxt libxmu libxpm libxaw xauth xinit xterm
""".split()
FIXED_FILES = ("ainpkg", "build.py", "README.md", "RECIPE_COMMIT")
SHA256 = re.compile(r"[0-9a-f]{64}")
COMMIT = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_file(path, expected):
    if path.is_symlink() or not path.is_file() or digest(path) != expected:
        raise ValueError(f"Missing or invalid SHA-256: {path.name}")


def recipe_spec(archive, name, revision):
    with tarfile.open(archive, "r:") as stream:
        if stream.pax_headers.get("comment") != revision:
            raise ValueError(f"{name}: Git archive revision differs from RECIPE_COMMIT")
        member = stream.getmember(f"packages/{name}/recipe.toml")
        if not member.isfile():
            raise ValueError(f"{name}: recipe text must be a regular file")
        spec = tomllib.loads(stream.extractfile(member).read().decode("utf-8"))
    if (spec["name"] != name or spec["cpu"].get(ARCH) != CPU
            or not SHA256.fullmatch(spec["source"]["sha256"])
            or not spec["source"]["url"].startswith("https://")):
        raise ValueError(f"{name}: invalid recipe name, CPU, or source pin")
    return spec


def order_packages(specs):
    graph = {name: spec.get("build_requires", []) for name, spec in specs.items()}
    for name, dependencies in graph.items():
        absent = set(dependencies) - graph.keys()
        if absent:
            raise ValueError(f"{name}: bundle lacks {', '.join(sorted(absent))}")
    return tuple(TopologicalSorter(graph).static_order())


def check_bundle(bundle):
    lines = (bundle / "SHA256SUMS").read_text(encoding="ascii").splitlines()
    hashes = {}
    for line in lines:
        checksum, filename = line.split("  ", 1)
        if not SHA256.fullmatch(checksum) or filename in hashes:
            raise ValueError("Invalid or repeated SHA256SUMS entry")
        hashes[filename] = checksum
    expected = set(FIXED_FILES) | {f"recipes/{name}.tar" for name in PACKAGES}
    for filename in sorted(expected):
        verify_file(bundle / filename, hashes.get(filename))
    revision = (bundle / "RECIPE_COMMIT").read_text(encoding="ascii").strip()
    if not COMMIT.fullmatch(revision):
        raise ValueError("Invalid RECIPE_COMMIT")
    specs = {name: recipe_spec(bundle / "recipes" / f"{name}.tar", name, revision)
             for name in PACKAGES}
    for pin in {spec["source"]["sha256"] for spec in specs.values()}:
        filename = f"sources/{pin}.tar"
        expected.add(filename)
        if hashes.get(filename) != pin:
            raise ValueError(f"Source fingerprint differs from recipe: {filename}")
        verify_file(bundle / filename, pin)
    if hashes.keys() != expected:
        raise ValueError("SHA256SUMS contains entries outside the X11 bundle")
    return revision, specs, order_packages(specs), hashes


def export_bundle(output, ref, cache):
    repo = Path(__file__).resolve().parent.parent
    revision = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "--verify", "--end-of-options", f"{ref}^{{commit}}"],
        text=True,
    ).strip()
    if output.exists() or output.is_symlink():
        raise ValueError(f"Bundle already exists: {output}")
    with tempfile.TemporaryDirectory(prefix=".genesis-x11-", dir=output.parent) as temp:
        bundle = Path(temp) / "genesis-x11"
        (bundle / "recipes").mkdir(parents=True)
        (bundle / "sources").mkdir()
        paths = {
            "ainpkg": "scripts/ainpkg",
            "build.py": "scripts/genesis-x11.py",
            "README.md": "docs/packages/genesis-x11.md",
        }
        for filename, git_path in paths.items():
            (bundle / filename).write_bytes(subprocess.check_output(
                ["git", "-C", str(repo), "show", f"{revision}:{git_path}"],
            ))
        (bundle / "RECIPE_COMMIT").write_text(revision + "\n", encoding="ascii")
        for name in PACKAGES:
            recipe = bundle / "recipes" / f"{name}.tar"
            with recipe.open("wb") as stream:
                subprocess.run(["git", "-C", str(repo), "archive", "--format=tar",
                                revision, f"packages/{name}"], stdout=stream, check=True)
            source = recipe_spec(recipe, name, revision)["source"]
            pin = source["sha256"]
            target = bundle / "sources" / f"{pin}.tar"
            if target.exists():
                continue
            cached = cache / target.name if cache else None
            if cached and cached.is_file():
                shutil.copyfile(cached, target)
            else:
                subprocess.run(["curl", "--proto", "=https", "--proto-redir", "=https",
                                "--fail", "--silent", "--show-error", "--location",
                                "--retry", "2", "--max-time", "120", "--output", str(target),
                                source["url"]], check=True)
            verify_file(target, pin)
        files = sorted(path for path in bundle.rglob("*") if path.is_file())
        (bundle / "SHA256SUMS").write_text(
            "".join(f"{digest(path)}  {path.relative_to(bundle).as_posix()}\n" for path in files),
            encoding="ascii",
        )
        check_bundle(bundle)
        compressed = Path(temp) / "bundle.tar.gz"
        with tarfile.open(compressed, "w:gz") as archive:
            archive.add(bundle, arcname="genesis-x11")
        os.link(compressed, output)
    print(f"{digest(output)}  {output}")


def require_host():
    if os.uname().machine != ARCH or os.confstr("CS_GNU_LIBC_VERSION") != ABI.replace("-", " "):
        raise ValueError("Native build requires x86_64 Genesis with glibc 2.44")
    if sys.version_info < (3, 12):
        raise ValueError("Native build requires Python 3.12 or later")
    # AINPKG uses this fixed tool search path inside isolated package builds.
    path = "/usr/bin:/bin"
    missing = [tool for tool in ("gcc", "make", "meson", "ninja", "pkg-config", "zstd",
                                 "awk", "sed", "perl", "bzip2", "xz", "gzip", "tar", "mcookie")
               if not shutil.which(tool, path=path)]
    if missing:
        raise ValueError(f"Missing Genesis build tools on {path}: {', '.join(missing)}")
    subprocess.run(["/usr/bin/env", f"PATH={path}", "pkg-config", "--exists", "--print-errors",
                    "zlib", "openssl", "libudev", "ncursesw"], check=True)


def build_bundle(bundle, jobs):
    require_host()
    revision, specs, order, hashes = check_bundle(bundle)
    output = Path(tempfile.mkdtemp(prefix="ainow-x11-", dir="/tmp"))
    identity = {}
    if os.geteuid() == 0:
        account = pwd.getpwnam("nobody")
        os.chown(output, account.pw_uid, account.pw_gid)
        identity = dict(user=account.pw_uid, group=account.pw_gid, extra_groups=())
    print(f"Genesis X11 build output: {output}", flush=True)
    cli = [sys.executable, str(bundle / "ainpkg")]
    packages = {}
    for number, name in enumerate(order, 1):
        spec = specs[name]
        recipe = f"recipes/{name}.tar"
        package = output / f"{name}.ainpkg"
        source = bundle / "sources" / f"{spec['source']['sha256']}.tar"
        command = cli + ["build", name, "--recipe-archive", str(bundle / recipe),
                         "--recipe-sha256", hashes[recipe], "--source", str(source),
                         "--jobs", str(jobs), "--output", str(package)]
        for dependency in spec.get("build_requires", []):
            command += ["--build-dependency", str(packages[dependency])]
        log = output / f"{name}.log"
        print(f"[{number}/{len(order)}] {name}", flush=True)
        with log.open("wb") as stream:
            result = subprocess.run(command, cwd=output, stdout=stream,
                                    stderr=subprocess.STDOUT, **identity)
        if result.returncode:
            raise ValueError(f"{name} build failed. See {log}")
        packages[name] = package

    with tempfile.TemporaryDirectory(prefix="verify-", dir=output) as directory:
        root = Path(directory)
        target = cli + ["--root", directory]
        subprocess.run(target + ["init", "--arch", ARCH, "--abi", ABI, "--cpu", CPU], check=True)
        for package in packages.values():
            subprocess.run(target + ["install", str(package)], check=True)
        subprocess.run(target + ["verify"], check=True)
        env = dict(os.environ, LD_LIBRARY_PATH=str(root / "usr/lib"), LC_ALL="C")
        for name, argument in (("Xorg", "-version"), ("xterm", "-version"),
                               ("xauth", "-V"), ("xkbcomp", "-version")):
            subprocess.run([str(root / "usr/bin" / name), argument], env=env, check=True)

    (output / "SHA256SUMS").write_text(
        "".join(f"{digest(package)}  {package.name}\n" for package in packages.values()),
        encoding="ascii",
    )
    (output / "RECIPE_COMMIT").write_text(revision + "\n", encoding="ascii")
    print(f"PASS: {len(packages)} native X11 packages installed and verified in a temporary root")
    print(f"PACKAGES={output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    export = commands.add_parser("export", help="export an offline bundle from the Git repository")
    export.add_argument("output", type=Path)
    export.add_argument("--ref", default="HEAD")
    export.add_argument("--cache", type=Path, help="directory of upstream archives named SHA256.tar")
    commands.add_parser("check", help="verify the extracted bundle without building")
    build = commands.add_parser("build", help="build and verify all packages on Genesis")
    build.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    args = parser.parse_args()
    bundle = Path(__file__).resolve().parent
    if args.command == "export":
        export_bundle(args.output, args.ref, args.cache)
    elif args.command == "check":
        revision, _, order, _ = check_bundle(bundle)
        print(f"PASS: {len(order)} recipes and upstream source pins verified at {revision}")
    else:
        if args.jobs < 1:
            parser.error("--jobs must be at least 1")
        build_bundle(bundle, args.jobs)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, tarfile.TarError, subprocess.CalledProcessError) as error:
        sys.exit(f"genesis-x11: {error}")
