#!/usr/bin/env bash
set -euo pipefail
umask 022
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source/wpa_supplicant
pkg-config --exists dbus-1 openssl
cat > .config <<'CONF'
CONFIG_DRIVER_NL80211=y
CONFIG_LIBNL32=y
CONFIG_CTRL_IFACE=y
CONFIG_CTRL_IFACE_DBUS_NEW=y
CONFIG_CTRL_IFACE_DBUS_INTRO=y
CONFIG_TLS=openssl
CONFIG_IEEE8021X_EAPOL=y
CONFIG_EAP_TLS=y
CONFIG_EAP_PEAP=y
CONFIG_EAP_TTLS=y
CONFIG_EAP_MSCHAPV2=y
CONFIG_SAE=y
CONFIG_IEEE80211W=y
CFLAGS += -O2 -march=x86-64 -mtune=generic -I$(AINPKG_DEPS)/usr/include/libnl3
LIBS += -L$(AINPKG_DEPS)/usr/lib
CONF
make -j"$JOBS" BINDIR=/usr/sbin
for command in wpa_supplicant wpa_cli wpa_passphrase; do
    install -Dm755 "$command" "$DESTDIR/usr/sbin/$command"
done
install -Dm644 dbus/dbus-wpa_supplicant.conf \
    "$DESTDIR/usr/share/dbus-1/system.d/wpa_supplicant.conf"
install -Dm644 dbus/fi.w1.wpa_supplicant1.service \
    "$DESTDIR/usr/share/dbus-1/system-services/fi.w1.wpa_supplicant1.service"
install -Dm644 systemd/wpa_supplicant.service \
    "$DESTDIR/usr/lib/systemd/system/wpa_supplicant.service"
install -Dm644 ../COPYING "$DESTDIR/usr/share/licenses/wpa-supplicant/COPYING"
