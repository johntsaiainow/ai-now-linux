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
mkdir -p "$records"
export PIP_NO_INDEX=1 PIP_DISABLE_PIP_VERSION_CHECK=1
export MAKEFLAGS=-j8
packages=(mpdecimal-4.0.1 Python-3.14.7 flit_core-4.0.2 packaging-26.3 wheel-0.48.0 setuptools-84.0.0 meson-1.12.0)
archives=(mpdecimal-4.0.1.tar.gz Python-3.14.7.tar.xz flit_core-4.0.2.tar.gz packaging-26.3.tar.gz wheel-0.48.0.tar.gz setuptools-84.0.0.tar.gz meson-1.12.0.tar.gz)
for a in "${archives[@]}" Python-3.14.7-openssl_4-1.patch python-3.14.7-docs-html.tar.bz2; do test -f "$base/$a"; done
run(){ stage=$1; shift; echo "=== $pkg / $stage ==="; time "$@" > "$log/$stage.log" 2>&1; tail -n 12 "$log/$stage.log"; }
for i in "${!packages[@]}"; do
 pkg=${packages[i]}; stage=prepare; log=$records/$pkg; src=$base/$pkg; archive=$base/${archives[i]}; mkdir -p "$log"
 if test -f "$log/acceptance.txt"; then sha256sum -c "$log/installed.sha256"; echo "[SKIP] $pkg"; continue; fi
 test ! -e "$log/started.txt"
 sha256sum "$archive" > "$log/source.sha256"
 date -Iseconds > "$log/started.txt"
 cd "$base"
 if test -e "$src"; then test -d "$src"; test ! -L "$src"; test ! -e "$src-bootstrap-preserved"; mv "$src" "$src-bootstrap-preserved"; fi
 tar -xf "$archive"; cd "$src"
 regression='not specified in supplied LFS commands'
 case "$pkg" in
 mpdecimal-*)
 run configure ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/mpdecimal-4.0.1
 run build make -j8
 run check make check_local
 regression='command exit 0; review log'
 run install make install
 mkdir -p "$log/integration"
 cat > "$log/integration/test.c" <<'C'
#include <mpdecimal.h>
int main(void) { return mpd_version()[0] == '4' ? 0 : 1; }
C
 run integration bash -c 'gcc "$1/integration/test.c" -lmpdec -o "$1/integration/test" && "$1/integration/test"' _ "$log"
 files=(/usr/lib/libmpdec.so)
 ;;
 Python-*)
 sha256sum "$base/Python-3.14.7-openssl_4-1.patch" "$base/python-3.14.7-docs-html.tar.bz2" >> "$log/source.sha256"
 run patch patch -Np1 -i ../Python-3.14.7-openssl_4-1.patch
 run configure ./configure --prefix=/usr --enable-shared --with-system-expat --enable-optimizations --without-static-libpython
 run build make -j8
 run check make test TESTOPTS='--timeout 120 -j8'
 regression='command exit 0; review log'
 run install make install
 if test -e /etc/pip.conf; then cp -p /etc/pip.conf "$log/pip.conf.before"; fi
 printf '[global]\nroot-user-action = ignore\ndisable-pip-version-check = true\n' > /etc/pip.conf
 install -dm755 /usr/share/doc/python-3.14.7/html
 run docs tar --strip-components=1 --no-same-owner --no-same-permissions -C /usr/share/doc/python-3.14.7/html -xvf ../python-3.14.7-docs-html.tar.bz2
 mkdir -p "$log/integration"
 cat > "$log/integration/test.py" <<'PY'
import sys, ssl, hashlib, sqlite3, ctypes, decimal, bz2, lzma, zlib, readline, curses, venv, tempfile, subprocess, pathlib, _decimal
assert sys.version_info[:3] == (3,14,7)
assert ssl.OPENSSL_VERSION.startswith('OpenSSL 4.')
assert hashlib.sha256(b'abc').hexdigest() == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
for m in (bz2,lzma,zlib):
    assert m.decompress(m.compress(b'Genesis')) == b'Genesis'
assert decimal.Decimal('0.1') + decimal.Decimal('0.2') == decimal.Decimal('0.3')
with sqlite3.connect(':memory:') as db:
    assert db.execute('select 21*2').fetchone() == (42,)
assert ctypes.CDLL(None).abs(-42) == 42
with tempfile.TemporaryDirectory() as d:
    venv.EnvBuilder(with_pip=True).create(d)
    subprocess.run([str(pathlib.Path(d)/'bin/python'), '-m', 'pip', '--version'], check=True)
print(sys.version, ssl.OPENSSL_VERSION, sqlite3.sqlite_version, _decimal.__libmpdec_version__)
print('PASS: Python runtime modules and venv')
PY
 run integration /usr/bin/python3 "$log/integration/test.py"
 files=(/usr/bin/python3 /usr/bin/pip3 /usr/lib/libpython3.14.so)
 ;;
 *)
 module=${pkg%-*}
 run build /usr/bin/pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
 run install /usr/bin/pip3 install --no-index --find-links dist "$module"
 version=${pkg##*-}
 run integration /usr/bin/python3 -c 'import importlib.metadata as m,sys; assert m.version(sys.argv[1]) == sys.argv[2]; print(sys.argv[1],m.version(sys.argv[1]))' "$module" "$version"
 mapfile -t files < <(/usr/bin/python3 -c 'import importlib.metadata as m,sys; d=m.distribution(sys.argv[1]); print(d.locate_file(next(p for p in d.files if str(p).endswith(".dist-info/METADATA"))))' "$module")
 test "${#files[@]}" -eq 1
 if test "$module" = meson; then
 install -vDm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
 install -vDm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
 mkdir -p "$log/integration"
 printf "project('genesis', 'c')\nexecutable('genesis', 'main.c')\n" > "$log/integration/meson.build"
 printf 'int main(void){return 0;}\n' > "$log/integration/main.c"
 run meson-setup meson setup "$log/integration/build" "$log/integration"
 run meson-build meson compile -C "$log/integration/build"
 run meson-test "$log/integration/build/genesis"
 files+=(/usr/bin/meson)
 fi
 ;;
 esac
 stage=records
 cd "$src"; mkdir -p "$log/upstream"
 find . -type f \( -name '*.log' -o -name '*.sum' -o -name '*.trs' -o -name config.status \) -exec cp --parents -t "$log/upstream" {} +
 sha256sum "${files[@]}" > "$log/installed.sha256"
 sha256sum -c "$log/installed.sha256"
 printf 'Package: %s\nStatus: BUILD AND INTEGRATION PASSED\nRegression: %s\nCompleted: %s\nSource cleanup: deferred\n' "$pkg" "$regression" "$(date -Iseconds)" > "$log/acceptance.txt.tmp"
 mv "$log/acceptance.txt.tmp" "$log/acceptance.txt"
 echo "[PASS] $pkg"
done
echo '[DONE] Batch 04: 7 packages'
