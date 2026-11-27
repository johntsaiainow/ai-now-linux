#!/usr/bin/env bash
set -euo pipefail
umask 022
: "${DESTDIR:?}" "${SOURCE_ARCHIVE:?}" "${JOBS:?}" "${AINPKG_ARCH:?}" "${AINPKG_PACKAGE:?}"
[[ "$AINPKG_ARCH" == x86_64 ]]
recipe_dir=$(dirname -- "$0")
mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source

CFLAGS="-O2 -march=x86-64 -mtune=generic -ffile-prefix-map=$PWD=/usr/src/openssh" \
    ./configure --prefix=/usr --sysconfdir=/etc/ssh \
    --libexecdir=/usr/libexec/openssh --with-privsep-path=/var/empty/sshd \
    --without-pam
make -j"$JOBS"

image=$(mktemp -d ../openssh-stage.XXXXXX)
image=$(realpath "$image")
make DESTDIR="$image" install-nokeys
chmod 0755 "$image/usr/libexec/openssh/ssh-keysign"

server_files=(
    etc/ssh/moduli etc/ssh/sshd_config usr/sbin/sshd
    usr/libexec/openssh/sshd-session usr/libexec/openssh/sshd-auth
    usr/libexec/openssh/sftp-server
)
for page in "$image"/usr/share/man/*/{sshd.8,sshd_config.5,moduli.5,sftp-server.8}; do
    if [[ -f "$page" ]]; then
        server_files+=("${page#"$image/"}")
    fi
done

case "$AINPKG_PACKAGE" in
    openssh)
        for path in "${server_files[@]}"; do
            rm -- "$image/$path"
        done
        cp -a -- "$image/." "$DESTDIR/"
        ;;
    openssh-server)
        for path in "${server_files[@]}"; do
            install -D -m "$(stat -c %a "$image/$path")" "$image/$path" "$DESTDIR/$path"
        done
        install -Dm755 "$image/usr/bin/ssh-keygen" "$DESTDIR/usr/libexec/openssh/ssh-keygen"
        install -Dm644 "$recipe_dir/sshd.service" "$DESTDIR/usr/lib/systemd/system/sshd.service"
        install -Dm644 "$recipe_dir/openssh-server.sysusers" "$DESTDIR/usr/lib/sysusers.d/openssh-server.conf"
        install -Dm644 "$recipe_dir/openssh-server.tmpfiles" "$DESTDIR/usr/lib/tmpfiles.d/openssh-server.conf"
        ;;
    *) exit 1 ;;
esac

install -Dm644 LICENCE "$DESTDIR/usr/share/licenses/$AINPKG_PACKAGE/LICENCE"
