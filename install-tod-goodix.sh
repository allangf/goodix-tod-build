#!/usr/bin/env bash
# install-tod-goodix.sh
# Instala libfprint (1.94.9+tod1) + TOD + plugin Goodix (53xc ou 550a) a partir de .debs locais,
# preferindo automaticamente o plugin correto pelo USB ID (27c6:530c → 53xc; 27c6:550a → 550a).
# Projetado para Debian 13 (trixie). Evita conflitos entre plugins.
#
# Uso:
#   sudo bash install-tod-goodix.sh [OUTDIR]
#
# Variáveis opcionais (env):
#   INSTALL_DEV=1    -> também instala pacotes -dev (headers) se existirem (padrão: 0)
#   HOLD=1           -> aplica apt-mark hold nos pacotes instalados (padrão: 1)
#   TRY_FPRINTD=1    -> tenta garantir fprintd/libpam-fprintd do repositório (padrão: 1)
#   PREFER_PLUGIN=   -> força "53xc" ou "550a" (sobrepõe autodetecção por USB ID)
#   DRY_RUN=1        -> mostra o que faria, sem aplicar
#
# Retornos:
#   0 = sucesso; !=0 em caso de erro.
#
# Requisitos:
#   - Executar como root
#   - OUTDIR deve conter .debs de: libfprint-2-2_*.deb, libfprint-2-tod1_*.deb
#     e pelo menos um dos plugins: libfprint-2-tod1-goodix-53xc_*.deb OU ...-550a_*.deb
#
set -Eeuo pipefail

# ---------- utils ----------
bblue="\033[1;34m"; byellow="\033[1;33m"; bred="\033[1;31m"; bgreen="\033[1;32m"; reset="\033[0m"
info(){ echo -e "${bblue}[INFO]${reset} $*"; }
warn(){ echo -e "${byellow}[WARN]${reset} $*"; }
err() { echo -e "${bred}[ERRO]${reset}  $*" >&2; }
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
    die "Por favor, execute como root (ex.: sudo $0 [OUTDIR])."
  fi
}

usage(){
  sed -n '1,80p' "$0"
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

[[ -d "$OUTDIR" ]] || die "Diretório OUTDIR não existe: $OUTDIR"

# ---------- detecta USB ID & escolhe plugin ----------
detect_usb_id(){
  # tenta lsusb; se não achar, vazio
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
    *) die "PREFER_PLUGIN inválido: '$PREFER_PLUGIN' (use '53xc' ou '550a')" ;;
  esac
else
  USB_ID="$(detect_usb_id || true)"
  if [[ -n "$USB_ID" ]]; then
    info "USB ID detectado: $USB_ID"
    case "$USB_ID" in
      27c6:530c|27c6:533c|27c6:538c|27c6:5840)
        PLUGIN="53xc"
        ;;
      27c6:550a)
        PLUGIN="550a"
        ;;
      *)
        warn "USB ID $USB_ID não mapeado; assumindo '53xc' por padrão."
        PLUGIN="53xc"
        ;;
    esac
  else
    warn "Não foi possível detectar USB ID (lsusb indisponível ou sem dispositivo Goodix). Padrão: '53xc'."
    PLUGIN="53xc"
  fi
fi

info "Plugin preferido: ${PLUGIN}"

# ---------- localiza .debs ----------
shopt -s nullglob
LIBFPRINT_DEB=( "$OUTDIR"/libfprint-2-2_*.deb )
LIBFPRINT_TOD_DEB=( "$OUTDIR"/libfprint-2-tod1_*.deb )

PLUGIN_53_DEB=( "$OUTDIR"/libfprint-2-tod1-goodix-53xc_*.deb )
PLUGIN_55_DEB=( "$OUTDIR"/libfprint-2-tod1-goodix-550a_*.deb )

LIBFPRINT_DEV_DEB=( "$OUTDIR"/libfprint-2-dev_*.deb )
LIBFPRINT_TOD_DEV_DEB=( "$OUTDIR"/libfprint-2-tod1-dev_*.deb )

