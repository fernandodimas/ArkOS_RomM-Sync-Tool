# RomM-Sync-Tool

Utilitário de sincronização de ROMs e saves para consoles portáteis rodando **ArkOS** (ARM/Debian), integrado com uma instância auto-hospedada do **[RomM](https://github.com/zurdi15/romm)**.

> **Versão atual:** `v1.4.1` — Refatoração completa: config versionada, cache de API, updater modular, temas de cores, health check expandido.

---

## Instalação no Console

### 1. Copiar os arquivos via SSH
```bash
# Copia o script principal e o updater
scp RomMSync.sh rommsync_updater.sh ark@<IP-DO-CONSOLE>:/roms/tools/
ssh ark@<IP-DO-CONSOLE> "chmod +x /roms/tools/RomMSync.sh /roms/tools/rommsync_updater.sh"

# Copia os temas de cores
scp -r themes/ ark@<IP-DO-CONSOLE>:/roms/tools/

# Copia config de exemplo (opcional)
scp rommsync_config.conf ark@<IP-DO-CONSOLE>:/roms/tools/
```

### 2. Instalar dependências (ArkOS)
```bash
# Como root no console:
opkg update
opkg install dialog jq curl wget zip bc
```

> **Nota:** `bc` é usado para cálculos de latência no health check. Em algumas versões do ArkOS já vem pré-instalado.

### 3. Executar
```bash
/roms/tools/RomMSync.sh

# Ou com ignore de cache:
/roms/tools/RomMSync.sh --force-refresh
```

Ou configure como item de menu no EmulationStation adicionando em `/roms/tools/`:
```
Game Name: RomM Sync
Command: bash /roms/tools/RomMSync.sh
Image: /roms/tools/RomMSync.png
```

---

## Funcionalidades

| Função | Descrição |
|--------|-----------|
| ⬆ Backup de Saves | Compacta `.srm`, `.state`, `.sav` e envia via `POST /api/saves/upload` |
| ⬇ Download de Jogos | Lista plataformas e ROMs via API; baixa direto para a pasta correta |
| ⚙ Reconfigurar | Atualiza URL/usuário/senha do servidor RomM |
| 📶 Status | Health check expandido: status HTTP, latência, disco, saves pendentes, cache |
| 🎨 Temas | 4 temas de cores para o dialog (arkos, alto contraste, azul, verde retro) |
| 📋 Log | Exibe histórico de operações |
| 🗑 Limpar Cache | Limpa cache da API e dados temporários |
| 🔄 Atualizar | Auto-update via updater modular com migrações encadeadas |

---

## Configuração

Na primeira execução, o script pergunta:
- **URL do RomM**: ex. `http://192.168.1.100:3000`
- **Usuário** e **Senha**

As credenciais são salvas em `~/.rommsync.conf` com permissão `600` (somente dono), usando **Basic Auth em Base64**.

---

## Mapeamento de Plataformas

O script mapeia automaticamente os slugs do RomM para as pastas do ArkOS:

| RomM Slug | Pasta ArkOS |
|-----------|-------------|
| `game-boy-advance` | `/roms/gba/` |
| `super-nintendo` | `/roms/snes/` |
| `playstation` / `psx` | `/roms/psx/` |
| `sega-genesis` | `/roms/megadrive/` |
| `nintendo-64` | `/roms/n64/` |
| `psp` | `/roms/psp/` |
| `nintendo-ds` | `/roms/nds/` |
| *(desconhecido)* | `/roms/<slug>/` *(fallback)* |

Para adicionar mapeamentos, edite o array `PLATFORM_MAP` no script.

---

## Estrutura de Arquivos

```
/roms/
├── tools/
│   └── RomMSync.sh       ← Script principal
├── saves/
│   ├── snes/             ← .srm, .state
│   ├── gba/
│   └── ...
├── snes/                 ← ROMs baixados
├── gba/
└── ...

~/.rommsync.conf           ← Config (oculta, chmod 600)
/tmp/rommsync/            ← Temporários (auto-limpos)
/tmp/rommsync.log         ← Log de operações
```

---

## Endpoints da API RomM Utilizados

| Método | Endpoint | Uso |
|--------|----------|-----|
| `GET` | `/api/heartbeat` | Teste de conexão |
| `GET` | `/api/platforms` | Lista plataformas disponíveis |
| `GET` | `/api/roms?platform_id=X&limit=200` | Lista ROMs de uma plataforma |
| `GET` | `/api/roms/{id}/content/{filename}` | Download da ROM |
| `POST` | `/api/saves/upload` | Upload de saves (form-data) |

---

## Estrutura de Arquivos

```
/roms/tools/
├── RomMSync.sh               ← Script principal
├── rommsync_updater.sh       ← Migrações de config pós-atualização
├── rommsync_config.conf      ← Config de exemplo (copiar para o PC da SD antes)
└── RomMSync.png              ← Ícone para EmulationStation (opcional)

~/.rommsync.conf              ← Config (oculta, chmod 600)
/dev/shm/rommsync/            ← Temp em RAM (auto-limpo no reboot)
/dev/shm/rommsync/cache/      ← Cache de respostas da API
/tmp/rommsync.log             ← Log de operações
```

---

## Changelog

### v1.3.0 (Fase 1 — Refatoração)
- CONF_VERSION adicionado ao `~/.rommsync.conf`
- Suporte a `ROMMSYNC_CONF_VERSION` para futuras migrações de config
- `TMP_DIR` usa `/dev/shm/rommsync` (RAM) com fallback para `/tmp/rommsync` (flash)
- `DLG_W`/`DLG_H` calculados automaticamente via `stty size` (fim dos valores hardcoded)
- Auto-update verifica versão remotamente via GitHub (wget→curl fallback)

### v1.4.0 (Fase 2 — Cache e Performance)
- Cache local de respostas da API em `/dev/shm/rommsync/cache/`
- TTL configurável via variável `CACHE_TTL` (padrão: 3600s)
- `api_get()` usa cache por padrão, pula para endpoints de escrita
- Novo item de menu: **Limpar Cache** (opção 6)
- Suporte a `--force-refresh` via CLI para ignorar cache
- Cache invalidado automaticamente após backup e download

### v1.4.1 (Fase 3 — Updater Modular)
- `rommsync_updater.sh` reescrito com migrações encadeadas por versão
- Compara versões via `_ver_gt()` (pure bash, sem sort -V)
- Limpeza automática de arquivos obsoletos
- Exibe changelog após atualização
- `self_update()` e `check_update()` agora chamam o updater após substituir o script
- Backup automático `.bak_v{X.Y.Z}` antes de sobrescrever

### v1.2.x — Pré-refatoração
- Script monolítico com backup de saves, download de ROMs, reconfiguração, status e log
- Auto-update via GitHub releases
- Suporte a múltiplas raízes de ROMs (`/roms` e `/roms2`)
- Smart upload com rclone para arquivos grandes

MIT. Contribuições bem-vindas!
