#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
export LDFLAGS="-Wl,-rpath-link,$AINPKG_DEPS/usr/lib"
CFLAGS="-O2 -march=x86-64 -mtune=generic" meson setup build \
    --prefix=/usr --libdir=lib --buildtype=plain --wrap-mode=nodownload \
    -Dxorg=false -Dxvfb=true -Dxnest=false -Dglx=false -Dglamor=false \
    -Ddrm=false -Ddri1=false -Ddri2=false -Ddri3=false -Dpciaccess=false \
    -Dudev=false -Dudev_kms=false -Dhal=false -Dsystemd_logind=false \
    -Dsecure-rpc=false -Dxdmcp=false -Dsha1=libcrypto \
    -Ddocs=false -Ddevel-docs=false \
    -Dxkb_dir=/usr/share/X11/xkb -Dxkb_bin_dir=/usr/bin \
    -Ddefault_font_path=built-ins
meson compile -C build -j "$JOBS"
meson install -C build --no-rebuild
# The shared Xserver manual belongs with the hardware Xorg package.
rm -f -- "$DESTDIR/usr/share/man/man1/Xserver.1"
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/xorg-xvfb/COPYING"
