#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
export LDFLAGS="-Wl,-rpath-link,$AINPKG_DEPS/usr/lib"
CFLAGS="-O2 -march=x86-64 -mtune=generic" ./configure \
    --prefix=/usr --libdir=/usr/lib --disable-static --sysconfdir=/etc --with-xserver=/usr/bin/X --with-xinitdir=/etc/X11/xinit
make -j"$JOBS"
make DESTDIR="$DESTDIR" install

# Keep user startup hooks and launch a single terminal from the system session.
sed -i '/^"\$twm" &$/,$d' "$DESTDIR/etc/X11/xinit/xinitrc"
printf '%s\n' 'exec xterm' >> "$DESTDIR/etc/X11/xinit/xinitrc"
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/xinit/COPYING"
