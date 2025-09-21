#!/usr/bin/env bash
# install-tod-goodix.sh
# Installs libfprint (1.94.9+tod1) + TOD + Goodix plugin (53xc or 550a) from local .debs,
# automatically preferring the correct plugin based on USB ID (27c6:530c → 53xc; 27c6:550a → 550a).
# Designed for Debian 13 (trixie). Prevents conflicts between plugins.
#
# Usage:
#   sudo bash install-tod-goodix.sh [OUTDIR]
#
# Optional env variables:
#   INSTALL_DEV=1    -> also install -dev packages (headers) if available (default: 0)
#   HOLD=1           -> apply apt-mark hold on installed packages (default: 1)
#   TRY_FPRINTD=1    -> try to ensure fprintd/libpam-fprintd from repository (default: 1)
#   PREFER_PLUGIN=   -> force "53xc" or "550a" (overrides USB ID auto-detection)
#   DRY_RUN=1        -> show what would be executed without applying
#
# Exit codes:
#   0 = success; non-zero on error.
#
# Requirements:
#   - Must run as root
#   - OUTDIR must contain .debs for: libfprint-2-2_*.deb, libfprint-2-tod1_*.deb
#     and at least one plugin: libfprint-2-tod1-goodix-53xc_*.deb OR ...-550a_*.deb
#
set -Eeuo pipefail

# ---------- utils ----------
bblue="\033[1;34m"; byellow="\033[1;33m"; bred="\033[1;31m"; bgreen="\033[1;32m"; reset="\033[0m"
info(){ echo -e "${bblue}[INFO]${reset} $*"; }
warn(){ echo -e "${byellow}[WARN]${reset} $*"; }
err() { echo -e "${bred}[ERROR]${reset}  $*" >&2; }
ok()  { echo -e "${bgreen}[OK]${reset}   $*"; }

die(){ err "$*"; exit 1; }

run(){
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "+ $*"
  else
    eval "$@"
  fi
}

need_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "Please run as root (e.g., sudo $0 [OUTDIR])."
  fi
}

usage(){
  sed -n '1,120p' "$0"
}

# ---------- args ----------
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage; exit 0
fi

need_root

OUTDIR="${1:-${OUTDIR:-./out}}"
INSTALL_DEV="${INSTALL_DEV:-0}"
HOLD="${HOLD:-1}"
TRY_FPRINTD="${TRY_FPRINTD:-1}"
PREFER_PLUGIN="${PREFER_PLUGIN:-}"
DRY_RUN="${DRY_RUN:-0}"

[[ -d "$OUTDIR" ]] || die "OUTDIR directory does not exist: $OUTDIR"

# ---------- detect USB ID & choose plugin ----------
detect_usb_id(){
  # try lsusb; if not found, return empty
  if command -v lsusb >/dev/null 2>&1; then
    lsusb | awk '/27c6:/ {print $6; found=1} END{if(!found) exit 1}'
  else
    return 1
  fi
}

PLUGIN=""
if [[ -n "$PREFER_PLUGIN" ]]; then
  case "$PREFER_PLUGIN" in
    53xc|550a) PLUGIN="$PREFER_PLUGIN" ;;
    *) die "Invalid PREFER_PLUGIN: '$PREFER_PLUGIN' (use '53xc' or '550a')" ;;
  esac
else
  USB_ID="$(detect_usb_id || true)"
  if [[ -n "$USB_ID" ]]; then
    info "Detected USB ID: $USB_ID"
    case "$USB_ID" in
      27c6:530c|27c6:533c|27c6:538c|27c6:5840)
        PLUGIN="53xc"
        ;;
      27c6:550a)
        PLUGIN="550a"
        ;;
      *)
        warn "USB ID $USB_ID not mapped; defaulting to '53xc'."
        PLUGIN="53xc"
        ;;
    esac
  else
    warn "Unable to detect USB ID (lsusb unavailable or no Goodix device). Defaulting to '53xc'."
    PLUGIN="53xc"
  fi
