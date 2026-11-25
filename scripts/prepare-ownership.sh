#!/usr/bin/env bash

set -euo pipefail

readonly LFS="/mnt/lfs"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

die() {
    echo "[FAIL] $*" >&2
    exit 1
}

[[ "$EUID" -eq 0 ]] ||
    die "Run this script with sudo"

# Verify the target before modifying anything.
bash "$SCRIPT_DIR/preflight.sh"

if pgrep -u lfs >/dev/null; then
    die "The lfs user still has running processes"
fi

TARGETS=(
    "$LFS/usr"
    "$LFS/var"
    "$LFS/etc"
    "$LFS/tools"
    "$LFS/lib64"
)

# Validate every target before changing ownership.
for target in "${TARGETS[@]}"; do
    [[ -d "$target" ]] ||
        die "Missing directory: $target"

    [[ ! -L "$target" ]] ||
        die "Unexpected symbolic link: $target"

    [[ "$(realpath "$target")" == "$target" ]] ||
        die "Invalid target path: $target"
done

echo "=== Transferring Ownership ==="

chown -hRP --from=lfs root:root "${TARGETS[@]}"

echo
echo "=== Ownership Verification ==="

ls -ld "${TARGETS[@]}"

REMAINING=$(find "${TARGETS[@]}" -xdev -user lfs -print)

[[ -z "$REMAINING" ]] ||
    die "Files owned by lfs remain"

echo
echo "[PASS] Ownership transfer completed"
