# Minimal, clean Debian 13 (trixie) builder image
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
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

WORKDIR /build

COPY build.sh /build.sh
RUN chmod +x /build.sh

# Default command expects env vars provided by docker-compose
CMD ["/build.sh"]
