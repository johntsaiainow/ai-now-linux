# AI-Now Linux

**Built from Source. Engineered for Intelligence.**

*One Core. Multiple Targets. One Engineering Ecosystem.*

AI-Now Linux is an internal operating-system engineering platform developed by AI-Now Technology, Inc. It provides a source-built foundation for company workstations, AI infrastructure and embedded systems. It is not intended to compete with general-purpose public Linux distributions.

## Current milestone — v0.1 Genesis

On November 26, 2026, Genesis booted independently in QEMU/KVM using its own Linux kernel, GRUB bootloader and native userspace. systemd reached multi-user.target with zero failed units; DHCP, gateway connectivity, native C compilation, Python execution and clean shutdown were demonstrated. A complete 80 GiB disk image was archived and verified by SHA256 against its decompressed contents.

| Component | Version |
|---|---|
| Linux | 7.1.8-ainow-genesis |
| GCC | 16.2.0 |
| Binutils | 2.47 |
| Glibc | 2.44 |
| systemd | 261.2 |
| Python | 3.14.7 |
| GRUB | 2.14 |
| Bash | 5.3 |

Genesis is an engineering baseline, not a production-ready release. Physical hardware compatibility and restored-image boot testing remain pending.

## Design principles

- Source-first engineering with the option to install compatible binary packages.
- One package installation engine and database for both source and binary workflows.
- Git-managed recipes, patches and hardware configuration; authenticated binary distribution through release assets or an internal repository.
- Hardware-specific kernels and firmware for company-owned devices rather than universal hardware coverage.
- Terminal-native administration with optional graphical environments for engineering and creative work.
- Reproducible build inputs, recorded tests, integrity verification and recoverable checkpoints.

## Target architecture

| Target | Intended role | Status |
|---|---|---|
| Genesis / QEMU | Development and recovery baseline | Boot demonstrated |
| EeePC 1005P | First physical prototype | Next target |
| Baihu | Engineering workstation and build host | Host in use; target OS planned |
| Neris-A / Neris-D | Local AI and GPU compute | Planned |
| Raspberry Pi / AION | Embedded devices | Future integration |
| FPGA / Zynq | Industrial and heterogeneous computing | Future integration |

Hardware targets and software profiles are separate. Compatible binaries may be shared; architecture, CPU instruction set and ABI must be validated before deployment.

## Roadmap

| Stage | Deliverable | Status |
|---|---|---|
| Genesis | Native toolchain, userspace, kernel, independent boot | Demonstrated |
| Checkpoint 003 | Full bootable disk archive | Verified contents |
| Package infrastructure | Chapter 11 staged build, install/remove/verify, Git recipes and GitHub asset transfer | Genesis and draft Release round-trip accepted |
| OpenSSH | Managed client and server packages | Genesis loopback SSH accepted; persistent service deployment pending |
| EeePC | Hardware inventory, dedicated kernel, removable-media boot | Planned |
| Deployment | ISO/USB builder, installer and recovery | Planned |
| Graphics | DRM/KMS, graphics stack and desktop | Planned |
| AI and embedded | GPU runtime, agents, Yocto/PetaLinux integration | Planned |

[Chapter 11 · ainpkg](docs/packages/ainpkg.md) documents the CLI, format, target-root workflow and test commands. Source builds and compatible binaries share one SQLite package database. The terminal menu remains planned.

## Chapter 12

[Installer and x86 hardware profiles](docs/deployment/chapter-12.md) covers file-based installation rehearsal and the EeePC, genericx86 and genericamd64 kernel targets. Rescue media and physical acceptance are pending.

## Engineering records

- [Day 01 — Foundation](docs/journal/2026-11-24.md)
- [Day 02 — Bootstrap](docs/journal/2026-11-25.md)
- [Day 03 — The Birth of Genesis and Chapter 11](docs/journal/2026-11-26.md)

The project builds on Linux From Scratch (13.1-systemd) and upstream free/open-source software. Individual upstream components retain their respective licenses. Project-specific licensing remains to be finalized. Internal use does not remove applicable license obligations.

Disk images, private keys, credentials and machine-specific backups must not be committed to Git. Engineering records distinguish demonstrated results from planned features and conditional test acceptance.

**AI-Now Technology, Inc.**  
*From Silicon to Intelligence.*
