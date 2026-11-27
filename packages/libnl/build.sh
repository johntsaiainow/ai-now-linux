#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
CFLAGS="-O2 -march=x86-64 -mtune=generic" ./configure \
    --prefix=/usr --libdir=/usr/lib --sysconfdir=/etc --disable-static
make -j"$JOBS"
make DESTDIR="$DESTDIR" install
# ainpkg v1 stores only regular files. Keep both SONAME and linker aliases.
while IFS= read -r -d '' alias; do
    target=$(realpath -e "$alias")
    [[ "$target" == "$DESTDIR/"* && -f "$target" ]]
    rm -- "$alias"
    cp -p -- "$target" "$alias"
done < <(find "$DESTDIR" -type l -print0)
# Relative prefixes work inside the build dependency tree and after installation.
sed -i -e 's|^prefix=/usr$|prefix=${pcfiledir}/../..|' \
    -e 's|^libdir=/usr/lib$|libdir=${exec_prefix}/lib|' "$DESTDIR"/usr/lib/pkgconfig/*.pc
find "$DESTDIR" -name '*.la' -type f -delete
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/libnl/COPYING"
