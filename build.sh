#!/usr/bin/env bash
set -euo pipefail

# ===================== Mandatory configuration via ARG/ENV =====================
: "${LIBFPRINT_DSC_URL:?Define LIBFPRINT_DSC_URL (URL of the .dsc for libfprint +tod1)}"
: "${GOODIX_REPO_URL:?Define GOODIX_REPO_URL (repo of the goodix plugin)}"
: "${GOODIX_BRANCH:=ubuntu/noble-devel}"

# To skip GPG verification of the .dsc, export: DGET_NO_CHECK=1
: "${DGET_NO_CHECK:=0}"

# Uploader key listed in the .dsc (Steve Langasek – Ubuntu)
: "${UBUNTU_UPLOADER_KEY:=AC483F68DE728F43F2202FCA568D30F321B2133D}"

# Suffix/Dist to harmonize with Debian 13 (trixie)
: "${DIST_NAME:=trixie}"
: "${LOCAL_SUFFIX:=~trixie1}"

export DEBIAN_FRONTEND=noninteractive
export DCH_FORCE_MAINTAINER=1
export DEBFULLNAME="local builder"
export DEBEMAIL="builder@local"

log()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
info() { printf "    %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; }
die()  { err "$*"; exit 1; }
run()  { "$@" || die "Command failed: \"$*\"."; }

trap 'err "Unexpected failure. Check logs above."; exit 1' ERR

log "Variables in use:"
info "LIBFPRINT_DSC_URL = ${LIBFPRINT_DSC_URL}"
info "GOODIX_REPO_URL   = ${GOODIX_REPO_URL}"
info "GOODIX_BRANCH     = ${GOODIX_BRANCH}"
info "DGET_NO_CHECK     = ${DGET_NO_CHECK}"
info "DIST_NAME         = ${DIST_NAME}"
info "LOCAL_SUFFIX      = ${LOCAL_SUFFIX}"

mkdir -p /out
cd /build

# ========================= GPG / Keyrings utilities ==========================
prepare_gnupg() { mkdir -p /root/.gnupg && chmod 700 /root/.gnupg; }

import_uploader_key() {
  command -v gpg >/dev/null 2>&1 || return 1
  local fp_main="${UBUNTU_UPLOADER_KEY:-AC483F68DE728F43F2202FCA568D30F321B2133D}"
  # chave antiga/alternativa vista no log:
  local fp_alt="${UBUNTU_UPLOADER_KEY_ALT:-5759F35001AA4A64}"

  prepare_gnupg

  echo "==> Importing uploader key(s) from keyserver.ubuntu.com…"
  # 1) tentar hkps (443)
  gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$fp_main" || true
  # 2) tentar hkp (porta 80) — útil em ambientes que bloqueiam TLS do dirmngr
  gpg --batch --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "$fp_main" || true

  # 3) se ainda não veio, buscar por e-mail (puxa todas as chaves do mantenedor)
  if ! gpg --list-keys "$fp_main" >/dev/null 2>&1; then
    gpg --batch --keyserver hkps://keyserver.ubuntu.com --search-keys "steve.langasek@ubuntu.com" <<<'y' || true
  fi

  # 4) importar fingerprint alternativo visto na sua saída, só para garantir
  gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$fp_alt" || true
  gpg --batch --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "$fp_alt" || true

  # 5) último recurso: baixar a chave armorizada direto do endpoint do Ubuntu
  if ! gpg --list-keys "$fp_main" >/dev/null 2>&1; then
    echo "==> Fallback: fetching armored key for $fp_main"
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${fp_main}" \
      | gpg --import || true
  fi

  # sucesso se, e somente se, a chave principal estiver presente
  gpg --list-keys "$fp_main" >/dev/null 2>&1
}

# ============================== Download source ===============================
fetch_src() {
  log "(1/6) Downloading and extracting libfprint TOD source."
  if [[ "${DGET_NO_CHECK}" = "1" ]]; then
    info "[INFO] DGET_NO_CHECK=1 -> skipping GPG verification of .dsc"
    run dget -u -x "${LIBFPRINT_DSC_URL}"
    return
  fi

  if ! command -v dget >/dev/null 2>&1; then
    warn "dget not found; using dpkg-source without GPG verification."
    local dsc="$(basename "${LIBFPRINT_DSC_URL}")"
    run wget -q "${LIBFPRINT_DSC_URL}"
    run dpkg-source -x "${dsc}"
    return
  fi

  prepare_gnupg
  if import_uploader_key && dget -x "${LIBFPRINT_DSC_URL}"; then
    return
  fi
  die "Failed to verify .dsc GPG signature. To proceed without verification, run with DGET_NO_CHECK=1."
}

find_src_dir() {
  local dir
  dir="$(find . -maxdepth 1 -type d -name 'libfprint-*+tod1' | head -n1 || true)"
  [[ -n "${dir}" ]] || die "libfprint +tod1 source directory not found."
  printf "%s\n" "${dir}"
}

# ============================ Meson/PC (udev) patches ========================
patch_meson_udev_dep() {
  # Safe replace: dependency('udev') -> dependency('libudev')
  local root="$1"
  while IFS= read -r -d '' f; do
    sed -i "s/dependency('udev')/dependency('libudev')/g" "$f"
  done < <(find "$root" -type f \( -name 'meson.build' -o -name 'meson_options.txt' \) -print0)
}

ensure_libudev_pc_vars() {
  # Shim libudev.pc to expose udevdir/udevrulesdir (when missing)
  local sys_pc
  sys_pc="$(pkg-config --variable=pcfiledir libudev 2>/dev/null || true)"
  [[ -n "${sys_pc}" ]] || die "libudev.pc not found."
  local src_pc="${sys_pc}/libudev.pc"
  [[ -f "${src_pc}" ]] || die "File libudev.pc not found in ${sys_pc}."

  local dst_dir="/usr/local/lib/pkgconfig"
  local dst_pc="${dst_dir}/libudev.pc"
  mkdir -p "${dst_dir}"
  if [[ ! -f "${dst_pc}" ]]; then
    cp -f "${src_pc}" "${dst_pc}"
    grep -q '^udevdir='      "${dst_pc}" || echo "udevdir=\${prefix}/lib/udev"       >> "${dst_pc}"
    grep -q '^udevrulesdir=' "${dst_pc}" || echo "udevrulesdir=\${udevdir}/rules.d" >> "${dst_pc}"
  fi
  export PKG_CONFIG_PATH="${dst_dir}:${PKG_CONFIG_PATH-}"
}

# ============================ Version/Distribution ===========================
normalize_version_changelog() {
  local pkgdir="$1"
  command -v dch >/dev/null 2>&1 || { warn "dch not found; skipping changelog normalization."; return 0; }
  (
    cd "${pkgdir}"
    local cur ver
    cur="$(dpkg-parsechangelog -SVersion)"
    ver="${cur%%-*}-0${LOCAL_SUFFIX}"
    dch --force-distribution --force-bad-version -b -v "${ver}" --distribution "${DIST_NAME}" "Rebuild for Debian ${DIST_NAME} (was ${cur})."
  )
}

# =============================== Build core TOD ===============================
build_core() {
  log "(2/6) Preparing and compiling libfprint-2-tod1 (core TOD)."
  local src_dir="$1"

  log "Applying core adjustments:"
  sed -i 's/\bsystemd-dev\b/libsystemd-dev/g' "${src_dir}/debian/control" || true
  patch_meson_udev_dep "${src_dir}"
  ensure_libudev_pc_vars
  normalize_version_changelog "${src_dir}"

  ( cd "${src_dir}" && dpkg-buildpackage -us -uc -b )
  find "${src_dir}/.." -maxdepth 1 -type f -name '*.deb' -exec cp -v {} /out/ \;
  log "[OK] Core packages copied to /out"
}

# ============ Install core packages locally to build plugin ==================
install_core_locals() {
  log "(3/6) Installing locally built packages required for plugin."
  apt-get update -qq
  run apt-get install -y /out/*.deb || true
  for pkg in gir1.2-fprint-2.0 libfprint-2-2 libfprint-2-dev libfprint-2-tod1 libfprint-2-tod-dev; do
    local deb
    deb="$(ls -1 /out/${pkg}_*.deb 2>/dev/null | head -n1 || true)"
    [[ -n "${deb}" ]] && run apt-get install -y "$deb" || true
    apt-mark hold "$pkg" >/dev/null 2>&1 || true
  done
  info "Headers, runtime and GIR locally installed and held."
}

# ============================== Build Goodix plugin ==========================
clone_and_patch_goodix() {
  log "(4/6) Cloning and patching Goodix plugin..."
  local try_branches=("${GOODIX_BRANCH}" "ubuntu/noble" "ubuntu/noble-devel" "ubuntu/mantic" "debian/sid" "main" "master")
  rm -rf goodix || true
  local ok=0 chosen_branch=""
  for br in "${try_branches[@]}"; do
    info "Trying branch: ${br}"
    for attempt in 1 2 3; do
      rm -rf goodix || true
      if git clone --depth=1 --branch "${br}" "${GOODIX_REPO_URL}" goodix; then ok=1; chosen_branch="${br}"; break; fi
      warn "Failed (attempt ${attempt}/3). Retrying..."; sleep 2
    done
    [[ "${ok}" = "1" ]] && break
  done
  [[ "${ok}" = "1" ]] || die "Could not clone ${GOODIX_REPO_URL} on any known branch."
  info "[OK] Successfully cloned (branch: ${chosen_branch})"
  cd goodix

  sed -i 's/, *dh-modaliases//g' debian/control || true
  sed -Ei 's/(--with(=|[[:space:]]*)modaliases)//g' debian/rules || true
  sed -i 's/\bsystemd-dev\b/libsystemd-dev/g' debian/control || true

  patch_meson_udev_dep "."
  ensure_libudev_pc_vars
  normalize_version_changelog "."
}

precheck_goodix_builddeps() {
  log "(5/6) Pre-validating plugin build-deps..."
  apt-get -qq update
  apt-get -y build-dep . || true
}

build_goodix() {
  log "(6/6) Building libfprint-2-tod1-goodix (plugin)."
  if ! dpkg-buildpackage -us -uc -b; then
    warn "Plugin build failed. Build-deps from repository:"
    apt-get -s build-dep . || true
    die "Plugin compilation failed (see messages above)."
  fi
  cd ..
  find . -maxdepth 1 -type f -name '*.deb' -exec cp -v {} /out/ \;
  log "[OK] Plugin packages copied to /out"
}

# ================================= Pipeline ==================================
fetch_src
SRC_DIR="$(find_src_dir)"

if ! pkg-config --exists libudev && ! pkg-config --exists udev; then
  die "libudev.pc (or alias udev.pc) not found. Install libudev-dev."
fi

build_core "${SRC_DIR}"
install_core_locals
clone_and_patch_goodix
precheck_goodix_builddeps
build_goodix

log "Artifacts ready in /out:"
ls -lh /out

log "==> Build completed successfully. All packages generated and copied to /out."
