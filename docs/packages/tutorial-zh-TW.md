# AI-Now Linux 自訂套件 Tutorial

`ainpkg` 套件由 Git 配方、經 SHA256 校驗的來源，以及安裝到 `DESTDIR` 的產物組成。先寫配方，再編成 `.ainpkg`，最後在另一個根目錄驗收安裝。以下指令在 AI-Now Linux repo 根目錄執行。需要 Python 3.12 以上、Bash、Git、tar 與 zstd。

## 1. 用 TUI 開始

```bash
./scripts/ainpkg-tui
```

| 選項 | 用途 |
| --- | --- |
| Create recipe | 建立 `packages/<name>/recipe.toml` 和 `build.sh` |
| Build package | 從指定 Git ref 建置，接受快取來源及多個建置依賴 |
| Inspect package | 校驗套件內容並查看 ABI、版本、Git commit 及檔案清單 |

`script` 範本適合 Shell、Python 等直接安裝的命令列工具。其來源 tarball 需有一個普通檔案 `bin/<套件名>`。`autotools` 範本適合用 `./configure`、`make` 和 `make DESTDIR=… install` 的專案。依上游建置方式調整產物清單。

## 2. 用腳本做一個完全離線的範例

```bash
lab=$(mktemp -d)
mkdir -p "$lab/src/bin"
printf '%s\n' '#!/bin/sh' 'echo "Hello, AI-Now Linux!"' \
  > "$lab/src/bin/hello-ainow"
tar -C "$lab/src" -czf "$lab/hello.tar.gz" bin
pin=$(sha256sum "$lab/hello.tar.gz" | cut -d ' ' -f1)

./scripts/ainpkg-new hello-ainow 1.0 https://example.invalid/hello.tar.gz "$pin"
vim packages/hello-ainow/recipe.toml packages/hello-ainow/build.sh
git add -- packages/hello-ainow
git commit -m 'Add hello-ainow custom recipe'

./scripts/ainpkg build hello-ainow --source "$lab/hello.tar.gz" \
  --output "$lab/hello-ainow.ainpkg"
./scripts/ainpkg inspect "$lab/hello-ainow.ainpkg"
```

範例使用保留網域和 `--source`，所以不會連網。製作正式套件時，把 URL 換成可信的上游 HTTPS 來源並記錄已核對的 SHA256。即使使用本機快取，建置器也會校驗來源。建置讀取已提交的 Git 配方，改完檔案後先提交，才能讓下一次建置使用修改。

### 配方的兩個檔案

- `recipe.toml` 記錄套件名稱、版本、支援的 CPU 基線、來源 URL 和 SHA256。需要其他 `.ainpkg` 參與建置時，填 `build_requires = ["套件名"]`。
- `build.sh` 可讀取 `SOURCE_ARCHIVE`、`DESTDIR`、`JOBS`、`AINPKG_PACKAGE` 和 `AINPKG_DEPS`。用一般帳號執行，產物寫入 `DESTDIR`。目前封裝接受 `usr/`、`etc/`、`opt/` 下的普通檔案。若上游產物包含符號連結、硬連結或 setuid 權限，須在配方明確處理。

## 3. 在臨時目標驗收

```bash
root=$(mktemp -d)
abi=$(getconf GNU_LIBC_VERSION | tr ' ' '-')
./scripts/ainpkg --root "$root" init --arch x86_64 --abi "$abi" --cpu x86-64-v1
./scripts/ainpkg --root "$root" install "$lab/hello-ainow.ainpkg" --dry-run
./scripts/ainpkg --root "$root" install "$lab/hello-ainow.ainpkg"
./scripts/ainpkg --root "$root" owner /usr/bin/hello-ainow
"$root/usr/bin/hello-ainow"
./scripts/ainpkg --root "$root" verify hello-ainow
./scripts/ainpkg --root "$root" remove hello-ainow
```

這個範例的建置 ABI 是目前主機的 glibc 版本。要給 EeePC 用，先在 Genesis 的 glibc 2.44 建置環境編譯，並用該環境驗收。發佈及下載流程見 [ainpkg 操作文件](ainpkg.md)。

## 4. 真實範例 · libnl 和 WPA Supplicant

在具備 GCC、make、flex、bison、pkg-config、OpenSSL 與 D-Bus 開發檔案的相容環境，用一般帳號建置：

```bash
out=$(mktemp -d)
./scripts/ainpkg build libnl --jobs 4 --output "$out/libnl.ainpkg"
./scripts/ainpkg build wpa-supplicant --jobs 4 \
  --build-dependency "$out/libnl.ainpkg" \
  --output "$out/wpa-supplicant.ainpkg"
```

`--build-dependency` 可以重複指定。建置器會檢查封裝內容、架構、glibc 與 CPU 基線，並將檔案放到臨時依賴樹。配方可用 `$AINPKG_DEPS/usr/include` 或套件提供的 pkg-config 資訊編譯。執行時依賴仍需先裝到同一目標。安裝這組套件時先裝 libnl，再裝 WPA Supplicant。D-Bus 與 systemd 設定會隨封裝交付，服務啟用由目標系統管理。

NetworkManager 與 `nmtui` 是後續套件，EeePC 的實際 Wi‑Fi 連線也要在目標上驗收。
