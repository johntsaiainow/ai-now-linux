#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
CFLAGS="-O2 -march=x86-64 -mtune=generic" ./configure \
    --prefix=/usr --libdir=/usr/lib --disable-static \
    --with-zlib=yes --with-bzip2=no --with-png=no --with-harfbuzz=no --with-brotli=no
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
    -e 's|^exec_prefix=/usr$|exec_prefix=${prefix}|' \
    -e 's|^libdir=/usr/lib$|libdir=${exec_prefix}/lib|' \
    -e 's|^includedir=/usr/include$|includedir=${prefix}/include|' \
    -e 's|^Libs: -L/usr/lib |Libs: -L${libdir} |' "$DESTDIR"/usr/lib/pkgconfig/*.pc
license_dir="$DESTDIR/usr/share/licenses/freetype"
install -d "$license_dir/docs"
install -m644 LICENSE.TXT "$license_dir/"
install -m644 docs/FTL.TXT docs/GPLv2.TXT "$license_dir/docs/"
