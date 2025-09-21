#!/usr/bin/env bash
# uninstall-tod-goodix.sh
# Remove COMPLETELY any Goodix TOD plugin (53xc/550a) installed from local .debs,
# clean leftover .so files and local udev rules, undo apt holds, and (optionally)
# repair the system by reinstalling base packages from the repository.
#
# Usage:
#   sudo bash uninstall-tod-goodix.sh [--yes] [--full] [--repair] [--keep-holds] [--purge]
#
# Flags:
#   --yes           : non-interactive (assume "yes" to prompts)
#   --full          : also remove libfprint-2-2/libfprint-2-tod1 *from local installs* if present,
#                     then reinstall base from repo unless --purge is used.
#   --repair        : force reinstall of base from repo (fprintd, libpam-fprintd, libfprint-2-2, libfprint-2-tod1)
#   --keep-holds    : DO NOT unhold packages (default behavior is to unhold)
#   --purge         : purge all related packages (fprintd, libpam-fprintd, libfprint-2-2, libfprint-2-tod1, plugins)
#                     WARNING: this disables the fingerprint stack entirely.
#   --dry-run       : show actions without applying
#
# Environment vars (alternative to flags):
#   YES=1           → --yes
#   FULL=1          → --full
#   REPAIR=1        → --repair
#   KEEP_HOLDS=1    → --keep-holds
#   PURGE=1         → --purge
#   DRY_RUN=1       → --dry-run
#
# Exit codes:
#   0 success; !=0 on error
#
set -Eeuo pipefail

# ---------- utils ----------
bblue="\033[1;34m"; byellow="\033[1;33m"; bred="\033[1;31m"; bgreen="\033[1;32m"; reset="\033[0m"
info(){ echo -e "${bblue}[INFO]${reset} $*"; }
warn(){ echo -e "${byellow}[WARN]${reset} $*"; }
err() { echo -e "${bred}[ERROR]${reset} $*" >&2; }
ok()  { echo -e "${bgreen}[OK]${reset} $*"; }

die(){ err "$*"; exit 1; }

run(){
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "+ $*"
  else
    eval "$@"
  fi
}

need_root(){
  # Use id -u instead of $EUID to avoid "parameter not set" in sh
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Please run as root (e.g., sudo $0)"
  fi
}

confirm(){
  local prompt="$1"
  if [[ "${YES:-0}" == "1" || "$ASSUME_YES" == "1" ]]; then
    return 0
  fi
  read -r -p "$prompt [y/N] " ans || true
  [[ "${ans:-}" =~ ^[Yy]$ ]]
}

usage(){
  sed -n '1,120p' "$0"
}

# ---------- args ----------
ASSUME_YES="0"; DO_FULL="0"; DO_REPAIR="0"; KEEP_HOLDS="0"; DO_PURGE="0"; DRY_RUN="${DRY_RUN:-0}"

for a in "$@"; do
  case "$a" in
    --yes) ASSUME_YES="1" ;;
    --full) DO_FULL="1" ;;
    --repair) DO_REPAIR="1" ;;
    --keep-holds) KEEP_HOLDS="1" ;;
    --purge) DO_PURGE="1" ;;
    --dry-run) DRY_RUN="1" ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown flag: $a"; usage; exit 2 ;;
  esac
done

# env fallbacks
[[ "${YES:-0}" == "1" ]] && ASSUME_YES="1"
[[ "${FULL:-0}" == "1" ]] && DO_FULL="1"
[[ "${REPAIR:-0}" == "1" ]] && DO_REPAIR="1"
[[ "${KEEP_HOLDS:-0}" == "1" ]] && KEEP_HOLDS="1"
[[ "${PURGE:-0}" == "1" ]] && DO_PURGE="1"

need_root

# ---------- constants ----------
TOD_DIR="/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1"
PLUGINS=( "libfprint-2-tod1-goodix-53xc" "libfprint-2-tod1-goodix-550a" )
BASE_PKGS=( "libfprint-2-2" "libfprint-2-tod1" )
STACK_PKGS=( "fprintd" "libpam-fprintd" )
ALL_PKGS=( "${STACK_PKGS[@]}" "${BASE_PKGS[@]}" "${PLUGINS[@]}" )

