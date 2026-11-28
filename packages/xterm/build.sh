#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
export CPPFLAGS="-I$AINPKG_DEPS/usr/include"
# Select the native ncurses linkage, including split terminfo when provided.
export LIBS="$(pkg-config --libs ncursesw)"
export LDFLAGS="-L$AINPKG_DEPS/usr/lib -Wl,-rpath-link,$AINPKG_DEPS/usr/lib"
CFLAGS="-O2 -march=x86-64 -mtune=generic" ./configure \
    --prefix=/usr --libdir=/usr/lib --with-app-defaults=/usr/share/X11/app-defaults \
    --x-includes="$AINPKG_DEPS/usr/include" --x-libraries="$AINPKG_DEPS/usr/lib" \
    --disable-rpath-hack --disable-freetype --with-xpm \
    --disable-desktop --disable-setuid --disable-setgid
make -j"$JOBS"
make DESTDIR="$DESTDIR" install
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/xterm/COPYING"
