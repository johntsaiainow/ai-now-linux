#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s PROFILE LINUX_SOURCE NEW_OUTPUT_DIR [--config-only]\n' "$0" >&2
    exit 2
}

[[ $# == 3 || $# == 4 ]] || usage
profile=$1
case "$profile" in
    genericx86) arch=i386 ;;
    genericamd64|eeepc-1005p) arch=x86_64 ;;
    *) usage ;;
esac
[[ $# == 3 || $4 == --config-only ]] || usage
source_dir=$(realpath -e -- "$2")
output_dir=$(realpath -m -- "$3")
case "$output_dir/" in
    /|"$source_dir/"*) printf 'Use a new directory outside the kernel tree.\n' >&2; exit 2 ;;
esac
project=$(cd "$(dirname -- "$0")/.." && pwd)
fragments=("$project/kernel/config/boot-common.config" "$project/kernel/config/$profile.config")
test -f "$source_dir/Makefile"
test -f "$source_dir/scripts/kconfig/merge_config.sh"
mkdir -- "$output_dir"
unset KCONFIG_CONFIG
export ARCH="$arch"
kernel_make=(make -C "$source_dir" "O=$output_dir")

"${kernel_make[@]}" defconfig
bash "$source_dir/scripts/kconfig/merge_config.sh" -m -O "$output_dir" \
    "$output_dir/.config" "${fragments[@]}"
"${kernel_make[@]}" olddefconfig

# Detect any requested options dropped by Kconfig dependency resolution.
awk '
  FNR == NR {actual[$0] = 1; next}
  /^CONFIG_[A-Za-z0-9_]+=/ || /^# CONFIG_[A-Za-z0-9_]+ is not set$/ {
    if (!($0 in actual)) {
      print "Unresolved kernel setting: " $0 > "/dev/stderr"
      failed = 1
    }
  }
  END {exit failed}
' "$output_dir/.config" "${fragments[@]}"

printf 'Resolved kernel configuration: %s/.config\n' "$output_dir"
if [[ $# == 3 ]]; then
    "${kernel_make[@]}" -j"${JOBS:-1}" bzImage modules
    printf 'Kernel image: %s/arch/x86/boot/bzImage\n' "$output_dir"
fi
