#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
CFLAGS="-O2 -march=x86-64 -mtune=generic" ./configure \
    --prefix=/usr --libdir=/usr/lib --disable-static --with-sdkdir=/usr/include/xorg
make -j"$JOBS"
make DESTDIR="$DESTDIR" install
find "$DESTDIR/usr/lib" -name '*.la' -type f -delete
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/xf86-input-evdev/COPYING"
