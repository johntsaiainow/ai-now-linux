# Bootstrap Git on Genesis

Git 2.56.1 is built from its pinned upstream release on the target ABI. This bootstrap recipe provides Git's C command-line tools and supports local repositories and file transport. HTTPS transport, Perl tools, localization, and GUI tools are outside this recipe. The bootstrap does not require Rust, libcurl, or a preinstalled Git in Genesis.

## Baihu · stage inputs

Run in a second Baihu terminal while keeping the Genesis serial console open. The HTTP server publishes only the staging directory on loopback.

```bash
cd /home/john/Projects/ai-now-linux
git fetch origin chapter-11-ainpkg
ref=$(git rev-parse FETCH_HEAD)
git cat-file -e "$ref:packages/git/recipe.toml"
stage=$(mktemp -d)
git show "$ref:scripts/ainpkg" > "$stage/ainpkg"
git archive --format=tar "$ref" packages/git > "$stage/git-recipe.tar"
curl -fLSs https://www.kernel.org/pub/software/scm/git/git-2.56.1.tar.xz \
    -o "$stage/git-2.56.1.tar.xz"
printf 'AINPKG_SHA256=%s\n' "$(sha256sum "$stage/ainpkg" | cut -d' ' -f1)"
printf 'RECIPE_SHA256=%s\n' "$(sha256sum "$stage/git-recipe.tar" | cut -d' ' -f1)"
python3 -m http.server 8766 --bind 127.0.0.1 --directory "$stage"
```

## Genesis · build without root privileges

Copy both digest assignments printed by Baihu into the Genesis shell. Then run this block as root. Python downloads the inputs into a fresh temporary directory and launches only the build subprocess as `nobody`. This avoids a dependency on `runuser` or `setpriv`. `ainpkg` verifies the recipe archive against the copied digest and independently verifies the source tarball using the committed recipe pin.

```bash
work=$(mktemp -d)
python3 - "$work" "${RECIPE_SHA256:?copy the digest from Baihu first}" "${AINPKG_SHA256:?copy the CLI digest from Baihu}" <<'PY'
import hashlib
import os
from pathlib import Path
import pwd
import subprocess
import sys
from urllib.request import urlretrieve

work = Path(sys.argv[1])
for name in ("ainpkg", "git-recipe.tar", "git-2.56.1.tar.xz"):
    urlretrieve(f"http://10.0.2.2:8766/{name}", work / name)

with (work / "ainpkg").open("rb") as stream:
    if hashlib.file_digest(stream, "sha256").hexdigest() != sys.argv[3]:
        raise SystemExit("ainpkg SHA256 mismatch")

builder = pwd.getpwnam("nobody")
work.chmod(0o755)
build_output = work / "output"
build_output.mkdir(mode=0o700)
os.chown(build_output, builder.pw_uid, builder.pw_gid)
output = build_output / "git.ainpkg"
subprocess.run(
    [sys.executable, str(work / "ainpkg"), "build", "git",
     "--recipe-archive", str(work / "git-recipe.tar"),
     "--recipe-sha256", sys.argv[2], "--source", str(work / "git-2.56.1.tar.xz"),
     "--output", str(output), "--jobs", "4"],
    cwd=build_output, user=builder.pw_uid, group=builder.pw_gid, extra_groups=(), check=True,
)
PY
```

## Genesis · exercise the managed package

Run against a temporary target directory to validate installation and ownership independently of the boot filesystem.

```bash
root=$(mktemp -d)
python3 "$work/ainpkg" --root "$root" init --arch x86_64 --abi glibc-2.44 --cpu x86-64-v1
python3 "$work/ainpkg" --root "$root" install "$work/output/git.ainpkg" --dry-run
python3 "$work/ainpkg" --root "$root" install "$work/output/git.ainpkg"
python3 "$work/ainpkg" --root "$root" verify git
python3 "$work/ainpkg" --root "$root" owner /usr/bin/git

(
    export PATH="$root/usr/bin:$PATH"
    export GIT_EXEC_PATH="$root/usr/libexec/git-core"
    export GIT_TEMPLATE_DIR="$root/usr/share/git-core/templates"
    git --version
    repo=$(mktemp -d)
    git init "$repo"
    git -C "$repo" -c user.name=Smoke -c user.email=smoke@example.invalid commit --allow-empty -m bootstrap
    git clone "file://$repo" "$repo-clone"
    git -C "$repo-clone" log -1 --oneline
)
```
