# Relatório de Sessão — Moonrider Android

**Data:** 14 de julho de 2026
**Projeto:** `moonrider-android` — porte Android de *Vengeful Guardian: Moonrider*
**Repositório:** github.com/requeijaum/joymasher-moonrider-android

---

## 1. Resumo

Esta sessão partiu de um porte WebView já funcional (APK universal do jogo
Construct 2/HTML5 rodando em WebView nativo, com overlay de opções ao vivo) e o
levou a um estado publicável: novas funcionalidades no menu, endurecimento de
segurança, empacotamento distribuível sem assets comerciais, licenciamento,
ícone, identificação precisa da versão dos assets e publicação no GitHub.

Todo o trabalho foi versionado em commits atômicos e enviado ao repositório
remoto. O código do porte é o único conteúdo versionado — **nenhum asset do jogo
é incluído ou redistribuído**; o usuário fornece a própria cópia legítima dos
assets para montar o APK.

---

## 2. O que foi feito

### 2.1 Menu de opções — valores custom
- Adicionado um botão `…` nas linhas **Trava de FPS** e **Escala** do menu ⚙.
- Cada botão abre um campo numérico inline (Enter confirma, Esc cancela) que
  aceita qualquer valor — FPS 10–240, escala 25–1000%.
- O motor já suportava valores arbitrários; o trabalho foi expor a UI ligada ao
  mesmo mecanismo (gate de FPS por-callback; escala por `width/height/margins`).
- Validado ao vivo em device: FPS custom 45 → cap age (jogo a 40, quantizado pelo
  timestep do C2); escala custom 175% → canvas 749px (= 428 × 1,75). Persistência
  em `localStorage` confirmada.

### 2.2 Correções e endurecimento
- **Back com dupla-batida para sair:** um toque em Voltar avisa; um segundo em até
  2s fecha o app. Válvula de segurança caso o menu/bridge falhe — o usuário nunca
  fica preso.
- **Removido `setAllowUniversalAccessFromFileURLs`:** reduz a superfície de ataque
  do WebView (o app é totalmente offline).
- Presets de FPS 90/120 mantidos: são honestos em hardware de alta taxa; o device
  de teste satura em 60 por limite do timestep do engine, não por bug.

### 2.3 Empacotamento distribuível (sem assets comerciais)
- Constatação-chave: a engine (`c2runtime.js`) e os dados (`data.js`) são idênticos
  ao build original; o único arquivo web original modificado é o `index.html`.
- Criado `dist/www-overrides/` com os quatro arquivos do porte (index.html,
  settings.js, options-menu.js, touch-controls.js) e `dist/index.html.diff` (diff
  unificado do index.html, com rótulos neutros).
- Criado `apply.sh <pasta-de-assets> [--build]`: valida os assets essenciais,
  verifica integridade (SHA-256), copia os assets para `assets/www/`, sobrepõe os
  overrides do porte e, opcionalmente, gera o APK — pipeline completo num comando.

### 2.4 Integridade dos assets
- Gerado `dist/assets.sha256`: hashes SHA-256 dos 19 arquivos essenciais (engine,
  dados, 10 CSVs de idioma, 4 CSVs de dados, intro) e hashes agregados das pastas
  `media/` (287 arquivos: 283 .ogg + 4 .m4a) e `images/` (1260 arquivos).
- O `apply.sh` executa a verificação automaticamente (aviso não-fatal em caso de
  divergência). Permite ao usuário confirmar a integridade da própria cópia sem
  redistribuir qualquer conteúdo.

### 2.5 Higiene do repositório
- `.gitignore` reescrito para bloquear todos os assets do jogo (engine, dados,
  áudio .ogg/.m4a, sprites, CSVs, ícones do jogo) e o SDK local/artefatos de build.
- Retirados do rastreio os assets que estavam indexados (`git rm --cached`,
  sem apagar do disco). Confirmado: nenhum asset comercial rastreado.
- Limpeza de APKs intermediários do diretório `build/` (~390 MB recuperados).

