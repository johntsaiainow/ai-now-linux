#!/bin/bash
set -Eeuo pipefail
cd /sources
test "$(id -u)" = 0
test "$(findmnt -n -o SOURCE /)" = /dev/loop25p2
test "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)"
test "$(gcc -dumpmachine)" = x86_64-pc-linux-gnu
export MAKEFLAGS=-j8
pkgs=(groff-1.24.1 grub-2.14 gzip-1.14 iproute2-7.1.0 kbd-2.10.0 libpipeline-1.5.8)
archives=(groff-1.24.1.tar.gz grub-2.14.tar.xz gzip-1.14.tar.xz iproute2-7.1.0.tar.xz kbd-2.10.0.tar.xz libpipeline-1.5.8.tar.gz)
for a in "${archives[@]}" kbd-2.10.0-backspace-1.patch; do test -f "$a"; done
run(){ local stage=$1; shift; echo "=== $pkg: $stage ==="; if time "$@" > "$log/$stage.log" 2>&1; then tail -8 "$log/$stage.log"; else tail -40 "$log/$stage.log"; return 1; fi; }
for i in "${!pkgs[@]}"; do
 cd /sources
 pkg=${pkgs[i]}; archive=${archives[i]}; log=/sources/build-logs/$pkg
 mkdir -p "$log"
 if test -f "$log/acceptance.txt"; then sha256sum -c "$log/installed.sha256"; continue; fi
 test ! -e "$log/started.txt"
 if test -e "$pkg"; then test ! -e "$pkg-bootstrap-preserved"; mv "$pkg" "$pkg-bootstrap-preserved"; fi
 sha256sum "/sources/$archive" > "$log/source.sha256"
 date -Iseconds > "$log/started.txt"
 run extract tar -xf "$archive"
 cd "$pkg"
 regression='command exit 0; review log'
 case $pkg in
 groff-*)
 run configure env PAGE=letter ./configure --prefix=/usr
 run build make -j1
 if ! run check make check; then
 echo 'Review Groff failure before installation (known: neqn-smoke-test.sh).'; exit 1
 fi
 run install make install
 bins=(/usr/bin/groff /usr/bin/troff /usr/bin/nroff)
 ;;
 grub-*)
 unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
 run fix sed -i 's/--image-base/--nonexist-linker-option/' configure
 run configure ./configure --prefix=/usr --sysconfdir=/etc --disable-efiemu --disable-werror
 run build make
 run install make install
 regression='Not run: LFS does not recommend suite in limited environment'
 bins=(/usr/bin/grub-mkimage /usr/bin/grub-script-check /usr/lib/grub/i386-pc/normal.mod)
 ;;
 gzip-*)
 run configure ./configure --prefix=/usr
 run build make
 run check make check
 run install make install
 bins=(/usr/bin/gzip /usr/bin/gunzip /usr/bin/zcat)
 ;;
 iproute2-*)
 run fix sed -i /ARPD/d Makefile
 rm -fv man/man8/arpd.8
 run build make NETNS_RUN_DIR=/run/netns
 run install make SBINDIR=/usr/sbin install
 run docs install -vDm644 COPYING README* -t /usr/share/doc/iproute2-7.1.0
 regression='No working upstream suite per LFS'
 bins=(/usr/sbin/ip /usr/sbin/ss /usr/sbin/tc)
 ;;
 kbd-*)
 sha256sum /sources/kbd-2.10.0-backspace-1.patch >> "$log/source.sha256"
 run patch patch -Np1 -i ../kbd-2.10.0-backspace-1.patch
 sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
 sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
 run configure ./configure --prefix=/usr --disable-vlock
 run build make
 run check make check
 run install make install
 run docs cp -R -v docs/doc -T /usr/share/doc/kbd-2.10.0
 bins=(/usr/bin/loadkeys /usr/bin/setfont /usr/bin/psfxtable)
 ;;
 libpipeline-*)
 run configure ./configure --prefix=/usr
 run build make
 run install make install
 regression='Not run: Check library unavailable per LFS'
 bins=(/usr/lib/libpipeline.so)
 ;;
 esac
 lab=$(mktemp -d /tmp/batch06-lab.XXXXXX)
 printf '%s\n' "$lab" > "$log/lab-path.txt"
 (
 set -Eeuo pipefail
 cd "$lab"
 case $pkg in
 groff-*) printf '.TH GENESIS 1\n.SH NAME\nGenesis infrastructure\n' > genesis.1; groff -Tascii -man genesis.1 > rendered.txt; grep -F 'Genesis infrastructure' rendered.txt ;;
 grub-*) grub-mkimage -O i386-pc -p /boot/grub -o core.img biosdisk part_gpt ext2 normal; test -s core.img; printf 'menuentry "Genesis" {\n echo Genesis\n}\n' > grub.cfg; grub-script-check grub.cfg ;;
 gzip-*) printf 'Genesis 42\n%.0s' {1..1000} > original; gzip -c original > data.gz; gzip -t data.gz; gzip -dc data.gz > restored; cmp original restored; python3 -c 'import gzip; assert gzip.open("data.gz","rb").read()==open("original","rb").read()' ;;
 iproute2-*) ip -Version; ss -Version; unshare --net bash -ec 'ip link set lo up; ip -4 addr show dev lo | grep -F 127.0.0.1; ip route show; ss -lnt; tc qdisc show dev lo' ;;
 kbd-*) loadkeys --version; setfont --version; loadkeys -m us > keymap.c; test -s keymap.c; test -d /usr/share/consolefonts ;;
 libpipeline-*) cat > lab.c <<'C'
#include <pipeline.h>
int main(void) {
    pipeline *p = pipeline_new();
    pipeline_command_args(p, "printf", "Genesis\\n", (void *)0);
    pipeline_command_args(p, "grep", "Genesis", (void *)0);
    int status = pipeline_run(p);
    return status != 0;
}
C
 gcc lab.c -o lab -lpipeline; ./lab > output; grep -Fx Genesis output ;;
 esac
 echo '[PASS] Integration'
 ) 2>&1 | tee "$log/integration.log"
 mkdir -p "$log/upstream"
 find . -type f \( -name '*.log' -o -name '*.sum' -o -name '*.trs' -o -name config.status \) -exec cp --parents -t "$log/upstream" {} +
 sha256sum "${bins[@]}" > "$log/installed.sha256"
 sha256sum -c "$log/installed.sha256"
 printf 'Package: %s\nStatus: BUILD AND INTEGRATION PASSED\nRegression: %s\nCompleted: %s\nSource cleanup: deferred\n' "$pkg" "$regression" "$(date -Iseconds)" > "$log/acceptance.txt.tmp"
 mv "$log/acceptance.txt.tmp" "$log/acceptance.txt"
 done
echo '[PASS] Batch 06 completed'
