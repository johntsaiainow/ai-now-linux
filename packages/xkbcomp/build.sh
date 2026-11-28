#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
# Use the C parser shipped in the release tarball.
touch xkbparse.c
export LDFLAGS="-Wl,-rpath-link,$AINPKG_DEPS/usr/lib"
CFLAGS="-O2 -march=x86-64 -mtune=generic" ./configure \
    --prefix=/usr --with-xkb-config-root=/usr/share/X11/xkb
make -j"$JOBS"
make DESTDIR="$DESTDIR" install
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/xkbcomp/COPYING"