[[ ${#LIBFPRINT_DEB[@]} -ge 1 ]] || die "Não encontrei libfprint-2-2_*.deb em $OUTDIR"
[[ ${#LIBFPRINT_TOD_DEB[@]} -ge 1 ]] || die "Não encontrei libfprint-2-tod1_*.deb em $OUTDIR"

case "$PLUGIN" in
  53xc) [[ ${#PLUGIN_53_DEB[@]} -ge 1 ]] || die "Preferido 53xc, mas não encontrei libfprint-2-tod1-goodix-53xc_*.deb em $OUTDIR" ;;
  550a) [[ ${#PLUGIN_55_DEB[@]} -ge 1 ]] || die "Preferido 550a, mas não encontrei libfprint-2-tod1-goodix-550a_*.deb em $OUTDIR" ;;
esac

# escolhe o mais recente (ordem lexical já costuma refletir versão)
pick_latest(){
  local arr=("$@")
  local n="${#arr[@]}"
  [[ "$n" -ge 1 ]] || return 1
  # simple: pega o último em sort
  printf "%s\n" "${arr[@]}" | sort -V | tail -n1
}

LIBFPRINT_DEB_FILE="$(pick_latest "${LIBFPRINT_DEB[@]}")"
LIBFPRINT_TOD_DEB_FILE="$(pick_latest "${LIBFPRINT_TOD_DEB[@]}")"
if [[ "$PLUGIN" == "53xc" ]]; then
  PLUGIN_DEB_FILE="$(pick_latest "${PLUGIN_53_DEB[@]}")"
else
  PLUGIN_DEB_FILE="$(pick_latest "${PLUGIN_55_DEB[@]}")"
fi

# devs (opcional)
LIBFPRINT_DEV_FILE=""; LIBFPRINT_TOD_DEV_FILE=""
if [[ "$INSTALL_DEV" == "1" ]]; then
  [[ ${#LIBFPRINT_DEV_DEB[@]} -ge 1 ]] && LIBFPRINT_DEV_FILE="$(pick_latest "${LIBFPRINT_DEV_DEB[@]}" || true)"
  [[ ${#LIBFPRINT_TOD_DEV_DEB[@]} -ge 1 ]] && LIBFPRINT_TOD_DEV_FILE="$(pick_latest "${LIBFPRINT_TOD_DEV_DEB[@]}" || true)"
fi

info "Selecionados:"
echo "  libfprint-2-2      : $LIBFPRINT_DEB_FILE"
echo "  libfprint-2-tod1   : $LIBFPRINT_TOD_DEB_FILE"
echo "  plugin Goodix      : $PLUGIN_DEB_FILE"
if [[ -n "$LIBFPRINT_DEV_FILE" || -n "$LIBFPRINT_TOD_DEV_FILE" ]]; then
  echo "  dev (opcionais)    : ${LIBFPRINT_DEV_FILE:-<none>} ; ${LIBFPRINT_TOD_DEV_FILE:-<none>}"
fi

# ---------- sanity & conflitos ----------
TOD_DIR="/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1"
OTHER_PLUGIN=$([[ "$PLUGIN" == "53xc" ]] && echo "550a" || echo "53xc")
OTHER_PKG="libfprint-2-tod1-goodix-${OTHER_PLUGIN}"
THIS_PKG="libfprint-2-tod1-goodix-${PLUGIN}"

# remove plugin conflitante se instalado
remove_conflicting_pkg(){
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    warn "Removendo pacote conflitante: $pkg"
    run "dpkg -r --force-depends $pkg"
  fi
}

# apaga .so conflitante remanescente
remove_conflicting_so(){
  local other="$1"
  local so_pattern="${TOD_DIR}/libfprint-tod-goodix-${other}-*.so"
  if ls ${so_pattern} >/dev/null 2>&1; then
    warn "Removendo .so conflitante: ${so_pattern}"
    run "rm -f ${so_pattern}"
  fi
}

# garante dependências mínimas de sistema para instalar .debs
prep_system(){
  run "apt-get update"
  # ferramentas úteis mas leves
  run "apt-get install -y --no-install-recommends udev ca-certificates"
}

# instala fprintd/libpam-fprintd do repo (se faltando)
ensure_fprintd_repo(){
  if [[ "$TRY_FPRINTD" == "1" ]]; then
    if ! dpkg -s fprintd >/dev/null 2>&1; then
      info "Instalando fprintd do repositório"
      run "apt-get install -y --no-install-recommends fprintd libpam-fprintd || true"
    fi
  fi
}

# ---------- instalação ----------
prep_system
ensure_fprintd_repo

# evitar serviço enquanto mexemos
run "systemctl stop fprintd 2>/dev/null || true"

# remove pacotes conflitantes e sobras de .so
remove_conflicting_pkg "$OTHER_PKG"
remove_conflicting_so "$OTHER_PLUGIN"

# instala base libfprint e tod1 primeiro (ordem importante)
info "Instalando base libfprint"
run "dpkg -i '$LIBFPRINT_DEB_FILE' || apt-get -f install -y"
run "dpkg -i '$LIBFPRINT_TOD_DEB_FILE' || apt-get -f install -y"

# instala plugin escolhido
info "Instalando plugin Goodix (${PLUGIN})"
run "dpkg -i '$PLUGIN_DEB_FILE' || apt-get -f install -y"

# instala devs (opcional)
if [[ -n "$LIBFPRINT_DEV_FILE" ]]; then
  info "Instalando libfprint-2-dev"
  run "dpkg -i '$LIBFPRINT_DEV_FILE' || apt-get -f install -y"
fi
if [[ -n "$LIBFPRINT_TOD_DEV_FILE" ]]; then
  info "Instalando libfprint-2-tod1-dev"
  run "dpkg -i '$LIBFPRINT_TOD_DEV_FILE' || apt-get -f install -y"
fi

# varre e garante que o outro plugin não está presente (caso algum metapacote tenha trazido)
remove_conflicting_pkg "$OTHER_PKG"
remove_conflicting_so "$OTHER_PLUGIN"

# hold para evitar sobrescritas pelo APT
if [[ "$HOLD" == "1" ]]; then
  info "Aplicando apt-mark hold"
  run "apt-mark hold libfprint-2-2 libfprint-2-tod1 $THIS_PKG fprintd libpam-fprintd 2>/dev/null || true"
fi

# udev & serviço
run "udevadm control --reload"
run "udevadm trigger"
run "systemctl daemon-reload"
run "systemctl restart fprintd || true"

# verificação final
echo
ok "Instalação concluída."
echo "Verifique:"
echo "  ls -l ${TOD_DIR}"
echo "  -> deve haver APENAS: libfprint-tod-goodix-${PLUGIN}-*.so"
echo
echo "Teste:"
echo "  LIBFPRINT_DEBUG=3 fprintd-enroll"
echo "  journalctl -u fprintd -b --no-pager -n 200"
echo
echo "Dicas:"
echo "  - Para simular sem aplicar: DRY_RUN=1 bash $0 $OUTDIR"
echo "  - Para forçar plugin: PREFER_PLUGIN=53xc (ou 550a)"
echo "  - Para incluir pacotes -dev: INSTALL_DEV=1"
echo "  - Para não aplicar hold: HOLD=0"
echo
