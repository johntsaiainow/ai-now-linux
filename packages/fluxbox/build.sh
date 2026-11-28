#!/usr/bin/env bash
set -euo pipefail
umask 022
recipe=$(dirname "$0")
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
# GCC rejects the old ordered comparison between a pointer and zero.
sed -i "s/text_prop.value > 0/text_prop.value != 0/" util/fluxbox-remote.cc

export CPPFLAGS="-I$AINPKG_DEPS/usr/include"
export LDFLAGS="-L$AINPKG_DEPS/usr/lib -Wl,-rpath-link,$AINPKG_DEPS/usr/lib"
CXXFLAGS="-O2 -march=x86-64 -mtune=generic -std=gnu++11" ./configure \
    --prefix=/usr --libdir=/usr/lib --disable-nls \
    --disable-imlib2 --disable-xft --disable-xpm \
    --disable-xinerama --disable-xrandr --disable-fribidi
make -j"$JOBS"
make DESTDIR="$DESTDIR" install
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/fluxbox/COPYING"
for file in genesis-session genesis-terminal; do
    install -Dm755 "$recipe/$file" "$DESTDIR/usr/bin/$file"
done
for file in init keys menu style; do
    install -Dm644 "$recipe/$file" "$DESTDIR/usr/share/ainow/genesis-desktop/$file"
done
