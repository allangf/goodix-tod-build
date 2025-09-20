#!/usr/bin/env bash
set -euo pipefail

# Installs libfprint + TOD + Goodix plugin built locally
# Usage:
#   sudo bash install-tod-goodix.sh [/path/to/out]
#
# Optional variables:
#   INSTALL_DEV=1  -> also installs -dev packages (headers)
#   HOLD=0         -> do not apply 'apt-mark hold' (default HOLD=1)

DEB_DIR="${1:-./out}"
INSTALL_DEV="${INSTALL_DEV:-0}"
HOLD="${HOLD:-1}"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "Must be run as root (use sudo)."; exit 1; }; }
say() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; exit 1; }

need_root
[ -d "$DEB_DIR" ] || die "Directory does not exist: $DEB_DIR"

cd "$DEB_DIR"

# Ensure unmatched globs expand to nothing
shopt -s nullglob

# Select only required packages (exclude -tests, -dbgsym)
# Core libfprint + TOD + GIR
req_core=()
for pat in \
  libfprint-2-2_*_amd64.deb \
  libfprint-2-tod1_*_amd64.deb \
  gir1.2-fprint-2.0_*_*.deb \
  libfprint-2-doc_*_all.deb
do
  matches=( $pat )
  if [ "${#matches[@]}" -gt 0 ]; then
    req_core+=( "${matches[0]}" )
  fi
done

# Goodix plugin (name may vary, e.g. 550a)
req_plugin=()
for pat in libfprint-2-tod1-goodix-*_amd64.deb; do
  matches=( $pat )
  if [ "${#matches[@]}" -gt 0 ]; then
    req_plugin+=( "${matches[0]}" )
  fi
done

# Optional -dev packages (for development)
opt_dev=()
if [ "$INSTALL_DEV" = "1" ]; then
  for pat in libfprint-2-dev_*_amd64.deb libfprint-2-tod-dev_*_amd64.deb; do
    matches=( $pat )
    if [ "${#matches[@]}" -gt 0 ]; then
      opt_dev+=( "${matches[0]}" )
    fi
  done
fi

# Minimal checks
[ "${#req_core[@]}" -ge 3 ] || die "Missing required .debs (need at least libfprint-2-2, libfprint-2-tod1 and gir1.2-fprint-2.0)."
[ "${#req_plugin[@]}" -ge 1 ] || die "Did not find Goodix plugin .deb (e.g., libfprint-2-tod1-goodix-550a_*.deb)."

say "Packages to be installed:"
printf '  %s\n' "${req_core[@]}" "${req_plugin[@]}" "${opt_dev[@]:-}"

say "Updating APT indexes..."
apt-get update -qq

# Tip: to preview actions before applying:
# apt-get -s install --allow-downgrades "${req_core[@]}" "${req_plugin[@]}" "${opt_dev[@]:-}" || true

say "Installing local packages (allowing downgrades if needed)..."
apt-get install -y --allow-downgrades \
  "${req_core[@]}" \
  "${req_plugin[@]}" \
  "${opt_dev[@]:-}"

if [ "$HOLD" = "1" ]; then
  say "Applying apt-mark hold to prevent replacement by repository versions..."
  hold_list=( libfprint-2-2 libfprint-2-tod1 gir1.2-fprint-2.0 )
  [ "$INSTALL_DEV" = "1" ] && hold_list+=( libfprint-2-dev libfprint-2-tod-dev )
  plugin_pkg="$(dpkg-deb -f "${req_plugin[0]}" Package 2>/dev/null || true)"
  [ -n "$plugin_pkg" ] && hold_list+=( "$plugin_pkg" )
  apt-mark hold "${hold_list[@]}" >/dev/null || true
  say "Packages on hold: ${hold_list[*]}"
fi

say "Restarting fprintd (if present)..."
systemctl daemon-reload || true
systemctl restart fprintd || true

say "Done."
