#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
# Give the hardware server its own protocol registry so it can coexist with Xvfb.
sed -i "/^serverconfigdir = /s/'xorg')/'xorg', 'hardware')/" meson.build
export LDFLAGS="-Wl,-rpath-link,$AINPKG_DEPS/usr/lib"
CFLAGS="-O2 -march=x86-64 -mtune=generic" meson setup build \
    --prefix=/usr --libdir=lib --buildtype=plain --wrap-mode=nodownload \
    -Dxorg=true -Dxvfb=false -Dxnest=false -Dglx=false -Dglamor=false \
    -Ddrm=true -Ddri1=false -Ddri2=false -Ddri3=false -Dpciaccess=true \
    -Dudev=true -Dudev_kms=true -Dhal=false -Dsystemd_logind=false \
    -Dsecure-rpc=false -Dxdmcp=false -Dsha1=libcrypto \
    -Ddocs=false -Ddevel-docs=false \
    -Dxkb_dir=/usr/share/X11/xkb -Dxkb_bin_dir=/usr/bin \
    -Dfallback_input_driver=evdev -Ddefault_font_path=built-ins
meson compile -C build -j "$JOBS"
meson install -C build --no-rebuild
test -f "$DESTDIR/usr/lib/xorg/modules/drivers/modesetting_drv.so"
# Keep the X alias usable by xinit with the regular-file package format.
test -L "$DESTDIR/usr/bin/X"
rm -- "$DESTDIR/usr/bin/X"
cat > "$DESTDIR/usr/bin/X" <<'SH'
#!/bin/sh
exec /usr/bin/Xorg "$@"
SH
chmod 755 "$DESTDIR/usr/bin/X"
sed -i -e 's|^prefix=/usr$|prefix=${pcfiledir}/../..|' \
    -e 's|^Requires.private:.*|& pciaccess|' \
    -e 's|^libdir=/usr/lib$|libdir=${exec_prefix}/lib|' "$DESTDIR"/usr/lib/pkgconfig/*.pc
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/xorg-server/COPYING"
