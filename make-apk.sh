#!/usr/bin/env bash
#
# make-apk.sh - Helper interativo para buildar o APK do Moonrider Android.
#
# Oferece dois caminhos:
#   * docker    - tudo dentro de um container Debian; nao instala nada no host
#                 (alem do proprio Docker). Reutiliza .android-sdk/ e os assets
#                 via bind-mount.
#   * baremetal - instala as dependencias (JDK + utilitarios) no sistema via
#                 apt e builda direto no host.
#
# Nos dois casos, se .android-sdk/ ainda nao estiver populado, o script faz o
# bootstrap (cmdline-tools -> platform-tools, platforms;android-34,
# build-tools;34.0.0) automaticamente.
#
# USO:
#   ./make-apk.sh                         # modo interativo (pergunta tudo)
#   ./make-apk.sh --mode docker    <assets-dir>
#   ./make-apk.sh --mode baremetal <assets-dir>
#   ./make-apk.sh --help
#
# NENHUM asset comercial e distribuido aqui: <assets-dir> e a SUA copia legitima
# do jogo (pasta com c2runtime.js, data.js, asteristic_logo.mp4, media/, ...).
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SDK="$HERE/.android-sdk"
IMAGE="moonrider-build"

# Componentes exigidos pelo build.sh (mantenha em sincronia com ele).
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
SDK_PACKAGES=("platform-tools" "platforms;android-34" "build-tools;34.0.0")

c_blue()  { printf '\033[1;34m%s\033[0m\n' "$*"; }
c_green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_yellow(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
die()     { printf '\033[1;31mERRO:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# --------------------------------------------------------------------------
# Parse de argumentos
# --------------------------------------------------------------------------
MODE=""
ASSETS_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --mode)  MODE="${2:-}"; shift 2 ;;
        --mode=*) MODE="${1#*=}"; shift ;;
        -h|--help) usage 0 ;;
        --*) die "opcao desconhecida: $1 (use --help)" ;;
        *)   [ -z "$ASSETS_DIR" ] && ASSETS_DIR="$1" || die "argumento extra: $1"; shift ;;
    esac
done

# --------------------------------------------------------------------------
# Modo interativo (se nao veio por flag)
# --------------------------------------------------------------------------
if [ -z "$MODE" ]; then
    c_blue "Como voce quer buildar o APK?"
    echo "  1) docker    - tudo num container Debian, nada instalado no host"
    echo "  2) baremetal - instala JDK + deps no sistema (apt) e builda direto"
    printf "Escolha [1/2]: "
    read -r choice
    case "$choice" in
        1) MODE="docker" ;;
        2) MODE="baremetal" ;;
        *) die "escolha invalida" ;;
    esac
fi

case "$MODE" in docker|baremetal) ;; *) die "modo invalido: '$MODE' (use docker ou baremetal)";; esac

# --------------------------------------------------------------------------
# Pasta de assets do jogo
# --------------------------------------------------------------------------
if [ -z "$ASSETS_DIR" ]; then
    c_blue "Onde estao os assets do jogo (pasta com c2runtime.js, data.js, asteristic_logo.mp4)?"
    printf "Caminho: "
    read -r ASSETS_DIR
fi
ASSETS_DIR="${ASSETS_DIR/#\~/$HOME}"
[ -n "$ASSETS_DIR" ] || die "voce precisa informar a pasta de assets do jogo"
[ -d "$ASSETS_DIR" ] || die "pasta de assets nao encontrada: $ASSETS_DIR"
for f in c2runtime.js data.js asteristic_logo.mp4; do
    [ -e "$ASSETS_DIR/$f" ] || die "asset essencial ausente em '$ASSETS_DIR': $f (essa nao parece a pasta do jogo)"
done
ASSETS_DIR="$(cd "$ASSETS_DIR" && pwd)"   # normaliza para caminho absoluto
c_green "Assets do jogo: $ASSETS_DIR"

# ==========================================================================
# Funcoes compartilhadas
# ==========================================================================

