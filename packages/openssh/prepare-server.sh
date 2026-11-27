#!/bin/sh
# Provision OpenSSH prerequisites on Genesis builds without systemd-sysusers.
set -eu

root=/
if [ "$#" -ne 0 ]; then
    if [ "$#" -ne 2 ] || [ "$1" != --root ] || [ ! -d "$2" ]; then
        printf '%s\n' "usage: prepare-server [--root DIRECTORY]" >&2
        exit 2
    fi
    root=$(realpath -- "$2")
    if [ "$root" = / ]; then
        printf '%s\n' "the offline root must be different from /" >&2
        exit 2
    fi
fi
root_prefix=${root%/}

for directory in etc var var/empty var/empty/sshd; do
    if [ -L "$root_prefix/$directory" ]; then
        printf 'Refusing symbolic link: %s\n' "$root_prefix/$directory" >&2
        exit 1
    fi
done

if ! grep -qs '^sshd:' "$root_prefix/etc/passwd"; then
    if grep -qs '^sshd:' "$root_prefix/etc/group"; then
        set -- --gid sshd
    else
        set -- --user-group
    fi
    if [ "$root" != / ]; then
        set -- --root "$root" "$@"
    fi
    useradd "$@" --system --no-create-home --home-dir /var/empty/sshd \
        --shell /usr/sbin/nologin --comment 'OpenSSH privilege separation' sshd
fi

install -d -o 0 -g 0 -m 0755 -- "$root_prefix/var/empty/sshd"
