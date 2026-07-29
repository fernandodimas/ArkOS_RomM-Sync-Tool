# Análise Completa do Projeto arkos_store_romm (RomM-Sync-Tool)

## Visão Geral

Este é um utilitário de sincronização de ROMs e saves para consoles portáteis rodando **ArkOS** (ARM/Debian), integrado com uma instância auto-hospedada do **[RomM](https://github.com/zurdi15/romm)**. O projeto principal é o script **RomMSync.sh** - um script bash interativo usando `dialog` para interface de terminal (TUI) com suporte a gamepad via `gptokeyb`.

O projeto **ThemeMaster** na pasta `ThemeMaster/` serve como projeto de referência - é uma aplicação madura que já roda no ArkOS para gerenciamento de temas do EmulationStation.

---

## Estrutura do Projeto

```
arkos_store_romm/
├── RomMSync.sh              # Script principal (58KB, ~2000 linhas)
├── rommsync_config.conf     # Configuração de exemplo (credenciais)
├── README.md                # Documentação completa
├── .gitignore
├── .githooks/pre-commit     # Hook de pré-commit
└── ThemeMaster/             # Projeto de referência (já roda no ArkOS)
    ├── ThemeMaster.sh       # Launcher script
    └── ThemeMaster/
        ├── ThemeMaster      # Binário principal (ELF aarch64)
        ├── tm-joypad        # Binário de controle (ELF aarch64)
        ├── tm-viewer        # Visualizador de imagens (ELF aarch64, usa SDL2)
        ├── updater          # Script de pós-instalação (bash)
        ├── ThemeMaster.cfg  # Configuração
        ├── paramcontrols.txt # Mapeamento de controles
        ├── changelog        # Histórico de versões
        ├── ThemeMaster.nfo  # Logo/asset
        ├── *.dialogrc       # Temas de cores para dialog
        └── data/
            ├── *.png        # Screenshots de temas (galeria)
            ├── gallery.db   # Banco de dados de temas (TSV)
            ├── gallery.version
            └── outdatedthemes.cache
```

---

## Análise do RomMSync.sh (Script Principal)

### Características Principais

| Característica | Detalhes |
|----------------|----------|
| **Linguagem** | Bash (script shell) |
| **Interface** | `dialog` (TUI ncurses) + `gptokeyb` (gamepad) |
| **Dependências** | `dialog`, `jq`, `curl`, `wget`, `zip`, `rclone` (opcional) |
| **Alvo** | ArkOS em ARM (RG351P, RG353P, RG552, etc.) |
| **Configuração** | `~/.rommsync.conf` (chmod 600, Basic Auth Base64) |
| **Log** | `/tmp/rommsync.log` + `/tmp/rommsync/` (temp) |

### Arquitetura do Script (Principais Seções)

#### 1. **Constantes e Configuração** (linhas 1-150)
- Versão: `3.2.0`
- URLs de atualização: GitHub `fernandodimas/ArkOS_RomM-Sync-Tool`
- Paths padrão: `/roms`, `/roms2`, `~/.rommsync.conf`
- Mapeamento de plataformas RomM → ArkOS (`PLATFORM_MAP` array associativo)
- Cores e configuração do `dialog`

#### 2. **Sistema de Dependências** (`check_dependencies`)
- Detecta gerenciador de pacotes: `opkg` (ArkOS), `apt`, `pacman`, `dnf`, `apk`
- Instala automaticamente: `dialog`, `jq`, `curl`, `wget`, `zip`
- Verifica `rclone` para uploads grandes (>50MB)
- Usa `wget` como preferência (mais confiável no ArkOS para HTTPS)

#### 3. **Conectividade de Rede** (`check_wifi`)
- Verifica rota padrão (`ip route`)
- Testa internet com `wget` (URLs: ubuntu.com, apple.com)
- Fallback para `curl`
- Flag global `INTERNET_OK` controla auto-update

#### 4. **Configuração** (`load_config`, `save_config`, `setup_config`)
- **3 métodos de configuração:**
  1. **Importar do SD** - arquivo `rommsync_config.conf` na mesma pasta do script
  2. **Manual** - input via dialog (requer teclado USB)
  3. **SSH** - instruções para configurar via terminal
- Salva credenciais em Base64 Basic Auth no arquivo de config (chmod 600)
- Testa conexão com `/api/heartbeat` antes de salvar

#### 5. **API RomM** (`api_get`, `api_post_file`, `smart_upload`)
- Autenticação: Basic Auth via header `Authorization`
- **Smart Upload**: usa `rclone` para arquivos >50MB, `curl` para menores
- Endpoints usados:
  - `GET /api/heartbeat` - health check
  - `GET /api/platforms` - lista plataformas
  - `GET /api/roms?platform_id=X&limit=200` - lista ROMs
  - `GET /api/roms/{id}/content/{filename}` - download ROM
  - `POST /api/saves/upload` - upload saves (multipart form-data)

#### 6. **JSON-to-Menu Mapping** (Skill crítica - linhas 380-450)
- Função `json_to_menu_entries`: converte array JSON → array bash compatível com `dialog --menu`
- Usa delimitador ASCII SOH (`\x01`) para separar ID do label (evita problemas com espaços)
- Usa `nameref` (`local -n _out_array`) para retornar array por referência
- Processamento em uma única passagem pelo `jq` (eficiência no ARM)

#### 7. **Backup de Saves** (`backup_saves`, `collect_saves_index`)
- Busca recursiva em `/roms` e `/roms2` (até 3 níveis)
- Extensões: `.srm`, `.state`, `.state*`, `.sav`
- Preserva estrutura de pastas no ZIP (`console/save.srm`, `console/sub/save.state`)
- Menu permite selecionar console específico ou "Todos"
- Upload via `smart_upload` com `platform_slug` no form-data

#### 8. **Download de Jogos** (`list_platforms`, `list_games`, `download_rom`)
- Fluxo: Plataforma → Jogos → Download
- Mapeamento slug RomM → pasta ArkOS via `PLATFORM_MAP` + fallback
- Progress bar com `wget --show-progress` + `dialog --gauge`
- Verifica arquivo existente antes de sobrescrever
- Destino padrão: `${ROMS_ROOTS[0]}/${arkos_folder}/`

#### 9. **Auto-Update** (`check_update`, `self_update`)
- Verifica versão no GitHub Raw (`raw.githubusercontent.com`)
- Comparação de versão sem `sort -V` (pure bash `_ver_gt`)
- Download via `wget` (preferencial) ou `curl`
- Valida sintaxe com `bash -n` antes de instalar
- Backup automático (`.bak_v{versao}`)
- Reexecuta script após atualização (`exit 0`)

#### 10. **Inicialização e Gamepad** (`main`)
- Configura TTY (`/dev/tty1`, chmod 666, fonte Terminus)
- Inicia `gptokeyb` (em `/opt/inttools/gptokeyb`) para mapear gamepad → teclado
- Cleanup via `trap` (EXIT, INT, TERM) mata `gptokeyb`
- Executa `check_update` automaticamente na inicialização

---

## Análise do ThemeMaster (Projeto de Referência)

### Estrutura e Arquitetura

O ThemeMaster é uma aplicação **híbrida**: launcher bash + binários compilados (C/C++) para performance.

| Componente | Tipo | Função |
|------------|------|--------|
| `ThemeMaster.sh` | Bash launcher | Configura ambiente, executa binário |
| `ThemeMaster` | ELF aarch64 (C++) | App principal - menus, downloads, instalação |
| `tm-joypad` | ELF aarch64 (C) | Mapeamento gamepad via `libevdev` + `uinput` |
| `tm-viewer` | ELF aarch64 (C++/SDL2) | Visualizador de imagens (screenshots) |
| `updater` | Bash | Pós-instalação, migrações de config, assets |

### Padrões de Arquitetura Reutilizáveis

#### 1. **Launcher Bash + Binários Nativos**
```bash
# ThemeMaster.sh
cd "$(dirname "$0")/ThemeMaster"
chmod +x ./ThemeMaster ./tm-joypad ./tm-viewer
# Detecta UI service (weston, sway, etc) e executa apropriado
```

#### 2. **Configuração Versionada** (`ThemeMaster.cfg`)
```
app_conf_version="4.10.0"
app_prerelease="off"
debug="off"
mode="B"
themes_location="/roms/themes/"
temp_ram_folder="/dev/shm/"
app_autocheckupdate="on"
collections=(Jetup13 CodyV59 farfenkugell EmuELEC RetroPie)
app_colorscheme="All_Black"
nblines="27"
nbcols="72"
```

#### 3. **Updater Pós-Instalação** (`updater`)
- Migrações forward-compatible (remove arquivos obsoletos, renomeia, atualiza config)
- One-shot modifications por versão
- Download de assets (logo, screenshots)
- Exibe changelog após update

#### 4. **Controle de Gamepad Nativo** (`tm-joypad`, `paramcontrols.txt`)
- Binário C usando `libevdev` + `/dev/uinput`
- Configuração via arquivo texto (`paramcontrols.txt`)
- Suporta múltiplos perfis: `generic`, `anbernic`, `rocknix`, etc.

#### 5. **Visualizador SDL2** (`tm-viewer`)
- Binário C++ ligado a `SDL2` + `SDL2_image`
- Usado para preview de screenshots em tela cheia

#### 6. **Galeria de Temas** (`data/gallery.db`)
- Formato TSV: `Account\tRepository\t480x320\t640x480\t854x480\t960x544`
- Filtro por resolução do dispositivo
- Screenshots locais em `data/*.png`

#### 7. **Temas de Cores Dialog** (`*.dialogrc`)
- `All_Black.dialogrc`, `White_on_Black.dialogrc`, etc.
- Configurável via `DIALOGRC` env var

#### 8. **Cache e Versionamento**
- `gallery.version` - timestamp da última atualização
- `outdatedthemes.cache` - cache de temas desatualizados
- `.version` extensão para logs de instalação (não `.log`)

---

## Comparação: RomMSync vs ThemeMaster

| Aspecto | RomMSync.sh | ThemeMaster |
|---------|-------------|-------------|
| **Linguagem Principal** | Bash puro | Bash + C/C++ (binários) |
| **Interface** | `dialog` (ncurses) | `dialog` + SDL2 viewer |
| **Gamepad** | `gptokeyb` (externo) | `tm-joypad` (próprio, libevdev) |
| **Atualização** | Self-update (bash substitui a si mesmo) | Updater script + download binários |
| **Configuração** | `~/.rommsync.conf` (simples) | `ThemeMaster.cfg` (versionado) |
| **Dependências** | Mínimas (dialog, jq, curl, wget, zip) | SDL2, libevdev, mais pesado |
| **Arquitetura** | Monolítico (um arquivo) | Modular (launcher + binários) |
| **Distribuição** | Script único via GitHub Raw | GitHub Releases (binários + assets) |
| **Logs** | `/tmp/rommsync.log` | `./ThemeMaster.log` |
| **Temp** | `/tmp/rommsync/` | `/dev/shm/` (RAM) |

---

## Pontos Fortes do RomMSync.sh

1. **Script único** - Fácil distribuição, instalação via `scp` + `chmod +x`
2. **Zero dependências de compilação** - Roda em qualquer ArkOS com busybox/bash
3. **JSON-to-Menu robusto** - Usa SOH delimiter + nameref, evita bugs de parsing
4. **Smart upload (rclone/curl)** - Otimiza saves grandes
5. **Auto-update seguro** - Valida sintaxe, backup, fallback wget/curl
6. **Multi-root ROMs** - Suporta `/roms` e `/roms2` (SD2)
7. **Configuração flexível** - 3 métodos (SD, manual, SSH)
8. **Diagnóstico de rede** - DNS, curl error, HTTP codes

---

## Oportunidades de Melhoria (Baseado no ThemeMaster)

### 1. **Configuração Versionada**
```bash
# Adicionar ao ~/.rommsync.conf
ROMMSYNC_CONF_VERSION="3.2.0"
```
Permitir migrações futuras no `load_config`.

### 2. **Updater Pós-Instalação Separado**
Extrair lógica de migração de config para script `rommsync_updater.sh` (como `ThemeMaster/updater`).

### 3. **Uso de `/dev/shm` (RAM) para Temporários**
```bash
# ThemeMaster usa:
temp_ram_folder="/dev/shm/"
# Mais rápido que /tmp em flash storage
```

### 4. **Cache de Dados da API**
- `gallery.db` estilo ThemeMaster para cache de plataformas/ROMs
- Evita re-download a cada navegação

### 5. **Temas de Cores Dialog**
Adicionar suporte a `DIALOGRC` customizado (cores por dispositivo).

### 6. **Detecção de Dispositivo/Resolução**
Ajustar `nblines`/`nbcols` do dialog automaticamente (como ThemeMaster faz).

### 7. **Gamepad Nativo (Opcional)**
Integrar lógica similar ao `tm-joypad` para não depender de `gptokeyb` externo.

### 8. **Distribuição via GitHub Releases**
Além do raw script, oferecer release com assets (ícone, config exemplo).

### 9. **Visualizador de Imagens (Opcional)**
Para preview de capas de jogos (usaria `tm-viewer` ou `fbi`/`fbv`).

### 10. **Modo Debug**
Flag `debug="on"` no config para logs verbosos (como ThemeMaster).

---

## Configuração Atual (rommsync_config.conf)

```ini
ROMM_URL="http://192.168.16.250:81"
ROMM_USER="admin"
ROMM_PASS="*Dims3410"
```

> **⚠️ Segurança**: Este arquivo contém credenciais reais. Não deve ser commitado. O `.gitignore` já o ignora.

---

## Mapeamento de Plataformas (PLATFORM_MAP)

| RomM Slug | Pasta ArkOS |
|-----------|-------------|
| game-boy-advance | /roms/gba/ |
| super-nintendo | /roms/snes/ |
| playstation / psx | /roms/psx/ |
| sega-genesis | /roms/megadrive/ |
| nintendo-64 | /roms/n64/ |
| psp | /roms/psp/ |
| nintendo-ds | /roms/nds/ |
| (desconhecido) | /roms/<slug>/ (fallback) |

---

## Dependências do Sistema (ArkOS)

```bash
opkg update
opkg install dialog jq curl wget zip
# rclone já vem pré-instalado no ArkOS
```

---

## Fluxo de Execução Principal

```
main()
├── ensure_tmp()                    # Cria /tmp/rommsync
├── log "iniciado"
├── Setup TTY + gptokeyb            # Gamepad support
├── trap cleanup                    # EXIT/INT/TERM
├── check_dependencies()            # Instala dialog, jq, curl, wget, zip
├── check_wifi()                    # Rota + Internet test
├── check_update()                  # Auto-update GitHub
├── load_config() || setup_config() # Configuração inicial
└── main_menu()                     # Loop do menu principal
    ├── 1: backup_saves()
    ├── 2: list_platforms() → list_games() → download_rom()
    ├── 3: reconfigure()
    ├── 4: show_status()
    ├── 5: view log
    ├── 6: self_update()
    └── 7: exit
```

---

## Conclusão

O **RomMSync.sh** é um script bash bem estruturado, robusto e adequado para o ambiente ArkOS. Segue boas práticas de shell scripting (set -euo pipefail, namerefs, SOH delimiter, validação de download, trap cleanup).

O **ThemeMaster** serve como excelente referência para evoluções futuras: configuração versionada, updater modular, cache local, detecção de hardware, temas de cores, e separação de responsabilidades (launcher + binários nativos).

### Próximos Passos Recomendados

1. **Adicionar versionamento de config** (`ROMMSYNC_CONF_VERSION`)
2. **Migrar temp para `/dev/shm/rommsync/`**
3. **Criar `rommsync_updater.sh`** para migrações futuras
4. **Implementar cache de plataformas/ROMs** (JSON local com timestamp)
5. **Adicionar detecção de resolução** para ajustar dialog automaticamente
6. **Suporte a temas de cores** (`.dialogrc` customizado)
7. **Publicar no GitHub Releases** além do raw script