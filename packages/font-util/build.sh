#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
CFLAGS="-O2 -march=x86-64 -mtune=generic" ./configure --prefix=/usr --libdir=/usr/lib
make -j"$JOBS"
make DESTDIR="$DESTDIR" install
sed -i 's|^prefix=/usr$|prefix=${pcfiledir}/../..|' "$DESTDIR"/usr/lib/pkgconfig/*.pc
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/font-util/COPYING"
