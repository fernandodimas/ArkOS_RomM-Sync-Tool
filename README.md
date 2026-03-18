# RomM-Sync-Tool

Utilitário de sincronização de ROMs e saves para consoles portáteis rodando **ArkOS** (ARM/Debian), integrado com uma instância auto-hospedada do **[RomM](https://github.com/zurdi15/romm)**.

---

## Instalação no Console

### 1. Copiar o script via SSH
```bash
scp RomMSync.sh ark@<IP-DO-CONSOLE>:/roms/tools/RomMSync.sh
ssh ark@<IP-DO-CONSOLE> "chmod +x /roms/tools/RomMSync.sh"
```

### 2. Instalar dependências (ArkOS)
```bash
# Como root no console:
opkg update
opkg install dialog jq curl wget zip
```

> **Nota:** Em algumas versões do ArkOS, essas ferramentas já vêm pré-instaladas.

### 3. Executar
```bash
/roms/tools/RomMSync.sh
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
| 📶 Status | Testa conectividade com o servidor em tempo real |
| 📋 Log | Exibe histórico de operações |

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

## Requisitos

- **ArkOS** em console ARM (RG351P, RG353P, RG552, etc.)
- **RomM** v2.x+ auto-hospedado com API habilitada
- Dependências: `dialog`, `jq`, `curl`, `wget`, `zip`
- Wi-Fi ativo no console

---

## Licença

MIT. Contribuições bem-vindas!
