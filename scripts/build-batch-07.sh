#!/bin/bash
set -Eeuo pipefail
trap 'echo "[FAIL] ${pkg:-preflight}: ${stage:-preflight}; inspect ${log:-/sources}" >&2' ERR
test "$(id -u)" = 0
test "$(findmnt -n -o SOURCE /)" = /dev/loop25p2
test "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)"
test "$(gcc -dumpmachine)" = x86_64-pc-linux-gnu
cd /sources
base=$PWD
export MAKEFLAGS=-j8 PIP_NO_INDEX=1 PIP_DISABLE_PIP_VERSION_CHECK=1
packages=(make-4.4.1 patch-2.8 tar-1.35 texinfo-7.3 vim-9.2.1025 markupsafe-3.0.3 jinja2-3.1.6)
archives=(make-4.4.1.tar.gz patch-2.8.tar.xz tar-1.35.tar.xz texinfo-7.3.tar.xz vim-9.2.1025.tar.gz markupsafe-3.0.3.tar.gz jinja2-3.1.6.tar.gz)
for a in "${archives[@]}" tar-1.35-acl_fix-1.patch; do test -f "$base/$a"; done
id tester
run(){ stage=$1; shift; echo "=== $pkg: $stage ==="; time "$@" > "$log/$stage.log" 2>&1; tail -8 "$log/$stage.log"; }
for i in "${!packages[@]}"; do
 pkg=${packages[i]}; archive=${archives[i]}; src=$base/$pkg; log=$base/build-logs/$pkg; stage=prepare
 mkdir -p "$log"
 if test -f "$log/acceptance.txt"; then sha256sum -c "$log/installed.sha256"; continue; fi
 test ! -e "$log/started.txt"
 cd "$base"
 sha256sum "$base/$archive" > "$log/source.sha256"
 date -Iseconds > "$log/started.txt"
 if test -e "$src"; then test -d "$src"; test ! -L "$src"; test ! -e "$src-bootstrap-preserved"; mv "$src" "$src-bootstrap-preserved"; fi
 run extract tar -xf "$archive"
 cd "$src"
 lab=$(mktemp -d /tmp/batch07-lab.XXXXXX); echo "$lab" > "$log/lab-path.txt"
 regression='command exit 0; review log'
 case "$pkg" in
 make-*)
 run configure ./configure --prefix=/usr
 run build make -j8
 chown -R tester .
 run check su tester -c "PATH=$PATH make check"
 run install make install
 printf 'all:\n\t@printf "Genesis\\n" > result\n' > "$lab/Makefile"
 run integration bash -c 'set -e; cd "$1"; make; grep -Fx Genesis result' _ "$lab"
 files=(/usr/bin/make);;
 patch-*)
 run configure ./configure --prefix=/usr
 run build make -j8
 run check make check
 run install make install
 run integration bash -c 'set -e; cd "$1"; printf "old\n" > a; printf "new\n" > b; rc=0; diff -u a b > delta || rc=$?; test "$rc" = 1; patch a < delta; cmp a b' _ "$lab"
 files=(/usr/bin/patch);;
 tar-*)
 sha256sum "$base/tar-1.35-acl_fix-1.patch" >> "$log/source.sha256"
 run patch patch -Np1 -i ../tar-1.35-acl_fix-1.patch
 run configure env FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
 run build make -j8
 run check unshare --mount --propagation private --pid --fork --mount-proc --net --uts --kill-child make -j1 check
 run install make install
 run docs make -C doc install-html docdir=/usr/share/doc/tar-1.35
 run integration bash -c 'set -e; cd "$1"; mkdir original restored; printf "Genesis\n" > original/data; setfattr -n user.genesis -v 42 original/data; setfacl -m u:tester:r-- original/data; tar --acls --xattrs -cf test.tar -C original .; tar --acls --xattrs -xf test.tar -C restored; cmp original/data restored/data; test "$(getfattr --only-values -n user.genesis restored/data)" = 42; getfacl -c original/data > a; getfacl -c restored/data > b; cmp a b' _ "$lab"
 files=(/usr/bin/tar);;
 texinfo-*)
 run configure ./configure --prefix=/usr
 run build make -j8
 run check make check
 run install make install
 printf '\\input texinfo\n@setfilename genesis.info\n@node Top\n@top Genesis\nGenesis documentation.\n@bye\n' > "$lab/genesis.texi"
 run integration bash -c 'set -e; cd "$1"; makeinfo genesis.texi; grep -F "Genesis documentation." genesis.info' _ "$lab"
 files=(/usr/bin/info /usr/bin/texi2any /usr/bin/install-info);;
 vim-*)
 echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
 run configure ./configure --prefix=/usr
 run build make -j8
 chown -R tester .
 sed '/test_plugin_glvs/d' -i src/testdir/Make_all.mak
 stage=check; echo "=== $pkg: check (serial; output redirected) ==="
 time su tester -c 'TERM=xterm-256color LANG=en_US.UTF-8 make -j1 test' > "$log/check.log" 2>&1
 grep -E 'FAILED: *0([^0-9]|$)' "$log/check.log"
 run install make install
 ln -sv vim /usr/bin/vi
 shopt -s nullglob
 for L in /usr/share/man/{,*/}man1/vim.1; do ln -sv vim.1 "$(dirname "$L")/vi.1"; done
 ln -sv ../vim/vim92/doc /usr/share/doc/vim-9.2.1025
 if test -e /etc/vimrc; then cp -a /etc/vimrc "$log/vimrc.previous"; fi
 cat > /etc/vimrc <<'VIMRC'
