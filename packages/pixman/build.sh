#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
CFLAGS="-O2 -march=x86-64 -mtune=generic" meson setup build \
    --prefix=/usr --libdir=lib --buildtype=plain -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled
meson compile -C build -j "$JOBS"
meson install -C build --no-rebuild

# AINPKG v1 represents both loader and linker aliases as regular files.
while IFS= read -r -d '' alias; do
    target=$(realpath -e "$alias")
    [[ "$target" == "$DESTDIR/"* && -f "$target" ]]
    rm -- "$alias"
    cp -p -- "$target" "$alias"
done < <(find "$DESTDIR/usr/lib" -type l -print0)
sed -i 's|^prefix=/usr$|prefix=${pcfiledir}/../..|' "$DESTDIR"/usr/lib/pkgconfig/*.pc
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/pixman/COPYING"
