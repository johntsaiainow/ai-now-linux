# Genesis X11 offline build

This bundle builds the X11 package set on x86_64 Genesis with glibc 2.44 and
the x86-64-v1 CPU baseline. It contains the pinned upstream archives, committed
recipes, and the AINPKG builder. The build uses the Genesis development tools
and its base zlib, OpenSSL, libudev and ncurses development files.

Extract the bundle in a snapshot-mode Genesis VM under a readable working
directory. Run the checksum check and build there. A root invocation runs the
recipes as `nobody`, so keep the bundle outside `/root` and ensure that `nobody`
can traverse the extraction path.

```sh
cd /tmp
tar -xzf /path/to/AI-Now_Genesis_X11_Offline_Build.tar.gz
cd genesis-x11
python3 build.py check
python3 build.py build --jobs 4
```

The build leaves the archives and logs in the printed `PACKAGES` directory.
Before printing PASS it installs the complete package set into a disposable
root, verifies the payloads, and runs the Xorg, xterm, xauth and xkbcomp version
commands. It does not deploy to the Eee PC or exercise a physical display.

On the Eee PC, first confirm that the native graphics boot exposes a DRM card
and that the installed system and the packages both report glibc 2.44. When
deploying to an explicit, mounted Genesis root with AINPKG already initialized,
preview the Xorg package and install the packages from the verified build
directory. Confirm `findmnt` identifies the intended Genesis root before the
installation. Run the preview and installation as the target administrator.

```sh
# Set these paths for the mounted Genesis installation and the verified build.
target_root=/mnt/genesis
package_dir=/path/to/verified-packages
findmnt --mountpoint "$target_root" || exit
(cd "$package_dir" && sha256sum -c SHA256SUMS) || exit
python3 ainpkg --root "$target_root" install "$package_dir/xorg-server.ainpkg" --dry-run || exit
while read -r checksum package; do
    python3 ainpkg --root "$target_root" install "$package_dir/$package" || exit
done < "$package_dir/SHA256SUMS"
python3 ainpkg --root "$target_root" verify
```

For the physical check, boot Genesis with DRM modesetting available, log in on
the local console, and run `startx`. The default session starts one xterm.
Confirm that the internal panel shows the terminal, the keyboard can enter a
command, and closing xterm ends the X session cleanly. This Xorg build uses
software rendering, udev and evdev, with systemd-logind integration disabled.
Record the Xorg log and the console identity if VT or DRM permissions prevent
startup.
