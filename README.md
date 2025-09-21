# 🔐 Goodix TOD Builder for Debian 13 (Trixie)

[![Debian](https://img.shields.io/badge/Debian-13_(Trixie)-A81D33?logo=debian&logoColor=white)](https://www.debian.org/)
[![Docker](https://img.shields.io/badge/Docker-ready-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![Status](https://img.shields.io/badge/build-reproducible-brightgreen)]()

This repository provides a **containerized, reproducible** way to build and install **libfprint TOD** and the **Goodix plugin** on **Debian 13 (Trixie)** — keeping the host **clean and stable** (only `.deb` packages are produced and installed).

The target device is the Goodix family (e.g. **27c6:530c**). The build uses Ubuntu’s libfprint **`1.94.9+tod1`** (signed source) plus the Goodix **“550a”** plugin, which is the variant that supports 53xx devices.

---

## ✅ Current state (what actually works here)

- **libfprint:** `1.94.9+tod1` (aligns with Debian’s `fprintd 1.94.5-2` so it installs cleanly).
- **Plugin:** **Goodix 550a** (`0.0.11+2404`) — packaged as `libfprint-2-tod1-goodix-550a`.
- **Signature verification:** **enabled by default** (`DGET_NO_CHECK=0`) using the Ubuntu uploader **Marco Trevisan**’s fingerprint:  
  `D4C501DA48EB797A081750939449C2F50996635F`.
- **Changelog normalization:** local suffix `+rebuild~trixie1` to mark host‑friendly rebuilds.
- **Host hygiene:** everything compiles inside Docker; installation on host is via generated `.deb` only.
- **Cleanup script included:** `uninstall-tod-goodix.sh` fully removes previous installs (plugins/core/fprintd) and unholds packages when needed.

> **Important:** Do **not** install the legacy package `libfprint-2-tod1-goodix` (without “-550a”). It conflicts with the 550a plugin (udev rules overlap). Use **only** `libfprint-2-tod1-goodix-550a` from this build.

---

## 📦 Repository layout

```
.
├── Dockerfile              # Debian 13 build image + uploader key import
├── docker-compose.yml      # Orchestration + env for the build
├── build.sh                # Pipeline: verify .dsc, fetch, patch, build
├── install-tod-goodix.sh   # Host installer for the generated .debs
├── uninstall-tod-goodix.sh # Host cleanup script (reset before retries)
└── out/                    # Output folder with generated .deb packages
```

---

## 🚀 Build (inside Docker)

Requirements: Docker Engine + Docker Compose plugin (v2).

```bash
docker compose build --no-cache
docker compose up --abort-on-container-exit
```
The `.deb` packages will appear under `./out/`.

### Build inputs (environment)
In `docker-compose.yml` you’ll find:

```yaml
environment:
  DGET_NO_CHECK: "0"   # keep signature verification ON
  LIBFPRINT_DSC_URL: "https://launchpad.net/ubuntu/+archive/primary/+files/libfprint_1.94.9+tod1-1.dsc"
  GOODIX_REPO_URL: "https://git.launchpad.net/libfprint-2-tod1-goodix"
  GOODIX_BRANCH: "ubuntu/noble-devel"  # default; builder attempts fallbacks if missing
  UBUNTU_UPLOADER_KEY: "D4C501DA48EB797A081750939449C2F50996635F"  # Marco Trevisan
  DIST_NAME: "trixie"
  LOCAL_SUFFIX: "~trixie1"
```

If your network blocks HKPS and GPG key retrieval fails, you can set `DGET_NO_CHECK=1` as a last resort to skip signature verification.

---

## 🧩 Install on the host

You can use the helper script (recommended):

```bash
sudo bash install-tod-goodix.sh ./out
# optional flags:
#   INSTALL_DEV=1  -> also installs -dev and GIR packages
#   HOLD=0         -> do not apt-mark hold (default is hold)
#   TRY_FPRINTD=0  -> skip fprintd install
```

Or install manually:

```bash
# Core + TOD
sudo apt-get install -y ./out/libfprint-2-2_*.deb ./out/libfprint-2-tod1_*.deb

# Goodix plugin (ONLY the 550a variant)
sudo apt-get install -y ./out/libfprint-2-tod1-goodix-550a_*.deb

# Optionally:
# sudo apt-get install -y ./out/libfprint-2-dev_*.deb ./out/libfprint-2-tod-dev_*.deb ./out/gir1.2-fprint-2.0_*.deb
```

**Protect your local build from repo upgrades:**
```bash
sudo apt-mark hold libfprint-2-2 libfprint-2-tod1 libfprint-2-tod1-goodix-550a gir1.2-fprint-2.0 libfprint-2-dev libfprint-2-tod-dev || true
```

> ⚠️ If you ever installed the **legacy** plugin (`libfprint-2-tod1-goodix` without “-550a”), remove it to avoid udev rule conflicts:
```bash
sudo apt-get remove --purge -y libfprint-2-tod1-goodix
```

---

## 🔍 Verify & test

```bash
# Device present?
lsusb | grep -iE '27c6|goodix'

# Reload rules, trigger, and restart fprintd
sudo udevadm control --reload
sudo udevadm trigger
sudo systemctl restart fprintd

# Enroll with debug
LIBFPRINT_DEBUG=3 fprintd-enroll

# Other
fprintd-list "$USER"
journalctl -u fprintd -b --no-pager | tail -n +1
```

Plugin path (reference):
```
/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-tod-goodix-550a-0.0.11.so
```

---

## 🧹 Cleanup / start over

When something goes wrong, start clean before a new attempt:

```bash
# Full reset (remove plugins/core/fprintd, drop holds, remove local udev rule)
sudo bash uninstall-tod-goodix.sh --full --unhold --remove-local-udev --yes

# Then install again (using the installer or manual steps)
sudo bash install-tod-goodix.sh ./out
```

You can also restore Debian repo defaults after cleanup:
```bash
sudo bash uninstall-tod-goodix.sh --full --unhold --reinstall-repo-core --yes
```

---

## 🧯 Troubleshooting

### A) `trying to overwrite ... 60-libfprint-2-tod1-goodix.rules`
Two plugin packages are present. Keep **`libfprint-2-tod1-goodix-550a`** and purge the **legacy** `libfprint-2-tod1-goodix`:
```bash
sudo apt-get remove --purge -y libfprint-2-tod1-goodix
```
Or run the cleaner’s plugin-only mode:
```bash
sudo bash uninstall-tod-goodix.sh --plugin-only --unhold --yes
```

### B) `No devices available` in `fprintd-enroll`
- Confirm the device:
  ```bash
  lsusb | grep -iE '27c6|goodix'
  ```
- Reload udev and restart the service:
  ```bash
  sudo udevadm control --reload
  sudo udevadm trigger
  sudo systemctl restart fprintd
  ```
- If your exact ID (e.g. **27c6:530c**) is not matched by rules, add a local rule:
  ```bash
  sudo tee /etc/udev/rules.d/61-libfprint-2-tod1-goodix-local.rules >/dev/null <<'EOF'
  ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="27c6", ATTR{idProduct}=="530c", TAG+="uaccess"
  EOF
  sudo udevadm control --reload
  sudo udevadm trigger
  sudo systemctl restart fprintd
  ```
- Retest with debug and check logs:
  ```bash
  LIBFPRINT_DEBUG=3 fprintd-enroll
  journalctl -u fprintd -b --no-pager | tail -n +100
  ```

### C) GPG verification fails during `.dsc` fetch
- Network/keyserver issues can block HKPS. As a last resort:
  ```bash
  DGET_NO_CHECK=1 docker compose up --abort-on-container-exit
  ```

---

## 🔧 Advanced

- **Switching Goodix branch:** set `GOODIX_BRANCH` (default `ubuntu/noble-devel`). The builder also tries several fallbacks if the branch is missing.
- **Deterministic builds:** provide a local armored key `UBUNTU_UPLOADER_KEY_FILE=/keys/uploader.asc` (mounted via volume); the pipeline imports it before hitting keyservers.
- **USB passthrough:** if running inside a VM/LXD, ensure the Goodix USB device is passed through to the host where you test `fprintd`.

---

## ↩️ Rollback to Debian repo versions

```bash
sudo apt-mark unhold libfprint-2-2 libfprint-2-tod1 libfprint-2-tod1-goodix-550a gir1.2-fprint-2.0 || true
sudo apt-get remove --purge -y libfprint-2-tod1-goodix-550a libfprint-2-tod1 libfprint-2-2
sudo apt-get install -y libfprint-2-2 fprintd
```

---

## 📜 License

Public domain — [The Unlicense](LICENSE).
