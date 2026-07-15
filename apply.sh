#!/usr/bin/env bash
#
# apply.sh - Monta o projeto Android sobrepondo os arquivos do port aos assets
#            originais do jogo (Vengeful Guardian: Moonrider, build Construct 2).
#
# USO:
#   ./apply.sh /caminho/para/os/assets/do/jogo [--build]
#
# A "pasta de assets do jogo" e o diretorio que contem c2runtime.js, data.js,
# a pasta media/, images/, os .csv de localizacao e asteristic_logo.mp4 —
# extraidos da sua propria copia legitima do jogo (Construct 2 / HTML5).
#
# O script:
#   1. Valida que a pasta tem os assets essenciais.
#   2. Copia TODOS os assets do jogo para assets/www/ (nada comercial vai pro git).
#   3. Sobrepoe os overrides do port (dist/www-overrides/*).
#   4. Opcionalmente builda o APK (--build) chamando build.sh.
#
# Nenhum asset comercial e distribuido com este repositorio; voce precisa
# fornecer sua propria copia legitima do jogo.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GAME_DIR="${1:-}"
DO_BUILD="${2:-}"

die() { echo "ERRO: $*" >&2; exit 1; }

[ -n "$GAME_DIR" ] || die "informe a pasta com os assets do jogo. Uso: ./apply.sh <pasta-do-jogo> [--build]"
[ -d "$GAME_DIR" ] || die "pasta nao encontrada: $GAME_DIR"

# --- 1. validar assets essenciais -----------------------------------------
REQUIRED=(c2runtime.js data.js asteristic_logo.mp4)
for f in "${REQUIRED[@]}"; do
    [ -e "$GAME_DIR/$f" ] || die "asset essencial ausente em '$GAME_DIR': $f
       (essa nao parece a pasta do jogo Moonrider; procure onde estao c2runtime.js e data.js)"
done
echo "==> assets do jogo validados em: $GAME_DIR"

# --- 1b. verificar integridade (SHA-256) ----------------------------------
# Nao fatal: apenas alerta se algo divergir do conteudo esperado (dist/assets.sha256).
MANIFEST="$HERE/dist/assets.sha256"
if [ -f "$MANIFEST" ] && command -v sha256sum >/dev/null 2>&1; then
    echo "==> verificando integridade dos assets (SHA-256) ..."
    if ( cd "$GAME_DIR" && sha256sum -c "$MANIFEST" --quiet ) 2>/dev/null; then
        echo "    arquivos essenciais: OK"
    else
        echo "    AVISO: um ou mais arquivos divergem do manifesto esperado."
        echo "           (versao diferente do jogo? prossegue mesmo assim)"
    fi
    # hashes agregados de media/ e images/ (comparados aos valores no manifesto)
    for pair in "media a737afecbf6c388b09ab1cac7be124348befeade3211f3e45c4e1dacb5701919" \
                "images 359ceb439184ae644d30464f0f6332266cef1deae3188d1f9c580cca0e40e5fc"; do
        d="${pair%% *}"; want="${pair##* }"
        if [ -d "$GAME_DIR/$d" ]; then
            got=$( cd "$GAME_DIR" && find "$d" -type f | sort | xargs sha256sum | sha256sum | awk '{print $1}' )
            [ "$got" = "$want" ] && echo "    $d/: OK" || echo "    AVISO: $d/ diverge (esperado $want, obtido $got)"
        fi
    done
fi

# --- 2. copiar assets do jogo ---------------------------------------------
WWW="$HERE/assets/www"
mkdir -p "$WWW"
echo "==> copiando assets do jogo para assets/www/ ..."
# copia tudo do jogo (js, csv, png, mp4, media/, images/) preservando estrutura
cp -a "$GAME_DIR/." "$WWW/"

# remove sobras do build Electron/NW.js/Steam que nao servem no Android (opcional)
for junk in main.js preload.js offline.js offlineClient.js user.js config.js \
            greenworks.js greenworks-*.node package.json yarn.lock steam_appid.txt \
            sw.js testdemo.mp4; do
    rm -f "$WWW/$junk"
done
# diretorios de dependencias nativas/Steam (greenworks/, node_modules/, steam_settings/):
# binarios .node de Windows/Linux/macOS que so incham o APK — o WebView nunca os usa.
# (mantido em sincronia com JUNK_DIRS do extract-assets.sh)
for junkdir in greenworks node_modules steam_settings; do
    rm -rf "$WWW/$junkdir"
done

# --- 3. sobrepor os overrides do port -------------------------------------
echo "==> aplicando overrides do port (index.html + settings/options/touch) ..."
cp -f "$HERE/dist/www-overrides/index.html"       "$WWW/index.html"
cp -f "$HERE/dist/www-overrides/settings.js"      "$WWW/settings.js"
cp -f "$HERE/dist/www-overrides/options-menu.js"  "$WWW/options-menu.js"
cp -f "$HERE/dist/www-overrides/touch-controls.js" "$WWW/touch-controls.js"

echo "==> pronto. assets/www/ montado com o port aplicado."

# --- 4. build opcional -----------------------------------------------------
if [ "$DO_BUILD" = "--build" ] || [ "$GAME_DIR" = "--build" ]; then
    [ -x "$HERE/build.sh" ] || die "build.sh nao encontrado/executavel"
    echo "==> iniciando build do APK ..."
    ( cd "$HERE" && ./build.sh )
    echo "==> APK gerado em build/Moonrider-debug.apk"
else
    echo "    Para gerar o APK agora:  ./build.sh"
    echo "    Ou rode:                 ./apply.sh \"$GAME_DIR\" --build"
fi
