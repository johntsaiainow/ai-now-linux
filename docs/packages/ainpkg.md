# Chapter 11 · Hybrid source/binary packages

`scripts/ainpkg` runs with Python 3.12 or newer and the `zstd` CLI. Source builds also require Git, Bash and the recipe toolchain. GitHub release transfers require `gh` and appropriate GitHub access.

## Build from a Git recipe

Clone or fetch the recipe repository and choose a reviewed commit. If using a branch or tag, resolve it to a commit before recording or distributing a build.

```bash
ref=$(git rev-parse HEAD)
scripts/ainpkg build openssh --repo . --ref "$ref" \
    --jobs 4 --output "$PWD/openssh.ainpkg"
```

The builder reads `packages/openssh/{recipe.toml,build.sh}` from the committed Git tree, verifies the upstream archive against the recipe SHA256 and invokes Bash as an unprivileged user with a private workspace and `DESTDIR`. Pass `--source /path/to/upstream.tar.gz` for a cached archive with the same required digest. Build on the intended native ABI with the declared CPU baseline. Build scripts execute as the invoking user and must come from reviewed commits. Use a disposable VM or equivalent isolation for that build user. The builder does not mount, enter or receive the target root.

The package format is zstd-compressed tar with a JSON manifest and sorted regular-file payloads under `usr/`, `etc/` or `opt/`. Package entries have normalized archive ownership and timestamps. Packages record the recipe commit, versions, compatibility tuple, file modes and SHA256 checksums. The installer checks exact Linux machine architecture, glibc version label and CPU baseline labels. The operator establishes the offline root's identity and separately checks its runtime libraries and actual CPU support. Dependency resolution, ELF validation and managed links are outside this milestone.

## Install on a disposable offline root

The following example is for the x86-64/glibc 2.41 validation build. A Genesis build must run against its own glibc 2.44 toolchain and be initialized with the corresponding tuple.

```bash
root=$(mktemp -d)
scripts/ainpkg --root "$root" init --arch x86_64 --abi glibc-2.41 --cpu x86-64-v1
scripts/ainpkg --root "$root" install ./openssh.ainpkg
scripts/ainpkg --root "$root" list
scripts/ainpkg --root "$root" owner /usr/bin/ssh
scripts/ainpkg --root "$root" verify openssh
scripts/ainpkg --root "$root" remove openssh
```

Source output and downloaded assets use the same `install` command and the SQLite database at `/var/lib/ainpkg/state.sqlite` inside the target. Install preflights ownership and file conflicts before writing and replaces files atomically. An exclusive lock serializes package operations. A committed SQLite undo table records previous bytes and modes before changes. The next command replays it if an earlier command died before the database commit. Use a trusted, exclusively controlled offline root and stable mount layout. Recovery covers package file bytes and modes. File ownership follows the installer account and directory inheritance. ACLs, extended attributes, directory cleanup and power-cut validation are outside this milestone. Existing symlinked paths and special files are rejected.

Files under `/etc` are treated as configuration. Existing unmanaged or locally modified configurations are preserved on install or upgrade, and their path is printed. An unmodified packaged configuration receives the new default. For a preserved config, review the new default inside the package and merge explicitly. Verify reports local config changes as informational and exits nonzero for missing files or modified non-config files. Removal keeps locally modified files and releases their database ownership.

OpenSSH uses the upstream `install-nokeys` target. The recipe installs the client, daemon, helpers, configuration, manual pages and license. It disables PAM integration and stages `ssh-keysign` without setuid. Runtime deployment requires compatible OpenSSL 3 and zlib, an `sshd` privilege-separation account and an administrator-prepared, root-owned `/var/empty/sshd`. Provision host keys independently in each target, validate with `sshd -t`, then enable a service after target-side testing. The package does not include keys or a service unit.

## Transfer an existing release asset

```bash
scripts/ainpkg upload johntsaiainow/ai-now-linux RELEASE_TAG ./openssh.ainpkg
scripts/ainpkg download johntsaiainow/ai-now-linux RELEASE_TAG ./openssh.ainpkg \
    --sha256 "$trusted_sha256"
```

Create the release separately under the approved distribution policy and record the filesystem compatibility tuple alongside the digest. Upload fails on duplicate assets and prints the SHA256. Distribute that SHA256 through a trusted channel. Download verifies the digest and package structure before creating the requested local file. Asset transfer does not install packages. Package signing and authenticated metadata beyond GitHub access plus an independently trusted checksum remain future work.

## Automated tests

```bash
python3 -m unittest discover -s tests -v
bash -n packages/openssh/build.sh
```

The test suite uses disposable target roots and a stub `gh` process. It does not deploy OpenSSH or publish a release.