# Bootstrap do Android SDK dentro de $SDK. Idempotente: so baixa o que falta.
# Roda tanto no host (baremetal) quanto dentro do container (docker), por isso
# so depende de: curl, unzip, e um JDK (para o sdkmanager).
bootstrap_sdk() {
    local bt="$SDK/build-tools/34.0.0/aapt2"
    local plat="$SDK/platforms/android-34/android.jar"
    if [ -f "$bt" ] && [ -f "$plat" ]; then
        c_green "SDK ja presente em .android-sdk/ (build-tools 34.0.0 + platform 34)."
        return 0
    fi

    c_yellow "SDK incompleto - fazendo bootstrap em .android-sdk/ ..."
    local sdkmgr="$SDK/cmdline-tools/latest/bin/sdkmanager"
    if [ ! -x "$sdkmgr" ]; then
        c_blue "==> baixando cmdline-tools ..."
        mkdir -p "$SDK/cmdline-tools"
        local tmp; tmp="$(mktemp -d)"
        curl -fL -o "$tmp/cmdline-tools.zip" "$CMDLINE_TOOLS_URL"
        unzip -q "$tmp/cmdline-tools.zip" -d "$tmp"
        rm -rf "$SDK/cmdline-tools/latest"
        mv "$tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
        rm -rf "$tmp"
    fi

    c_blue "==> aceitando licencas e instalando pacotes do SDK ..."
    yes | "$sdkmgr" --sdk_root="$SDK" --licenses >/dev/null 2>&1 || true
    "$sdkmgr" --sdk_root="$SDK" "${SDK_PACKAGES[@]}"

    [ -f "$bt" ]   || die "bootstrap falhou: aapt2 nao encontrado apos instalar build-tools"
    [ -f "$plat" ] || die "bootstrap falhou: android.jar nao encontrado apos instalar a platform"
    c_green "SDK pronto."
}

# ==========================================================================
# MODO BAREMETAL
# ==========================================================================
run_baremetal() {
    c_blue "=== Modo baremetal ==="

    # 1. dependencias de sistema
    local need=()
    command -v javac    >/dev/null 2>&1 || need+=("openjdk-21-jdk-headless")
    command -v zip      >/dev/null 2>&1 || need+=("zip")
    command -v unzip    >/dev/null 2>&1 || need+=("unzip")
    command -v curl     >/dev/null 2>&1 || need+=("curl")
    command -v sha256sum>/dev/null 2>&1 || need+=("coreutils")

    if [ ${#need[@]} -gt 0 ]; then
        if command -v apt-get >/dev/null 2>&1; then
            c_yellow "Instalando dependencias via apt: ${need[*]}"
            local SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
            $SUDO apt-get update
            $SUDO apt-get install -y --no-install-recommends "${need[@]}"
        else
            die "faltam dependencias (${need[*]}) e este host nao usa apt. Instale-as manualmente."
        fi
    else
        c_green "Dependencias de sistema ja presentes (JDK, zip, unzip, curl)."
    fi

    command -v javac >/dev/null 2>&1 || die "javac ainda ausente apos a instalacao"

    # 2. SDK
    bootstrap_sdk

    # 3. build
    c_blue "==> montando assets e buildando (apply.sh --build) ..."
    "$HERE/apply.sh" "$ASSETS_DIR" --build
}

# ==========================================================================
# MODO DOCKER
# ==========================================================================
run_docker() {
    c_blue "=== Modo docker ==="
    command -v docker >/dev/null 2>&1 || die "docker nao encontrado no host"
    docker info >/dev/null 2>&1 || die "o daemon do Docker nao esta acessivel (permissao? 'sudo usermod -aG docker \$USER' ou rode com sudo)"
    [ -f "$HERE/Dockerfile.build" ] || die "Dockerfile.build nao encontrado no repo"

    c_blue "==> construindo a imagem '$IMAGE' ..."
    docker build -f "$HERE/Dockerfile.build" -t "$IMAGE" "$HERE"

    # Roda o helper de novo DENTRO do container, em modo baremetal: la o apt e o
    # bootstrap do SDK acontecem no ambiente isolado do container, escrevendo em
    # .android-sdk/ (bind-mount) para reuso posterior. Os assets entram read-only.
    # --user com o UID/GID do host: evita que build/, .android-sdk/ e debug.keystore
    # saiam pertencendo a root (senao o host nao consegue limpar/rebuildar sem sudo).
    # HOME=/tmp: gravavel por qualquer UID (sdkmanager escreve ~/.android).
    c_blue "==> buildando dentro do container (como UID $(id -u):$(id -g)) ..."
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -e HOME=/tmp \
        -v "$HERE":/app \
        -v "$ASSETS_DIR":/assets:ro \
        -w /app \
        "$IMAGE" \
        ./make-apk.sh --mode baremetal /assets
}

# ==========================================================================
case "$MODE" in
    baremetal) run_baremetal ;;
    docker)    run_docker ;;
esac

APK="$HERE/build/Moonrider-debug.apk"
if [ -f "$APK" ]; then
    echo
    c_green "APK gerado: $APK"
    ls -lh "$APK"
    echo
    echo "Instalar no dispositivo (USB debugging ligado):"
    echo "  ${SDK}/platform-tools/adb install -r \"$APK\""
else
    die "o build terminou mas o APK nao foi encontrado em $APK"
fi
