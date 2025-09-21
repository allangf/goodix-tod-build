#!/usr/bin/env bash
# Installs libfprint TOD (1.94.9+tod1) and the Goodix plugin from ./out
# Compatible with Debian 13 (trixie). Prefer the -550a plugin variant when available.
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

# ---------- utils ----------
info(){ echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
die(){ err "$*"; exit 1; }

require_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "Please run as root (e.g., sudo $0 [OUTDIR])"
  fi
}

# ---------- main ----------
require_root

OUTDIR="${1:-${OUTDIR:-./out}}"
# If the script is inside the repo, default to ./out relative to the script
if [[ "${OUTDIR}" == "./out" ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
  [[ -d "${SCRIPT_DIR}/out" ]] && OUTDIR="${SCRIPT_DIR}/out"
fi

[[ -d "${OUTDIR}" ]] || die "Directory with packages not found: ${OUTDIR}"

shopt -s nullglob

# Detect which Goodix plugin variant to install (prefer -550a)
PLUGIN_550A=("${OUTDIR}"/libfprint-2-tod1-goodix-550a_*_amd64.deb)
PLUGIN_OLD=("${OUTDIR}"/libfprint-2-tod1-goodix_*_amd64.deb)

PLUGIN_DEB=""
PLUGIN_NAME=""

if [[ ${#PLUGIN_550A[@]} -gt 0 ]]; then
  PLUGIN_DEB="${PLUGIN_550A[0]}"
  PLUGIN_NAME="libfprint-2-tod1-goodix-550a"
  info "Selected Goodix plugin: 550a variant → $(basename "${PLUGIN_DEB}")"
elif [[ ${#PLUGIN_OLD[@]} -gt 0 ]]; then
  PLUGIN_DEB="${PLUGIN_OLD[0]}"
  PLUGIN_NAME="libfprint-2-tod1-goodix"
  warn "No -550a variant found; using $(basename "${PLUGIN_DEB}")"
else
  die "No Goodix plugin package found in ${OUTDIR} (neither *-550a_*.deb nor *-goodix_*.deb)."
fi

# Local package set (install everything present in the directory)
DEBSET=(
  "${OUTDIR}"/gir1.2-fprint-2.0_*_amd64.deb
  "${OUTDIR}"/libfprint-2-2_*_amd64.deb
  "${OUTDIR}"/libfprint-2-2-dbgsym_*_amd64.deb
  "${OUTDIR}"/libfprint-2-dev_*_amd64.deb
  "${OUTDIR}"/libfprint-2-doc_*_all.deb
  "${OUTDIR}"/libfprint-2-tests_*_amd64.deb
  "${OUTDIR}"/libfprint-2-tests-dbgsym_*_amd64.deb
  "${OUTDIR}"/libfprint-2-tod1_*_amd64.deb
  "${OUTDIR}"/libfprint-2-tod1-dbgsym_*_amd64.deb
  "${OUTDIR}"/libfprint-2-tod-dev_*_amd64.deb
)

# Ensure at least one core package exists
have_core=0
for p in "${DEBSET[@]}"; do
  [[ -f "$p" ]] && have_core=1 && break
done
[[ $have_core -eq 1 ]] || die "No core libfprint .deb found in ${OUTDIR}."

# Remove the opposite plugin variant if installed
if [[ "${PLUGIN_NAME}" == "libfprint-2-tod1-goodix-550a" ]]; then
  if dpkg -s libfprint-2-tod1-goodix &>/dev/null; then
    info "Removing legacy variant (libfprint-2-tod1-goodix) before installing -550a…"
    apt-get remove -y libfprint-2-tod1-goodix || true
  fi
else
  if dpkg -s libfprint-2-tod1-goodix-550a &>/dev/null; then
    info "Removing -550a variant before installing the legacy ‘goodix’…"
    apt-get remove -y libfprint-2-tod1-goodix-550a || true
  fi
fi

# Unhold packages to allow upgrade/downgrade
HOLD_PKGS=(
  gir1.2-fprint-2.0 libfprint-2-2 libfprint-2-dev libfprint-2-doc
  libfprint-2-tests libfprint-2-tod1 libfprint-2-tod-dev
  libfprint-2-tod1-goodix libfprint-2-tod1-goodix-550a
)
for p in "${HOLD_PKGS[@]}"; do
  if apt-mark showhold | grep -qx "$p"; then
    info "Removing hold: $p"
    apt-mark unhold "$p" || true
  fi
done

info "Updating APT indexes…"
apt-get update -y

# Ensure repository fprintd is installed
info "Installing/updating repository fprintd…"
apt-get install -y --allow-change-held-packages fprintd

# Main installation (try apt first; fallback to dpkg + fix)
info "Installing local .deb packages…"
set +e
apt-get install -y --allow-downgrades --allow-change-held-packages \
  "${DEBSET[@]}" "${PLUGIN_DEB}"
APT_RC=$?
set -e

if [[ $APT_RC -ne 0 ]]; then
  warn "apt could not resolve everything; applying fallback (dpkg -i + apt-get -f install)…"
  dpkg -i "${DEBSET[@]}" "${PLUGIN_DEB}" || true
  apt-get -f install -y
fi

# Hold packages to prevent repository from replacing local builds
TO_HOLD=(gir1.2-fprint-2.0 libfprint-2-2 libfprint-2-tod1 "${PLUGIN_NAME}")
for p in "${TO_HOLD[@]}"; do
  if dpkg -s "$p" &>/dev/null; then
    info "Applying hold on $p"
    apt-mark hold "$p" || true
  fi
done

# Post-install steps
info "Reloading udev rules and restarting fprintd…"
udevadm control --reload || true
udevadm trigger || true

if systemctl daemon-reload 2>/dev/null; then
  systemctl restart fprintd 2>/dev/null || systemctl start fprintd 2>/dev/null || true
else
  warn "systemd not available? Skipped restarting fprintd."
fi

# Sanity
PLUGIN_DIR="/usr/lib/$(uname -m)/libfprint-2/tod-1"
info "TOD plugin directory: ${PLUGIN_DIR}"
ls -lah "${PLUGIN_DIR}" || true

info "Installed versions (dpkg -l):"
dpkg -l | awk '/fprint/ {print $2, $3}' || true

cat <<'EOT'

==> All set! Proceed with testing:
    fprintd-enroll
    fprintd-verify
    fprintd-list "$USER"

If you see "No devices available", check:
  - USB cable/power of the sensor (on desktops) or: dmesg | grep -i goodix
  - Whether device 27c6:530c/27c6:* appears in `lsusb`
  - Service logs:  journalctl -u fprintd --no-pager -n 200

EOT
