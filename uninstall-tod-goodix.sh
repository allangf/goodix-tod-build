#!/usr/bin/env bash
# Removes the Goodix plugin and locally built libfprint TOD packages to restore a clean system.
# Reinstalls repository (Debian trixie) packages and clears any holds.
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

info(){ echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
die(){ err "$*"; exit 1; }

require_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "Please run as root (e.g., sudo $0)"
  fi
}

require_root

# Remove holds so downgrades/removals are allowed
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

# Remove either Goodix plugin variant if present
info "Removing Goodix plugins (if installed)…"
apt-get remove -y libfprint-2-tod1-goodix libfprint-2-tod1-goodix-550a || true

# Optional: purge debug/tests for a cleaner system
info "Removing debug/test packages (if present)…"
apt-get remove -y libfprint-2-2-dbgsym libfprint-2-tests libfprint-2-tests-dbgsym || true

# Ensure repository core is installed (allowing downgrade)
info "Reinstalling libfprint TOD from repository (allow downgrade if needed)…"
apt-get install -y --allow-downgrades --reinstall \
  gir1.2-fprint-2.0 libfprint-2-2 libfprint-2-tod1 libfprint-2-dev libfprint-2-tod-dev || true

# Repository fprintd
info "Ensuring repository fprintd is installed…"
apt-get install -y fprintd || true

# Clean up orphaned dependencies
apt-get autoremove -y || true

# Post-cleanup: reload udev and restart fprintd
info "Reloading udev and restarting fprintd…"
udevadm control --reload || true
udevadm trigger || true
if systemctl daemon-reload 2>/dev/null; then
  systemctl restart fprintd 2>/dev/null || systemctl start fprintd 2>/dev/null || true
fi

info "Final state (dpkg -l | grep fprint):"
dpkg -l | grep -E 'fprint|fprintd' || true

cat <<'EOT'

==> Cleanup completed.

To attempt installation again:
  1) Place the .deb files under ./out (or pass the path as an argument)
  2) Run: sudo ./install-tod-goodix.sh [OUTDIR]

EOT
