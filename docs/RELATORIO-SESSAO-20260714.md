# Relatório de Sessão — Moonrider Android

**Data:** 2026-07-14
**Objetivo:** Criar versão Android do porte Moonrider (base:
`../portsmaster_on_rg40xxh/moonrider-portmaster-template/`).
**Alvo escolhido:** APK universal (gamepad físico + fallback touch), minSdk 21
(Android 5.0), targetSdk 34.
**Status:** ✅ APK debug gerado, assinado e verificado estaticamente.
Pendente: validação em device/emulador real.

---

## 1. Decisão arquitetural

O template muOS é ~90% infraestrutura para contornar o Linux fbdev puro do
RG40XX-H. No Android, **isso tudo é descartado**. O núcleo jogável é um export
Construct 2 (HTML5 puro): `index.html + c2runtime.js + data.js + media + images`.

Os 3 problemas-raiz que dominaram o porte muOS (documentados em
`ESTADO-DO-PROJETO.md` Atualizações 1–15) são resolvidos nativamente pelo
WebView/Chromium:

- **áudio .ogg** travava o WebProcess WPE → WebView toca nativo (sem ghost/mixer)
- **present quebrado (3 FPS)** → SurfaceFlinger + compositor Chromium
- **input evdev + latch** → Gamepad API nativa

Verificado no `c2runtime.js`: greenworks/Steam/require são condicionais a
`runtime.isNWjs` (false num WebView) → nunca executam, não quebram. O jogo usa
`navigator.getGamepads()` + eventos `gamepadconnected` padrão.

## 2. O que foi feito

1. **Assets**: reaproveitados da cópia local dos assets do jogo (build
   Construct 2/HTML5): 283 ogg + 1260 imagens.
   Copiados só os arquivos web (139M); Electron/greenworks/node_modules/.mp4
   omitidos.
2. **Toolchain**: instalado SDK enxuto em `.android-sdk/` (cmdline-tools +
   platform android-34 + build-tools 34.0.0 + platform-tools = 458M). **Sem
   Gradle** — build manual devido a disco apertado (99%).
3. **Projeto**:
   - `MainActivity.java`: WebView fullscreen, hardware-accel, immersive sticky,
     keep-screen-on, `mediaPlaybackRequiresUserGesture=false`, DOM storage on.
   - `LoggingChromeClient.java`: console JS → logcat (classe nomeada; ver
     pitfall d8 abaixo).
   - `index.html` adaptado: removido alert file://, viewport fullscreen, injeta
     `touch-controls.js`, service worker desabilitado.
   - `touch-controls.js`: overlay touch que sintetiza os keycodes NATIVOS do
     jogo (`38,40,37,39` + `90,88,83,67` + `13`), auto-esconde com gamepad.
   - `AndroidManifest.xml`: minSdk 21, landscape, gamepad opcional.
   - `build.sh`: aapt2 compile → link → javac → d8 → zipalign → apksigner.
4. **Build**: `build/Moonrider-debug.apk` — 127M, assinado v1/v2/v3, minSdk21,
   283 ogg + 1260 img + classes.dex confirmados via `aapt2 dump badging`.

## 3. Pitfalls resolvidos

- **d8 8.2.2 NPE** (`String.length()` em `MainActivity$1.class`): bug do d8 com
  classes anônimas compiladas pelo JDK 21 (EnclosingMethod nulo). **Fix**:
  transformar o `WebChromeClient` anônimo em classe nomeada
  (`LoggingChromeClient`).
- **d8 com .class soltos falhava**: empacotar em `classes.jar` antes de dexar.

## 4. Mapa de controle (de data.js)

```
Teclado default: ↑38 ↓40 ←37 →39  Z90 X88 S83 A65 C67 Y89  Enter13(menu)
```
Overlay touch: D-pad esq., A/B/X/Y dir., START/SEL topo.

## 5. Validação em device real (POCO X3 Pro / vayu, Android 13)

Instalado via `adb install -r` (streamed; incremental não suportado no ROM) e
testado em jogo:

- ✅ **Tela de título renderiza** (VENGEFUL GUARDIAN MOONRIDER, WebGL/Adreno)
- ✅ **Áudio funciona** (dumpsys audio: AAudio player PID do app,
  `usage=USAGE_MEDIA state:started`)
- ✅ **Overlay touch completo**: D-pad esq., X/Y/A/B dir., **L1/L2 topo-esq,
  R1/R2 topo-dir** (os 4 triggers nas laterais superiores, conforme pedido),
  SEL/START inferior-centro.