### 2.6 Licenciamento
- Adicionado `LICENSE.md` (Apache License 2.0) e `NOTICE`.
- Escolha do Apache 2.0 sobre MIT: concessão explícita de patente (relevante para
  um porte de interoperabilidade), atribuição robusta via NOTICE e isenção de
  marca.
- O `NOTICE` delimita que a licença cobre **somente o código autoral do porte** e
  exclui explicitamente os assets do jogo, atribuídos aos titulares (JoyMasher /
  The Arcade Crew / Asteristic Game Studio). jQuery registrado como MIT.

### 2.7 Ícone do app
- Copiado o ícone custom (PNG 256×256) para `docs/icon.png`, gerado nas 5
  densidades do launcher (mdpi 48 → xxxhdpi 192) e empacotado no APK.
- Exibido no topo do README com legenda de atribuição em itálico.

### 2.8 README
- Traduzido para inglês e depois enxugado ao essencial (de ~324 para ~110 linhas):
  requisitos, build, instalação, descrição do porte, menu de opções, verificação
  de integridade, roadmap e seção legal.
- Roadmap com 5 itens (i18n do menu, troca de idioma do jogo, remap de gamepad,
  feedback do overlay touch, cheats) e prioridade sugerida.

### 2.9 Identificação da versão dos assets
- Comparação com as lojas oficiais (Steam AppID 1942010, GOG): mesmo jogo, mesma
  data de lançamento (12 Jan 2023), 10 idiomas, mesmos titulares.
- Com o histórico de builds da Steam (dois builds no total), a versão dos assets
  foi cravada como o **build de lançamento** (BuildID 10293244, 12 Jan 2023), e
  **não** o patch posterior (BuildID 10710596, 28 Mar 2023).
- Três marcadores independentes confirmam: `steam_appid.txt` ainda presente (o
  patch o removeu), ausência de `CRT.ini` (o patch o adicionou) e ausência das
  faixas de música de boss introduzidas pelo patch. O patch posterior foi
  majoritariamente correções, balanceamento e um CRT exclusivo de Windows — pouco
  relevante para este porte.

### 2.10 Publicação
- Configurado o remote `origin` (SSH) e enviado todo o histórico ao GitHub.
- Verificação de segurança pré-push: nenhum arquivo de asset comercial no índice
  (busca por engine, dados, .ogg, .m4a, media/, images/, CSVs → zero resultados).
- Publicados 27 arquivos (~476 KB): código do porte, tooling de distribuição,
  documentação, licença, NOTICE e ícones.

---

## 3. Estado atual

- APK buildado, instalado e validado em device real (POCO X3 Pro, Android 13).
- Repositório publicado, working tree limpo, local sincronizado com o remoto.
- Código do porte licenciado (Apache 2.0); assets do jogo fora do versionamento.
- Versão dos assets identificada (build de lançamento).

## 4. Compatibilidade

- `minSdkVersion` 21 (Android 5.0), `targetSdkVersion`/`compileSdkVersion` 34.
- Cobertura Android 5.0–14+. Features declaradas como opcionais (gamepad,
  touchscreen, USB host, landscape) — sem filtragem por hardware.
- Validado apenas em Android 13; o piso minSdk 21 é declarado mas não testado em
  hardware Android 5–6.

## 5. Pendências (roadmap — não implementadas)

1. **i18n do menu** — strings do overlay ainda em PT hardcoded.
2. **Troca de idioma do jogo** — raiz identificada (o jogo lê `navigator.language`
   sem seletor próprio); plano é sobrescrever esse valor antes do boot + reload.
3. **Menu de remap de gamepad** — o jogo tem remap nativo; falta confirmar
   navegabilidade via gamepad físico no WebView.
4. **Feedback do overlay touch** — botões sem estado visual de "pressionado" nem
   pulso tátil.
5. **Cheats** (opcional) — slow-mo é simples; invencibilidade depende de localizar
   a variável de HP no event sheet ofuscado.

---

*Projeto não-oficial, sem afiliação com JoyMasher / The Arcade Crew / Asteristic
Game Studio. Todos os assets do jogo são propriedade de seus respectivos
titulares e devem ser fornecidos pelo usuário a partir de sua própria cópia
legítima.*
