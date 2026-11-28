#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
CFLAGS="-O2 -march=x86-64 -mtune=generic" meson setup build \
    --prefix=/usr --libdir=lib --buildtype=plain --wrap-mode=nodownload -Dintel=enabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
    -Dvmwgfx=disabled -Dfreedreno=disabled -Dvc4=disabled -Detnaviv=disabled \
    -Dtests=false -Dman-pages=disabled -Dvalgrind=disabled
meson compile -C build -j "$JOBS"
meson install -C build --no-rebuild
# AINPKG v1 represents both loader and linker aliases as regular files.
while IFS= read -r -d '' alias; do
    target=$(realpath -e "$alias")
    [[ "$target" == "$DESTDIR/"* && -f "$target" ]]
    rm -- "$alias"
    cp -p -- "$target" "$alias"
done < <(find "$DESTDIR/usr/lib" -type l -print0)
sed -i -e 's|^prefix=/usr$|prefix=${pcfiledir}/../..|' \
    -e 's|^libdir=/usr/lib$|libdir=${exec_prefix}/lib|' "$DESTDIR"/usr/lib/pkgconfig/*.pc
license_dir="$DESTDIR/usr/share/licenses/libdrm"
install -d "$license_dir"
sed -n '/^\/\*$/,/^ \*\//p' xf86drm.c > "$license_dir/core.txt"
sed -n '1,/^ \*\//p' intel/intel_bufmgr.c > "$license_dir/intel.txt"
