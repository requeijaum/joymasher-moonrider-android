# Moonrider Android

Porte Android de **Vengeful Guardian: Moonrider** (jogo Construct 2/HTML5) para
um APK universal via WebView nativo. Empacota o mesmo app Construct 2 usado no
porte muOS/PortMaster (`../portsmaster_on_rg40xxh/`), mas no Android **toda a
infraestrutura de contorno do muOS desaparece**: sem WPE WebKit, sem backend
Mali-fbdev, sem audio-ghost, sem mixer miniaudio nativo, sem bridge evdev.

O WebView (Chromium do sistema, atualizável a partir do Android 5.0) resolve
nativamente os três problemas-raiz que consumiram o porte muOS:

| Problema no muOS | Solução no Android |
|---|---|
| decode de `.ogg` travava o WebProcess | WebView toca `<audio>`/WebAudio nativo |
| present/frame_complete quebrado (3 FPS) | SurfaceFlinger + compositor Chromium |
| input via evdev + latch anti-borda | Gamepad API nativa do Chromium |

## Alvo

- **APK universal**: detecta gamepad físico (handheld Android, controle BT) e,
  quando não há, mostra um overlay touch on-screen.
- **minSdk 21 (Android 5.0)**, targetSdk 34.
- Orientação landscape, immersive fullscreen, tela sempre acesa.

## Arquitetura

```
assets/www/               <- app Construct 2 (mesmo do porte muOS)
  index.html              <- adaptado: sem alert file://, viewport fullscreen,
                             injeta touch-controls.js, SW desabilitado
  touch-controls.js       <- overlay touch -> dispara os keycodes NATIVOS do jogo
  c2runtime.js, data.js   <- runtime + event sheet originais (intocados)
  jquery-3.4.1.min.js
  media/*.ogg (283)       <- áudio
  images/ (1260)          <- sprites
src/.../MainActivity.java  <- WebView fullscreen, hardware-accel, immersive
src/.../LoggingChromeClient.java <- console JS -> logcat
AndroidManifest.xml        <- minSdk21, landscape, gamepad opcional
build.sh                   <- build manual (aapt2+javac+d8+zipalign+apksigner)
```

### Controles

O jogo já suporta teclado nativamente. Mapa default (de `data.js`
`varConKB_DEFAULT`/`_MENU`):

```
↑=38  ↓=40  ←=37  →=39
Z=90  X=88  S=83  A=65  C=67  Y=89   Enter=13 (confirmar menu)
```

- **Gamepad físico**: lido direto pela Gamepad API do C2 (`navigator.getGamepads`).
  O overlay touch some automaticamente quando um gamepad conecta.
- **Touch**: `touch-controls.js` sintetiza `keydown`/`keyup` reais desses
  keycodes — sem tocar no engine. Layout: D-pad à esquerda, botões A/B/X/Y à
  direita, START/SEL no topo.

## Build

Não usa Gradle (build manual enxuto). Requer o SDK local em `.android-sdk/`
(cmdline-tools + platform android-34 + build-tools 34.0.0), já instalado.

```bash
./build.sh
# -> build/Moonrider-debug.apk
```

## Instalar / testar

```bash
adb install -r build/Moonrider-debug.apk
adb logcat -s MoonriderJS   # ver console JS do jogo
```

## Notas

- Os assets são propriedade da JoyMasher/The Arcade Crew; **não versionar** o
  conteúdo de `assets/www/media` e `assets/www/images` publicamente.
- Saves usam `localStorage` (origin `file://`), persistente entre execuções.
- Ficheiros Electron/Steam (greenworks, main.js, node_modules, .mp4) foram
  deliberadamente omitidos: o código Steam no `c2runtime.js` é condicional a
  `runtime.isNWjs` (false num WebView), então nunca executa.
- APK ~127M por causa dos assets. Para reduzir: recomprimir `.ogg`/sprites.

## Pendente (validação em device real)

✅ **Validado em device real** (POCO X3 Pro / vayu, LineageOS, Android 13):
tela de título renderiza (WebGL/Adreno), áudio toca (AAudio player USAGE_MEDIA
started), overlay touch completo com os 4 shoulders (L1/L2 topo-esq, R1/R2
topo-dir). Ver `docs/RELATORIO-SESSAO-20260714.md`.

### Pitfall crítico: vídeo de intro é OBRIGATÓRIO
O jogo abre com o vídeo `asteristic_logo.mp4` (plugin Video do C2). Se ele
faltar, o app fica em **tela preta e sem som** — o C2 espera o vídeo terminar
antes de avançar ao menu, e é o primeiro user-gesture/mídia que destrava o
contexto de áudio do WebView. **Sempre copiar `asteristic_logo.mp4` (3.9MB)**
para `assets/www/`. O `testdemo.mp4` (217MB, attract/demo) é opcional.

## Menu de opções ao vivo (⚙)

Botão de engrenagem no canto superior direito abre um painel que aplica tudo
**ao vivo** (JavaScript) e salva em `localStorage`:

| Opção | Efeito |
|-------|--------|
| Trava de FPS | 30 / 60 / 90 / 120 / Sem trava — gate por-callback no requestAnimationFrame (medido: cap 30→30fps, 60→60fps) |
| Escala | Off / Auto / 50 / 100 / 200 / 300 / 400 / 500% da resolução nativa 428×240 (pixels perfeitos; medido: 100%→428px, 200%→856px, 500%→2140px) |
| Suavização de pixels | nearest (nítido) vs linear |
| Volume | 0–100% (GainNode master no WebAudio) |
| Áudio | Estéreo / Mono (downmix real via channel merger) |
| Mostrar FPS | Contador no topo |
| Filtro CRT | Scanlines retrô |
| Brilho | 50–150% |
| Vibração | Haptics nos botões touch |
| Manter tela acesa | Bridge nativo FLAG_KEEP_SCREEN_ON |
| Forçar overlay touch | Botões visíveis mesmo com gamepad |
| **Sair do jogo** | Fecha o app (Activity.finish) via bridge nativo — o "Quit" do menu do jogo chama uma API NW.js/Electron inexistente no WebView e não funciona |

Arquivos: `assets/www/settings.js` (patches de API, carregado ANTES do
c2runtime) + `assets/www/options-menu.js` (UI). Abrir o menu pausa o jogo.
