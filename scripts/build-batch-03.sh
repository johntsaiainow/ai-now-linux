#!/usr/bin/bash
set -Eeuo pipefail
PKG=preflight
STAGE=preflight
trap 'echo "[FAIL] $PKG / $STAGE / line $LINENO"' ERR
test "$(id -u)" -eq 0
test "$(findmnt -n -o SOURCE /)" = /dev/loop25p2
test "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)"
test "$(gcc -dumpmachine)" = x86_64-pc-linux-gnu
BASE=/sources
JOBS=8
packages=(perl-5.44.0 autoconf-2.73 automake-1.18.1 openssl-4.0.1 elfutils-0.195 libffi-3.8.0 sqlite-autoconf-3530400)
archives=(perl-5.44.0.tar.xz autoconf-2.73.tar.xz automake-1.18.1.tar.xz openssl-4.0.1.tar.gz elfutils-0.195.tar.bz2 libffi-3.8.0.tar.gz sqlite-autoconf-3530400.tar.gz)
for a in "${archives[@]}" sqlite-doc-3530400.zip; do
 test -f "$BASE/$a"; test ! -L "$BASE/$a"
done
stage() {
 STAGE=$1; shift
 echo "=== $PKG / $STAGE ==="; date
 time "$@" > "$LOG/$STAGE.log" 2>&1
 tail -n 12 "$LOG/$STAGE.log"
}
for i in "${!packages[@]}"; do
 PKG=${packages[i]}; SRC=$BASE/$PKG; LOG=$BASE/build-logs/$PKG
 STAGE=prepare
 if test -f "$LOG/acceptance.txt"; then
  sha256sum -c "$LOG/installed.sha256"; continue
 fi
 mkdir -p "$LOG"
 test ! -e "$LOG/started.txt"
 sha256sum "$BASE/${archives[i]}" > "$LOG/source.sha256"
 date -Iseconds > "$LOG/started.txt"
 cd "$BASE"
 if test -e "$SRC"; then
  test -d "$SRC"; test ! -L "$SRC"; test ! -e "$SRC-bootstrap-preserved"
  mv "$SRC" "$SRC-bootstrap-preserved"
 fi
 tar -xf "${archives[i]}"; cd "$SRC"
 regression='command exit 0; detailed review pending'
 case "$PKG" in
 perl-5.44.0)
  export BUILD_ZLIB=False BUILD_BZIP2=0
  stage configure sh Configure -des -D prefix=/usr -D vendorprefix=/usr -D privlib=/usr/lib/perl5/5.44/core_perl -D archlib=/usr/lib/perl5/5.44/core_perl -D sitelib=/usr/lib/perl5/5.44/site_perl -D sitearch=/usr/lib/perl5/5.44/site_perl -D vendorlib=/usr/lib/perl5/5.44/vendor_perl -D vendorarch=/usr/lib/perl5/5.44/vendor_perl -D man1dir=/usr/share/man/man1 -D man3dir=/usr/share/man/man3 -D 'pager=/usr/bin/less -isR' -D useshrplib -D usethreads
  stage build make -j"$JOBS"
  stage check env TEST_JOBS="$JOBS" make test_harness
  stage install make install
  unset BUILD_ZLIB BUILD_BZIP2
  stage integration /usr/bin/perl -MCompress::Zlib -MIO::Compress::Bzip2 -Mthreads -e 'die unless uncompress(compress("Genesis")) eq "Genesis"; die unless threads->create(sub {42})->join == 42; print "PASS\n"'
  files=(/usr/bin/perl)
  ;;
 autoconf-2.73|automake-1.18.1)
  opts=(--prefix=/usr)
  if [[ $PKG == automake-* ]]; then opts+=(--docdir=/usr/share/doc/automake-1.18.1); fi
  stage configure ./configure "${opts[@]}"
  stage build make -j"$JOBS"
  stage check make -j"$JOBS" check
  stage install make install
  mkdir -p "$LOG/integration"; cd "$LOG/integration"
  printf '%s\n' 'AC_INIT([genesis],[0.1])' 'AC_PROG_CC' 'AC_OUTPUT' > configure.ac
  if [[ $PKG == autoconf-* ]]; then
   stage integration bash -ec 'autoconf; ./configure'
   files=(/usr/bin/autoconf /usr/bin/autoheader)
  else
   printf '%s\n' 'AC_INIT([genesis],[0.1])' 'AM_INIT_AUTOMAKE([foreign])' 'AC_PROG_CC' 'AC_CONFIG_FILES([Makefile])' 'AC_OUTPUT' > configure.ac
   printf '%s\n' 'bin_PROGRAMS = genesis' 'genesis_SOURCES = main.c' > Makefile.am
   printf '%s\n' 'int main(void) { return 0; }' > main.c
   stage integration bash -ec 'autoreconf -fi; ./configure; make; ./genesis'
   files=(/usr/bin/automake /usr/bin/aclocal)
  fi
  ;;
 openssl-4.0.1)
  stage configure ./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
  stage build make -j"$JOBS"
  stage check make -j"$JOBS" test
  stage install make INSTALL_LIBS= MANSUFFIX=ssl install
  mv -v /usr/share/doc/openssl /usr/share/doc/openssl-4.0.1
  cp -vfr doc/* /usr/share/doc/openssl-4.0.1
  stage integration bash -ec 'openssl version; test "$(printf abc | openssl dgst -sha256 | awk "{print \$NF}")" = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad; openssl list -providers'
  files=(/usr/bin/openssl /usr/lib/libssl.so /usr/lib/libcrypto.so)
  ;;
 elfutils-0.195)
  stage configure ./configure --prefix=/usr --disable-debuginfod --enable-libdebuginfod=dummy
  stage build bash -ec 'make -j8 -C lib; make -j8 -C libelf'
  stage check make -j"$JOBS" -k check
  stage install make -C libelf install
  install -vm644 config/libelf.pc /usr/lib/pkgconfig
  rm /usr/lib/libelf.a
  mkdir -p "$LOG/integration"; cd "$LOG/integration"
  cat > main.c <<'C'
#include <libelf.h>
#include <fcntl.h>
#include <unistd.h>
int main(void) {
 if (elf_version(EV_CURRENT)==EV_NONE) return 1;
 int fd=open("/usr/bin/bash",O_RDONLY); if(fd<0) return 2;
 Elf *e=elf_begin(fd,ELF_C_READ,0);
 int ok=e && elf_kind(e)==ELF_K_ELF;
 if(e) elf_end(e);
 close(fd); return !ok;
}
C
  stage integration bash -ec 'gcc main.c -lelf -o genesis; ./genesis'
  files=(/usr/lib/libelf.so /usr/lib/pkgconfig/libelf.pc)
  ;;
 libffi-3.8.0)
  stage configure ./configure --prefix=/usr --disable-static --with-gcc-arch=native
  stage build make -j"$JOBS"
  stage check make -j"$JOBS" check
  stage install make install
  mkdir -p "$LOG/integration"; cd "$LOG/integration"
  cat > main.c <<'C'
#include <ffi.h>
static int twice(int n) { return n*2; }
int main(void) {
 ffi_cif cif; ffi_type *types[]={&ffi_type_sint};
 int n=21; void *args[]={&n}; ffi_arg result=0;
 if(ffi_prep_cif(&cif,FFI_DEFAULT_ABI,1,&ffi_type_sint,types)!=FFI_OK) return 1;
 ffi_call(&cif,FFI_FN(twice),&result,args); return result!=42;
}
C
  stage integration bash -ec 'gcc main.c -lffi -o genesis; ./genesis'
  files=(/usr/lib/libffi.so)
  ;;
 sqlite-autoconf-3530400)
  python3 -m zipfile -e ../sqlite-doc-3530400.zip .
  stage configure ./configure --prefix=/usr --disable-static --enable-fts{4,5} 'CPPFLAGS=-D SQLITE_ENABLE_COLUMN_METADATA=1 -D SQLITE_ENABLE_UNLOCK_NOTIFY=1 -D SQLITE_ENABLE_DBSTAT_VTAB=1 -D SQLITE_SECURE_DELETE=1'
  stage build make -j"$JOBS" LDFLAGS.rpath=""
  stage install make install
  cp -v -R sqlite-doc-3530400 -T /usr/share/doc/sqlite-3.53.4
  mkdir -p "$LOG/integration"; cd "$LOG/integration"
  stage integration bash -ec 'sqlite3 -bail genesis.db "CREATE TABLE memory(value INTEGER); INSERT INTO memory VALUES(42); CREATE VIRTUAL TABLE search USING fts5(text); INSERT INTO search VALUES('\''Genesis'\'');"; test "$(sqlite3 -bail genesis.db "SELECT value FROM memory;")" = 42; test "$(sqlite3 -bail genesis.db "SELECT count(*) FROM search WHERE search MATCH '\''Genesis'\'';")" = 1; test "$(sqlite3 -bail genesis.db "PRAGMA integrity_check;")" = ok'
  regression='not run; no regression command in supplied LFS instructions'
  files=(/usr/bin/sqlite3 /usr/lib/libsqlite3.so)
  ;;
 esac
 STAGE=records
 cd "$SRC"; mkdir -p "$LOG/upstream"
 find . -type f \( -name '*.log' -o -name '*.sum' -o -name '*.trs' -o -name config.status -o -name config.h \) -exec cp --parents -t "$LOG/upstream" {} +
 grep -in 'warning:' "$LOG/build.log" > "$LOG/warnings.log" || { rc=$?; test "$rc" -eq 1; }
 sha256sum "${files[@]}" > "$LOG/installed.sha256"
 sha256sum -c "$LOG/installed.sha256"
 printf 'Package: %s\nStatus: BUILD AND INTEGRATION PASSED\nRegression: %s\nCompleted: %s\nSource cleanup: deferred\n' "$PKG" "$regression" "$(date -Iseconds)" > "$LOG/acceptance.txt.tmp"
 mv "$LOG/acceptance.txt.tmp" "$LOG/acceptance.txt"
 echo "[PASS] $PKG"
done
echo '[DONE] Batch 03'
