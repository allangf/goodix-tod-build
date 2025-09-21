#!/usr/bin/env bash
set -euo pipefail

# clean.sh — reset builder artifacts and (optionally) host packages safely
#
# DEFAULT (no flags): clean project artifacts + stop docker compose service.
#
# Flags (combine as needed):
#   --artifacts              Remove ./out/*.deb and ephemeral build leftovers
#   --docker                 docker compose down -v (from repo root)
#   --prune-images           Also prune dangling Docker images (safe-ish)
#   --packages-old-plugin    Purge legacy package 'libfprint-2-tod1-goodix' (non -550a)
#   --packages-all           Purge ALL libfprint TOD/libfprint packages and fprintd (AGGRESSIVE)
#   --remove-local-udev-rule Remove /etc/udev/rules.d/61-libfprint-2-tod1-goodix-local.rules (if present)
#   --unhold                 apt-mark unhold libfprint/fprintd packages
#   --yes                    Do not ask for confirmations
#   --dry-run                Print actions but do not execute
#   --help                   Show help
#
# Examples:
#   # Typical project reset (artifacts + docker):
#   ./clean.sh --artifacts --docker
#
#   # Full reset of conflicting Goodix plugin generation:
#   ./clean.sh --artifacts --docker --packages-old-plugin --remove-local-udev-rule
#
#   # Nuclear reset (be careful!):
#   sudo ./clean.sh --packages-all --unhold --remove-local-udev-rule --yes
#
# Notes:
#   * Package operations require root (sudo). Non-root runs will skip them.
#   * We avoid broad 'docker system prune -a'. Use --prune-images to prune dangling images only.
#   * The script is idempotent and won’t fail if some targets are already absent.
#
# Keep scripts in English per project convention.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${REPO_ROOT}/out"

confirm() {
  local msg="$1"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  read -r -p "$msg [y/N] " ans || true
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

say()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; exit 1; }

is_root()      { [[ "$(id -u)" == "0" ]]; }
is_installed() { dpkg -s "$1" &>/dev/null; }
is_held()      { apt-mark showhold 2>/dev/null | grep -qx "$1"; }

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf "[dry-run] %s\n" "$*"
  else
    "$@"
  fi
}

docker_compose_cmd() {
  if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    echo "docker compose"
  elif command -v docker-compose &>/dev/null; then
    echo "docker-compose"
  else
    die "Docker Compose not found. Install Docker (v2 preferred)."
  fi
}

usage() {
  sed -n '1,80p' "$0" | sed -n '1,80p'
}

# Defaults
DO_ARTIFACTS=0
DO_DOCKER=0
DO_PRUNE_IMAGES=0
DO_PKG_OLD_PLUGIN=0
DO_PKG_ALL=0
DO_REMOVE_LOCAL_UDEV=0
DO_UNHOLD=0
ASSUME_YES=0
DRY_RUN=0

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifacts) DO_ARTIFACTS=1 ;;
    --docker) DO_DOCKER=1 ;;
    --prune-images) DO_PRUNE_IMAGES=1 ;;
    --packages-old-plugin) DO_PKG_OLD_PLUGIN=1 ;;
    --packages-all) DO_PKG_ALL=1 ;;
    --remove-local-udev-rule) DO_REMOVE_LOCAL_UDEV=1 ;;
    --unhold) DO_UNHOLD=1 ;;
    --yes) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown flag: $1 (use --help)";;
  esac
  shift
done

# If no flags, choose a safe default (artifacts + docker)
if [[ $DO_ARTIFACTS -eq 0 && $DO_DOCKER -eq 0 && $DO_PKG_OLD_PLUGIN -eq 0 && $DO_PKG_ALL -eq 0 && $DO_REMOVE_LOCAL_UDEV -eq 0 && $DO_UNHOLD -eq 0 && $DO_PRUNE_IMAGES -eq 0 ]]; then
  DO_ARTIFACTS=1
  DO_DOCKER=1
fi

# Actions
clean_artifacts() {
  say "Cleaning build artifacts in ${OUT_DIR}…"
  if [[ -d "$OUT_DIR" ]]; then
    run find "$OUT_DIR" -type f -name '*.deb' -print -delete
    # If you want to keep only latest series, you could selectively delete here.
  else
    warn "Output dir not found: $OUT_DIR (skipping)"
  fi
}

