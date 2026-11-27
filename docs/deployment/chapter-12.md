# Chapter 12 · Installer and x86 hardware profiles

Chapter 11 acceptance is the starting point. Chapter 12 first produces a file-based installation rehearsal, then rescue media, and then an independently booting EeePC. The original Genesis image and the existing EeePC installation are preserved throughout the rehearsal.

## Kernel targets

| Target | Initial kernel architecture | Required acceptance |
|---|---|---|
| `eeepc-1005p` | x86-64 candidate | Inventory CPU flags and PCI devices, choose the final architecture, and validate storage, console, input and network on the actual machine |
| `genericx86` | i386 Kbuild target, i686-class 32-bit x86 kernel | Boot a supported 32-bit CPU model with a separately built 32-bit userspace and run the basic tool tests |
| `genericamd64` | x86-64 kernel for AMD and Intel CPUs | Boot a baseline x86-64 test VM and run the basic tool tests with a matching x86-64 userspace |

The shared fragment enables boot storage and serial console support. The EeePC candidate adds the AT keyboard path; NIC, graphics, firmware and CPU tuning depend on the hardware inventory. A 32-bit kernel cannot use the existing 64-bit Genesis root filesystem. Package and rootfs compatibility must be validated for each target.

Use the Linux 7.1.8 source tarball and the checked-in SHA256 in `kernel/linux-7.1.8.sha256`. With the verified source unpacked and the kernel build toolchain available on Baihu:

```bash
scripts/build-kernel-profile.sh eeepc-1005p /path/to/linux-7.1.8 /path/to/new-eeepc-build --config-only
scripts/build-kernel-profile.sh genericx86 /path/to/linux-7.1.8 /path/to/new-x86-build --config-only
scripts/build-kernel-profile.sh genericamd64 /path/to/linux-7.1.8 /path/to/new-amd64-build --config-only
```

Omit `--config-only` and use a new output directory to build `bzImage` and modules. Set `JOBS` to control parallelism. The script uses the upstream defconfig, overlays the checked-in fragments, runs `olddefconfig`, and fails if a requested setting did not resolve. It does not install the kernel on the build host.

All three Linux 7.1.8 candidates compiled through `bzImage modules` and executed a minimal native init in QEMU TCG (`qemu32` for the i686-class profile and `qemu64` for the 64-bit profiles). These checks validate kernel boot and architecture. EeePC Ethernet, Wi-Fi and audio depend on physical PCI and codec identification and separate device tests.

## Build EeePC images from Genesis

Run on Baihu after shutting down any VM using the Genesis RAW. On Ubuntu, install `grub-pc-bin` for the BIOS modules. The builders check for them before copying the rootfs. Download the verified EeePC candidate kernel bundle. Use a new output directory:

```bash
sudo unshare --mount --propagation private scripts/build-eeepc-rescue.sh \
  /home/john/Projects/ai-now-linux/images/ai-now-linux.raw \
  "$HOME/Downloads/ainow-7.1.8-ainow-eeepc-1005p-kernel.tar.zst" \
  "$HOME/eeepc-media"
```

The wrapper pins the kernel bundle digest, opens Genesis partition 2 through a read-only loop, and mounts ext4 with journal replay disabled. It measures the rootfs, checks workspace capacity, stages the candidate kernel modules and writes a fresh deployment image and a separate rescue image containing that payload. The output directory contains `eeepc-deploy.img`, `eeepc-rescue.img` and `SHA256SUMS`. The source filesystem contents are copied into the new images, so keep them local unless the rootfs has been prepared for distribution. The EeePC physical boot and device support still require hardware acceptance.

## Install from rescue media

`scripts/ainstall` is a Python terminal installer that writes a prepared, offline BIOS/MBR disk image. The initial payload layout is one active Linux partition starting at an aligned offset. A separate rescue USB will carry the installer, the target image and release checksums. This layout keeps the first installer independent of GPT relocation and filesystem resizing. The existing Genesis GPT RAW is not a compatible payload.

The builder creates a BIOS image from a prepared root tree and kernel. Run it on Baihu inside a private mount namespace. The source trees should be sealed snapshots prepared for deployment and rescue, and include the matching kernel modules. The rescue tree must include Python, the disk utilities and an administrator login. Assign sizes after measuring the trees and payload.

```bash
sudo unshare --mount --propagation private scripts/build-bios-image.sh \
  "$deploy_rootfs" "$kernel" "$deploy_mib" "$deploy_image"
sudo unshare --mount --propagation private scripts/build-bios-image.sh \
  "$rescue_rootfs" "$kernel" "$rescue_mib" "$rescue_image" "$deploy_image" "$deploy_sha256"
```

The optional arguments embed `ainstall`, the deployment image, and its SHA256 under `/opt/ainow-install` or `/usr/local/sbin`. The builder only partitions a newly created loop image and refuses existing output files. It generates a fresh ext4 UUID, `fstab` and BIOS GRUB configuration. GRUB searches by filesystem UUID and passes the MBR PARTUUID to the kernel for direct root mount. If the staged tree provides `/boot/initrd.img`, GRUB loads it. The builder, interactive block-device write, and an independent boot from the installed virtual disk passed in QEMU using a BusyBox fixture. The final installed-disk boot used the AI-Now EeePC candidate kernel and mounted ext4 directly, without an initramfs. Building and booting the actual AI-Now rescue and deployment images still requires the prepared Genesis rootfs on Baihu. The target image must contain an already tested bootloader, kernel, root filesystem and consistent boot references. The rescue and target filesystems must have different identifiers. Large destination disks will have unallocated space after the copied layout. Image deployment replaces the disk layout and is not a secure erase.

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
