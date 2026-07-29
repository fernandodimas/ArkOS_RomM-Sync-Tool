#!/bin/bash
# =============================================================================
# RomM-Sync-Tool - Updater
# Responsável por migrações forward-compatíveis de configuração e limpeza
# de arquivos obsoletos após atualização do RomMSync.sh via GitHub.
#
# Uso:
#   ./rommsync_updater.sh [previous_version]
#
# O argumento previous_version pode ser omitido — o script detecta
# automaticamente a versão anterior a partir do .bak_v{X.Y.Z}.
# =============================================================================

set -euo pipefail

readonly UPDATER_LOG="/tmp/rommsync.log"
readonly CONFIG_FILE="${HOME}/.rommsync.conf"

# --- Funções Utilitárias ---------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [updater] $*" >> "$UPDATER_LOG"
}

# _ver_gt v1 v2 → retorna 0 se v1 > v2 (puro bash)
_ver_gt() {
    local v1="$1" v2="$2"
    [ "$v1" = "$v2" ] && return 1
    local IFS='.'
    local -a a1=($v1) a2=($v2)
    local i
    for i in 0 1 2; do
        local n1="${a1[$i]:-0}" n2="${a2[$i]:-0}"
        if [ "$n1" -gt "$n2" ] 2>/dev/null; then return 0
        elif [ "$n1" -lt "$n2" ] 2>/dev/null; then return 1
        fi
    done
    return 1
}

# detect_previous_version → imprime versão anterior a partir do backup ou do config
detect_previous_version() {
    # Tenta detectar do backup
    local backup_file
    backup_file=$(ls -1 "${SCRIPT_DIR}/RomMSync.sh"*.bak_v* 2>/dev/null | head -1)
    if [ -n "$backup_file" ]; then
        local ver
        ver=$(echo "$backup_file" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | tr -d 'v')
        if [ -n "$ver" ]; then
            echo "$ver"
            return 0
        fi
    fi
    # Tenta detectar do config
    if [ -f "$CONFIG_FILE" ]; then
        local conf_ver
        conf_ver=$(grep -m1 '^ROMMSYNC_CONF_VERSION=' "$CONFIG_FILE" 2>/dev/null \
                    | cut -d'"' -f2 | tr -d 'v')
        if [ -n "$conf_ver" ]; then
            echo "$conf_ver"
            return 0
        fi
    fi
    # Fallback: assume 1.0.0
    echo "1.0.0"
    return 0
}

# --- Arquivos a Limpar (Forward-Compatible) --------------------------------
# Cada entrada: padrão para arquivos que não existem mais nesta versão.
# Executa 'rm -f' em qualquer match — seguro mesmo se o arquivo não existir.

cleanup_deprecated_files() {
    log "Limpando arquivos obsoletos..."

    # Arquivos removidos na v1.3.0
    # (nenhum por enquanto — primeiro release pós-refatoração)

    # Arquivos que NÃO devem existir no diretório
    rm -f "${SCRIPT_DIR}/"*.log 2>/dev/null    # Logs ficam em /tmp/
    rm -f "${SCRIPT_DIR}/"*.tmp 2>/dev/null
    rm -f "${SCRIPT_DIR}/"*.bak 2>/dev/null    # Backups antigos
    rm -f "${SCRIPT_DIR}/"*.bak_v* 2>/dev/null # Backups de versão

    log "Limpeza concluída."
}

# --- Migrações de Configuração ---------------------------------------------
# Cada função aplica as mudanças necessárias para saltar de uma versão
# específica para a próxima. As migrações são encadeadas automaticamente.

migrate_to_110() {
    log "Migrando config para v1.1.0..."

    # Garante que o campo CONF_VERSION existe
    if ! grep -q '^ROMMSYNC_CONF_VERSION=' "$CONFIG_FILE"; then
        echo 'ROMMSYNC_CONF_VERSION="1.1.0"' >> "$CONFIG_FILE"
    else
        sed -i 's/^ROMMSYNC_CONF_VERSION=.*/ROMMSYNC_CONF_VERSION="1.1.0"/' "$CONFIG_FILE"
    fi

    log "Migração v1.1.0 concluída."
}

migrate_to_120() {
    log "Migrando config para v1.2.0..."

    # Adiciona AUTOUPDATE se não existe
    if ! grep -q '^AUTOUPDATE=' "$CONFIG_FILE"; then
        echo 'AUTOUPDATE="on"' >> "$CONFIG_FILE"
    fi

    # Atualiza versão
    sed -i 's/^ROMMSYNC_CONF_VERSION=.*/ROMMSYNC_CONF_VERSION="1.2.0"/' "$CONFIG_FILE"

    log "Migração v1.2.0 concluída."
}

migrate_to_130() {
    log "Migrando config para v1.3.0..."

    # Cache layer adicionado — não requer mudança de config
    # mas atualiza a versão
    sed -i 's/^ROMMSYNC_CONF_VERSION=.*/ROMMSYNC_CONF_VERSION="1.3.0"/' "$CONFIG_FILE"

    log "Migração v1.3.0 concluída."
}

