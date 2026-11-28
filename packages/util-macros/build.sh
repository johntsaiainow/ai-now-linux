#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
./configure --prefix=/usr
make -j"$JOBS"
make DESTDIR="$DESTDIR" install

# AINPKG adds usr/lib/pkgconfig from the build dependency tree to pkg-config.
install -d "$DESTDIR/usr/lib/pkgconfig"
mv "$DESTDIR"/usr/share/pkgconfig/*.pc "$DESTDIR/usr/lib/pkgconfig/"
sed -i 's|^prefix=/usr$|prefix=${pcfiledir}/../..|' "$DESTDIR"/usr/lib/pkgconfig/*.pc
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/util-macros/COPYING"
