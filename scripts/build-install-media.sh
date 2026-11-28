#!/usr/bin/env bash
# Build a console deployment image and an offline installer USB image.
set -euo pipefail
fail() { printf 'build-install-media: %s\n' "$*" >&2; exit 1; }
[[ $# == 5 || $# == 6 ]] ||
    fail "usage: $0 PROFILE SEALED_ROOTFS KERNEL DEPLOY_MIB NEW_OUTPUT_DIRECTORY [OFFLINE_PACKAGES]"
profile=$1
case "$profile" in
    generic32) elf_class=1; elf_machine=3 ;;
    generic64|eeepc1005p) elf_class=2; elf_machine=62 ;;
    *) fail 'choose generic32, generic64 or eeepc1005p' ;;
esac
[[ $EUID == 0 ]] || fail 'run as root inside a private mount namespace'
root=$(realpath -e -- "$2")
kernel=$(realpath -e -- "$3")
size=$4
parent=$(realpath -e -- "$(dirname -- "$5")")
output="$parent/$(basename -- "$5")"
project=$(cd "$(dirname -- "$0")/.." && pwd)
[[ "$root" != / && "$parent/" != "$root/"* && ! -e "$output" && ! -L "$output" ]] ||
    fail 'use a prepared rootfs and a new output directory outside it'
[[ "$size" =~ ^[1-9][0-9]{2,6}$ ]] && (( size >= 128 && size <= 1048447 )) ||
    fail 'choose a deployment size between 128 and 1048447 MiB'
[[ -f "$kernel" && -x "$root/usr/bin/python3" && -f "$root/etc/passwd" ]] ||
    fail 'expected a Linux kernel and a staged Genesis rootfs with Python'
if [[ $# == 6 ]]; then
    catalog=$(realpath -e -- "$6")
    [[ -d "$catalog" && "$catalog/" != "$root/"* && "$parent/" != "$catalog/"* ]] ||
        fail 'use a separate directory for the offline packages'
fi

python3 - "$root" "$kernel" "$elf_class" "$elf_machine" <<'PY'
import sys
import re
from pathlib import Path

root = Path(sys.argv[1])
shell = (root / "usr/bin/bash").resolve()
if not shell.is_relative_to(root):
    raise SystemExit("The staged shell resolves outside the rootfs")
with shell.open("rb") as stream:
    elf = stream.read(20)
elf_class, machine = map(int, sys.argv[3:])
if elf[:6] != b"\x7fELF" + bytes((elf_class, 1)) or int.from_bytes(elf[18:20], "little") != machine:
    raise SystemExit("The staged userspace architecture differs from the selected profile")
with open(sys.argv[2], "rb") as stream:
    boot = stream.read(0x238)
    if len(boot) != 0x238 or boot[0x202:0x206] != b"HdrS" or bool(boot[0x236] & 1) != (elf_class == 2):
        raise SystemExit("The kernel architecture differs from the selected profile")
    version_offset = int.from_bytes(boot[0x20e:0x210], "little")
    if not version_offset:
        raise SystemExit("Missing kernel release in the boot header")
    stream.seek(0x200 + version_offset)
    release = re.match(rb"[A-Za-z0-9][A-Za-z0-9._+-]*", stream.read(256))
if not release:
    raise SystemExit("Invalid kernel release in the boot header")
modules = (root / "lib/modules" / release[0].decode("ascii")).resolve()
if not modules.is_relative_to(root) or not (modules / "modules.dep").is_file():
    raise SystemExit(f"Stage matching kernel modules first: {modules}")
PY

work=$(mktemp -d "$parent/.genesis-media.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
stage="$work/rootfs"
products="$work/products"
mkdir -- "$stage" "$products"
cp -ax -- "$root/." "$stage/"
for path in etc/ainow-hardware-profile usr/local/sbin/ainow-setup \
            usr/local/lib/ainow/ainpkg opt/ainow-packages; do
    [[ $(realpath -m -- "$stage/$path") == "$stage/$path" ]] ||
        fail "unexpected symlink in $path"
done
printf '%s\n' "$profile" > "$stage/etc/ainow-hardware-profile"
install -Dm755 "$project/scripts/ainow-setup" "$stage/usr/local/sbin/ainow-setup"
install -Dm755 "$project/scripts/ainpkg" "$stage/usr/local/lib/ainow/ainpkg"
if [[ $# == 6 ]]; then
    [[ ! -e "$stage/opt/ainow-packages" ]] ||
        fail 'the staged root already contains an offline package catalog'
    cp -ax -- "$catalog" "$stage/opt/ainow-packages"
fi

export AINOW_BOOT_PROFILE=console
deploy="$products/$profile-console.img"
rescue="$products/$profile-installer.img"
"$project/scripts/build-bios-image.sh" "$stage" "$kernel" "$size" "$deploy"
digest=$(sha256sum "$deploy" | cut -d ' ' -f 1)
"$project/scripts/build-bios-image.sh" "$stage" "$kernel" "$((size * 2 + 256))" \
    "$rescue" "$deploy" "$digest"
(cd "$products" && sha256sum -- *.img > SHA256SUMS && sha256sum -c SHA256SUMS)
mv -T --no-clobber -- "$products" "$output"
[[ ! -e "$products" ]] || fail 'output directory appeared during the build'
printf 'Images and SHA256SUMS: %s\n' "$output"
