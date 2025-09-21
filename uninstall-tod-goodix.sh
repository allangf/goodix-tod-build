#!/usr/bin/env bash
set -euo pipefail

# uninstall-tod-goodix.sh — sanitize host before a fresh install
#
# Purpose:
#   Remove previously installed libfprint TOD + Goodix packages (and optional core/fprintd),
#   drop apt holds, clear udev overrides, and leave the machine clean for a new run.
#
# Usage (run as root):
#   sudo ./uninstall-tod-goodix.sh [--plugin-only | --full] [--reinstall-repo-core] [--remove-local-udev]
#                                  [--unhold] [--yes] [--dry-run]
#
# Flags:
#   --plugin-only          Remove only Goodix plugin packages (both legacy and -550a). Keep core libfprint and fprintd.
#   --full                 Remove ALL related packages: fprintd + libfprint core + TOD + dev/gir/tests/docs. (Default)
#   --reinstall-repo-core  After cleanup, install libfprint-2-2 (and fprintd) from Debian repos.
#   --remove-local-udev    Remove /etc/udev/rules.d/61-libfprint-2-tod1-goodix-local.rules if present.
#   --unhold               Unhold any held libfprint/fprintd packages before removing.
#   --yes                  Do not ask for confirmation (assume "yes").
#   --dry-run              Print actions only, do not execute.
#   --help, -h             Show this help.
#
# Examples:
#   # Full reset (recommended before a fresh install):
#   sudo ./uninstall-tod-goodix.sh --full --unhold --remove-local-udev --yes
#
#   # Only remove the Goodix plugin variants to avoid conflicts:
#   sudo ./uninstall-tod-goodix.sh --plugin-only --unhold --yes
#
#   # Full reset and restore Debian repo versions afterwards:
#   sudo ./uninstall-tod-goodix.sh --full --unhold --reinstall-repo-core --yes
#
# Notes:
#   * Keep scripts in English per project convention.

say()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; exit 1; }

need_root() { [[ "$(id -u)" == "0" ]] || die "Must run as root (use sudo)."; }

is_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

is_held() {
  apt-mark showhold 2>/dev/null | grep -qx "$1"
}

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf "[dry-run] %s\n" "$*"
  else:
    "$@"
  fi
}

confirm() {
  local msg="$1"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  read -r -p "$msg [y/N] " ans || true
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

usage() { sed -n '1,120p' "$0"; }

# Defaults
MODE="full"         # "full" or "plugin-only"
REINSTALL_REPO=0
REMOVE_LOCAL_UDEV=0
UNHOLD=0
ASSUME_YES=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-only) MODE="plugin-only" ;;
    --full) MODE="full" ;;
    --reinstall-repo-core) REINSTALL_REPO=1 ;;
    --remove-local-udev) REMOVE_LOCAL_UDEV=1 ;;
    --unhold) UNHOLD=1 ;;
    --yes) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown flag: $1 (use --help)";;
  esac
  shift
done

need_root

say "Requested mode: $MODE"
[[ $UNHOLD -eq 1 ]] && say "Will unhold packages before removal."
[[ $REINSTALL_REPO -eq 1 ]] && say "Will reinstall Debian repo libfprint-2-2 and fprintd after cleanup."
[[ $REMOVE_LOCAL_UDEV -eq 1 ]] && say "Will remove local udev Goodix override."

if ! confirm "Proceed with package removals and cleanup?"; then
  die "Aborting on user request."
fi

APT_YES=(-y)
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  APT_YES=()
fi

# Stop fprintd if running (ignore errors)
run systemctl stop fprintd || true

# Unhold packages if requested
maybe_unhold() {
  local pkg="$1"
  if [[ $UNHOLD -eq 1 ]] && is_held "$pkg"; then
    say "Unholding $pkg"
    run apt-mark unhold "$pkg"
  fi
}

# Remove a package if installed
maybe_purge() {
  local pkg="$1"
  if is_installed "$pkg"; then
    say "Purging $pkg"
    run apt-get remove --purge "${APT_YES[@]}" "$pkg"
  else
    warn "$pkg not installed (skip)"
  fi
}

# The sets
PLUGIN_PKGS=(libfprint-2-tod1-goodix-550a libfprint-2-tod1-goodix)
CORE_PKGS=(libfprint-2-tod1 libfprint-2-2)
EXTRA_PKGS=(libfprint-2-dev libfprint-2-tod-dev gir1.2-fprint-2.0 libfprint-2-tests libfprint-2-doc)
FPRINTD_PKGS=(fprintd)

ALL_PKGS=("${PLUGIN_PKGS[@]}" "${FPRINTD_PKGS[@]}" "${CORE_PKGS[@]}" "${EXTRA_PKGS[@]}")

say "Dropping holds (if any)…"
for p in "${ALL_PKGS[@]}"; do
  if [[ $UNHOLD -eq 1 ]]; then
    if is_held "$p"; then
      say "Unholding $p"
      run apt-mark unhold "$p"
    fi
  fi
done

if [[ "$MODE" == "plugin-only" ]]; then
  say "[PLUGIN-ONLY] Removing Goodix plugin packages…"
  for p in "${PLUGIN_PKGS[@]}"; do
    maybe_purge "$p"
  done
else
  say "[FULL] Removing fprintd, libfprint core + TOD, dev/gir/tests/docs…"
  for p in "${FPRINTD_PKGS[@]}" "${PLUGIN_PKGS[@]}" "${EXTRA_PKGS[@]}" "${CORE_PKGS[@]}"; do
    maybe_purge "$p"
  done
fi

say "Autoremoving residual dependencies…"
run apt-get autoremove --purge "${APT_YES[@]}" || true

# Local udev override (optional)
if [[ $REMOVE_LOCAL_UDEV -eq 1 ]]; then
  local_rule="/etc/udev/rules.d/61-libfprint-2-tod1-goodix-local.rules"
  if [[ -f "$local_rule" ]]; then
    say "Removing local udev rule: $local_rule"
    run rm -f "$local_rule"
  else
    warn "Local udev rule not present: $local_rule (skip)"
  fi
fi

say "Reloading udev rules and triggering…"
run udevadm control --reload
run udevadm trigger

# Reinstall repo core if asked
if [[ $REINSTALL_REPO -eq 1 ]]; then
  say "Reinstalling Debian repo libfprint-2-2 and fprintd…"
  run apt-get update
  run apt-get install "${APT_YES[@]}" libfprint-2-2 fprintd || warn "Reinstall from repo failed. Check APT sources."
fi

# Status summary
say "Final package status (dpkg -l | grep -E 'libfprint|fprintd'):"
run bash -c "dpkg -l | grep -E 'libfprint|fprintd' || true"

say "Done."
