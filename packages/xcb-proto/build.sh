#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
PYTHON=python3 ./configure --prefix=/usr
make -j"$JOBS"
make DESTDIR="$DESTDIR" pythondir=/usr/share/xcb/python install

# AINPKG adds usr/lib/pkgconfig from the build dependency tree to pkg-config.
install -d "$DESTDIR/usr/lib/pkgconfig"
mv "$DESTDIR"/usr/share/pkgconfig/*.pc "$DESTDIR/usr/lib/pkgconfig/"
sed -i 's|^prefix=/usr$|prefix=${pcfiledir}/../..|' "$DESTDIR"/usr/lib/pkgconfig/*.pc
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/xcb-proto/COPYING"

# pkg-config must return generator and XML paths in the extracted dependency.
sed -i -e 's|^xcbincludedir=.*|xcbincludedir=${datadir}/xcb|' \
    -e 's|^pythondir=.*|pythondir=${datadir}/xcb/python|' "$DESTDIR/usr/lib/pkgconfig/xcb-proto.pc"
find "$DESTDIR" -type f -name '*.pyc' -delete
