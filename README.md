## Big Remote

Big Remote — controle remoto nativo para macOS (barra de menus) para TVs Samsung Tizen, com foco na The Frame, e TVs Sony BRAVIA e LG webOS. O Mac fala direto com a TV pela rede local: sem celular e sem nuvem obrigatória.

## Motivação

O app SmartThings do celular é o jeito mais fácil de mexer na TV: abrir apps, ligar o Modo Arte, ligar e desligar. Quando o celular está longe ou sem bateria, esses ajustes ficam fora de alcance. O Big Remote leva esses comandos para a barra de menus do Mac e transforma ajustes repetidos em presets de um clique.

Inspirado por [glass-home-samsung-tv](https://github.com/victaphu/glass-home-samsung-tv), mas com outra premissa: **o celular nunca é requisito** ([ADR 0001](specs/adr/0001-lan-first-no-phone.md)).

---

## Status do build

[![CI/CD](https://github.com/danielvm-git/big-remote-control/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/danielvm-git/big-remote-control/actions/workflows/ci-cd.yml)
[![Release](https://img.shields.io/github/v/release/danielvm-git/big-remote-control)](https://github.com/danielvm-git/big-remote-control/releases)

| Job | O que faz |
|-----|-----------|
| `ci` (macOS) | `scripts/preflight.sh`: SwiftLint estrito, XcodeGen, build e testes |
| `verify` (Linux) | Checagens portáveis, Conventional Commits, bloqueio de `Co-authored-by` |
| `release` (`main`) | [big-release](https://github.com/danielvm-git/big-release): versão, `CHANGELOG.md`, tag e GitHub Release |

---

## Estilo de código

- [SwiftLint](https://github.com/realm/SwiftLint) estrito (`.swiftlint.yml`; cada exceção tem justificativa).
- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Regras completas em [CONVENTIONS.md](CONVENTIONS.md) (metodologia [bigpowers](https://github.com/danielvm-git/bigpowers)).

---

## Tecnologias

| Camada | Escolha |
|--------|---------|
| Linguagem | Swift 6 (concorrência estrita `complete`) |
| UI | SwiftUI: `MenuBarExtra`, `Window`, `Settings` |
| Plataforma | macOS 15+, App Sandbox (`network.client`) |
| Projeto | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) |
| Rede | WebSocket (WSS 8002), REST (HTTP 8001), UDP (Wake-on-LAN) |
| Testes | Swift Testing, sem test host e sem rede |
| CI/CD | GitHub Actions ([template `ci-cd-swift.yml`](https://github.com/danielvm-git/.github)) + big-release |
| Dependências | nenhuma |

---

## Funcionalidades

Verificadas numa The Frame 43" (QN43LS03D, 2024) em 29/10/2026 — [relatório](specs/verifications/VERIFY-2026-10-29-frame43.md).

- **Controle remoto** — volume, mudo, setas, OK, voltar, início, fonte, play/pausa, canais e envio de texto.
- **Apps** — Netflix, YouTube, Prime Video, Disney+, HBO Max, Spotify, Apple TV e outros, via REST ([ADR 0003](specs/adr/0003-rest-first-app-launch.md)).
- **Modo Arte da The Frame** — liga e desliga, mostra o status ao vivo, ajusta brilho e sensor de movimento.
- **Ligar a TV** — com a TV em standby, o app manda `KEY_POWER`; o Wake-on-LAN fica como plano B ([ADR 0002](specs/adr/0002-frame-power-off.md)).
- **Presets** — sequências de passos com um clique ("Cinema", "Desligar tudo").
- **Várias TVs** — busca na rede local (`/24`), adicionar por IP, estado ao vivo a cada 7 s (somente leitura).
- **SmartThings (opcional)** — desligar de verdade, modo de imagem, modo de som e entrada HDMI por nome.

`KEY_FACTORY` é bloqueada no app inteiro, inclusive nos presets.

---

## Exemplo de preset

```json
{
  "name": "Cinema",
  "symbol": "popcorn",
  "steps": [
    { "type": "power", "power": "tv" },
    { "type": "delay", "seconds": 1.5 },
    { "type": "smartThings", "capability": "custom.picturemode", "command": "setPictureMode", "arguments": ["Filme"] },
    { "type": "launchApp", "appID": "3201907018807" }
  ]
}
```

---

## Instalação

Requisitos: macOS 15+, Xcode 26+, XcodeGen e SwiftLint.

```bash
brew install xcodegen swiftlint
gh repo clone danielvm-git/big-remote-control && cd big-remote-control
xcodegen generate
xcodebuild -scheme BigRemote -destination 'platform=macOS' -derivedDataPath build build
open "build/Build/Products/Debug/Big Remote.app"
```

`BigRemote.xcodeproj` é gerado e não vai para o git: mude o `project.yml`. A assinatura é ad hoc ("Sign to Run Locally").

### Sandbox e rede

- O App Sandbox fica ligado, só com `com.apple.security.network.client`.
- Na primeira conexão o macOS pede a permissão **Rede local**. Aceite. Para mudar depois: Ajustes do Sistema › Privacidade e Segurança › Rede Local.
- O certificado autoassinado da TV (WSS 8002) só é aceito para IPs privados (10/8, 172.16/12, 192.168/16).

---

### iPhone (TestFlight)

O app de iPhone usa os mesmos clientes de TV do Mac e fala direto com a TV pela rede local. Ele é opcional: o Mac nunca depende dele.

1. Entre com a sua Apple ID em Xcode > Settings > Accounts.
2. Crie o app em App Store Connect com o bundle ID `com.danielvm.BigRemoteiOS`.
3. Rode `TEAM_ID=<seu team ID> bash scripts/testflight.sh`.

No iPhone, cada TV é pareada de novo e o MAC (Wake-on-LAN) é digitado à mão. O iOS bloqueia broadcast UDP, então ligar por Wake-on-LAN pelo iPhone pode falhar (ADR 0006).

## Referência do protocolo

[`docs/PROTOCOL.md`](docs/PROTOCOL.md) — endpoints, payloads, IDs de apps e o resultado dos testes ao vivo por modelo.

---

## Testes

```bash
bash scripts/preflight.sh
```

O Preflight roda SwiftLint, yamllint, shellcheck, XcodeGen, build e os testes. Os testes compilam só `Models/` e `Services/Protocol/`: nunca abrem o app nem tocam a rede.

```swift
@Test func keyClickPayloadMatchesSpec() throws {
    let json = try RemotePayloads.key("KEY_VOLUP")
    #expect(json.contains(#""DataOfCmd":"KEY_VOLUP""#))
}
```

---

## Como usar

1. **Ache a TV** — Configurações › TVs › "Procurar na rede", ou adicione pelo IP.
2. **Pareie** — aperte qualquer tecla. A TV mostra "Permitir Big Remote?". **O aviso some rápido**: fique com o controle físico na mão e aceite logo. O token fica salvo por TV.
3. **Use a barra de menus** — escolha a TV, use o controle, os apps favoritos, o Modo Arte e os presets.
4. **Crie presets** — na janela "Big Remote" › Presets. O arquivo fica em `~/Library/Containers/com.danielvm.BigRemote/Data/Library/Application Support/Big Remote/presets.json`.

Se a TV recusar: Configurações da TV › Geral › Gerenciador de dispositivos externos › Gerenciador de conexão do dispositivo › Lista de dispositivos. Em "Notificação de acesso", use "Somente na primeira vez".

### Passos de preset

| `type` | Campos | Efeito |
|---|---|---|
| `key` | `key` (`KEY_…`), `holdSeconds` opcional | Tecla (Click). Com `holdSeconds`: Press, espera, Release |
| `delay` | `seconds` (0–120) | Espera |
| `launchApp` | `appID`, `launchType` opcional | Abre o app (REST; se falhar, WebSocket) |
| `artMode` | `on` | Liga (acorda se preciso) ou desliga o Modo Arte |
| `power` | `power`: `tv` / `art` / `off` / `wake` | Energia como nos botões |
| `text` | `text` | Substitui o texto do campo focado na TV e confirma |
| `smartThings` | `capability`, `command`, `arguments` | Comando na nuvem; sem token o passo é pulado com aviso |

`target` (opcional, menos em `delay`): `"selected"` (padrão), `"all"` ou o `id` de uma TV. Um passo com várias TVs roda em paralelo; um passo com erro não interrompe os outros.

### SmartThings (opcional)

Só é necessário para desligar de verdade a The Frame e para modo de imagem, modo de som e entrada por nome. O Mac acessa a nuvem direto, sem celular.

1. Crie um token em <https://account.smartthings.com/tokens> com `r:devices:*`, `w:devices:*`, `x:devices:*`. **Tokens pessoais novos valem 24 h.**
2. Cole em Configurações › SmartThings. O token fica no Keychain.
3. Uso contínuo: crie um app OAuth-In com `smartthings apps:create` ([detalhes](docs/PROTOCOL.md)). O refresh automático ainda não existe.

### Limitações conhecidas

- A The Frame 2024 não desliga de verdade pela rede local; sem SmartThings, "Desligar" vai para o Modo Arte.
- O Wake-on-LAN não acordou a Frame 2024 testada; o caminho que funciona é `KEY_POWER` em standby.
- O ID do Globoplay não foi confirmado. Use "Verificar" em Configurações › Apps.
- Sem atalhos globais de teclado; sem refresh OAuth do SmartThings.

---

## Contribuir

1. Crie um branch: `git checkout -b feat/minha-mudanca`
2. Rode `bash scripts/preflight.sh` — tem que ficar verde.
3. Commits em [Conventional Commits](https://www.conventionalcommits.org/), sem rodapé `Co-authored-by`.
4. Integre com `bash scripts/land-branch.sh <branch> "<mensagem convencional>"`.

Contexto para agentes de IA: [AGENTS.md](AGENTS.md) (`CLAUDE.md` e `GEMINI.md` são symlinks). Planejamento: [`specs/`](specs/README.md).

---

## Créditos

- README baseado no [Kickass README template](https://github.com/akashnimare/readme-template) de **Akash Nimare**, via o template Swift de [danielvm-git/.github](https://github.com/danielvm-git/.github).
- Protocolo: [samsungtvws](https://github.com/xchwarze/samsung-tv-ws-api) e [glass-home-samsung-tv](https://github.com/victaphu/glass-home-samsung-tv).
- Metodologia: [bigpowers](https://github.com/danielvm-git/bigpowers). Releases: [big-release](https://github.com/danielvm-git/big-release).

---

## Licença

Distribuído sob a licença MIT. Veja [LICENSE](LICENSE).
