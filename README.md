# 🔐 Goodix TOD Builder for Debian 13

[![Debian](https://img.shields.io/badge/Debian-13_(Trixie)-A81D33?logo=debian&logoColor=white)](https://www.debian.org/)
[![Docker](https://img.shields.io/badge/Docker-ready-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![Status](https://img.shields.io/badge/build-in_progress-yellow)]()

This repository contains a reproducible environment for building and installing **libfprint TOD** and the **Goodix plugin** to enable support for the **Shenzhen Goodix Technology Co., Ltd. Fingerprint Reader (27c6:530c)** on **Debian 13 (Trixie)**.  

The build process runs entirely inside Docker, keeping the host system clean and only leaving the generated `.deb` packages for installation.

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
├── Dockerfile              # Build environment (Debian 13 + deps)
├── docker-compose.yml      # Orchestration of the build container
├── build.sh                # Automated pipeline: fetch, patch, build libfprint TOD + Goodix
├── install-tod-goodix.sh   # Install helper for generated .debs
└── out/                    # Output folder with generated .deb packages
```

---

## 🛠️ Features

- Full build of **libfprint-2-tod1** and **libfprint-2-tod1-goodix**.  
- Compatibility adjusted for **Debian 13 (trixie)** using local suffix (`~trixie1`).  
- Dockerized build to keep host clean.  
- Helper script for installation with optional:
  - **Development headers** (`-dev` packages)  
  - **Package hold** (`apt-mark hold`) to prevent repository upgrades  

---

## 🚀 Usage

### 1. Build the packages
```bash
docker compose build --no-cache
docker compose up
```

> The `.deb` packages will appear under `./out/` on the host.

---

### 2. Install on host
```bash
sudo bash install-tod-goodix.sh ./out
```

Optional environment variables:

- `INSTALL_DEV=1` → also install `-dev` packages  
- `HOLD=0` → do not apply `apt-mark hold`  

---

## 🔍 Quick verification

After installation:

```bash
# Check if Goodix device is detected
lsusb | grep -i goodix

# Enroll a fingerprint
fprintd-enroll

# List enrolled fingerprints
fprintd-list $USER

# Debug logs
journalctl -u fprintd -b
```

The plugin is usually installed under:

```
/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/
```

---

## 📑 Notes

- At the moment, it is **not yet possible to run `dget` with GPG verification** inside the container (still in progress).  
  To bypass this, the build script currently allows `DGET_NO_CHECK=1`.  
- The suffix `~trixie1` ensures compatibility with Debian 13 packages.  
- For rollback: remove TOD packages and reinstall the official `libfprint` from Debian:
  ```bash
  sudo apt-get remove --purge libfprint-2-tod1 libfprint-2-tod1-goodix libfprint-2-2
  sudo apt-get install -y libfprint-2-2
  ```

---

## 🧭 Roadmap

- [ ] Fix GPG key import and enable `dget` verification by default  
- [ ] Test with additional Goodix device IDs  
- [ ] Provide prebuilt `.deb` packages for convenience  

---

## 🖥️ Tested environment

- Debian 13 (Trixie) x86_64  
- Goodix Fingerprint Reader **27c6:530c**  

---

## 🤝 Contributing

Contributions are welcome!  
Feel free to open issues or submit pull requests for improvements, bug fixes, or additional device support.

---

## 📜 License

This repository is released into the **public domain** under [The Unlicense](LICENSE).