" Begin /etc/vimrc
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1
set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif
" End /etc/vimrc
VIMRC
 run integration bash -c 'set -e; cd "$1"; printf "Genesis\n" > text; vim -Nu NONE -i NONE -n -es text -c "%s/Genesis/AI-Now Linux/" -c wq; grep -Fx "AI-Now Linux" text; xxd text > hex; xxd -r hex restored; cmp text restored; test "$(readlink /usr/bin/vi)" = vim' _ "$lab"
 files=(/usr/bin/vim /usr/bin/vi /usr/bin/xxd /etc/vimrc);;
 markupsafe-*|jinja2-*)
 name=${pkg%-*}; version=${pkg##*-}
 run build pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
 run install pip3 install --no-index --find-links dist "$name"
 run integration python3 - "$name" "$version" <<'PY'
import sys, importlib.metadata as m
from markupsafe import escape
assert m.version(sys.argv[1]) == sys.argv[2]
assert str(escape('<tag>')) == '&lt;tag&gt;'
if sys.argv[1] == 'jinja2':
    from jinja2 import Environment
    assert Environment(autoescape=True).from_string('{{ name }}: {{ 21*2 }}').render(name='<tag>') == '&lt;tag&gt;: 42'
print('PASS')
PY
 # Locate only the distribution's own metadata, not vendored metadata.
 metadata=$(python3 - "$name" "$version" <<'PY'
import sys, importlib.metadata as m
from pathlib import Path
name, version = sys.argv[1:]
d = m.distribution(name)
p = Path(d._path) / 'METADATA'
assert p.is_file() and d.version == version
print(p)
PY
 )
 files=("$metadata")
 regression='No upstream suite executed; local integration only';;
 esac
 stage=records; cd "$src"; mkdir -p "$log/upstream"
 find . -type f \( -name '*.log' -o -name '*.sum' -o -name '*.trs' -o -name config.status \) -exec cp --parents -t "$log/upstream" {} +
 sha256sum "${files[@]}" > "$log/installed.sha256"
 sha256sum -c "$log/installed.sha256"
 printf 'Package: %s\nStatus: BUILD AND INTEGRATION PASSED\nRegression: %s\nCompleted: %s\nSource cleanup: deferred\n' "$pkg" "$regression" "$(date -Iseconds)" > "$log/acceptance.txt.tmp"
 mv "$log/acceptance.txt.tmp" "$log/acceptance.txt"
 echo '[PASS] Integration'
done
 echo '[PASS] Batch 07 completed'
