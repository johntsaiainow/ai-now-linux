# Chapter 11 · Hybrid source/binary packages

`scripts/ainpkg` runs with Python 3.12 or newer and the `zstd` CLI. Source builds also require Bash and the recipe toolchain. Use Git or a verified Git recipe export. GitHub release transfers require `gh` and appropriate GitHub access.

## Build from a Git recipe

Clone or fetch the recipe repository and choose a reviewed commit. If using a branch or tag, resolve it to a commit before recording or distributing a build.

```bash
ref=$(git rev-parse HEAD)
scripts/ainpkg build openssh --repo . --ref "$ref" \
    --jobs 4 --output "$PWD/openssh.ainpkg"
```

The builder reads `packages/openssh/{recipe.toml,build.sh}` from the committed Git tree, verifies the upstream archive against the recipe SHA256 and invokes Bash as an unprivileged user with a private workspace and `DESTDIR`. Pass `--source /path/to/upstream.tar.gz` for a cached archive with the same required digest. Build on the intended native ABI with the declared CPU baseline. Build scripts execute as the invoking user and must come from reviewed commits. Use a disposable VM or equivalent isolation for that build user. The builder does not mount, enter or receive the target root.

The package format is zstd-compressed tar with a JSON manifest and sorted regular-file payloads under `usr/`, `etc/` or `opt/`. Package entries have normalized archive ownership and timestamps. Packages record the recipe commit, versions, compatibility tuple, file modes and SHA256 checksums. The installer checks exact Linux machine architecture, glibc version label and CPU baseline labels. The operator establishes the offline root's identity and separately checks its runtime libraries and actual CPU support. Dependency resolution, ELF validation and managed links are outside this milestone.

For a Genesis guest without Git, follow the [Git bootstrap procedure](git-bootstrap.md).

## Inspect a package and preview changes

```bash
scripts/ainpkg inspect ./openssh.ainpkg
scripts/ainpkg --root "$root" install ./openssh.ainpkg --dry-run
scripts/ainpkg --root "$root" remove openssh --dry-run
```

`inspect` validates the archive and prints its manifest as JSON without opening a target. Install and removal previews use the same preflight checks as their write operations. They show which files would be added, replaced, removed or preserved. Preview opens the package database read-only and stops if an interrupted transaction needs recovery. In that case, run `verify` to recover and check the target before previewing again. Install rechecks the plan when applying it. Reinstalling an identical file keeps its existing inode.

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

## OpenSSH client and server

Both packages use the same pinned upstream source and stage via `install-nokeys`.

```bash
scripts/ainpkg build openssh --ref "$ref" --output ./openssh.ainpkg
scripts/ainpkg build openssh --ref "$ref" --package openssh-server \
    --output ./openssh-server.ainpkg
```

`openssh` owns the client tools and configuration. `openssh-server` owns the daemon, server helpers and configuration, the systemd service, and the sysusers and tmpfiles fragments. The server includes a private key generation helper, so the client package is optional. Neither package distributes a host key. PAM is disabled and the client's `ssh-keysign` is staged without setuid. Build on the target ABI with OpenSSL and zlib available. Runtime requires the matching OpenSSL and zlib libraries from the target build environment.

When upgrading from a managed combined `openssh` package, preview and install the new client package first so it releases the old daemon paths, then install `openssh-server`. The installer preserves edited server configuration during that transition.

Systemd targets with sysusers and tmpfiles apply the packaged provisioning rules at boot. Genesis has sysusers disabled. The service runs its packaged `prepare-server` helper before generating keys. The helper uses Shadow's `useradd` when the local `sshd` account is absent and ensures that `/var/empty/sshd` is root-owned with mode 0755. To provision an existing offline target with a populated account database, run the helper explicitly:

```bash
"$root/usr/libexec/openssh/prepare-server" --root "$root"
```

The service is opt-in. Review the target's authentication settings and intended listeners before starting it. On first start, the unit generates missing host keys and validates the configuration before running the daemon. Removing the package leaves generated host keys and the system account in place. Stop the service before package removal.

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
