"""Select, verify and install a kernel from trusted Genesis media metadata."""

import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
from urllib.parse import urlsplit
from urllib.request import urlopen


CATALOG = Path("/opt/ainow-kernels/catalog.json")
RELEASE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,63}")


def architecture():
    machine = platform.machine()
    if machine == "x86_64":
        return "x86_64"
    if re.fullmatch(r"i[3-6]86", machine):
        return "i686"
    raise ValueError(f"Unsupported installer architecture: {machine}")


def read_catalog(path, arch):
    entries = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(entries, list):
        raise ValueError("Kernel catalog must be a JSON list")
    selected = []
    for entry in entries:
        if (not isinstance(entry, dict) or
                not all(isinstance(entry.get(key), str) for key in ("name", "arch", "release", "sha256", "url"))):
            raise ValueError("Invalid kernel catalog entry")
        url = urlsplit(entry["url"])
        size = entry.get("size")
        if (entry["arch"] not in {"x86_64", "i686"} or
                not RELEASE.fullmatch(entry["release"]) or
                not re.fullmatch(r"[a-f0-9]{64}", entry["sha256"]) or
                url.scheme != "https" or not url.hostname or url.username is not None or
                not isinstance(size, int) or isinstance(size, bool) or size <= 0):
            raise ValueError(f"Invalid kernel metadata for {entry['name']!r}")
        if entry["arch"] == arch:
            selected.append(entry)
    return selected


def download(entry, archive):
    with urlopen(entry["url"], timeout=30) as response, archive.open("xb") as output:
        if urlsplit(response.geturl()).scheme != "https":
            raise ValueError("Kernel download redirected away from HTTPS")
        digest = hashlib.sha256()
        remaining = entry["size"]
        while remaining:
            data = response.read(min(remaining, 1024 * 1024))
            if not data:
                raise ValueError("Kernel download ended early")
            digest.update(data)
            output.write(data)
            remaining -= len(data)
        if response.read(1) or digest.hexdigest() != entry["sha256"]:
            raise ValueError("Kernel download size or SHA256 does not match the catalog")


def prepare_kernel(catalog, workspace):
    entries = read_catalog(catalog, architecture())
    if not entries:
        raise ValueError("Kernel catalog has no builds for this installer architecture")
    bundled = platform.release()
    entries = [entry for entry in entries if entry["release"] != bundled]
    print(f"0. Keep the bundled kernel ({bundled})")
    for index, entry in enumerate(entries, 1):
        print(f"{index}. {entry['name']} ({entry['release']})")
    choice = input("Kernel [0]: ").strip() or "0"
    if not re.fullmatch(r"[0-9]{1,5}", choice) or int(choice) > len(entries):
        raise ValueError("Choose a kernel from the list")
    if int(choice) == 0:
        return None
    entry = entries[int(choice) - 1]
    archive = workspace / "kernel.tar.gz"
    print(f"Downloading {entry['name']}…", flush=True)
    download(entry, archive)
    with tarfile.open(archive, "r:gz") as payload:
        payload.extractall(workspace, filter="data")
    release = entry["release"]
    boot = workspace / f"boot/vmlinuz-{release}"
    if not boot.is_file():
        boot = workspace / "bzImage"
    modules = workspace / f"lib/modules/{release}"
    with boot.open("rb") as stream:
        header = stream.read(0x238)
        position = int.from_bytes(header[0x20e:0x210], "little")
        stream.seek(0x200 + position)
        version = stream.read(256).split(b"\0", 1)[0].split()
    if (len(header) != 0x238 or header[0x202:0x206] != b"HdrS" or not position or
            bool(header[0x236] & 1) != (entry["arch"] == "x86_64") or
            not version or version[0] != release.encode() or not (modules / "modules.dep").is_file()):
        raise ValueError("Kernel image or modules do not match the catalog release and architecture")
    initrd = workspace / f"boot/initrd-{release}.img"
    print(f"Kernel download verified: {release}", flush=True)
    return release, boot, modules, initrd if initrd.is_file() else None


def install_kernel(root, kernel):
    release, image, modules, initrd = kernel
    boot = root / "boot"
    cfg = boot / "grub/grub.cfg"
    # The media builder writes a native console entry with the target's UUIDs.
    original = cfg.read_text()
    graphics = re.search(r"^menuentry .* --id graphics \{\n([^}]+)\}", original, re.MULTILINE)
    if not graphics or not re.search(r"^set default=\w+$", original, re.MULTILINE):
        raise ValueError("Cannot locate the installer-generated GRUB entries")
    lines = [line for line in graphics[1].splitlines() if not line.lstrip().startswith("initrd ")]
    body = "\n".join(lines).replace("linux /boot/vmlinuz ", f"linux /boot/vmlinuz-{release} ", 1)
    if f"linux /boot/vmlinuz-{release} " not in body:
        raise ValueError("Cannot locate the GRUB kernel command")
    if initrd:
        body += f"\n    initrd /boot/{initrd.name}"
    entry = f"\nmenuentry 'AI-Now Linux ({release})' --id selected-kernel {{\n{body}\n}}\n"
    candidate = cfg.with_name("grub.cfg.kernel-new")
    config = re.sub(r"^set default=\w+$", "set default=selected-kernel", original, count=1, flags=re.MULTILINE)
    destination = (root / "lib/modules" / release).resolve()
    targets = [(image, boot / f"vmlinuz-{release}")]
    if initrd:
        targets.append((initrd, boot / initrd.name))
    if (not destination.is_relative_to(root) or destination.exists() or
            any(target.exists() or target.is_symlink() for _, target in targets)):
        raise ValueError(f"Kernel module destination is invalid or already exists: {release}")

    with candidate.open("x") as stream:
        stream.write(config + entry)
    try:
        subprocess.run(["grub-script-check", candidate], check=True)
        try:
            shutil.copytree(modules, destination, symlinks=True)
            subprocess.run(["depmod", "-b", root, release], check=True)
            for source, target in targets:
                shutil.copyfile(source, target)
            candidate.chmod(cfg.stat().st_mode & 0o777)
            candidate.replace(cfg)
        except Exception:
            for _, target in targets:
                target.unlink(missing_ok=True)
            if destination.is_dir():
                shutil.rmtree(destination)
            raise
    finally:
        candidate.unlink(missing_ok=True)
