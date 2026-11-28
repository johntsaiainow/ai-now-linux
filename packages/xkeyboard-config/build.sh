#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source
meson setup build --prefix=/usr --libdir=lib -Dnls=false
meson compile -C build -j "$JOBS"
meson install -C build --no-rebuild

# AINPKG v1 stores regular files. Keep the legacy Xorg path as a copy of the database.
share="$DESTDIR/usr/share"
test -L "$share/X11/xkb"
rm -- "$share/X11/xkb"
cp -a -- "$share/xkeyboard-config-2" "$share/X11/xkb"

# Preserve the legacy metadata and optional man page aliases as regular files.
test -L "$share/pkgconfig/xkeyboard-config.pc"
rm -- "$share/pkgconfig/xkeyboard-config.pc"
install -d "$DESTDIR/usr/lib/pkgconfig"
mv "$share/pkgconfig/xkeyboard-config-2.pc" "$DESTDIR/usr/lib/pkgconfig/"
pc="$DESTDIR/usr/lib/pkgconfig/xkeyboard-config-2.pc"
sed -i -e 's|^datadir=/usr/share$|datadir=${pcfiledir}/../../share|' \
    -e 's|^xkb_root=/usr/share/|xkb_root=${datadir}/|' \
    -e 's|^xkb_base=/usr/share/|xkb_base=${datadir}/|' "$pc"
cp -p -- "$pc" "$DESTDIR/usr/lib/pkgconfig/xkeyboard-config.pc"
if [[ -L "$share/man/man7/xkeyboard-config.7" ]]; then
    rm -- "$share/man/man7/xkeyboard-config.7"
    cp -p -- "$share/man/man7/xkeyboard-config-2.7" "$share/man/man7/xkeyboard-config.7"
fi
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/xkeyboard-config/COPYING"
