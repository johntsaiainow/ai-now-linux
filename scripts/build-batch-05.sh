#!/bin/bash
set -Eeuo pipefail
trap 'echo "[FAIL] ${pkg:-preflight} / ${stage:-preflight} / line $LINENO" >&2' ERR
test "$(id -u)" = 0
test "$(findmnt -n -o SOURCE /)" = /dev/loop25p2
test "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)"
test "$(gcc -dumpmachine)" = x86_64-pc-linux-gnu
cd /sources
base=$PWD
records=$base/build-logs
export MAKEFLAGS=-j8
packages=(kmod-34.2 coreutils-9.11 diffutils-3.12 findutils-4.11.0)
for p in "${packages[@]}"; do test -f "$base/$p.tar.xz"; done
test -f "$base/coreutils-9.11-i18n-1.patch"
id tester
if ! test -f "$records/coreutils-9.11/acceptance.txt"; then
 if getent group dummy || getent group 102; then echo 'Group dummy or GID 102 already exists; stop for review'; exit 1; fi
fi
run(){ stage=$1; shift; echo "=== $pkg / $stage ==="; time "$@" > "$log/$stage.log" 2>&1; tail -n 15 "$log/$stage.log"; }
for pkg in "${packages[@]}"; do
 stage=prepare; log=$records/$pkg; src=$base/$pkg; mkdir -p "$log"
 if test -f "$log/acceptance.txt"; then sha256sum -c "$log/installed.sha256"; continue; fi
 test ! -e "$log/started.txt"
 sha256sum "$base/$pkg.tar.xz" > "$log/source.sha256"
 date -Iseconds > "$log/started.txt"
 cd "$base"
 if test -e "$src"; then test -d "$src"; test ! -L "$src"; test ! -e "$src-bootstrap-preserved"; mv "$src" "$src-bootstrap-preserved"; fi
 tar -xf "$pkg.tar.xz"; cd "$src"
 regression='command exit 0; review logs'
 mkdir -p "$log/integration"
 case "$pkg" in
 kmod-*)
 mkdir -p build; cd build
 run configure meson setup --prefix=/usr .. --buildtype=release -D manpages=false
 run build ninja -j8
 run install ninja install
 regression='No regression command in supplied LFS commands; no module loading performed'
 run integration kmod --version
 files=(/usr/bin/kmod /usr/lib/libkmod.so)
 ;;
 coreutils-*)
 sha256sum "$base/coreutils-9.11-i18n-1.patch" >> "$log/source.sha256"
 run patch patch -Np1 -i ../coreutils-9.11-i18n-1.patch
 run autoreconf autoreconf -fv
 run automake automake -af
 run configure env FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
 run build make -j8
 # Isolate PID and network namespaces for root regression; retain private mount namespace.
 run check-root unshare --mount --propagation private --pid --fork --mount-proc --net --uts --kill-child make -j1 NON_ROOT_USERNAME=tester check-root
 groupadd -g 102 dummy -U tester
 trap 'groupdel dummy' EXIT
 chown -R tester .
 run check su tester -c "PATH=$PATH make -k RUN_EXPENSIVE_TESTS=yes check" < /dev/null
 groupdel dummy; trap - EXIT
 run install make install
 mv -v /usr/bin/chroot /usr/sbin
 mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
 sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
 cat > "$log/integration/test.sh" <<'LAB'
set -Eeuo pipefail
cd "$(mktemp -d /tmp/coreutils-lab.XXXXXX)"
printf 'Genesis\n' > original
setfattr -n user.genesis -v 42 original
setfacl -m u:tester:r-- original
cp -a original copy
cmp original copy
test "$(getfattr --only-values -n user.genesis copy)" = 42
getfacl -c original > original.acl
getfacl -c copy > copy.acl
cmp original.acl copy.acl
printf 'PASS: content, xattr, ACL\n'
pwd
LAB
 run integration bash "$log/integration/test.sh"
 files=(/usr/bin/cp /usr/bin/ls /usr/bin/mv /usr/bin/sha256sum /usr/sbin/chroot)
 ;;
 diffutils-*)
 run configure ./configure --prefix=/usr
 run build make -j8
 run check make check
 run install make install
 run integration bash -c 'set -e; cd "$1"; printf "Genesis\n" > a; cp a b; cmp a b; diff a b; printf "Next\n" >> b; rc=0; diff -u a b > delta || rc=$?; test "$rc" = 1; grep -Fxq "+Next" delta' _ "$log/integration"
 files=(/usr/bin/diff /usr/bin/cmp /usr/bin/diff3)
 ;;
 findutils-*)
 run configure ./configure --prefix=/usr --localstatedir=/var/lib/locate
 run build make -j8
 chown -R tester .
 run check su tester -c "PATH=$PATH make check -k"
 run install make install
 run integration bash -c 'set -e; cd "$1"; mkdir -p tree; touch tree/a.c tree/b.txt; test "$(find tree -type f -name "*.c" -print)" = tree/a.c; test "$(printf "Genesis\n" | xargs printf "%s")" = Genesis' _ "$log/integration"
 files=(/usr/bin/find /usr/bin/xargs)
 ;;
 esac
 stage=records; cd "$src"; mkdir -p "$log/upstream"
 find . -type f \( -name '*.log' -o -name '*.sum' -o -name '*.trs' -o -name config.status \) -exec cp --parents -t "$log/upstream" {} +
 sha256sum "${files[@]}" > "$log/installed.sha256"
 sha256sum -c "$log/installed.sha256"
 printf 'Package: %s\nStatus: BUILD AND INTEGRATION PASSED\nRegression: %s\nCompleted: %s\nSource cleanup: deferred\n' "$pkg" "$regression" "$(date -Iseconds)" > "$log/acceptance.txt.tmp"
 mv "$log/acceptance.txt.tmp" "$log/acceptance.txt"
 echo "[PASS] $pkg"
done
echo '[DONE] Batch 05: 4 packages'
