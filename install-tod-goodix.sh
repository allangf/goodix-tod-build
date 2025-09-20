#!/usr/bin/env bash
set -euo pipefail

# Installs locally built libfprint TOD core + Goodix plugin from a directory.
# Keeps the host clean and stable (applies apt-mark hold).
#
# Usage:
#   sudo bash install-tod-goodix.sh [/path/to/out]
#
# Optional env:
#   INSTALL_DEV=1  -> also installs -dev and GIR packages
#   HOLD=1         -> apt-mark hold packages after install (default 1)
#   TRY_FPRINTD=1  -> try to install/rebuild fprintd if ABI matches (default 1)

DEB_DIR="${1:-./out}"
INSTALL_DEV="${INSTALL_DEV:-0}"
HOLD="${HOLD:-1}"
TRY_FPRINTD="${TRY_FPRINTD:-1}"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "Must run as root (use sudo)."; exit 1; }; }
say() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; exit 1; }

need_root
[ -d "$DEB_DIR" ] || die "Directory not found: $DEB_DIR"

shopt -s nullglob
cd "$DEB_DIR"

say "Installing locally built libfprint TOD core + Goodix plugin (.deb)…"
# Install core first, then plugin (ignore ordering quirks by letting apt resolve)
DEBS=(*.deb)
[ ${#DEBS[@]} -gt 0 ] || die "No .deb files found in: $DEB_DIR"
apt-get update -qq
apt-get install -y ./libfprint-2-*.deb || true
apt-get install -y ./*.deb

if [ "$INSTALL_DEV" = "1" ]; then
  say "Installing -dev and GIR packages as requested (INSTALL_DEV=1)…"
  apt-get install -y \
    ./libfprint-2-dev_*.deb \
    ./libfprint-2-tod-dev_*.deb \
    ./gir1.2-fprint-2.0_*.deb || true
fi

if [ "$HOLD" = "1" ]; then
  say "Applying apt-mark hold to prevent repository overrides…"
  for pkg in \
    libfprint-2-2 libfprint-2-tod1 libfprint-2-dev libfprint-2-tod-dev \
    gir1.2-fprint-2.0; do
      apt-mark hold "$pkg" >/dev/null 2>&1 || true
  done
fi

# Optional: try installing fprintd if ABI is compatible;
# if mismatch, provide guidance (don’t pull random repo versions).
if [ "$TRY_FPRINTD" = "1" ]; then
  say "Checking fprintd compatibility…"
  if apt-cache policy fprintd | grep -q "Installed: (none)"; then
    if apt-get install -y fprintd; then
      say "fprintd installed from repository (ABI appears compatible)."
    else
      warn "Could not install fprintd from repository. You may need to rebuild fprintd against your local libfprint if ABI differs."
      warn "Tip: apt-get source fprintd && dpkg-buildpackage -us -uc -b, then install the resulting .deb and hold it."
    fi
  else
    say "fprintd already present; ensure it works with the newly installed TOD."
  fi
fi

say "Done. Test with:  fprintd-enroll  and  fprintd-verify"
say "TOD plugin path is usually under:  /usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/"
