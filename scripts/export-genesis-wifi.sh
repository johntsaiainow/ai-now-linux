#!/usr/bin/env bash
# Prepare the reviewed build inputs for transfer to an offline Genesis VM.
set -euo pipefail
[[ $# == 1 ]] || { printf 'Usage: %s NEW_BUNDLE.tar.gz\n' "$0" >&2; exit 2; }
parent=$(realpath -e -- "$(dirname -- "$1")")
output="$parent/$(basename -- "$1")"
[[ ! -e "$output" && ! -L "$output" ]] || { echo 'Bundle already exists.' >&2; exit 1; }
repo=$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel)
ref=$(git -C "$repo" rev-parse HEAD)
work=$(mktemp -d -- "$parent/.wifi-export.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/genesis-wifi"
stage="$work/genesis-wifi"

git -C "$repo" show "$ref:scripts/ainpkg" > "$stage/ainpkg"
git -C "$repo" show "$ref:scripts/build-genesis-wifi.py" > "$stage/build.py"
for name in libnl wpa-supplicant; do
    git -C "$repo" archive --format=tar "$ref" "packages/$name" > "$stage/$name-recipe.tar"
    git -C "$repo" show "$ref:packages/$name/recipe.toml" |
        python3 -c 'import sys, tomllib; source = tomllib.load(sys.stdin.buffer)["source"]; print(source["url"]); print(source["sha256"])'         > "$work/source"
    mapfile -t metadata < "$work/source"
    curl --proto '=https' --proto-redir '=https' -fLsS \
        "${metadata[0]}" -o "$stage/$name-source.tar.gz"
    printf '%s  %s\n' "${metadata[1]}" "$stage/$name-source.tar.gz" | sha256sum -c -
done
printf '%s\n' "$ref" > "$stage/RECIPE_COMMIT"
(cd "$stage" && sha256sum ainpkg build.py RECIPE_COMMIT ./*.tar ./*.tar.gz > SHA256SUMS)
tar -czf "$work/bundle.tar.gz" -C "$work" genesis-wifi
ln -T -- "$work/bundle.tar.gz" "$output"
sha256sum -- "$output"
