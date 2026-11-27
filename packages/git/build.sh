#!/usr/bin/env bash
set -euo pipefail
umask 022
: "${DESTDIR:?}" "${SOURCE_ARCHIVE:?}" "${JOBS:?}" "${AINPKG_ARCH:?}"
[[ "$AINPKG_ARCH" == x86_64 ]]

mkdir source
tar -xf "$SOURCE_ARCHIVE" -C source --strip-components=1
cd source

options=(
    prefix=/usr gitexecdir=/usr/libexec/git-core sysconfdir=/etc
    "CFLAGS=-O2 -march=x86-64 -mtune=generic -ffile-prefix-map=$PWD=/usr/src/git"
    NO_CURL=YesPlease NO_EXPAT=YesPlease NO_OPENSSL=YesPlease
    NO_TCLTK=YesPlease NO_GETTEXT=YesPlease NO_PERL=YesPlease NO_RUST=YesPlease
    SKIP_DASHED_BUILT_INS=YesPlease NO_INSTALL_HARDLINKS=YesPlease
)
make -j"$JOBS" "${options[@]}" all
make "${options[@]}" DESTDIR="$DESTDIR" install
# Upstream falls back to symlinks for these public built-in aliases.
# The current package format stages independent regular files only.
for name in git-receive-pack git-upload-archive git-upload-pack; do
    alias_path="$DESTDIR/usr/bin/$name"
    if [[ -L "$alias_path" ]]; then
        [[ "$(readlink "$alias_path")" == git ]]
        rm -- "$alias_path"
        install -m755 "$DESTDIR/usr/bin/git" "$alias_path"
    fi
done
install -Dm644 COPYING "$DESTDIR/usr/share/licenses/git/COPYING"
