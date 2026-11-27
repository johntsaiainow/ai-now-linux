#!/usr/bin/env bash
# Build the checked-in EeePC kernel and use it for a local Genesis media build.
set -euo pipefail
[[ $# == 2 ]] || { printf "Usage: %s GENESIS.raw NEW_OUTPUT_DIRECTORY\n" "$0" >&2; exit 2; }
[[ $EUID != 0 ]] || { printf "Run as a normal user. Only image creation uses sudo.\n" >&2; exit 2; }
project=$(cd "$(dirname -- "$0")/.." && pwd)
raw=$(realpath -e -- "$1")
output=$(realpath -m -- "$2")
[[ -f "$raw" && ! -e "$output" && ! -L "$output" ]] || { printf "Need an existing Genesis RAW and a new output directory.\n" >&2; exit 2; }
[[ -d "$(dirname -- "$output")" && -r /usr/lib/grub/i386-pc/modinfo.sh ]] || { printf "Need an existing output parent and grub-pc-bin.\n" >&2; exit 2; }
for tool in curl gcc make flex bison bc pkg-config depmod zstd sudo unshare; do
    command -v "$tool" >/dev/null || { printf "Missing build tool: %s\n" "$tool" >&2; exit 2; }
done
pkg-config --exists libelf openssl || { printf "Install libelf-dev and libssl-dev first.\n" >&2; exit 2; }
work=$(mktemp -d -- "$(dirname -- "$output")/eeepc-kernel-build.XXXXXX")
printf "Build directory: %s\n" "$work"
curl -fLSs https://www.kernel.org/pub/linux/kernel/v7.x/linux-7.1.8.tar.xz -o "$work/linux-7.1.8.tar.xz"
(cd "$work" && sha256sum -c "$project/kernel/linux-7.1.8.sha256")
tar -xJf "$work/linux-7.1.8.tar.xz" -C "$work"
source_dir="$work/linux-7.1.8"
output_dir="$work/kernel"
if [[ -z ${JOBS:-} ]]; then
    JOBS=$(nproc)
    if (( JOBS > 8 )); then JOBS=8; fi
fi
export JOBS
"$project/scripts/build-kernel-profile.sh" eeepc-1005p "$source_dir" "$output_dir"
release=$(make -s -C "$source_dir" O="$output_dir" ARCH=x86_64 kernelrelease)
[[ "$release" == 7.1.8-ainow-eeepc-1005p ]] || { printf "Unexpected kernel release: %s\n" "$release" >&2; exit 2; }
stage="$work/staged"
make -s -C "$source_dir" O="$output_dir" ARCH=x86_64 INSTALL_MOD_PATH="$stage" INSTALL_MOD_STRIP=1 modules_install
install -Dm644 -- "$output_dir/arch/x86/boot/bzImage" "$stage/bzImage"
install -Dm644 -- "$output_dir/.config" "$stage/config"
# Package only the boot image and installed modules. Build/source links are local.
rm -f -- "$stage/lib/modules/$release/build" "$stage/lib/modules/$release/source"
bundle="$work/ainow-$release-kernel.tar.zst"
tar --zstd -C "$stage" -cf "$bundle" ./bzImage ./config "./lib/modules/$release"
bundle_sha=$(sha256sum -- "$bundle" | cut -d " " -f 1)
printf "Kernel bundle: %s\nSHA256: %s\n" "$bundle" "$bundle_sha"
sudo unshare --mount --propagation private env "AINOW_EEEPC_KERNEL_SHA256=$bundle_sha" \
    "$project/scripts/build-eeepc-rescue.sh" "$raw" "$bundle" "$output"
(cd "$output" && sha256sum -c SHA256SUMS)
