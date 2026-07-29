# Plano de Refatoração - RomM-Sync-Tool

## Princípios
- **Não quebrar o que funciona** — Script único, bash puro, compatível ArkOS
- **Entregas incrementais** — Cada fase funcional e testável
- **Compatibilidade retroativa** — Configs antigas continuam funcionando

---

## Status Geral

| Fase | Status |
|------|--------|
| Fase 1: Fundação | ✅ Concluída |
| Fase 2: Cache e Performance | ✅ Concluída |
| Fase 3: Updater Modular | ✅ Concluída |
| Fase 4: UX e Temas | ✅ Concluída |
| Fase 5: Robustez Avançada | ✅ Concluída |

---

## Fase 1: Fundação (✅ Concluída)

### 1.1 Versionamento de Configuração ✅
- `readonly CONF_VERSION="1.4.0"` em `save_config()`
- Campo `ROMMSYNC_CONF_VERSION` persistido em `~/.rommsync.conf`
- `migrate_config()` detecta config antiga sem versão e migra automaticamente

### 1.2 Temp em RAM (/dev/shm) ✅
- `guarantee_tmp()` detecta `/dev/shm` e seta `TMP_DIR`
- Fallback automático para `/tmp/rommsync` se `/dev/shm` indisponível
- `ensure_tmp()` chama `guarantee_tmp()`

### 1.3 Detecção de Resolução do Dialog ✅
- `stty size` lê colunas e linhas do terminal
- `DLG_W=$((cols - 4))`, `DLG_H=$((rows - 4))` em `main()`
- Fallback 72x27 se `stty` falhar

---

## Fase 2: Cache e Performance (✅ Concluída)

### 2.1 Cache Local de Respostas da API ✅
- Cache em `/dev/shm/rommsync/cache/<endpoint>.json`
- TTL padrão: 3600s (configurável via `CACHE_TTL`)
- Funções: `cache_dir()`, `cache_get()`, `cache_set()`, `cache_invalidate()`, `cache_invalidate_all()`

### 2.2 Integração com `api_get()` ✅
- Cache-first por padrão
- Endpoints de escrita bustam cache (`/api/saves/upload`, `/api/roms`)
- Respostas não-JSON não são cacheadas

### 2.3 Suporte a `--force-refresh` e Invalidação ✅
- CLI: `--force-refresh` ignora cache
- Menu opção 7: "Limpar Cache"
- Cache invalidado após backup/download

---

## Fase 3: Updater Modular (✅ Concluída)

### 3.1 `rommsync_updater.sh` Completo ✅
- Migrações encadeadas: v1.0.0 → v1.1.0 → v1.2.0 → v1.3.0 → v1.4.0 → v1.4.1
- `_ver_gt()` compara versões em bash puro
- `detect_previous_version()` detecta via backup ou config
- `cleanup_deprecated_files()` remove arquivos obsoletos
- `show_changelog()` exibe mudanças

### 3.2 Integração com `self_update()` e `check_update()` ✅
- Chamam updater após substituir script
- Passam `NEW_VERSION`, `SCRIPT_DIR` como env vars
- Backup `.bak_v{X.Y.Z}` antes de sobrescrever

---

## Fase 4: UX e Temas (✅ Concluída)

### 4.1 Temas de Cores Dialog ✅
4 temas em `themes/`:
- `rommsync_arkos.dialogrc` — Padrão (preto/verde)
- `rommsync_high_contrast.dialogrc` — Alto contraste (amarelo/preto)
- `rommsync_blue.dialogrc` — Azul
- `rommsync_green.dialogrc` — Verde retro

- `apply_theme()` carrega tema via `export DIALOGRC`
- `theme_menu()` permite selecionar e persistir em `DIALOGRC_THEME`

### 4.2 Menu Principal Reorganizado ✅
9 opções na ordem:
1. Backup de Saves
2. Download de Jogos
3. Reconfigurar Conexão
4. Status da Conexão
5. Ver Log
6. Tema de Cores
7. Limpar Cache
8. Atualizar Script
9. Sair

---

## Fase 5: Robustez Avançada (✅ Concluída)

### 5.1 Health Check Expandido ✅
`show_status()` expandido com:
- Latência API (curl write-out `%{time_total}`)
- Espaço livre em `/roms` (`df -h`)
- Contagem de saves locais (`.srm`, `.state`, `.sav`)
- Contagem de entradas no cache
- Tema ativo

### 5.2 Gamepad (gptokeyb) ✅
- `rommsync.controls` — Mapeamento de teclas para dialog
- `gptokeyb` já integrado no ArkOS
- Documentado no AGENTS.md

### 5.3 README Atualizado ✅
- Versão v1.4.1
- Tabela de funcionalidades expandida
- Instruções de instalação atualizadas

---

## Arquivos Criados/Modificados

### Novos
- `rommsync_updater.sh` — Updater com migrações
- `themes/rommsync_arkos.dialogrc` — Tema padrão
- `themes/rommsync_high_contrast.dialogrc` — Alto contraste
- `themes/rommsync_blue.dialogrc` — Tema azul
- `themes/rommsync_green.dialogrc` — Tema verde
- `rommsync.controls` — Mapeamento gptokeyb
- `AGENTS.md` — Documentação do projeto

### Modificados
- `RomMSync.sh` — Todas as fases integradas
- `README.md` — v1.4.1, features expandidas

---

## Checklist de Validação

### Fase 1
- [x] Config antiga carrega sem erro
- [x] Campo `ROMMSYNC_CONF_VERSION` salvo
- [x] `/dev/shm/rommsync` criado e usado (com fallback)
- [x] Dialog adapta a resolução

### Fase 2
- [x] Cache hit é instantâneo
- [x] `--force-refresh` invalida cache
- [x] Cache expira após TTL

### Fase 3
- [x] `self_update` baixa e substitui
- [x] Updater migra config automaticamente
- [x] Backup antes de sobrescrever

### Fase 4
- [x] Menu "Tema de Cores" aplica tema selecionado
- [x] Tema persistido no config

### Fase 5
- [x] Health check mostra latência, disco, saves
- [x] Gamepad funciona via gptokeyb
- [x] README atualizado