clean_docker() {
  local dc
  dc="$(docker_compose_cmd)"
  say "Stopping and removing compose services/volumes (from ${REPO_ROOT})…"
  ( cd "$REPO_ROOT" && run $dc down -v --remove-orphans )

  if [[ $DO_PRUNE_IMAGES -eq 1 ]]; then
    say "Pruning dangling Docker images (safe) …"
    run docker image prune -f
  else
    warn "Skipping image prune. Use --prune-images to remove dangling layers."
  fi
}

pkg_unhold_if_needed() {
  local pkg="$1"
  if is_held "$pkg"; then
    say "Unholding $pkg"
    run apt-mark unhold "$pkg"
  fi
}

pkg_remove_if_installed() {
  local pkg="$1"
  if is_installed "$pkg"; then
    say "Purging $pkg"
    run apt-get remove --purge -y "$pkg"
  else
    warn "$pkg not installed (skip)"
  fi
}

udev_reload_trigger() {
  say "Reloading udev rules and triggering…"
  run udevadm control --reload
  run udevadm trigger
}

remove_local_udev_rule() {
  local rule="/etc/udev/rules.d/61-libfprint-2-tod1-goodix-local.rules"
  if [[ -f "$rule" ]]; then
    say "Removing local udev rule: $rule"
    run rm -f "$rule"
    udev_reload_trigger
  else
    warn "Local udev rule not present: $rule (skip)"
  fi
}

packages_old_plugin() {
  if ! is_root; then
    warn "Not root; skipping package changes. Re-run with sudo for --packages-* actions."
    return 0
  fi
  say "Removing legacy 'libfprint-2-tod1-goodix' (non -550a)…"
  pkg_unhold_if_needed "libfprint-2-tod1-goodix"
  pkg_remove_if_installed "libfprint-2-tod1-goodix"
}

packages_all() {
  if ! is_root; then
    warn "Not root; skipping package changes. Re-run with sudo for --packages-all."
    return 0
  fi
  say "FULL RESET: removing all libfprint TOD/fprintd packages (AGGRESSIVE)."

  # Unhold (optional step also available via --unhold)
  for p in libfprint-2-2 libfprint-2-tod1 libfprint-2-tod1-goodix-550a libfprint-2-tod1-goodix libfprint-2-dev libfprint-2-tod-dev gir1.2-fprint-2.0 fprintd; do
    pkg_unhold_if_needed "$p"
  done

  # Purge packages
  for p in libfprint-2-tod1-goodix-550a libfprint-2-tod1-goodix fprintd libfprint-2-tod1 libfprint-2-2 libfprint-2-dev libfprint-2-tod-dev gir1.2-fprint-2.0 ; do
    pkg_remove_if_installed "$p"
  done

  # Autoremove leftovers
  say "Autoremoving residual dependencies…"
  run apt-get autoremove -y --purge || true

  udev_reload_trigger
}

unhold_all() {
  if ! is_root; then
    warn "Not root; skipping apt-mark changes. Re-run with sudo for --unhold."
    return 0
  fi
  say "Unholding libfprint/fprintd packages…"
  for p in libfprint-2-2 libfprint-2-tod1 libfprint-2-tod1-goodix-550a libfprint-2-tod1-goodix libfprint-2-dev libfprint-2-tod-dev gir1.2-fprint-2.0 fprintd; do
    pkg_unhold_if_needed "$p"
  done
}

# Confirm aggressive operations
if [[ $DO_PKG_ALL -eq 1 ]]; then
  confirm "You are about to purge libfprint/fprintd packages from this system. Continue?" || exit 1
fi

# Execute
[[ $DO_ARTIFACTS -eq 1 ]] && clean_artifacts
[[ $DO_DOCKER -eq 1   ]] && clean_docker
[[ $DO_PKG_OLD_PLUGIN -eq 1 ]] && packages_old_plugin
[[ $DO_PKG_ALL -eq 1 ]] && packages_all
[[ $DO_REMOVE_LOCAL_UDEV -eq 1 ]] && remove_local_udev_rule
[[ $DO_UNHOLD -eq 1 ]] && unhold_all

say "Done."
