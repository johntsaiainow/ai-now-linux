#!/usr/bin/env bash
# Convert the known Genesis GPT layout into separate EeePC BIOS images.
set -euo pipefail

fail() { printf 'build-eeepc-rescue: %s\n' "$*" >&2; exit 1; }
[[ $# == 3 ]] || fail "usage: $0 GENESIS.raw EEEPC_KERNEL.tar.zst NEW_OUTPUT_DIRECTORY"
raw=$(realpath -e -- "$1")
bundle=$(realpath -e -- "$2")
output_parent=$(realpath -e -- "$(dirname -- "$3")")
output="$output_parent/$(basename -- "$3")"
project=$(cd "$(dirname -- "$0")/.." && pwd)
kernel_release=7.1.8-ainow-eeepc-1005p
kernel_sha=${AINOW_EEEPC_KERNEL_SHA256:-5ca6b1993c82d7eec95eb2cfaf0176cfcf252f63b7fe908bf46776b61417081f}
[[ "$kernel_sha" =~ ^[a-f0-9]{64}$ ]] || fail 'expected a lowercase kernel SHA256'
mib=1048576

[[ -f "$raw" && -f "$bundle" ]] || fail 'both inputs must be regular files'
[[ ! -e "$output" && ! -L "$output" ]] || fail 'output directory already exists'
printf '%s  %s\n' "$kernel_sha" "$bundle" | sha256sum -c -
[[ $EUID == 0 ]] || fail 'run as root inside a private mount namespace'
[[ -r /usr/lib/grub/i386-pc/modinfo.sh ]] ||
    fail 'missing i386-pc GRUB modules. On Ubuntu or Debian install grub-pc-bin.'
for tool in blkid blockdev cp df du grub-install losetup mkfs.ext4 mount mountpoint sfdisk tar umount zstd; do
    command -v "$tool" >/dev/null || fail "missing tool: $tool"
done

work=$(mktemp -d -- "$output_parent/.eeepc-build.XXXXXX")
source_mount="$work/source"
stage="$work/rootfs"
kernel_stage="$work/kernel"
products="$work/products"
source_loop=
cleanup() {
    local result=$?
    trap - EXIT
    if mountpoint -q -- "$source_mount" && ! umount -- "$source_mount"; then
        printf 'Source unmount failed. Files preserved at %s\n' "$work" >&2
        exit 1
    fi
    if [[ -n "$source_loop" ]] && ! losetup --detach "$source_loop"; then
        printf 'Source detach failed. Files preserved at %s\n' "$work" >&2
        exit 1
    fi
    rm -rf -- "$work"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -- "$source_mount" "$stage" "$kernel_stage" "$products"

source_loop=$(losetup --find --show --read-only --partscan -- "$raw")
[[ "$source_loop" =~ ^/dev/loop[0-9]+$ &&
   $(losetup --list --noheadings --output BACK-FILE -- "$source_loop") == "$raw" ]] ||
    fail 'source loop identity verification failed'
[[ $(blkid -s PTTYPE -o value -- "$source_loop") == gpt ]] ||
    fail 'Genesis source must use GPT'
partition="${source_loop}p2"
for ((retry=0; retry<40; retry++)); do
    [[ ! -b "$partition" ]] || break
    sleep 0.1
done
[[ -b "$partition" && $(blockdev --getro "$partition") == 1 &&
   $(blkid -s TYPE -o value -- "$partition") == ext4 ]] ||
    fail 'Genesis partition 2 must be read-only ext4'
mount -o ro,noload -- "$partition" "$source_mount"
[[ -f "$source_mount/etc/passwd" && -x "$source_mount/usr/bin/python3" ]] ||
    fail 'partition 2 does not contain the expected Genesis rootfs'

bytes=$(du -sx -B1 -- "$source_mount" | cut -f1)
root_mib=$(((bytes + mib - 1) / mib))
deploy_mib=$((root_mib + root_mib / 4 + 512))
rescue_mib=$((deploy_mib * 2 + 256))
required=$(((root_mib + deploy_mib + rescue_mib + 256) * mib))
available=$(df -B1 --output=avail -- "$output_parent" | tail -n 1)
[[ "$available" =~ ^[[:space:]]*[0-9]+$ ]] || fail 'could not determine available disk space'
printf 'Rootfs: %s MiB. Deployment image: %s MiB. Rescue image: %s MiB.\n' \
    "$root_mib" "$deploy_mib" "$rescue_mib"
(( available >= required )) ||
    fail "need at least $required available bytes in the output filesystem"

cp -ax -- "$source_mount/." "$stage/"
umount -- "$source_mount"
losetup --detach "$source_loop"
source_loop=

tar --zstd -xf "$bundle" -C "$kernel_stage" ./bzImage "./lib/modules/$kernel_release"
[[ -f "$kernel_stage/bzImage" && -d "$kernel_stage/lib/modules/$kernel_release" ]] ||
    fail 'kernel bundle is incomplete'
[[ $(realpath -m -- "$stage/usr/lib/modules") == "$stage/usr/lib/modules" ]] ||
    fail 'unexpected module directory symlink'
mkdir -p -- "$stage/usr/lib/modules"
cp -a -- "$kernel_stage/lib/modules/$kernel_release" "$stage/usr/lib/modules/"
# Do not carry an initramfs for the original Genesis kernel into the new boot menu.
if [[ -e "$stage/boot/initrd.img" || -L "$stage/boot/initrd.img" ]]; then
    [[ ! -L "$stage/boot" ]] || fail 'unexpected boot directory symlink'
    mv -- "$stage/boot/initrd.img" "$work/genesis-initrd"
fi

export AINOW_BOOT_PROFILE=eeepc

deploy="$products/eeepc-deploy.img"
rescue="$products/eeepc-rescue.img"
"$project/scripts/build-bios-image.sh" "$stage" "$kernel_stage/bzImage" "$deploy_mib" "$deploy"
deploy_sha=$(sha256sum -- "$deploy" | cut -d ' ' -f1)
"$project/scripts/build-bios-image.sh" "$stage" "$kernel_stage/bzImage" "$rescue_mib" \
    "$rescue" "$deploy" "$deploy_sha"
(cd "$products" && sha256sum eeepc-deploy.img eeepc-rescue.img > SHA256SUMS)
mv -T --no-clobber -- "$products" "$output"
[[ ! -e "$products" ]] || fail 'output directory appeared during the build'
printf 'Images and SHA256SUMS: %s\n' "$output"
