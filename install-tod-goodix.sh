#!/usr/bin/env bash
set -euo pipefail

# Installs libfprint + TOD + Goodix plugin built locally
# Usage:
#   sudo bash install-tod-goodix.sh [/path/to/out]
#
# Optional env:
#   INSTALL_DEV=1  -> also installs -dev packages (headers)
#   HOLD=0         -> do not apt-mark hold (default HOLD=1)
#   TRY_FPRINTD=1  -> try to install fprintd/libpam-fprintd from repo if compatible (default 1)

DEB_DIR="${1:-./out}"
INSTALL_DEV="${INSTALL_DEV:-0}"
HOLD="${HOLD:-1}"
TRY_FPRINTD="${TRY_FPRINTD:-1}"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "Must be run as root (use sudo)."; exit 1; }; }
say() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; exit 1; }

need_root
[ -d "$DEB_DIR" ] || die "Directory does not exist: $DEB_DIR"

# Normalize to an absolute directory and enter it
DEB_DIR="$(cd "$DEB_DIR" && pwd -P)"
cd "$DEB_DIR"

# Make unmatched globs expand to nothing
shopt -s nullglob

# Helper: collect first match of each glob as absolute path
collect_first_abs() {
  local outvar="$1"; shift
  local res=() pat matches
  for pat in "$@"; do
    matches=( $pat )
    if [ "${#matches[@]}" -gt 0 ]; then
      res+=( "$(readlink -f -- "${matches[0]}")" )
    fi
  done
  eval "$outvar=(\"\${res[@]}\")"
}

# Core libfprint + TOD + GIR (+doc optional)
req_core=()
collect_first_abs req_core \
  "libfprint-2-2_*_amd64.deb" \
  "libfprint-2-tod1_*_amd64.deb" \
  "gir1.2-fprint-2.0_*_*.deb"

# doc is optional; include it if present
opt_doc=()
collect_first_abs opt_doc "libfprint-2-doc_*_all.deb"

# Goodix plugin (name may vary, e.g., -550a)
req_plugin=()
collect_first_abs req_plugin "libfprint-2-tod1-goodix-*_amd64.deb"

# Optional -dev packages
opt_dev=()
if [ "$INSTALL_DEV" = "1" ]; then
  collect_first_abs opt_dev \
    "libfprint-2-dev_*_amd64.deb" \
    "libfprint-2-tod-dev_*_amd64.deb"
fi

# Minimal checks
[ "${#req_core[@]}" -ge 3 ] || die "Missing required .debs (need at least libfprint-2-2, libfprint-2-tod1 and gir1.2-fprint-2.0)."
[ "${#req_plugin[@]}" -ge 1 ] || die "Did not find Goodix plugin .deb (e.g., libfprint-2-tod1-goodix-550a_*.deb)."

say "Packages to be installed:"
printf '  %s\n' "${req_core[@]}" "${opt_doc[@]:-}" "${req_plugin[@]}" "${opt_dev[@]:-}"

say "Updating APT indexes..."
apt-get update -qq

# Install local packages (allowing downgrades, since repo may be newer)
say "Installing local packages (allowing downgrades if needed)..."
apt-get install -y --allow-downgrades \
  "${req_core[@]}" \
  "${opt_doc[@]:-}" \
  "${req_plugin[@]}" \
  "${opt_dev[@]:-}"

# Hold local packages so the repo won't overwrite them
if [ "$HOLD" = "1" ]; then
  say "Applying apt-mark hold to prevent replacement by repository versions..."
  hold_list=( libfprint-2-2 libfprint-2-tod1 gir1.2-fprint-2.0 )
  [ "$INSTALL_DEV" = "1" ] && hold_list+=( libfprint-2-dev libfprint-2-tod-dev )
  # add the plugin package name (read from its .deb control)
  plugin_pkg="$(dpkg-deb -f "${req_plugin[0]}" Package 2>/dev/null || true)"
  [ -n "$plugin_pkg" ] && hold_list+=( "$plugin_pkg" )
  apt-mark hold "${hold_list[@]}" >/dev/null || true
  say "Packages on hold: ${hold_list[*]}"
fi

# Optionally try to install fprintd/libpam-fprintd from the repo.
# If the repo's fprintd depends on libfprint-2-2 >= 1.94.9 and you have 1.94.7+tod1,
# this will fail gracefully and we print guidance to rebuild fprintd locally.
try_install_fprintd() {
  if [ "$TRY_FPRINTD" != "1" ]; then
    warn "Skipping fprintd install attempt (TRY_FPRINTD=0)."
    return 0
  fi
  say "Trying to install fprintd/libpam-fprintd from repository (if compatible)..."
  if apt-get install -y fprintd libpam-fprintd; then
    say "fprintd installed from repository."
    return 0
  fi

  warn "Repository fprintd could not be installed (likely needs libfprint-2-2 >= repo version)."
  cat <<'EOF'
To use fprintd with your TOD-enabled libfprint, rebuild fprintd locally:

  sudo apt-get update
  sudo apt-get install -y devscripts build-essential fakeroot dpkg-dev
  # Ensure local -dev headers are present (installed above)
  sudo apt-mark hold libfprint-2-2 libfprint-2-dev libfprint-2-tod1 libfprint-2-tod-dev || true

  mkdir -p ~/src && cd ~/src
  sudo apt-get build-dep -y fprintd
  apt-get source fprintd
  cd fprintd-*/

  # (Optional) relax minimum libfprint-2-dev if set to >= 1:1.94.9
  sed -i 's/libfprint-2-dev (>= 1:1\.94\.9)/libfprint-2-dev (>= 1:1.94.7)/' debian/control || true

  export DEBFULLNAME="local builder" DEBEMAIL="builder@local" DCH_FORCE_MAINTAINER=1
  dch --force-distribution --distribution trixie -b "Rebuild against local libfprint 1.94.7+tod1."

  dpkg-buildpackage -us -uc -b
  cd ..
  sudo apt-get install -y --allow-downgrades ./fprintd_*_amd64.deb ./libpam-fprintd_*_amd64.deb
  sudo apt-mark hold fprintd libpam-fprintd || true
EOF
}

try_install_fprintd

# Restart fprintd only if it exists (don’t error if service is absent)
say "Restarting fprintd (if present)..."
if systemctl list-unit-files | grep -q '^fprintd\.service'; then
  systemctl daemon-reload || true
  systemctl restart fprintd || true
else
  warn "fprintd service not found. If you rebuild/install fprintd later, you can start it with: sudo systemctl restart fprintd"
fi

say "Done."