fi

info "Preferred plugin: ${PLUGIN}"

# ---------- locate .debs ----------
shopt -s nullglob
LIBFPRINT_DEB=( "$OUTDIR"/libfprint-2-2_*.deb )
LIBFPRINT_TOD_DEB=( "$OUTDIR"/libfprint-2-tod1_*.deb )

PLUGIN_53_DEB=( "$OUTDIR"/libfprint-2-tod1-goodix-53xc_*.deb )
PLUGIN_55_DEB=( "$OUTDIR"/libfprint-2-tod1-goodix-550a_*.deb )

LIBFPRINT_DEV_DEB=( "$OUTDIR"/libfprint-2-dev_*.deb )
LIBFPRINT_TOD_DEV_DEB=( "$OUTDIR"/libfprint-2-tod1-dev_*.deb )

[[ ${#LIBFPRINT_DEB[@]} -ge 1 ]] || die "Could not find libfprint-2-2_*.deb in $OUTDIR"
[[ ${#LIBFPRINT_TOD_DEB[@]} -ge 1 ]] || die "Could not find libfprint-2-tod1_*.deb in $OUTDIR"

case "$PLUGIN" in
  53xc) [[ ${#PLUGIN_53_DEB[@]} -ge 1 ]] || die "Preferred 53xc, but libfprint-2-tod1-goodix-53xc_*.deb not found in $OUTDIR" ;;
  550a) [[ ${#PLUGIN_55_DEB[@]} -ge 1 ]] || die "Preferred 550a, but libfprint-2-tod1-goodix-550a_*.deb not found in $OUTDIR" ;;
esac

# choose the most recent package (lexical order usually matches version order)
pick_latest(){
  local arr=("$@")
  local n="${#arr[@]}"
  [[ "$n" -ge 1 ]] || return 1
  printf "%s\n" "${arr[@]}" | sort -V | tail -n1
}

LIBFPRINT_DEB_FILE="$(pick_latest "${LIBFPRINT_DEB[@]}")"
LIBFPRINT_TOD_DEB_FILE="$(pick_latest "${LIBFPRINT_TOD_DEB[@]}")"
if [[ "$PLUGIN" == "53xc" ]]; then
  PLUGIN_DEB_FILE="$(pick_latest "${PLUGIN_53_DEB[@]}")"
else
  PLUGIN_DEB_FILE="$(pick_latest "${PLUGIN_55_DEB[@]}")"
fi

# dev packages (optional)
LIBFPRINT_DEV_FILE=""; LIBFPRINT_TOD_DEV_FILE=""
if [[ "$INSTALL_DEV" == "1" ]]; then
  [[ ${#LIBFPRINT_DEV_DEB[@]} -ge 1 ]] && LIBFPRINT_DEV_FILE="$(pick_latest "${LIBFPRINT_DEV_DEB[@]}" || true)"
  [[ ${#LIBFPRINT_TOD_DEV_DEB[@]} -ge 1 ]] && LIBFPRINT_TOD_DEV_FILE="$(pick_latest "${LIBFPRINT_TOD_DEV_DEB[@]}" || true)"
fi

info "Selected packages:"
echo "  libfprint-2-2      : $LIBFPRINT_DEB_FILE"
echo "  libfprint-2-tod1   : $LIBFPRINT_TOD_DEB_FILE"
echo "  Goodix plugin      : $PLUGIN_DEB_FILE"
if [[ -n "$LIBFPRINT_DEV_FILE" || -n "$LIBFPRINT_TOD_DEV_FILE" ]]; then
  echo "  dev (optional)     : ${LIBFPRINT_DEV_FILE:-<none>} ; ${LIBFPRINT_TOD_DEV_FILE:-<none>}"
fi

# ---------- sanity & conflicts ----------
TOD_DIR="/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1"
OTHER_PLUGIN=$([[ "$PLUGIN" == "53xc" ]] && echo "550a" || echo "53xc"))
OTHER_PKG="libfprint-2-tod1-goodix-${OTHER_PLUGIN}"
THIS_PKG="libfprint-2-tod1-goodix-${PLUGIN}"

# remove conflicting plugin package if installed
remove_conflicting_pkg(){
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    warn "Removing conflicting package: $pkg"
    run "dpkg -r --force-depends $pkg"
  fi
}

# remove leftover conflicting .so library
remove_conflicting_so(){
  local other="$1"
  local so_pattern="${TOD_DIR}/libfprint-tod-goodix-${other}-*.so"
  if ls ${so_pattern} >/dev/null 2>&1; then
    warn "Removing conflicting .so: ${so_pattern}"
    run "rm -f ${so_pattern}"
  fi
}

# ensure minimal system dependencies to install .debs
prep_system(){
  run "apt-get update"
  # install lightweight but useful tools
  run "apt-get install -y --no-install-recommends udev ca-certificates"
}

# ensure fprintd/libpam-fprintd from repository (if missing)
ensure_fprintd_repo(){
  if [[ "$TRY_FPRINTD" == "1" ]]; then
    if ! dpkg -s fprintd >/dev/null 2>&1; then
      info "Installing fprintd from repository"
      run "apt-get install -y --no-install-recommends fprintd libpam-fprintd || true"
    fi
  fi
}

# ---------- installation ----------
prep_system
ensure_fprintd_repo

# stop fprintd service while modifying
run "systemctl stop fprintd 2>/dev/null || true"

# remove conflicting package and .so
remove_conflicting_pkg "$OTHER_PKG"
remove_conflicting_so "$OTHER_PLUGIN"

# install base libfprint and tod1 first (order matters)
info "Installing libfprint base"
run "dpkg -i '$LIBFPRINT_DEB_FILE' || apt-get -f install -y"
run "dpkg -i '$LIBFPRINT_TOD_DEB_FILE' || apt-get -f install -y"

# install chosen plugin
info "Installing Goodix plugin (${PLUGIN})"
run "dpkg -i '$PLUGIN_DEB_FILE' || apt-get -f install -y"

# install dev packages (optional)
if [[ -n "$LIBFPRINT_DEV_FILE" ]]; then
  info "Installing libfprint-2-dev"
  run "dpkg -i '$LIBFPRINT_DEV_FILE' || apt-get -f install -y"
fi
if [[ -n "$LIBFPRINT_TOD_DEV_FILE" ]]; then
  info "Installing libfprint-2-tod1-dev"
  run "dpkg -i '$LIBFPRINT_TOD_DEV_FILE' || apt-get -f install -y"
fi

# sweep again to ensure the other plugin is not present (in case some meta-package pulled it in)
remove_conflicting_pkg "$OTHER_PKG"
remove_conflicting_so "$OTHER_PLUGIN"

# hold packages to prevent overwriting by APT
if [[ "$HOLD" == "1" ]]; then
  info "Applying apt-mark hold"
  run "apt-mark hold libfprint-2-2 libfprint-2-tod1 $THIS_PKG fprintd libpam-fprintd 2>/dev/null || true"
fi

# reload udev and restart service
run "udevadm control --reload"
run "udevadm trigger"
run "systemctl daemon-reload"
run "systemctl restart fprintd || true"

# ---------- final check ----------
echo
ok "Installation completed."
echo "Verify:"
echo "  ls -l ${TOD_DIR}"
echo "  -> ONLY: libfprint-tod-goodix-${PLUGIN}-*.so should be present"
echo
echo "Test:"
echo '  LIBFPRINT_DEBUG=3 fprintd-enroll'
echo "  journalctl -u fprintd -b --no-pager -n 200"
echo
echo "Tips:"
echo "  - Simulate without applying: DRY_RUN=1 bash $0 $OUTDIR"
echo "  - Force plugin: PREFER_PLUGIN=53xc (or 550a)"
echo "  - Include -dev packages: INSTALL_DEV=1"
echo "  - Do not hold packages: HOLD=0"
echo
