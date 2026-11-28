#!/usr/bin/env bash
# Create only a new image file. Destructive tools are confined to its loop device.
set -euo pipefail

fail() { printf 'build-bios-image: %s\n' "$*" >&2; exit 1; }
[[ $# == 4 || $# == 6 ]] ||
    fail "usage: $0 STAGED_ROOTFS KERNEL SIZE_MIB OUTPUT.img [DEPLOY.img SHA256]"

rootfs=$(realpath -e -- "$1")
kernel=$(realpath -e -- "$2")
size=$3
parent=$(realpath -e -- "$(dirname -- "$4")")
output="$parent/$(basename -- "$4")"
project=$(cd "$(dirname -- "$0")/.." && pwd)

[[ "$rootfs" != / && -d "$rootfs/etc" && -d "$rootfs/usr" ]] ||
    fail 'supply a prepared root filesystem directory'
[[ -f "$kernel" && -s "$kernel" ]] || fail 'kernel must be a nonempty regular file'
[[ "$size" =~ ^[1-9][0-9]{2,6}$ ]] && (( size >= 128 && size < 2097152 )) ||
    fail 'image size must be between 128 and 2097151 MiB'
[[ -d "$parent" && ! -e "$output" && ! -L "$output" ]] ||
    fail 'output must be a new file'
[[ "$parent/" != "$rootfs/"* ]] || fail 'output directory must be outside the staged rootfs'
[[ $EUID == 0 ]] || fail 'run as root in a private mount namespace to manage loop devices'
[[ -r /usr/lib/grub/i386-pc/modinfo.sh ]] ||
    fail 'missing i386-pc GRUB modules. On Ubuntu or Debian install grub-pc-bin.'
for tool in blkid cp findmnt grub-install losetup mkfs.ext4 mount mountpoint             python3 sfdisk sha256sum truncate umount; do
    command -v "$tool" >/dev/null || fail "missing tool: $tool"
done

work=$(mktemp -d -- "$parent/.ainow-image.XXXXXX")
mount_dir="$work/root"
image="$work/disk.img"
loop=
cleanup() {
    local result=$?
    trap - EXIT
    if mountpoint -q -- "$mount_dir" && ! umount -- "$mount_dir"; then
        printf 'Unmount failed. Build files preserved at %s\n' "$work" >&2
        exit 1
    fi
    if [[ -n "$loop" ]] && ! losetup --detach "$loop"; then
        printf 'Loop detach failed. Build files preserved at %s\n' "$work" >&2
        exit 1
    fi
    rm -rf -- "$work"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -- "$mount_dir"

if [[ $# == 6 ]]; then
    payload=$(realpath -e -- "$5")
    digest=$6
    python3 "$project/scripts/ainstall" --image "$payload" --sha256 "$digest" \
        --output "$work/preview.img"
fi

truncate -s "${size}M" -- "$image"
loop=$(losetup --find --show --partscan -- "$image")
[[ "$loop" =~ ^/dev/loop[0-9]+$ &&
   $(losetup --list --noheadings --output BACK-FILE -- "$loop") == "$image" ]] ||
    fail 'could not verify the new loop device identity'

printf 'label: dos\nunit: sectors\n\nstart=2048, type=83, bootable\n' | sfdisk -- "$loop"
partition="${loop}p1"
for ((retry=0; retry<40; retry++)); do
    [[ ! -b "$partition" ]] || break
    sleep 0.1
done
[[ -b "$partition" ]] || fail "partition device did not appear: $partition"
mkfs.ext4 -F -L AINOWROOT "$partition"
uuid=$(blkid -s UUID -o value -- "$partition")
partuuid=$(blkid -s PARTUUID -o value -- "$partition")
[[ "$uuid" =~ ^[a-f0-9-]{36}$ && "$partuuid" =~ ^[a-f0-9]{8}-01$ ]] ||
    fail 'could not determine the new filesystem and MBR partition identifiers'
mount -- "$partition" "$mount_dir"
[[ $(findmnt --noheadings --output SOURCE --mountpoint "$mount_dir") == "$partition" ]] ||
    fail 'mounted source does not match the new loop partition'
cp -ax -- "$rootfs/." "$mount_dir/"

verify_path() {
    [[ $(realpath -m -- "$mount_dir/$1") == "$mount_dir/$1" ]] ||
        fail "unsafe symlink in image path: $1"
}
for path in boot/vmlinuz boot/initrd.img boot/grub/grub.cfg etc/fstab; do verify_path "$path"; done
install -Dm644 -- "$kernel" "$mount_dir/boot/vmlinuz"
printf 'UUID=%s / ext4 defaults 0 1\n' "$uuid" > "$mount_dir/etc/fstab"

grub-install --target=i386-pc --boot-directory="$mount_dir/boot" --recheck "$loop"
initrd=
if [[ -f "$mount_dir/boot/initrd.img" ]]; then initrd='initrd /boot/initrd.img'; fi
default_entry=serial
case "${AINOW_BOOT_PROFILE:-}" in
    eeepc) default_entry=local ;;
    console) default_entry=graphics ;;
esac
cat > "$mount_dir/boot/grub/grub.cfg" <<GRUB
set default=$default_entry
set timeout=5
menuentry 'AI-Now Linux (serial console)' --id serial {
    search --no-floppy --fs-uuid --set=root $uuid
    linux /boot/vmlinuz root=PARTUUID=$partuuid rw rootwait console=tty0 console=ttyS0,115200n8
    $initrd
}
menuentry 'AI-Now Linux (local console, basic display)' --id local {
    search --no-floppy --fs-uuid --set=root $uuid
    linux /boot/vmlinuz root=PARTUUID=$partuuid rw rootwait console=tty0 nomodeset loglevel=7
    $initrd
}
menuentry 'AI-Now Linux (local console, native graphics)' --id graphics {
    search --no-floppy --fs-uuid --set=root $uuid
    linux /boot/vmlinuz root=PARTUUID=$partuuid rw rootwait console=tty0
    $initrd
}
GRUB

if [[ $# == 6 ]]; then
    verify_path usr/local/sbin/ainstall
    verify_path usr/local/sbin/ainow_kernel.py
    verify_path opt/ainow-install/deploy.img
    verify_path opt/ainow-install/SHA256SUMS
    install -Dm755 -- "$project/scripts/ainstall" "$mount_dir/usr/local/sbin/ainstall"
    install -Dm644 -- "$project/scripts/ainow_kernel.py" "$mount_dir/usr/local/sbin/ainow_kernel.py"
    install -Dm644 -- "$payload" "$mount_dir/opt/ainow-install/deploy.img"
    printf '%s  deploy.img\n' "$digest" > "$mount_dir/opt/ainow-install/SHA256SUMS"
    (cd "$mount_dir/opt/ainow-install" && sha256sum -c SHA256SUMS)
fi

sync -f "$mount_dir"
umount -- "$mount_dir"
losetup --detach "$loop"
loop=
ln -T -- "$image" "$output"
sha256sum -- "$output"
