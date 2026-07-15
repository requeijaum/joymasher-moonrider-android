#!/usr/bin/env bash
#
# extract-assets.sh - Extrai os assets Construct 2 do jogo (Vengeful Guardian:
#                     Moonrider) para uma pasta limpa, pronta para o apply.sh.
#
# O jogo comercial (Steam/GOG) e um app Electron: os assets do Construct 2
# (c2runtime.js, data.js, media/, images/, asteristic_logo.mp4) ficam DENTRO de
# resources/app.asar. Este script localiza e extrai esse asar — ou aceita uma
# pasta que ja tenha os assets soltos — e entrega tudo em um diretorio de saida.
#
# USO:
#   ./extract-assets.sh <entrada> [pasta-de-saida]
#
#   <entrada> pode ser:
#     * um arquivo app.asar
#     * a pasta de instalacao do jogo (contendo game/resources/app.asar,
#       resources/app.asar, ou o proprio app.asar em algum nivel)
#     * uma pasta que JA tem os assets extraidos (com c2runtime.js na raiz)
#
#   [pasta-de-saida]  padrao: ./game-assets/
#
# Depois:
#   ./apply.sh ./game-assets --build      # monta assets/www/ e builda o APK
#   # ou, num passo so:
#   ./extract-assets.sh <entrada> && ./apply.sh ./game-assets --build
#
# NENHUM asset comercial e distribuido com este repositorio. Voce fornece sua
# propria copia legitima do jogo.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IN="${1:-}"
OUT="${2:-$HERE/game-assets}"

# Assets que provam que chegamos na raiz certa do Construct 2.
REQUIRED=(c2runtime.js data.js asteristic_logo.mp4)
# Lixo Electron/NW.js/Steam que nao serve no Android (espelha o apply.sh).
JUNK_FILES=(main.js preload.js offline.js offlineClient.js user.js config.js
            greenworks.js package.json yarn.lock steam_appid.txt sw.js testdemo.mp4)
JUNK_DIRS=(greenworks node_modules steam_settings)

die()  { printf '\033[1;31mERRO:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m    %s\033[0m\n' "$*"; }

[ -n "$IN" ] || die "informe a entrada. Uso: ./extract-assets.sh <app.asar | pasta-do-jogo | pasta-extraida> [saida]"
[ -e "$IN" ] || die "entrada nao encontrada: $IN"

# Confere se um diretorio tem os assets essenciais na raiz.
has_assets() {
    local d="$1" f
    for f in "${REQUIRED[@]}"; do
        [ -e "$d/$f" ] || return 1
    done
    return 0
}

# Localiza um app.asar a partir da entrada (arquivo direto ou pasta de instalacao).
find_asar() {
    local base="$1"
    if [ -f "$base" ] && [[ "$base" == *.asar ]]; then
        printf '%s\n' "$base"; return 0
    fi
    if [ -d "$base" ]; then
        local cand
        for cand in \
            "$base/game/resources/app.asar" \
            "$base/resources/app.asar" \
            "$base/app.asar"; do
            [ -f "$cand" ] && { printf '%s\n' "$cand"; return 0; }
        done
        # busca em profundidade como ultimo recurso
        cand="$(find "$base" -maxdepth 5 -name app.asar -type f 2>/dev/null | head -1)"
        [ -n "$cand" ] && { printf '%s\n' "$cand"; return 0; }
    fi
    return 1
}

# Remove o lixo Electron/Steam de um diretorio de assets.
strip_junk() {
    local d="$1" j
    for j in "${JUNK_FILES[@]}"; do rm -f  "$d/$j"; done
    rm -f "$d"/greenworks-*.node
    for j in "${JUNK_DIRS[@]}";  do rm -rf "$d/$j"; done
}

# --------------------------------------------------------------------------
# Caso A: a entrada JA e uma pasta com os assets extraidos.
# --------------------------------------------------------------------------
if [ -d "$IN" ] && has_assets "$IN"; then
    info "entrada ja contem os assets extraidos (c2runtime.js encontrado)."
    SRC="$IN"
    COPY_MODE="dir"
else
    # ----------------------------------------------------------------------
    # Caso B: precisamos extrair de um app.asar.
    # ----------------------------------------------------------------------
    info "procurando app.asar em: $IN"
    ASAR="$(find_asar "$IN")" || die "nao achei app.asar nem assets soltos em '$IN'.
       Aponte para a pasta de instalacao do jogo, para o app.asar, ou para uma
       pasta ja extraida contendo c2runtime.js."
    ok "app.asar: $ASAR"

    command -v npx  >/dev/null 2>&1 || die "npx nao encontrado (instale Node.js >= 16: apt install nodejs npm)"

    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    info "extraindo app.asar (npx asar) ... isso pode levar ~1 min"
    # asar@3.2.0 funciona em Node 16-22; @electron/asar exige Node >= 22.12.
    npx --yes asar@3.2.0 extract "$ASAR" "$TMP/asar" \
        || npx --yes @electron/asar extract "$ASAR" "$TMP/asar" \
        || die "falha ao extrair o asar (nem asar@3.2.0 nem @electron/asar funcionaram)"

    # O Construct 2 costuma ficar na raiz do asar; se nao, procura a subpasta certa.
    if has_assets "$TMP/asar"; then
        SRC="$TMP/asar"
    else
        SUB="$(find "$TMP/asar" -maxdepth 4 -name c2runtime.js -type f 2>/dev/null | head -1)"
        [ -n "$SUB" ] || die "asar extraido, mas c2runtime.js nao encontrado dentro dele."
        SRC="$(dirname "$SUB")"
        ok "assets C2 encontrados em: ${SRC#$TMP/asar/}"
    fi
    COPY_MODE="dir"
fi

# --------------------------------------------------------------------------
# Copiar para a saida e limpar o lixo.
# --------------------------------------------------------------------------
has_assets "$SRC" || die "validacao final falhou: faltam assets essenciais em $SRC"

info "copiando assets para: $OUT"
mkdir -p "$OUT"
# preserva estrutura (media/, images/, .csv, .mp4, .js)
cp -a "$SRC/." "$OUT/"

info "removendo sobras Electron/NW.js/Steam (greenworks, node_modules, ...)"
strip_junk "$OUT"

# Verificacao final + resumo
for f in "${REQUIRED[@]}"; do
    [ -e "$OUT/$f" ] || die "pos-copia: asset essencial sumiu: $f"
done
ok "assets essenciais: OK (c2runtime.js, data.js, asteristic_logo.mp4)"
[ -d "$OUT/media" ]  && ok "media/:  presente" || echo "    AVISO: media/ ausente (audio pode faltar)"
[ -d "$OUT/images" ] && ok "images/: presente" || echo "    AVISO: images/ ausente (sprites podem faltar)"

echo
info "pronto. Assets limpos em: $OUT"
echo "    Tamanho: $(du -sh "$OUT" 2>/dev/null | cut -f1)"
echo
echo "Proximo passo:"
echo "    ./apply.sh \"$OUT\" --build        # monta assets/www/ e builda o APK"
echo "    ./make-apk.sh --mode docker \"$OUT\"  # build isolado em container Debian"
