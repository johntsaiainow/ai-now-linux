#!/usr/bin/env bash

set -euo pipefail

readonly LFS="/mnt/lfs"
readonly SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

die() {
    echo "[FAIL] $*" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] ||
    die "Run this script with sudo"

# Enter a private mount namespace.
if [[ "${1:-}" != "--private" ]]; then
    exec unshare --mount --propagation private \
        /bin/bash "$SCRIPT_PATH" --private
fi

# Never proceed inside PID 1's mount namespace.
[[ "$(readlink /proc/self/ns/mnt)" != \
   "$(readlink /proc/1/ns/mnt)" ]] ||
    die "Still in host mount namespace"

# Verify private mount propagation.
[[ "$(findmnt -n -o PROPAGATION -M /)" == "private" ]] ||
    die "Mount propagation is not private"

echo "[PASS] Private mount namespace"

# Revalidate the target inside this namespace.
bash "$SCRIPT_DIR/preflight.sh"

[[ "$(stat -c '%u:%g' "$LFS/usr")" == "0:0" ]] ||
    die "Ownership transfer incomplete"

# Validate mount destinations before mounting.
for name in dev proc sys run; do
    target="$LFS/$name"

    [[ ! -L "$target" ]] ||
        die "Unexpected symbolic link: $target"

    mkdir -p "$target"

    [[ "$(realpath "$target")" == "$target" ]] ||
        die "Invalid mount destination: $target"

    if mountpoint -q "$target"; then
        die "Already mounted: $target"
    fi
done

MOUNTS=()

cleanup() {
    local i
    local failed=0

    echo
    echo "=== Cleaning up virtual filesystems ==="

    for ((i=${#MOUNTS[@]}-1; i>=0; i--)); do
        if ! umount "${MOUNTS[i]}"; then
            echo "[WARN] Unmount failed: ${MOUNTS[i]}" >&2
            failed=1
        fi
    done

    if (( failed == 0 )); then
        echo "[PASS] Virtual filesystems released"
    fi
}

trap cleanup EXIT

safe_mount() {
    local target="${@: -1}"

    [[ "$target" == "$LFS/"* ]] ||
        die "Mount outside target forbidden"

    [[ "$(realpath "$target")" == "$target" ]] ||
        die "Invalid mount destination"

    mount "$@"
    MOUNTS+=("$target")

    echo "[PASS] Mounted $target"
}

safe_mount --bind /dev "$LFS/dev"

safe_mount -t devpts devpts \
    -o newinstance,gid=5,mode=0620,ptmxmode=0666 \
    "$LFS/dev/pts"

safe_mount -t proc proc "$LFS/proc"

safe_mount -t sysfs sysfs "$LFS/sys"

safe_mount -t tmpfs tmpfs \
    -o nosuid,nodev "$LFS/run"

if [[ -L "$LFS/dev/shm" ]]; then
    SHM_PATH="$(realpath /dev/shm)"

    [[ "$SHM_PATH" == /run/* ]] ||
        die "Unexpected shared memory path"

    mkdir -p "$LFS$SHM_PATH"
    chmod 1777 "$LFS$SHM_PATH"
else
    safe_mount -t tmpfs tmpfs \
        -o nosuid,nodev,mode=1777 "$LFS/dev/shm"
fi

echo
echo "=== Target Mount Table ==="

findmnt -R "$LFS"

echo
echo "=== Entering AI-Now Linux ==="

chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="${TERM:-linux}" \
    PS1='(ai-now chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    MAKEFLAGS="-j8" \
    TESTSUITEFLAGS="-j8" \
    /bin/bash --login