migrate_to_140() {
    log "Migrando config para v1.4.0..."

    # Cache TTL configurável — opcional
    if ! grep -q '^CACHE_TTL=' "$CONFIG_FILE"; then
        echo 'CACHE_TTL="3600"' >> "$CONFIG_FILE"
    fi

    sed -i 's/^ROMMSYNC_CONF_VERSION=.*/ROMMSYNC_CONF_VERSION="1.4.0"/' "$CONFIG_FILE"

    log "Migração v1.4.0 concluída."
}

migrate_to_141() {
    log "Migrando config para v1.4.1..."

    # Updater modular — nenhuma mudança de config, apenas bump de versão
    sed -i 's/^ROMMSYNC_CONF_VERSION=.*/ROMMSYNC_CONF_VERSION="1.4.1"/' "$CONFIG_FILE"

    log "Migração v1.4.1 concluída."
}

# Encadeia migrações na ordem cronológica
apply_migrations() {
    local current="${ROMMSYNC_CONF_VERSION:-0.0.0}"

    log "Versão atual da config: $current"
    log "Versão do script: $NEW_VERSION"

    # Config sem versão — recria a partir dos dados existentes
    if [ "$current" = "0.0.0" ] || [ -z "$current" ]; then
        log "Config antiga detectada (sem versão). Recriando..."
        if [ -n "${ROMM_URL:-}" ] && [ -n "${ROMM_USER:-}" ]; then
            local old_pass="${ROMM_PASS:-}"
            local old_b64="${ROMM_AUTH_B64:-}"
            cat > "$CONFIG_FILE" <<EOF
# RomM-Sync-Tool Configuration
# Gerado em: $(date)
# Migrado automaticamente pelo updater v${NEW_VERSION}
ROMMSYNC_CONF_VERSION="${NEW_VERSION}"
ROMM_URL="${ROMM_URL}"
ROMM_USER="${ROMM_USER}"
ROMM_PASS="${old_pass}"
ROMM_AUTH_B64="${old_b64}"
AUTOUPDATE="on"
CACHE_TTL="3600"
EOF
            chmod 600 "$CONFIG_FILE"
            current="${NEW_VERSION}"
            log "Config recriada com versão ${NEW_VERSION}"
        else
            log "AVISO: dados insuficientes para recriar config."
            return
        fi
    fi

    # Migrações encadeadas — aplica todas as versões entre current e NEW_VERSION
    local versions=("1.0.0" "1.1.0" "1.2.0" "1.3.0" "1.4.0" "1.4.1")
    local apply=0
    local prev=""
    for ver in "${versions[@]}"; do
        if [ "$apply" = "1" ]; then
            case "$prev" in
                "1.0.0") migrate_to_110 ;;
                "1.1.0") migrate_to_120 ;;
                "1.2.0") migrate_to_130 ;;
                "1.3.0") migrate_to_140 ;;
                "1.4.0") migrate_to_141 ;;
            esac
        fi
        if [ "$ver" = "$current" ]; then
            apply=1
        fi
        prev="$ver"
    done

    # Atualiza versão final se chegamos até a última migração
    if [ "$apply" = "1" ] && [ -n "$prev" ]; then
        sed -i "s/^ROMMSYNC_CONF_VERSION=.*/ROMMSYNC_CONF_VERSION=\"${NEW_VERSION}\"/" "$CONFIG_FILE"
    fi

    log "Migrações concluídas."
}

# --- Exibe Changelog -------------------------------------------------------

show_changelog() {
    local changelog_file="${SCRIPT_DIR}/CHANGELOG.md"
    # Extrai linhas até a primeira linha que começa com #
    local changelog=""
    if [ -f "$changelog_file" ]; then
        changelog=$(head -30 "$changelog_file")
    fi

    if [ -n "$changelog" ]; then
        dialog --clear --backtitle "RomM-Sync-Tool - Atualização" \
               --title "Mudanças nesta versão" \
               --msgbox "$changelog" 18 65 2>&1
    fi
}

# --- Entrypoint ------------------------------------------------------------

main() {
    log "=== Updater v${NEW_VERSION} iniciado ==="

    # Detecta versão anterior
    local prev_version="${1:-$(detect_previous_version)}"
    log "Versão anterior: $prev_version → nova: $NEW_VERSION"

    # Se versão anterior é igual ou mais nova, nada a fazer
    if [ "$prev_version" = "$NEW_VERSION" ]; then
        log "Versões iguais. Nenhuma migração necessária."
        return
    fi

    # Carrega config se existir
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi

    # Aplica migrações
    apply_migrations

    # Limpa arquivos obsoletos
    cleanup_deprecated_files

    # Exibe changelog
    show_changelog

    log "=== Updater concluído ==="
}

# --- Variáveis de ambiente (passadas pelo RomMSync.sh) ---------------------
# NEW_VERSION: versão do script recém-instalado
# SCRIPT_DIR: diretório onde o script está instalado
: "${NEW_VERSION:=?}"
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

main "$@"
