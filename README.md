# 🔐 Goodix TOD Builder for Debian 13 (Trixie)

[![Debian](https://img.shields.io/badge/Debian-13_(Trixie)-A81D33?logo=debian&logoColor=white)](https://www.debian.org/)
[![Docker](https://img.shields.io/badge/Docker-ready-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![Status](https://img.shields.io/badge/build-reproducible-brightgreen)]()

This repository provides a **containerized, reproducible** way to build and install **libfprint TOD** and the **Goodix plugin** on **Debian 13 (Trixie)** — with **no pollution of the host** (only `.deb` packages are produced and installed).

The setup targets Goodix fingerprint readers such as the **Shenzhen Goodix 27c6:530c** family and uses the **Goodix “550a” plugin** sources that are known to support the 53xx series.

---

## ✅ What’s new / current reality

- Uses **libfprint `1.94.9+tod1`** (from Ubuntu’s signed sources) to match Debian’s `fprintd 1.94.5-2`.
- Goodix plugin built from **`ubuntu/jammy-devel`** (covers 27c6:53xx devices).
- **GPG verification ON by default** via the uploader fingerprint  
  (`D4C501DA48EB797A081750939449C2F50996635F`, Marco Trevisan). Fallback via armored URL or disabled with `DGET_NO_CHECK=1`.
- Output packages are suffixed `+rebuild~trixie1` to clearly mark local rebuilds.
- Helper **`clean.sh`** to reset artifacts/containers and optionally purge conflicting/legacy packages from the host.

---

## 🧩 Repository layout

```
.
├── Dockerfile              # Minimal Debian 13 build image + GPG key import
├── docker-compose.yml      # Orchestration + env/args for the build
├── build.sh                # Full pipeline: verify .dsc, fetch, patch, build
├── install-tod-goodix.sh   # Installs the generated .debs on the host
├── clean.sh                # Cleans artifacts and (optionally) host packages
└── out/                    # Output folder with generated .deb packages
```

---

## 🚀 Quick start

> Requirements: Docker Engine + Docker Compose plugin (v2).

Build the packages in Docker (no host pollution):
```bash
docker compose build --no-cache
docker compose up --abort-on-container-exit
```
Artifacts will be available under `./out/`.

Install on the host:
```bash
# Core libfprint + TOD
sudo apt-get install -y ./out/libfprint-2-2_*.deb ./out/libfprint-2-tod1_*.deb

# Goodix plugin (550a ONLY)
sudo apt-get install -y ./out/libfprint-2-tod1-goodix-550a_*.deb

# Optional developer bits
# sudo apt-get install -y ./out/libfprint-2-dev_*.deb ./out/libfprint-2-tod-dev_*.deb ./out/gir1.2-fprint-2.0_*.deb
```

**Keep the system stable:** hold packages to avoid repo upgrades replacing your local builds.
```bash
sudo apt-mark hold libfprint-2-2 libfprint-2-tod1 libfprint-2-tod1-goodix-550a gir1.2-fprint-2.0   libfprint-2-dev libfprint-2-tod-dev || true
```

> If you previously had the **legacy** `libfprint-2-tod1-goodix` (without “-550a”), remove it:
```bash
sudo apt-get remove --purge -y libfprint-2-tod1-goodix || true
```

---

## 🔍 Verify the device & test

```bash
# 1) Is the device present?
lsusb | grep -iE '27c6|goodix'

# 2) Reload udev rules, then restart fprintd
sudo udevadm control --reload
sudo udevadm trigger
sudo systemctl restart fprintd

# 3) Try enrolling (with debug)
LIBFPRINT_DEBUG=3 fprintd-enroll

# other useful commands
fprintd-list "$USER"
journalctl -u fprintd -b --no-pager | tail -n +1
```

Plugin shared object location (for reference):
```
/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-tod-goodix-550a-0.0.11.so
```

---

## 🛠️ Build configuration details

The default `docker-compose.yml` uses:
```yaml
environment:
  DGET_NO_CHECK: "0"   # keep signature verification ON
  LIBFPRINT_DSC_URL: "https://launchpad.net/ubuntu/+archive/primary/+files/libfprint_1.94.9+tod1-1.dsc"
  GOODIX_REPO_URL: "https://git.launchpad.net/libfprint-2-tod1-goodix"
  GOODIX_BRANCH: "ubuntu/jammy-devel"  # 27c6:53xx support
  UBUNTU_UPLOADER_KEY: "D4C501DA48EB797A081750939449C2F50996635F"  # Marco Trevisan
  DIST_NAME: "trixie"
  LOCAL_SUFFIX: "~trixie1"
```

The `Dockerfile` imports the uploader key from the Ubuntu keyserver (with fallback). If your network blocks HKPS, the build falls back to downloading the armored key and importing it.

If you must skip verification:
```bash
DGET_NO_CHECK=1 docker compose up --abort-on-container-exit
```

---

## 🧹 Clean & reset

Use the included cleaner to avoid stale artifacts or conflicting packages:

```bash
# Typical reset (artifacts + containers)
./clean.sh --artifacts --docker

# Also remove the legacy Goodix plugin package (no “-550a”)
sudo ./clean.sh --packages-old-plugin --yes

# Full reset (aggressive: removes all libfprint/fprintd-related pkgs)
sudo ./clean.sh --packages-all --unhold --remove-local-udev-rule --yes
```

> The cleaner is **idempotent** and won’t fail if targets are missing.

---

## 🧯 Troubleshooting

### 1) “trying to overwrite ... 60-libfprint-2-tod1-goodix.rules”
You have **two different Goodix packages** installed/generated:
- `libfprint-2-tod1-goodix-550a` (**keep this one**)
- `libfprint-2-tod1-goodix` (legacy, **remove this one**)

**Fix:**
```bash
sudo apt-get remove --purge -y libfprint-2-tod1-goodix
# or use the cleaner:
sudo ./clean.sh --packages-old-plugin --yes
```

### 2) `No devices available` in `fprintd-enroll`
- Confirm your USB ID:
  ```bash
  lsusb | grep -iE '27c6|goodix'
  ```
- Ensure udev rules were loaded and the service restarted:
  ```bash
  sudo udevadm control --reload
  sudo udevadm trigger
  sudo systemctl restart fprintd
  ```
- If your exact ID (e.g. **27c6:530c**) is not referenced by the plugin’s rules, add a **local rule**:
  ```bash
  sudo tee /etc/udev/rules.d/61-libfprint-2-tod1-goodix-local.rules >/dev/null <<'EOF'
  ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="27c6", ATTR{idProduct}=="530c", TAG+="uaccess"
  EOF

  sudo udevadm control --reload
  sudo udevadm trigger
  sudo systemctl restart fprintd
  ```
- Retest with debug:
  ```bash
  LIBFPRINT_DEBUG=3 fprintd-enroll
  journalctl -u fprintd -b --no-pager | tail -n +100
  ```

### 3) `fprintd` dependency mismatch
We align on **libfprint 1.94.9+tod1** so that Debian’s `fprintd 1.94.5-2` installs cleanly.  
If you change libfprint versions, you may need to:
- Upgrade/downgrade `fprintd` accordingly, **or**
- Rebuild `fprintd` against your libfprint:
  ```bash
  apt-get source fprintd
  (cd fprintd-* && dpkg-buildpackage -us -uc -b)
  sudo apt-get install -y ../fprintd_*_amd64.deb
  sudo apt-mark hold fprintd
  ```

### 4) GPG verification issues during `dget`
- Network/keyserver issues? Use the armored key fallback (already in the `Dockerfile`), or as a last resort:
  ```bash
  DGET_NO_CHECK=1 docker compose up --abort-on-container-exit
  ```

---

## 🔧 Advanced

- **Switching branches/sources:** adjust `GOODIX_BRANCH` in `docker-compose.yml`. The build script also tries fallbacks (`jammy/focal/noble`) automatically if your branch is missing.
- **Deterministic builds:** mount a local armored key and set `UBUNTU_UPLOADER_KEY_FILE=/keys/uploader.asc` (the script will import it before hitting keyservers).
- **Offline-ish builds:** pre-populate `./out/` or use a local proxy/cache; the pipeline uses only standard Debian/Ubuntu tooling.

---

## 🖥️ Tested env

- Debian 13 (Trixie) x86_64
- Goodix Fingerprint Reader **27c6:530c**
- libfprint **1.94.9+tod1** + Goodix **550a (0.0.11+2404)** + `fprintd 1.94.5-2`

---

## ↩️ Rollback

```bash
sudo apt-mark unhold libfprint-2-2 libfprint-2-tod1 libfprint-2-tod1-goodix-550a gir1.2-fprint-2.0 || true
sudo apt-get remove --purge -y libfprint-2-tod1-goodix-550a libfprint-2-tod1 libfprint-2-2
sudo apt-get install -y libfprint-2-2  # from Debian repos
```

---

## 📜 License

This repo is released into the **public domain** under [The Unlicense](LICENSE).