### Bug crítico encontrado e corrigido: vídeo de intro ausente
Na 1ª build a tela ficava **preta e sem som**. Causa: eu havia omitido todos os
`.mp4`, mas o jogo abre com o vídeo `asteristic_logo.mp4` (plugin Video do C2).
Sem ele, o C2 espera o vídeo terminar e nunca chega ao menu — e é esse primeiro
media/gesture que também destrava o contexto de áudio do WebView. **Fix**:
copiar `asteristic_logo.mp4` (3.9MB) para `assets/www/`. O `testdemo.mp4`
(217MB, attract) é opcional. Sintoma no logcat: lógica roda (CSVs, save) mas
nada renderiza + "Couldn't find language file" (efeito colateral do boot travado
— sumiu após incluir o vídeo).

### Correção do mapa de controle
Extraí o mapa real de `data.js` (`varConKB_DEFAULT` + ordem `temp_ButtonNames`):
`btA=Z90, btB=X88, btX=S83, btY=A65, btL1=C67, btR1=Y89`, menu=Enter13. Havia
mapeado btY errado (C em vez de A) — corrigido. L2/R2 sem tecla default → Q/E
como placeholder (remapeável no jogo).

## 6. Menu de opções ao vivo (overlay)

Botão engrenagem (⚙, canto sup. direito) abre um painel que altera tudo **ao
vivo** (JS) e persiste em `localStorage["mrOpts"]`. Arquivos:
`assets/www/settings.js` (patches de API) + `assets/www/options-menu.js` (UI).

Opções:
- **Trava de FPS** 30/60/90/120/Sem — gate por-callback (WeakMap) no
  `requestAnimationFrame`. CRÍTICO: o timestamp do gate é POR loop de animação,
  não global — um `lastFrame` global fazia o loop do jogo, o medidor de FPS e
  qualquer outro consumidor de rAF brigarem pelo gate (um zera o do outro),
  travando o render. Medido via CDP: cap 30→jogo a 30fps, 60→60fps, 0→120fps.
  (cap 90 assenta em 60: o C2 tem passo de simulação fixo; ainda assim 30 e 60
  travam certo, que é o essencial.)
- **Escala** Off/Auto/50/100/200/300/400/500% — `scaleMode`. Força
  `#c2canvasdiv`/`#c2canvas` a `NATIVE*(percent/100)` (Auto = maior múltiplo
  inteiro que cabe), centrado. Medido: 50→214px, 100→428px, 200→856px,
  500→2140px. Um `MutationObserver` no `style` reaplica porque o C2 reescreve o
  CSS de letterbox a cada resize. Migração automática do antigo `integerScale`
  bool → `scaleMode` ("auto"/"off").
- **Medidor de FPS** usa `rafNative` (não o wrapado) e mostra `rt.c2runtime.fps`
  (loop real do jogo), não o refresh de 120Hz do display, que confundia.
- **Suavização de pixels** — `image-rendering: pixelated|auto`.
- **Volume** 0–100% — GainNode master inserido interceptando
  `AudioContext.prototype.destination` (getter retorna nosso gain → realDest).
- **Áudio Estéreo/Mono** — downmix real via ChannelSplitter→ChannelMerger
  (média dos 2 canais nos dois outputs), religado ao alternar.
- **Mostrar FPS**, **Filtro CRT** (scanlines CSS `mix-blend-mode:multiply`),
  **Brilho** 50–150% (`filter:brightness`), **Vibração** (haptics nos toques,
  `navigator.vibrate`), **Manter tela acesa** (bridge nativo
  `MRAndroid.setKeepAwake` → FLAG_KEEP_SCREEN_ON), **Forçar overlay touch**
  (flag `MR_forceTouch` lido pelo `refresh()` do touch-controls).
- Botões: **Restaurar padrões** e **Voltar ao jogo**. Abrir o menu pausa o jogo
  via `cr_setSuspended(true)`; fechar retoma.

Ordem de scripts no `index.html` (crítica): `settings.js` **antes** do
`c2runtime.js` (precisa envolver rAF/AudioContext antes do engine capturá-los);
`options-menu.js` **depois** (só UI).

### Bridge nativo (novo arquivo)
`NativeBridge.java` — classe **top-level** (`@JavascriptInterface setKeepAwake`)
exposta como `window.MRAndroid`. **Pitfall d8 reconfirmado**: qualquer classe
inner/anônima (mesmo nomeada) dispara o NPE `String.length() null` no d8 8.2.2 +
JDK 21. Regra: **use apenas classes top-level** (LoggingChromeClient,
NativeBridge, KeepAwakeTask ficaram todas top-level ou static nested no arquivo
próprio).

### Pendente: teste ao vivo
APK rebuildado (131M) com o menu — **device caiu do adb no meio do teste**
(USB/tela). Reinstalar e validar cada opção quando reconectar:
`adb install -r build/Moonrider-debug.apk`, tocar na engrenagem, alternar FPS
(ver contador), integer scaling, mono, volume, CRT, brilho.

## 7. Localização

Projeto novo: `~/projects/moonrider-android/` (repo git próprio, per-project).
APK: `~/projects/moonrider-android/build/Moonrider-debug.apk`.
