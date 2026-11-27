# Chapter 12 · Installer and x86 hardware profiles

Chapter 11 acceptance is the starting point. Chapter 12 first produces a file-based installation rehearsal, then rescue media, and then an independently booting EeePC. The original Genesis image and the existing EeePC installation are preserved throughout the rehearsal.

## Kernel targets

| Target | Initial kernel architecture | Required acceptance |
|---|---|---|
| `eeepc-1005p` | x86-64 candidate | Inventory CPU flags and PCI devices; choose the final architecture; validate storage, console, input and network on the actual machine |
| `genericx86` | i386 Kbuild target, 32-bit x86 kernel | Boot a supported 32-bit CPU model with a separately built 32-bit userspace and run the basic tool tests |
| `genericamd64` | x86-64 kernel for AMD and Intel CPUs | Boot a baseline x86-64 test VM and run the basic tool tests with a matching x86-64 userspace |

The shared fragment enables boot storage and serial console support. The EeePC candidate adds the AT keyboard path; NIC, graphics, firmware and CPU tuning depend on the hardware inventory. A 32-bit kernel cannot use the existing 64-bit Genesis root filesystem. Package and rootfs compatibility must be validated for each target.

With unpacked, verified Linux sources and the kernel build toolchain on Baihu:

```bash
scripts/build-kernel-profile.sh eeepc-1005p /path/to/linux-7.1.8 /path/to/new-eeepc-build --config-only
scripts/build-kernel-profile.sh genericx86 /path/to/linux-7.1.8 /path/to/new-x86-build --config-only
scripts/build-kernel-profile.sh genericamd64 /path/to/linux-7.1.8 /path/to/new-amd64-build --config-only
```

Omit `--config-only` and use a new output directory to build `bzImage` and modules. Set `JOBS` to control parallelism. The script uses the upstream defconfig, overlays the checked-in fragments, runs `olddefconfig`, and fails if a requested setting did not resolve. It does not install the kernel on the build host.

## Install from rescue media

`scripts/ainstall` is a Python terminal installer that writes a prepared, offline BIOS/MBR disk image. The initial payload layout is one active Linux partition starting at an aligned offset. A separate rescue USB will carry the installer, the target image and release checksums. This layout keeps the first installer independent of GPT relocation and filesystem resizing. The existing Genesis GPT RAW is not a compatible payload.

The builder for the bootable payload and rescue USB is a separate pending deliverable. The target image must contain an already tested bootloader, kernel, root filesystem and consistent boot references. The rescue and target filesystems must have different identifiers. Large destination disks will have unallocated space after the copied layout. Image deployment replaces the disk layout and is not a secure erase.

For file-based rehearsal, run the following with a trusted release digest:

```bash
scripts/ainstall --image ./eeepc-deploy.img --sha256 "$expected_sha256" --output ./test-disk.img
scripts/ainstall --image ./eeepc-deploy.img --sha256 "$expected_sha256" --output ./test-disk.img --apply
```

The first command verifies the input and previews the operation. The second publishes a new, verified destination file. The installer refuses an existing file. Reboot that output image in QEMU before preparing any USB media.

Whole-disk installation uses `--disk` with a `/dev/disk/by-id/` identifier and starts with a write-free preview. The Linux exclusive open rejects a device already claimed by an active mount, swap or a similar kernel user. The installer also checks disk type, sector size, capacity and device identity. Applying to a disk additionally requires `--apply` and typing the exact identifier in the interactive confirmation. It flushes and rereads the written image range to verify its SHA256. There is no automatic resize or rollback after a disk write starts.

Before running the real disk path, boot the rescue USB on the EeePC, verify the target disk model and capacity, and check the readability of any Yocto data that must be kept. After installation, remove the USB and verify that the internal disk boots independently. Capture the boot and package tests in the journal.

## Tests

```bash
python3 -m unittest discover -s tests -v
bash -n scripts/build-kernel-profile.sh
```

Installer tests use small synthetic images and exercise previews, exact copy, input validation, rejection of existing paths and interactive disk confirmation. These tests do not boot a system or access a physical drive.
