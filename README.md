# 🔐 Goodix TOD Builder for Debian 13 (Trixie)

[![Debian](<https://img.shields.io/badge/Debian-13_(Trixie)-A81D33?logo=debian&logoColor=white>)](https://www.debian.org/) [![Docker](https://img.shields.io/badge/Docker-ready-2496ED?logo=docker&logoColor=white)](https://www.docker.com/) [![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/) [![Arch](https://img.shields.io/badge/arch-x86__64-informational)](#) [![License: Unlicense](https://img.shields.io/badge/license-Unlicense-blue.svg)](http://unlicense.org/)
(#license) [![libfprint](https://img.shields.io/badge/libfprint-1.94.9%2Btod1-blue)](https://gitlab.freedesktop.org/libfprint/libfprint) [![Goodix 53xc](https://img.shields.io/badge/Goodix-53xc-success)](#support-matrix) [![Goodix 550a](https://img.shields.io/badge/Goodix-550a-success)](#support-matrix) [![GPG Verified](https://img.shields.io/badge/GPG-Verified-8A2BE2)](#gpg-verification)

This repository provides a **containerized, reproducible** way to build and install **libfprint TOD** and the **Goodix plugin** on **Debian 13 (Trixie)** — keeping the host **clean and stable** (only `.deb` packages are produced and installed).

Target devices: **Goodix fingerprint readers** (e.g. `27c6:530c`, `27c6:533c`, `27c6:538c`, `27c6:5840`, `27c6:550a`).

All builds happen inside Docker. On the host you only install the resulting `.deb` packages via the provided installer script.

---

## ✅ Current State

- **libfprint:** `1.94.9+tod1` (upstream Ubuntu, cleanly coexists with Debian’s `fprintd`).
- **Plugins:**
  - **Goodix 53xc** (for `27c6:530c/533c/538c/5840`)
  - **Goodix 550a** (for `27c6:550a`)
- **Signature verification:** Enabled by default (uses Ubuntu uploader Marco Trevisan’s fingerprint `D4C5 01DA 48EB 797A 0817 5093 9449 C2F5 0996 635F`).
- **Changelog normalization:** Suffix `+rebuild~trixie1` marks local rebuilds.
- **Host hygiene:** Nothing is built directly on the host, only inside Docker.

---

## 🧭 Quickstart

```bash
git clone <your-repo-url> goodix-tod-builder
cd goodix-tod-builder

# 1) Build inside Docker (outputs to ./out)
sudo ./build.sh

# 2) Install the correct plugin (auto-detects 53xc vs 550a)
sudo ./install-tod-goodix.sh ./out

# 3) Test
LIBFPRINT_DEBUG=3 fprintd-enroll
journalctl -u fprintd -b --no-pager -n 200
```

> Tip: `DRY_RUN=1` simulates actions without changing the system.

---

## 📦 Scripts

### `build.sh`

- Builds all packages in a container (no host pollution).
- Produces `.deb` under `./out/`.

### `install-tod-goodix.sh`

- Auto-detects your Goodix USB ID (`lsusb`).
- Installs **only one** Goodix plugin (prevents conflicts):
  - `27c6:530c/533c/538c/5840` → **53xc**
  - `27c6:550a` → **550a**
- Removes the other plugin (and stray `.so`) if present.
- Reloads udev and restarts `fprintd`.
- Applies `apt-mark hold` by default.

**Options**:

```bash
PREFER_PLUGIN=53xc|550a  # force selection
INSTALL_DEV=1            # also install -dev packages
HOLD=0                   # skip apt hold
DRY_RUN=1                # simulate actions
```

### `uninstall-tod-goodix.sh`

- Removes both Goodix plugins, leftover `.so`, and local udev rules.
- Optionally removes base libs and repairs from Debian repos.

**Modes**:

```bash
--yes                # non-interactive
--full --repair      # remove local libs and reinstall clean base from repo
--purge              # purge entire fingerprint stack (fprintd/libpam/libfprint + plugins)
--keep-holds         # keep apt holds
--dry-run            # simulate actions
```

---

## 🧩 Support Matrix

| USB ID    | Device family | Plugin | Status |
| --------- | ------------- | ------ | ------ |
| 27c6:530c | Goodix 53xc   | 53xc   | ✅     |
| 27c6:533c | Goodix 53xc   | 53xc   | ✅     |
| 27c6:538c | Goodix 53xc   | 53xc   | ✅     |
| 27c6:5840 | Goodix 53xc   | 53xc   | ✅     |
| 27c6:550a | Goodix 550a   | 550a   | ✅     |

> If your device is not listed, try `lsusb` and open an issue/PR with the ID.

---

## 🔍 Troubleshooting

### fprintd crashes with:

```
libfprint-tod:ERROR:...goodix_tod_wrapper.c:goodix_tod_wrapper_init: assertion failed: (goodix_moc_identify == NULL)
```

**Cause**: both Goodix plugins installed simultaneously.  
**Fix**:

```bash
sudo ./uninstall-tod-goodix.sh --yes
sudo ./install-tod-goodix.sh ./out   # will install only the correct plugin
```

### Both `.so` are present in TOD dir

```bash
ls -l /usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/
# Keep only ONE: libfprint-tod-goodix-53xc-*.so OR libfprint-tod-goodix-550a-*.so
```

### APT upgrades overwrote your local packages

```bash
sudo apt-mark hold libfprint-2-2 libfprint-2-tod1   libfprint-2-tod1-goodix-53xc libfprint-2-tod1-goodix-550a   fprintd libpam-fprintd
```

### Device not detected / enroll fails

- Check USB ID: `lsusb | grep -i 27c6:`
- Verify udev rules presence in `/lib/udev/rules.d/60-libfprint-2-tod1-goodix-*.rules`
- Reload udev: `sudo udevadm control --reload && sudo udevadm trigger`
- Restart service: `sudo systemctl restart fprintd`
- Logs: `journalctl -u fprintd -b --no-pager -n 200`

### Recover to stock Debian

```bash
sudo ./uninstall-tod-goodix.sh --full --repair --yes
```

---

## ❓ FAQ

**Q: Debian 12 (Bookworm) supported?**  
A: This repo targets **Debian 13**. Some steps may work on 12, but packaging and dependencies were tuned for 13.

**Q: Ubuntu support?**  
A: Not targeted. The build might succeed, but use distro-native packages on Ubuntu when possible.

**Q: Safe to update via APT after install?**  
A: Yes, but the installer places `apt-mark hold` by default to avoid accidental overwrites.

**Q: How to switch from 550a → 53xc (or vice versa)?**  
A: Just rerun the installer with `PREFER_PLUGIN=...` or plug the device and let auto-detection choose. The other plugin is removed automatically.

---

## 🔏 GPG Verification

The libfprint sources are signed by Ubuntu uploader **Marco Trevisan** (Canonical). Fingerprint:

```
D4C5 01DA 48EB 797A 0817 5093 9449 C2F5 0996 635F
```

This builder fetches and validates signatures during the build.

---

## 📄 License

**Public domain**. See [LICENSE](LICENSE).