RULES=(
  "/lib/udev/rules.d/60-libfprint-2-tod1-goodix-53xc.rules"
  "/lib/udev/rules.d/60-libfprint-2-tod1-goodix-550a.rules"
  "/etc/udev/rules.d/60-libfprint-2-tod1-goodix-53xc.rules"
  "/etc/udev/rules.d/60-libfprint-2-tod1-goodix-550a.rules"
  "/etc/udev/rules.d/61-libfprint-2-tod1-goodix-local.rules"
  "/lib/udev/rules.d/61-libfprint-2-tod1-goodix-local.rules"
)

# ---------- helpers ----------
pkg_installed(){
  dpkg -s "$1" >/dev/null 2>&1
}

apt_unhold(){
  local pkgs=("$@")
  for p in "${pkgs[@]}"; do
    if apt-mark showhold | grep -qx "$p"; then
      info "Removing hold: $p"
      run "apt-mark unhold '$p' || true"
    fi
  done
}

apt_hold(){
  local pkgs=("$@")
  for p in "${pkgs[@]}"; do
    run "apt-mark hold '$p' 2>/dev/null || true"
  done
}

remove_pkg_soft(){
  local p="$1"
  if pkg_installed "$p"; then
    info "Removing package: $p"
    run "dpkg -r --force-depends '$p' || true"
  fi
}

purge_pkg(){
  local p="$1"
  if dpkg -l | awk '{print $2}' | grep -qx "$p"; then
    info "Purging package: $p"
    run "apt-get purge -y '$p' || true"
  fi
}

# ---------- actions ----------
info "Stopping fprintd (if running)"
run "systemctl stop fprintd 2>/dev/null || true"

# undo holds (unless KEEP_HOLDS)
if [[ "$KEEP_HOLDS" != "1" ]]; then
  apt_unhold "${ALL_PKGS[@]}"
else
  warn "Keeping APT holds (KEEP_HOLDS=1)."
fi

# remove plugins
for p in "${PLUGINS[@]}"; do
  remove_pkg_soft "$p"
done

# remove stray .so files
for so in "${TOD_DIR}"/libfprint-tod-goodix-53xc-*.so "${TOD_DIR}"/libfprint-tod-goodix-550a-*.so; do
  if [[ -e "$so" ]]; then
    warn "Removing leftover: $so"
    run "rm -f '$so'"
  fi
done

# cleanup udev rules
for r in "${RULES[@]}"; do
  if [[ -e "$r" ]]; then
    warn "Removing udev rule: $r"
    run "rm -f '$r'"
  fi
done

# full or purge?
if [[ "$DO_PURGE" == "1" ]]; then
  if confirm "You requested --purge. This will remove the entire fingerprint stack (fprintd/libpam/libfprint). Continue?"; then
    for p in "${ALL_PKGS[@]}"; do
      purge_pkg "$p"
    done
  else
    warn "Purge canceled by user."
  fi
else
  if [[ "$DO_FULL" == "1" ]]; then
    info "Removing libfprint base (--full mode)"
    for p in "${BASE_PKGS[@]}"; do
      remove_pkg_soft "$p"
    done
    # fprintd/libpam can be reinstalled below if requested
  fi
fi

# repair (reinstall from repo)
if [[ "$DO_REPAIR" == "1" && "$DO_PURGE" != "1" ]]; then
  info "Updating APT indexes"
  run "apt-get update"

  info "Reinstalling base from repository"
  run "apt-get install -y --no-install-recommends ${STACK_PKGS[*]} ${BASE_PKGS[*]} || true"
fi

# udev & service refresh
run "udevadm control --reload"
run "udevadm trigger"
run "systemctl daemon-reload"
run "systemctl restart fprintd 2>/dev/null || true"

echo
ok "Uninstall/cleanup completed."
echo "Suggested checks:"
echo "  - ls -l ${TOD_DIR}    # there should be no leftover Goodix .so"
echo "  - dpkg -l | egrep 'fprint|libfprint|goodix'"
echo
echo "Useful combos:"
echo "  * Repair everything from repo:  sudo bash $0 --full --repair --yes"
echo "  * Full purge (danger):          sudo bash $0 --purge --yes"
echo "  * Remove plugins only:          sudo bash $0 --yes"
echo "  * Keep holds:                   sudo bash $0 --keep-holds --yes"
echo "  * Dry run / simulate:           DRY_RUN=1 sudo bash $0 --full"
