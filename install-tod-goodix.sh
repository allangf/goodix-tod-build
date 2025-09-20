#!/usr/bin/env bash
set -euo pipefail

# Installs locally built libfprint TOD core + Goodix plugin from a directory.
# Keeps the host clean and stable (applies apt-mark hold).
#
# Usage:
#   sudo bash install-tod-goodix.sh [/path/to/out]
#
# Optional env:
#   INSTALL_DEV=1   -> also install -dev and GIR packages
#   HOLD=1          -> apt-mark hold packages after install (default 1)
#   TRY_FPRINTD=1   -> try to install fprintd if not present (default 1)
#   INCLUDE_DBG=1   -> include *_dbgsym*.deb if present (default 0)

DEB_DIR="${1:-./out}"
INSTALL_DEV="${INSTALL_DEV:-0}"
HOLD="${HOLD:-1}"
TRY_FPRINTD="${TRY_FPRINTD:-1}"
INCLUDE_DBG="${INCLUDE_DBG:-0}"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "Must run as root (use sudo)."; exit 1; }; }
say() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; exit 1; }

need_root
[ -d "$DEB_DIR" ] || die "Directory not found: $DEB_DIR"
cd "$DEB_DIR"

# Collect debs (optionally exclude debug symbols)
shopt -s nullglob
if [ "$INCLUDE_DBG" = "1" ]; then
  mapfile -t DEBS < <(ls -1 ./*.deb)
else
  mapfile -t DEBS < <(ls -1 ./*.deb | grep -v -- '_dbgsym')
fi
[ ${#DEBS[@]} -gt 0 ] || die "No .deb files found in: $DEB_DIR"

say "Installing locally built libfprint TOD core + Goodix plugin (.deb)…"
apt-get update -qq

# First attempt: let apt resolve everything in one go from local files
if ! apt-get install -y "${DEBS[@]}"; then
  warn "Apt failed to resolve everything in one pass; applying fallback (dpkg -i + apt-get -f install)…"
  # Force local install then fix dependencies
  if ! dpkg -i "${DEBS[@]}"; then
    apt-get -f install -y
    # Try once more to ensure everything is configured
    dpkg -i "${DEBS[@]}" || true
  fi
fi

# Optionally install dev/GIR (if present among produced artifacts)
if [ "$INSTALL_DEV" = "1" ]; then
  say "Installing -dev and GIR packages as requested (INSTALL_DEV=1)…"
  set +e
  apt-get install -y ./libfprint-2-dev_*.deb ./libfprint-2-tod-dev_*.deb ./gir1.2-fprint-2.0_*.deb
  set -e
fi

# Hold only packages that actually exist/are installed
if [ "$HOLD" = "1" ]; then
  say "Applying apt-mark hold to prevent repository overrides…"
  for pkg in libfprint-2-2 libfprint-2-tod1 libfprint-2-dev libfprint-2-tod-dev gir1.2-fprint-2.0; do
    if dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null | grep -q '^install ok installed'; then
      apt-mark hold "$pkg" >/dev/null 2>&1 || true
    fi
  done
fi

# Optionally install fprintd from repo if not present (only if ABI likely matches)
if [ "$TRY_FPRINTD" = "1" ]; then
  say "Checking fprintd availability…"
  if ! dpkg-query -W -f='${Status}\n' fprintd 2>/dev/null | grep -q '^install ok installed'; then
    if apt-get install -y fprintd; then
      say "fprintd installed from repository."
    else
      warn "Could not install fprintd from repository. You may need to rebuild it against your local libfprint."
      warn "Tip: apt-get source fprintd && dpkg-buildpackage -us -uc -b; then install the resulting .deb and hold it."
    fi
  else
    say "fprintd already present."
  fi
fi

# Post-install sanity: show plugin path and versions
say "Post-install sanity checks:"
# Multi-arch path detection for the TOD plugin directory
PLUGIN_DIR="$(dirname "$(dirname "$(dpkg -L libfprint-2-tod1 2>/dev/null | grep -E '/libfprint-2/tod-1/?$' | head -n1 || echo /usr/lib/x86_64-linux-gnu/libfprint-2/tod-1)")")/libfprint-2/tod-1"
if [ -d "$PLUGIN_DIR" ]; then
  say "TOD plugin dir: $PLUGIN_DIR"
  ls -l "$PLUGIN_DIR" || true
else
  warn "Could not locate TOD plugin directory. Expected under */libfprint-2/tod-1"
fi

# Show installed versions (if present)
for pkg in libfprint-2-2 libfprint-2-tod1 libfprint-2-tod1-goodix-550a gir1.2-fprint-2.0 fprintd; do
  if dpkg-query -W -f='${Package} ${Version}\n' "$pkg" 2>/dev/null; then
    :
  fi
done

say "Done. Test with:  fprintd-enroll  and  fprintd-verify"
say "TOD plugin path is usually:  /usr/lib/*/libfprint-2/tod-1/"
