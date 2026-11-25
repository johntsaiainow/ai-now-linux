#!/usr/bin/env bash

set -euo pipefail

readonly LFS="/mnt/lfs"
readonly IMAGE="/home/john/Projects/ai-now-linux/images/ai-now-linux.raw"
readonly EXPECTED_UUID="cf7b7e99-cf6b-470d-9fe1-87b9742e72af"

die() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

[[ -f "$IMAGE" ]] ||
    die "Disk image not found"

[[ -d "$LFS" ]] ||
    die "Mount directory not found"

[[ "$(realpath "$LFS")" == "/mnt/lfs" ]] ||
    die "Invalid target path"

mountpoint -q "$LFS" ||
    die "Target is not mounted"

pass "Target mountpoint verified"

DEVICE=$(findmnt -n -o SOURCE -M "$LFS")

[[ "$DEVICE" =~ ^/dev/loop[0-9]+p2$ ]] ||
    die "Target is not a loop partition"

pass "Target device: $DEVICE"

LOOP="${DEVICE%p2}"

BACKING=$(sudo losetup -n -O BACK-FILE "$LOOP")

[[ "$BACKING" == "$IMAGE" ]] ||
    die "Incorrect backing image"

pass "Backing image verified"

UUID=$(sudo blkid -s UUID -o value "$DEVICE")

[[ "$UUID" == "$EXPECTED_UUID" ]] ||
    die "Filesystem UUID mismatch"

pass "Filesystem UUID verified"

[[ "$(findmnt -n -o FSTYPE -M "$LFS")" == "ext4" ]] ||
    die "Incorrect filesystem type"

pass "Filesystem type verified"

OPTIONS=$(findmnt -n -o OPTIONS -M "$LFS")

[[ ",$OPTIONS," == *,rw,* ]] ||
    die "Target filesystem is read-only"

pass "Read/write filesystem verified"

MOUNTS=$(findmnt -R -n -o TARGET "$LFS")

[[ "$MOUNTS" == "$LFS" ]] ||
    die "Unexpected nested mounts detected"

pass "No unexpected nested mounts"

[[ -x "$LFS/usr/bin/bash" ]] ||
    die "Target Bash not found"

[[ -x "$LFS/usr/bin/gcc" ]] ||
    die "Target GCC not found"

[[ -x "$LFS/usr/bin/g++" ]] ||
    die "Target G++ not found"

pass "Temporary toolchain verified"

echo
echo "AI-Now Linux Preflight: PASS"
