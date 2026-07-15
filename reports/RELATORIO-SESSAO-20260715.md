# Relatório de Sessão — Moonrider Android

**Data:** 15 de julho de 2026
**Projeto:** `moonrider-android` — porte Android de *Vengeful Guardian: Moonrider*
**Repositório:** github.com/requeijaum/joymasher-moonrider-android

---

## 1. Resumo

Esta sessão levou o projeto de "porte publicado" a "pipeline de build completo,
reproduzível e documentado de ponta a ponta". Partindo do build APK entregue na
sessão anterior, foram automatizadas as duas pontas que ainda eram manuais —
extração dos assets e orquestração do build —, corrigidos dois defeitos reais
descobertos por revisão, e o pipeline inteiro foi reproduzido do zero numa
máquina de build Linux separada para provar que funciona.

Todo o trabalho foi versionado em commits atômicos e enviado ao remoto. O código
do porte e o tooling continuam sendo o único conteúdo versionado — **nenhum asset
comercial é incluído ou redistribuído**.

---

## 2. O que foi feito

### 2.1 Novo script `extract-assets.sh`
- Extrai os assets Construct 2 de dentro do `resources/app.asar` do jogo Electron
  para uma pasta limpa, pronta para o `apply.sh`.
- Aceita três formas de entrada: o `app.asar` direto, a pasta de instalação do
  jogo (localiza o asar sozinho) ou uma pasta já extraída (valida e copia).
- Usa `npx asar@3.2.0` (fallback `@electron/asar`), valida os assets essenciais
  antes e depois, e remove todo o lixo Electron/Steam.
- A pasta de saída padrão (`game-assets/`) foi adicionada ao `.gitignore` para
  que assets comerciais extraídos nunca sejam commitados por acidente.

### 2.2 Novo helper de build `make-apk.sh`
- Build num comando, com dois modos: **docker** (container Debian isolado, nada
  instalado no host) e **baremetal** (instala deps via apt e builda direto).
- Bootstrap idempotente do Android SDK (baixa cmdline-tools, instala
  platform-tools + platforms;android-34 + build-tools;34.0.0) — um clone novo
  builda do zero sem setup manual do SDK.
- Acompanha o `Dockerfile.build` (Debian trixie + JDK + utilitários de shell); o
  SDK e os assets entram por bind-mount, nunca são copiados para a imagem.

### 2.3 Correção — lixo Electron/Steam vazando para o APK
- **Defeito:** o `apply.sh` removia apenas os arquivos `greenworks` na raiz do
  www, mas o asar também carrega as subpastas `greenworks/`, `node_modules/` e
  `steam_settings/`, com binários `.node` de Windows/Linux/macOS. Esse conteúdo
  entrava no APK sem nunca ser carregado pelo WebView (~6 MB de peso morto).
- **Correção:** `apply.sh` e `extract-assets.sh` agora removem esses diretórios.

### 2.4 Correção — artefatos de build pertencendo a root
- **Defeito:** no modo docker o container rodava como root e escrevia no
  bind-mount, deixando `build/`, `.android-sdk/` e o keystore de debug com dono
  root — impossível limpar/rebuildar no host sem privilégio elevado.
- **Correção:** o `make-apk.sh` passa `--user` com o UID/GID do host (e um HOME
  gravável para o `sdkmanager`), então os artefatos saem com o dono correto.
- Estado herdado do build anterior foi reparado de forma não-destrutiva via
  ajuste de posse pelo próprio container, sem apagar nada.

### 2.5 Achado — `testdemo.mp4` é peso morto (erro de empacotamento)
- Arquivo de **208 MB** — o maior do jogo inteiro — referenciado **apenas** no
  `offline.js`, que é o manifesto de cache do Service Worker do Construct 2.
- Não é usado por nenhuma lógica de jogo (ausente de `data.js`, `c2runtime.js` e
  de qualquer `<video>`/`<script>`). Tem cara de captura de teste/desenvolvimento
  deixada por engano no build de varejo. O único vídeo real usado é o
  `asteristic_logo.mp4` (3,8 MB, a vinheta obrigatória do estúdio).
- O porte não carrega o Service Worker (assets servidos de `file:///android_asset`),
  então o manifesto é irrelevante no Android. O pipeline já descarta o arquivo —
  sem isso o APK teria ~338 MB em vez de ~130 MB.

### 2.6 Documentação
- **BUILD.md** reestruturado em torno do fluxo recomendado (extract-assets →
  make-apk), com seção de extração de assets, tabela dos quatro scripts,
  justificativa do `--user` no docker e novas entradas de troubleshooting
  (asar/npx, artefatos root). Pipeline manual completo preservado.
- **README.md** — seção Build atualizada para destacar o caminho rápido, com o
  fluxo manual (`apply.sh`/`build.sh`) abaixo.

### 2.7 Reprodução limpa (validação de ponta a ponta)
- Numa máquina de build Linux separada, todo o conteúdo anterior e as imagens
  Docker usadas foram apagados, e o pipeline foi repetido do zero: clone limpo →
  extração do asar → `extract-assets.sh` → `make-apk.sh --mode docker`.
- Resultado verificado independentemente: APK assinado (apksigner reporta
  Verifies nos esquemas v1/v2/v3), package `com.joymasher.moonrider`, minSdk 21 /
  targetSdk 34, assets essenciais embarcados, **zero** ocorrências de
  greenworks/`.node`/`testdemo` dentro do APK, dono não-root, e zero arquivos
  root sobrando no repositório.
- A saída limpa do `extract-assets.sh` mede 143 MB contra 361 MB do asar bruto.

---

## 3. Estado atual

- Pipeline completo do jogo cru ao APK funcional, testado do zero e documentado.
- Repositório publicado, working tree limpo, local sincronizado com o remoto.
- Quatro scripts versionados e executáveis (`extract-assets.sh`, `make-apk.sh`,
  `apply.sh`, `build.sh`) + `Dockerfile.build`.
- Assets comerciais continuam totalmente fora do versionamento.

## 4. Pendências

Nenhuma obrigatória. Roadmap de funcionalidades da sessão anterior segue aberto
(i18n do menu, troca de idioma do jogo, remap de gamepad, feedback do overlay
touch, cheats). Melhorias opcionais de tooling: integrar a extração diretamente
no `make-apk.sh` (aceitar o jogo cru num único comando).

---

*Projeto não-oficial, sem afiliação com JoyMasher / The Arcade Crew / Asteristic
Game Studio. Todos os assets do jogo são propriedade de seus respectivos
titulares e devem ser fornecidos pelo usuário a partir de sua própria cópia
legítima.*
