# 🔐 Goodix TOD Builder for Debian 13

[![Debian](https://img.shields.io/badge/Debian-13_(Trixie)-A81D33?logo=debian&logoColor=white)](https://www.debian.org/)
[![Docker](https://img.shields.io/badge/Docker-ready-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![Status](https://img.shields.io/badge/build-verified-brightgreen)]()

This repository contains a reproducible environment for building and installing **libfprint TOD** and the **Goodix plugin** to enable support for the **Shenzhen Goodix Technology Co., Ltd. Fingerprint Reader (27c6:530c)** on **Debian 13 (Trixie)**.

The entire build happens inside Docker, keeping the host clean. Only the generated `.deb` packages are written out to the host (`./out/`).

---

## ✨ Motivation

Out-of-the-box, Debian 13 does not ship support for certain Goodix fingerprint readers such as:

```
Bus 001 Device 003: ID 27c6:530c Shenzhen Goodix Technology Co.,Ltd. Fingerprint Reader
```

This project provides a containerized pipeline to build and install the required **libfprint TOD** components and the **Goodix plugin** so that this hardware works on Debian.

---

## 📂 Repository structure

```
.
├── Dockerfile              # Docker build environment (Debian 13 + all deps)
├── docker-compose.yml      # Orchestrates the builder container
├── build.sh                # Pipeline: fetch, verify (.dsc, GPG), patch, build libfprint TOD + Goodix
├── install-tod-goodix.sh   # Installer for the generated .debs (keeps host clean/stable)
├── LICENSE
└── out/                    # Output folder with generated .deb packages
```

---

## 🛠️ What’s included / key points

- ✅ **Signed-source verification ON by default** via `dscverify`/`gpgv`
  - The uploader’s key **`AC483F68DE728F43F2202FCA568D30F321B2133D`** is fetched **during the image build** and used by `build.sh`, which exports it to `~/.gnupg/trustedkeys.gpg` so `gpgv` sees it.
  - No need for a `keys/` directory on the host.
- 🧱 Full build of **libfprint-2-tod1** and **libfprint-2-tod1-goodix** inside Docker.
- 🧩 Compatibility tuned for **Debian 13 (trixie)** with a version suffix:
  - Changelog is normalized to append `+rebuild~trixie1` (e.g., `…-0ubuntu4+rebuild~trixie1`), avoiding version downgrades.
- 🧰 Installer script that:
  - Installs local `.deb` only (won’t pull unrelated repo packages accidentally).
  - Optional `-dev`/GIR, optional `_dbgsym` inclusion, apt-mark **hold**, and `fprintd` helper.
- 🧽 Host stays clean — only `./out` is populated with artifacts.

---

## 🚀 Build

Requirements:
- Docker and Docker Compose Plugin

Build steps:
```bash
docker compose build --no-cache
docker compose up
```

Artifacts will be created under:
```
./out/
```

Default sources used by the pipeline:
- **libfprint (TOD)** .dsc from Ubuntu (example):  
  `http://archive.ubuntu.com/ubuntu/pool/main/libf/libfprint/libfprint_1.94.7+tod1-0ubuntu4.dsc`
- **Goodix plugin** repository:  
  `https://git.launchpad.net/libfprint-2-tod1-goodix` (branch `ubuntu/noble-devel` by default)

You can tweak these via environment variables in `docker-compose.yml`:
- `LIBFPRINT_DSC_URL`
- `GOODIX_REPO_URL`
- `GOODIX_BRANCH`
- `DIST_NAME` (default `trixie`)
- `LOCAL_SUFFIX` (default `~trixie1`)
- `DGET_NO_CHECK` (default `0` = verification ON)

> **Note:** The Dockerfile downloads the uploader’s armored key (by exact fingerprint) during image build. If you need to override the key URL, build with:
> ```bash
> docker build >   --build-arg UPLOADER_KEY_URL="https://keyserver.ubuntu.com/pks/lookup?fingerprint=on&op=get&search=0xAC483F68DE728F43F2202FCA568D30F321B2133D" >   -t goodix-tod-build .
> ```

---

## 🧩 Install on host

After the build completes:

```bash
sudo bash install-tod-goodix.sh ./out
```

Optional environment variables:

- `INSTALL_DEV=1` → also install `-dev` and GIR packages (if produced)  
- `HOLD=0`       → do **not** apply `apt-mark hold` (default is `1`)  
- `TRY_FPRINTD=0`→ skip attempting to install `fprintd` from the repo (default is `1`)  
- `INCLUDE_DBG=1`→ also install `*_dbgsym*.deb` if present (default is `0`)

Examples:
```bash
# Minimal
sudo bash install-tod-goodix.sh ./out

# With dev headers + GIR, keep packages on hold
INSTALL_DEV=1 HOLD=1 sudo bash install-tod-goodix.sh ./out
```

Uninstall / rollback:
```bash
sudo apt-get remove --purge -y libfprint-2-tod1-goodix-550a libfprint-2-tod1 libfprint-2-2
sudo apt-get install -y libfprint-2-2
sudo apt-mark unhold libfprint-2-2 libfprint-2-tod1 libfprint-2-tod-dev libfprint-2-dev gir1.2-fprint-2.0 || true
```

---

## 🔍 Quick verification

After installation:

```bash
# Check device
lsusb | grep -i goodix

# Enroll a fingerprint
fprintd-enroll

# List enrolled fingerprints
fprintd-list "$USER"

# Debug logs
journalctl -u fprintd -b
```

The TOD plugin is typically installed under:
```
/usr/lib/*/libfprint-2/tod-1/
```

---

## 🧪 How the build works (high level)

1. **Keyring prep & GPG import**  
   `build.sh` prepares `~/.gnupg`, imports the uploader key (by fingerprint), and **exports** it to `~/.gnupg/trustedkeys.gpg` so that `gpgv`/`dscverify` can validate the `.dsc`.

2. **Fetch & verify**  
   `dget -x` downloads and **verifies** the `.dsc` + tarballs. If you *must* bypass validation (not recommended), set `DGET_NO_CHECK=1`.

3. **Patch & build**  
   Applies minor Meson/systemd/udev compatibility tweaks, normalizes the version (adds `+rebuild~trixie1`), and builds the **libfprint TOD** core.

4. **Build Goodix plugin**  
   Installs the locally built core in the container, clones the Goodix repo (with fallback branches), applies small compat patches, and builds the plugin.

5. **Artifacts**  
   All resulting `.deb` packages are copied to `/out` (mounted to `./out` on the host).

---

## 🧯 Troubleshooting

- **“dscverify … No public key”**  
  The build injects the correct key (fingerprint `AC483F68…`) into `trustedkeys.gpg`.  
  If you still see this, rebuild the image without cache:
  ```bash
  docker compose build --no-cache
  docker compose up
  ```
  and check inside the container:
  ```bash
  gpg --list-keys --with-colons | grep '^fpr:::::::::AC483F68DE728F43F2202FCA568D30F321B2133D:$'
  ls -lh /root/.gnupg/trustedkeys.gpg
  ```

- **Network hiccups / keyservers flaky**  
  The Dockerfile fetches the armored key by **exact fingerprint** during the image build to minimize runtime dependency on keyservers. You can also bake a local mirror (see `UPLOADER_KEY_URL` build-arg).

- **`libudev.pc not found`**  
  The builder image installs `libudev-dev`. If you reproduce this error in a custom base image, ensure `libudev-dev` is present.

- **`fprintd` mismatch**  
  If the repo `fprintd` doesn’t match the newly built libfprint ABI, the installer will tell you how to rebuild:
  ```
  apt-get source fprintd && dpkg-buildpackage -us -uc -b
  ```
  then install your local `fprintd` and put it on hold.

- **Versioning**  
  We append `+rebuild~trixie1` to the Ubuntu source version (e.g., `…-0ubuntu4+rebuild~trixie1`). This avoids version downgrade warnings while clearly marking the Debian 13 rebuild.

---

## 🖥️ Tested environment

- Debian 13 (Trixie) x86_64  
- Goodix Fingerprint Reader **27c6:530c**

---

## 🤝 Contributing

Issues and PRs are welcome — especially for testing on additional Goodix IDs, adding CI steps, or improving the installer checks.

---

## 📜 License

This repository is released into the **public domain** under [The Unlicense](LICENSE).
