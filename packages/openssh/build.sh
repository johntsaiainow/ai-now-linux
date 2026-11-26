#!/usr/bin/env bash
set -euo pipefail
umask 022
: "${DESTDIR:?}" "${SOURCE_ARCHIVE:?}" "${JOBS:?}" "${AINPKG_ARCH:?}"
[[ "$AINPKG_ARCH" == x86_64 ]]
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source

CFLAGS="-O2 -march=x86-64 -mtune=generic -ffile-prefix-map=$PWD=/usr/src/openssh" \
    ./configure --prefix=/usr --sysconfdir=/etc/ssh \
    --libexecdir=/usr/libexec/openssh --with-privsep-path=/var/empty/sshd \
    --without-pam
make -j"$JOBS"
make DESTDIR="$DESTDIR" install-nokeys
chmod 0755 "$DESTDIR/usr/libexec/openssh/ssh-keysign"
install -Dm644 LICENCE "$DESTDIR/usr/share/licenses/openssh/LICENCE"
