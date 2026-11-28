# Genesis Fluxbox desktop

Build this add-on in the x86-64 Genesis glibc 2.44 VM. Reuse the
`genesis-x11-glibc-2.44-packages.tar.gz` archive previously produced by the
X11 build. The add-on needs the packaged X11 development libraries and the
Genesis C++ toolchain.

Copy both tarballs to `/tmp` in the VM. In the Genesis VM run:

```sh
cd /tmp
mkdir -m 755 genesis-x11-inputs
tar -xzf genesis-x11-glibc-2.44-packages.tar.gz -C genesis-x11-inputs
tar -xzf AI-Now_Genesis_Fluxbox_Offline_Build.tar.gz
cd genesis-fluxbox
python3 build.py /tmp/genesis-x11-inputs
```

If you run as root, the script builds as `nobody`. Keep both extracted
directories and files accessible to that account. The build prints
`PACKAGE=/tmp/ainow-fluxbox-…/fluxbox.ainpkg` after temporary-root validation.
Keep the archive and its `SHA256SUMS` before stopping a snapshot-mode VM.

Install the resulting package onto the existing Genesis target alongside
the X11 packages using AINPKG from the rescue environment. Preview the install
with `--dry-run`, then install and verify `fluxbox`. After booting the Eee PC
from its internal drive, run this at the local text console:

```sh
startx /usr/bin/genesis-session
```

Check the window titlebar, terminal, bottom toolbar and right-click menu.
`Ctrl+Alt+T` opens another terminal. The menu's **End session** item returns
to the text console.
