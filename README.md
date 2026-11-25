# AI-Now Linux

**One Core. Multiple Profiles. Built from Source.**

AI-Now Linux is an independent Linux distribution project developed by AI-Now Technology, Inc., designed for personal computing, enterprise infrastructure, embedded systems, and dedicated AI appliances.

Built upon Linux From Scratch (LFS), the project aims to establish a transparent, customizable, maintainable, and reproducible operating system platform.

## Project Objectives

- Build an independent Linux system from source.
- Develop a modular, profile-driven build system.
- Integrate custom C, C++, and Python system utilities.
- Support artificial intelligence and autonomous agent applications.
- Explore Linux kernel customization and operating system engineering.
- Provide a foundation for specialized commercial computing products.

## Planned Build Profiles

```bash
./build.sh --profile personal
./build.sh --profile enterprise
./build.sh --profile embedded
./build.sh --profile ai-appliance
```

| Profile | Target Environment |
|---|---|
| Personal | Workstations and software development |
| Enterprise | Servers and enterprise infrastructure |
| Embedded | Embedded devices and industrial systems |
| AI Appliance | Dedicated AI computing platforms |

All profiles are intended to share a common operating system foundation while maintaining independent package selections, kernel configurations, and system services.

## Technical Foundation

- Linux From Scratch 13.1-systemd
- Linux Kernel
- GNU Toolchain
- GNU C Library
- Systemd
- GRUB
- C / C++ / Python
- QEMU / KVM

## Development Status

**Target Release: v0.1.0 — Genesis**

Early development stage. The initial objective is a bootable, self-contained command-line Linux system.

- [x] Host system qualification
- [x] Virtual disk preparation
- [x] Source acquisition and verification
- [ ] Build environment preparation
- [ ] Cross-toolchain bootstrap
- [ ] Base system compilation
- [ ] Kernel configuration and compilation
- [ ] First system boot
- [ ] Automated build engine
- [ ] Profile-based distribution builds

## Engineering Documentation

Development journals, architectural decisions, build procedures, and verification results will be maintained in the `docs/` directory.

## Maintainer

AI-Now Technology, Inc.
California, United States

## License

Project licensing is under consideration. Upstream components retain their respective licenses.

---

*From source code to independent systems.*
