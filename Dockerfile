# Minimal, clean Debian 13 (Trixie) builder image
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

# Core toolchain and build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    debhelper-compat \
    debian-keyring \
    devscripts \
    dirmngr \
    dpkg-dev \
    git \
    gnupg \
    gobject-introspection \
    gtk-doc-tools \
    libcairo2-dev \
    libgirepository1.0-dev \
    libglib2.0-dev \
    libglib2.0-doc \
    libgudev-1.0-dev \
    libgusb-dev \
    libgusb-doc \
    libnss3-dev \
    libpam0g-dev \
    libpixman-1-dev \
    libsystemd-dev \
    libudev-dev \
    libusb-1.0-0-dev \
    meson \
    ninja-build \
    pkg-config \
    python3-cairo \
    python3-gi \
    ubuntu-keyring \
    umockdev \
    wget && \
    mkdir -p /root/.gnupg && chmod 700 /root/.gnupg && \
    rm -rf /var/lib/apt/lists/*

# --- GPG uploader key (Ubuntu) ---
# Primary: fingerprint
ARG UPLOADER_KEY_FPR="D4C501DA48EB797A081750939449C2F50996635F"
# Derive the armored key URL from the fingerprint (ENV can expand ARG set above)
ENV UPLOADER_KEY_URL="https://keyserver.ubuntu.com/pks/lookup?fingerprint=on&op=get&search=0x${UPLOADER_KEY_FPR}"

# Import uploader key so dget/gpgv can verify .dsc/.orig.tar signatures
# Try keyserver first; if it fails, fallback to armored key URL
RUN (gpg --batch --no-tty --keyserver hkps://keyserver.ubuntu.com --recv-keys "$UPLOADER_KEY_FPR" || \
    curl -fsSL "$UPLOADER_KEY_URL" | gpg --import) && \
    gpg --batch --yes --no-tty --export "$UPLOADER_KEY_FPR" > /root/.gnupg/trustedkeys.gpg

# Expose the key fingerprint as an env var (build.sh may use it)
ENV UBUNTU_UPLOADER_KEY=${UPLOADER_KEY_FPR}

# --- Build-time defaults (can be overridden by build args / docker-compose) ---
ARG LIBFPRINT_DSC_URL="https://launchpad.net/ubuntu/+archive/primary/+files/libfprint_1.94.9+tod1-1.dsc"
ARG GOODIX_REPO_URL="https://git.launchpad.net/libfprint-2-tod1-goodix"
ARG GOODIX_BRANCH="ubuntu/noble-devel"

ENV LIBFPRINT_DSC_URL=${LIBFPRINT_DSC_URL} \
    GOODIX_REPO_URL=${GOODIX_REPO_URL} \
    GOODIX_BRANCH=${GOODIX_BRANCH}

WORKDIR /build

# Build pipeline entrypoint
COPY build.sh /build.sh
RUN chmod +x /build.sh

# Default command runs the build pipeline
CMD ["/build.sh"]
