#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
export LDFLAGS="-Wl,-rpath-link,$AINPKG_DEPS/usr/lib"
CFLAGS="-O2 -march=x86-64 -mtune=generic" ./configure \
    --prefix=/usr --libdir=/usr/lib --disable-static --disable-open-zfile --with-localedir=no
make -j"$JOBS"
make DESTDIR="$DESTDIR" install
# AINPKG v1 represents both loader and linker aliases as regular files.
while IFS= read -r -d '' alias; do
    target=$(realpath -e "$alias")
    [[ "$target" == "$DESTDIR/"* && -f "$target" ]]
    rm -- "$alias"
    cp -p -- "$target" "$alias"
done < <(find "$DESTDIR/usr/lib" -type l -print0)
find "$DESTDIR/usr/lib" -name '*.la' -type f -delete
sed -i -e 's|^prefix=/usr$|prefix=${pcfiledir}/../..|' \
    -e 's|^libdir=/usr/lib$|libdir=${exec_prefix}/lib|' "$DESTDIR"/usr/lib/pkgconfig/*.pc
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/libxpm/COPYING"
