#!/bin/bash
# =============================================================================
# RomM-Sync-Tool v1.1
# Utilitário de sincronização de ROMs e Saves para ArkOS via API do RomM
# Desenvolvido para consoles portáteis ARM (R36S, RG351P, RG353P, etc.)
# =============================================================================

set -euo pipefail

# Garante terminal compatível com framebuffer do ArkOS (necessário para dialog)
export TERM="${TERM:-linux}"

# --- Constantes -----------------------------------------------------------
readonly SCRIPT_NAME="RomM-Sync-Tool"
readonly VERSION="1.2.9"
readonly CONFIG_FILE="${HOME}/.rommsync.conf"
readonly TMP_DIR="/tmp/rommsync"
# Raízes onde o ArkOS armazena ROMs e saves
readonly ROMS_ROOTS=("/roms" "/roms2")
readonly LOG_FILE="/tmp/rommsync.log"

# GitHub — usado pelo auto-updater
readonly GITHUB_REPO="fernandodimas/ArkOS_RomM-Sync-Tool"
readonly GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/main/RomMSync.sh"
# Arquivo de config para import sem teclado (mesmo diretório do script)
# Ex: /opt/system/Tools/rommsync_config.conf
readonly CONFIG_IMPORT_NAME="rommsync_config.conf"

# TTY da tela física do ArkOS
CURR_TTY="/dev/tty1"

# PID do gptokeyb (mapeador de controle → teclado)
GPTOKEYB_PID=""
# Caminho do gptokeyb e config no ArkOS4clone (@lcdyk)
GPTOKEYB_BIN="/opt/inttools/gptokeyb"
GPTOKEYB_CFG="/opt/inttools/keys.gptk"
GPTOKEYB_DB="/opt/inttools/gamecontrollerdb.txt"

# Tamanho padrão para dialog em telas 640x480
readonly DLG_H=15
readonly DLG_W=55

# Backtitle global com versão — aparece no topo de TODOS os dialogs
BACKTITLE="$SCRIPT_NAME  v$VERSION"

# Mapeamento: slug do RomM → pasta do ArkOS
# Formato: "romm-slug|arkos-folder"
declare -A PLATFORM_MAP=(
    ["gba"]="gba"
    ["gbc"]="gbc"
    ["gb"]="gb"
    ["snes"]="snes"
    ["nes"]="nes"
    ["n64"]="n64"
    ["genesis"]="megadrive"
    ["megadrive"]="megadrive"
    ["game-boy-advance"]="gba"
    ["game-boy-color"]="gbc"
    ["game-boy"]="gb"
    ["super-nintendo"]="snes"
    ["nintendo"]="nes"
    ["nintendo-64"]="n64"
    ["sega-genesis"]="megadrive"
    ["sega-mega-drive"]="megadrive"
    ["playstation"]="psx"
    ["psx"]="psx"
    ["ps1"]="psx"
    ["psp"]="psp"
    ["nds"]="nds"
    ["nintendo-ds"]="nds"
    ["dreamcast"]="dreamcast"
    ["arcade"]="arcade"
    ["fba"]="fba"
    ["mame"]="mame"
    ["neogeo"]="neogeo"
    ["atari-2600"]="atari2600"
    ["atari2600"]="atari2600"
    ["atari-7800"]="atari7800"
    ["lynx"]="lynx"
    ["wonderswan"]="wonderswan"
    ["wonderswan-color"]="wonderswancolor"
    ["pcengine"]="pcengine"
    ["pc-engine"]="pcengine"
    ["turbografx-16"]="pcengine"
    ["gamegear"]="gamegear"
    ["game-gear"]="gamegear"
    ["mastersystem"]="mastersystem"
    ["sega-master-system"]="mastersystem"
    ["saturn"]="saturn"
    ["sega-saturn"]="saturn"
    ["virtualboy"]="virtualboy"
    ["virtual-boy"]="virtualboy"
    ["n3ds"]="3ds"
    ["3ds"]="3ds"
    ["ngpc"]="ngpc"
    ["neo-geo-pocket"]="ngpc"
    ["gba-gbc"]="gba"
    ["sg1000"]="sg1000"
    ["sega-sg-1000"]="sg1000"
)

# --- Funções Utilitárias --------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

cleanup() {
    log "Limpando arquivos temporários..."
    rm -rf "$TMP_DIR"
    log "Finalizado."
}

# Garante limpeza ao sair
trap cleanup EXIT INT TERM

ensure_tmp() {
    mkdir -p "$TMP_DIR"
}

# check_dependencies: verifica cada ferramenta necessária e exibe tabela visual.
# Skill ativada: Config Persistence — dependências checadas ANTES do menu principal.
check_dependencies() {
    # Ferramentas obrigatórias e suas descrições
    declare -A DEP_DESC=(
        ["dialog"]="Interface TUI  (menus/caixas)"
        ["jq"]="Parser JSON    (dados da API)"
        ["curl"]="HTTP Client    (chamadas à API)"
        ["zip"]="Compactador    (backup de saves)"
        ["wget"]="Downloader     (download de ROMs)"
    )
    # Ferramentas opcionais
    declare -A OPT_DESC=(
        ["rclone"]="Motor de sync  (uploads grandes — opcional)"
    )

    local missing=()
    local status_lines="DEPENDÊNCIA       STATUS         DESCRIÇÃO\n"
    status_lines+="─────────────────────────────────────────────────────\n"

    for cmd in dialog jq curl zip wget; do
        if command -v "$cmd" &>/dev/null; then
            status_lines+="$(printf '%-16s  %-13s  %s' "$cmd" '✓ OK' "${DEP_DESC[$cmd]}")\n"
        else
            status_lines+="$(printf '%-16s  %-13s  %s' "$cmd" '✗ AUSENTE' "${DEP_DESC[$cmd]}")\n"
            missing+=("$cmd")
        fi
    done

    status_lines+="─────────────────────────────────────────────────────\n"

    # Checa rclone (opcional — influencia método de upload)
    if command -v rclone &>/dev/null; then
        RCLONE_AVAILABLE=1
        status_lines+="$(printf '%-16s  %-13s  %s' "rclone" '✓ Disponível' "${OPT_DESC[rclone]}")\n"
    else
        RCLONE_AVAILABLE=0
        status_lines+="$(printf '%-16s  %-13s  %s' "rclone" '○ Não inst.' "${OPT_DESC[rclone]}")\n"
    fi

    # Se há dependência faltando, oferece instalar ou sair
    if [ ${#missing[@]} -gt 0 ]; then
        local pkg_list="${missing[*]}"

        # Detecta gerenciador de pacotes disponível
        local pkg_update="" pkg_install=""
        if command -v apt-get &>/dev/null; then
            pkg_update="sudo apt-get update -y"
            pkg_install="sudo apt-get install -y"
        elif command -v opkg &>/dev/null; then
            pkg_update="opkg update"
            pkg_install="opkg install"
        fi

        if command -v dialog &>/dev/null; then
            # Mostra quais pacotes faltam e pergunta se quer instalar
            dialog --backtitle "$BACKTITLE" \
                   --title "⚠  Dependências Ausentes" \
                   --cr-wrap \
                   --yesno "$(printf '%b' "$status_lines")\n\nPacotes necessários: $pkg_list\n\nDeseja instalar agora?" \
                   22 62 > "$CURR_TTY"
            local resp=$?

            if [ "$resp" -eq 0 ]; then
                if [ -z "$pkg_update" ]; then
                    dialog --backtitle "$BACKTITLE" \
                           --title "Erro" \
                           --msgbox "Nenhum gerenciador de pacotes encontrado.\n\nInstale manualmente: $pkg_list" \
                           $DLG_H $DLG_W > "$CURR_TTY"
                    exit 1
                fi

                # Usuário escolheu instalar
                dialog --backtitle "$BACKTITLE" \
                       --title "Instalando Dependências" \
                       --infobox "Atualizando lista de pacotes...\nAguarde..." \
                       7 $DLG_W > "$CURR_TTY"

                local log_tmp="${TMP_DIR}/pkg_install.log"
                mkdir -p "$TMP_DIR"
                {
                    # Conserta dpkg interrompido (caso exista estado pendente)
                    sudo dpkg --configure -a 2>&1 || true
                    $pkg_update 2>&1 || true   # falha de rede não é fatal
                    $pkg_install $pkg_list 2>&1
                } | tee "$log_tmp" | \
                dialog --backtitle "$BACKTITLE" \
                       --title "Instalando Dependências" \
                       --programbox "Saída do gerenciador de pacotes:" \
                       20 $DLG_W > "$CURR_TTY"

                # Verifica se tudo foi instalado
                local still_missing=()
                for cmd in "${missing[@]}"; do
                    command -v "$cmd" &>/dev/null || still_missing+=("$cmd")
                done

                if [ ${#still_missing[@]} -eq 0 ]; then
                    dialog --backtitle "$BACKTITLE" \
                           --title "Instalação Concluída" \
                           --msgbox "✓ Dependências instaladas com sucesso!\n\nO script continuará normalmente." \
                           $DLG_H $DLG_W > "$CURR_TTY"
                else
                    dialog --backtitle "$BACKTITLE" \
                           --title "Erro na Instalação" \
                           --msgbox "✗ Ainda faltam: ${still_missing[*]}\n\nVeja o log em:\n$log_tmp\n\nO script será encerrado." \
                           $DLG_H $DLG_W > "$CURR_TTY"
                    clear
                    exit 1
                fi
            else
                # Usuário escolheu não instalar / pressionou Não
                local install_cmd="${pkg_install:-"apt-get install -y"}"
                dialog --backtitle "$BACKTITLE" \
                       --title "Encerrando" \
                       --msgbox "Instalação cancelada.\n\nInstale manualmente quando quiser:\n  $pkg_update\n  $install_cmd $pkg_list" \
                       $DLG_H $DLG_W > "$CURR_TTY"
                clear
                exit 0
            fi
        else
            echo ""
            echo "=== $SCRIPT_NAME: Dependências Ausentes ==="
            printf '%b' "$status_lines"
            echo ""
            local install_cmd="${pkg_install:-"apt-get install -y"}"
            echo "Instale com:  $pkg_update && $install_cmd $pkg_list"
            echo ""
            exit 1
        fi
    fi



    log "Dependências OK. rclone disponível: $RCLONE_AVAILABLE"
}

check_wifi() {
    log "Verificando conectividade de rede..."

    # Método 1: verifica rota padrão (não requer root, não usa ICMP)
    if ip route 2>/dev/null | grep -q "^default"; then
        log "Rede OK (rota padrão detectada)."
        return 0
    fi

    # Método 2: curl TCP para 8.8.8.8 porta 53 (DNS over TCP, sem ICMP)
    if curl --silent --connect-timeout 3 --max-time 4 \
            "http://connectivity-check.ubuntu.com/" \
            -o /dev/null 2>/dev/null; then
        log "Rede OK (curl connectivity-check)."
        return 0
    fi

    # Método 3: ping (pode falhar sem root em alguns sistemas)
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null 2>&1 || \
       ping -c 1 -W 3 1.1.1.1 &>/dev/null 2>&1; then
        log "Rede OK (ping)."
        return 0
    fi

    # Nenhum método confirmou conectividade — avisa mas permite continuar
    log "AVISO: Nenhum método detectou conectividade. Wi-Fi pode não estar ativo."
    dialog --backtitle "$BACKTITLE" \
           --title "Sem Conexão Detectada" \
           --yesno "⚠  Não foi possível confirmar a conexão Wi-Fi.\n\nVerifique se o Wi-Fi está conectado.\n\nDeseja tentar continuar mesmo assim?" \
           $DLG_H $DLG_W > "$CURR_TTY"
    local resp=$?
    if [ "$resp" -ne 0 ]; then
        exit 1
    fi
    log "Usuário optou por continuar sem confirmação de rede."
}

# --- Configuração ---------------------------------------------------------

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

save_config() {
    local url="$1"
    local user="$2"
    local pass="$3"

    # Gera Basic Auth Base64
    local b64
    b64=$(printf '%s:%s' "$user" "$pass" | base64 | tr -d '\n')

    cat > "$CONFIG_FILE" <<EOF
# RomM-Sync-Tool Configuration
# Gerado em: $(date)
ROMM_URL="${url%/}"
ROMM_USER="${user}"
ROMM_PASS="${pass}"
ROMM_AUTH_B64="${b64}"
EOF
    chmod 600 "$CONFIG_FILE"
    log "Configuração salva em $CONFIG_FILE"
}

setup_config() {
    local url user pass

    dialog --backtitle "$BACKTITLE" \
           --title "Configuração Inicial" \
           --msgbox "Bem-vindo ao $SCRIPT_NAME v$VERSION!\n\nEscolha como fornecer as configurações\ndo servidor RomM." \
           $DLG_H $DLG_W > "$CURR_TTY"

    # --- Menu de método de configuração ------------------------------------
    local method
    method=$(dialog --output-fd 1 \
                    --backtitle "$BACKTITLE" \
                    --title "Como configurar?" \
                    --menu "Escolha uma opção:" $DLG_H $DLG_W 4 \
                    "sd"     "Importar arquivo do cartão SD (recomendado)" \
                    "manual" "Digitar manualmente (requer teclado USB)" \
                    "ssh"    "Ver instruções para configurar via SSH" \
                    2>"$CURR_TTY") || return 1

    case "$method" in

      # ----------------------------------------------------------------
      # Opção 1: Importar do cartão SD
      # O usuário cria /roms/rommsync_config.conf no PC antes de rodar
      # ----------------------------------------------------------------
      sd)
        # Pasta do script em execução (ex: /opt/system/Tools)
        local script_dir
        script_dir=$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")
        local import_path="${script_dir}/${CONFIG_IMPORT_NAME}"

        local import_info="Coloque o arquivo na mesma pasta do app:\n\n  $import_path\n\nFormato do arquivo:\n  ROMM_URL=\"http://SEU_IP:PORTA\"\n  ROMM_USER=\"usuario\"\n  ROMM_PASS=\"senha\"\n\nCrie no PC, copie via SD/USB ou SSH e pressione OK."
        dialog --backtitle "$BACKTITLE" \
               --title "Importar Arquivo de Config" \
               --msgbox "$import_info" \
               16 $DLG_W > "$CURR_TTY"

        if [ ! -f "$import_path" ]; then
            dialog --backtitle "$BACKTITLE" \
                   --title "Arquivo não encontrado" \
                   --msgbox "Arquivo não encontrado em:\n  $import_path\n\nCrie o arquivo e tente novamente." \
                   $DLG_H $DLG_W > "$CURR_TTY"
            return 1
        fi

        # Lê as variáveis do arquivo
        local imp_url imp_user imp_pass
        imp_url=$(grep  -m1 'ROMM_URL='  "$import_path" | cut -d= -f2- | tr -d '"' | xargs)
        imp_user=$(grep -m1 'ROMM_USER=' "$import_path" | cut -d= -f2- | tr -d '"' | xargs)
        imp_pass=$(grep -m1 'ROMM_PASS=' "$import_path" | cut -d= -f2- | tr -d '"' | xargs)

        if [ -z "$imp_url" ] || [ -z "$imp_user" ]; then
            dialog --backtitle "$BACKTITLE" \
                   --title "Arquivo Inválido" \
                   --msgbox "O arquivo não contém ROMM_URL e ROMM_USER.\nVerifique o formato e tente novamente." \
                   $DLG_H $DLG_W > "$CURR_TTY"
            return 1
        fi

        url="$imp_url"
        user="$imp_user"
        pass="$imp_pass"
        log "Config importada de $import_path: url=$url user=$user"
        ;;

      # ----------------------------------------------------------------
      # Opção 2: Digitar manualmente (requer teclado USB conectado)
      # ----------------------------------------------------------------
      manual)
        url=$(dialog --output-fd 1 --backtitle "$BACKTITLE" \
                     --title "URL do Servidor" \
                     --inputbox "Digite a URL do RomM:\n(ex: http://192.168.1.100:3000)" \
                     $DLG_H $DLG_W "http://" \
                     2>"$CURR_TTY") || return 1

        user=$(dialog --output-fd 1 --backtitle "$BACKTITLE" \
                      --title "Usuário" \
                      --inputbox "Nome de usuário do RomM:" \
                      $DLG_H $DLG_W "" \
                      2>"$CURR_TTY") || return 1

        pass=$(dialog --output-fd 1 --backtitle "$BACKTITLE" \
                      --title "Senha" \
                      --passwordbox "Senha do RomM:" \
                      $DLG_H $DLG_W "" \
                      2>"$CURR_TTY") || return 1
        ;;

      # ----------------------------------------------------------------
      # Opção 3: Instruções SSH
      # ----------------------------------------------------------------
      ssh)
        local hostname_str
        hostname_str=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "<IP-DO-CONSOLE>")
        dialog --backtitle "$BACKTITLE" \
               --title "Configurar via SSH" \
               --msgbox "No seu PC, abra um terminal e execute:\n\n  ssh ark@${hostname_str}\n  (senha padrão: ark)\n\nDepois crie o arquivo de config:\n\n  nano ~/.rommsync.conf\n\nFormato:\n  ROMM_URL=\"http://IP:PORTA\"\n  ROMM_USER=\"usuario\"\n  ROMM_PASS=\"senha\"\n  ROMM_AUTH_B64=\"base64(user:pass)\"\n\nSalve (Ctrl+X) e relance o app." \
               22 $DLG_W > "$CURR_TTY"
        return 1  # volta ao menu para tentar novamente
        ;;
    esac

    # --- Testa a conexão com os dados obtidos ----------------------------
    dialog --backtitle "$BACKTITLE" \
           --infobox "Testando conexão com o servidor..." \
           5 $DLG_W > "$CURR_TTY"

    local test_b64
    test_b64=$(printf '%s:%s' "$user" "$pass" | base64 | tr -d '\n')

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                     -H "Authorization: Basic $test_b64" \
                     "${url%/}/api/heartbeat" 2>/dev/null || echo "000")

    if [ "$http_code" != "200" ]; then
        dialog --backtitle "$BACKTITLE" \
               --title "Erro de Conexão" \
               --yesno "Não foi possível conectar (HTTP $http_code).\n\nDeseja salvar a configuração mesmo assim?" \
               $DLG_H $DLG_W > "$CURR_TTY" || return 1
    fi

    save_config "$url" "$user" "$pass"

    dialog --backtitle "$BACKTITLE" \
           --title "Sucesso" \
           --msgbox "✓ Configuração salva!\n\nServidor: $url\nUsuário:  $user" \
           $DLG_H $DLG_W > "$CURR_TTY"
}

# --- Funções de API -------------------------------------------------------

api_get() {
    local endpoint="$1"
    local response
    response=$(curl -s \
                    -H "Authorization: Basic $ROMM_AUTH_B64" \
                    -H "Accept: application/json" \
                    "${ROMM_URL}${endpoint}" 2>&1)
    echo "$response"
}

api_post_file() {
    local endpoint="$1"
    local file="$2"
    local extra_args="${3:-}"
    local response
    # shellcheck disable=SC2086
    response=$(curl -s \
                    -X POST \
                    -H "Authorization: Basic $ROMM_AUTH_B64" \
                    -F "file=@${file}" \
                    $extra_args \
                    "${ROMM_URL}${endpoint}" 2>&1)
    echo "$response"
}

# =============================================================================
# SKILL: JSON-to-Menu Mapping
# Converte o array JSON da API do RomM em um array flat compatível com
# `dialog --menu`. Esse é o ponto onde a maioria dos scripts falha porque:
#   1. jq emite várias linhas — arrays bash precisam de leitura segura
#   2. Nomes com espaços/aspas quebram o split de palavras do shell
#   3. IDs numéricos que viram índices causam dessincronização
#
# Uso:
#   json_to_menu_entries <json_array> <id_field> <label_template> <result_array_name>
#
#   json_array       : JSON bruto (string)
#   id_field         : campo jq para o valor de "tag" do dialog (ex: ".id")
#   label_template   : expressão jq que gera o rótulo (ex: '.name + " (" + .slug + ")"')
#   result_array_name: nome do array bash de saída (passado por referência via eval)
#
# Retorno: popula o array nomeado em result_array_name com pares [tag, item, tag, item…]
# =============================================================================
json_to_menu_entries() {
    local json="$1"
    local id_field="$2"
    local label_tpl="$3"
    local -n _out_array="$4"   # nameref: modificação direta do array do chamador

    _out_array=()              # garante array limpo

    # Processa cada objeto do array JSON como uma linha compacta
    # O truque principal: usar \u0001 (ASCII SOH) como delimitador interno
    # para separar id do label sem depender de espaço/newline
    while IFS= read -r entry; do
        # Cada 'entry' vem no formato "ID\u0001LABEL"
        local tag label
        tag="${entry%%$'\x01'*}"
        label="${entry#*$'\x01'}"

        # Pula entradas vazias ou com id nulo
        [ -z "$tag" ] || [ "$tag" = "null" ] && continue

        # Trunca label a 48 chars para caber no dialog (55 colunas - 7 de margem)
        label="${label:0:48}"

        _out_array+=("$tag" "$label")
    done < <(
        # jq monta cada linha como "id\u0001label" — saída segura, sem newlines em nomes
        echo "$json" | jq -r \
            --argjson id_field  "null" \
            ".[] | (${id_field} | tostring) + \"\u0001\" + (${label_tpl})" \
            2>/dev/null
    )

    log "json_to_menu_entries: ${#_out_array[@]} entradas geradas (${#_out_array[@]}/2 itens)"
}

# =============================================================================
# SKILL: Rclone Integration
# Motor de transferência alternativo para uploads grandes.
# O rclone já vem pré-instalado no ArkOS e suporta retomada (--retries).
# Usa o script RomMSync como interface, delegando a transferência ao rclone
# via remote HTTP com autenticação Basic.
#
# Estratégia de fallback:
#   1. Se rclone está disponível E arquivo > RCLONE_THRESHOLD → usa rclone
#   2. Caso contrário → usa curl (comportamento padrão)
# =============================================================================

# Limite em bytes acima do qual o rclone é preferido (padrão: 50 MB)
readonly RCLONE_THRESHOLD=$((50 * 1024 * 1024))

# Upload de arquivo via rclone (remote HTTP configurado on-the-fly)
rclone_upload() {
    local file="$1"       # arquivo local a enviar
    local dest_url="$2"   # URL HTTP de destino completa
    local label="$3"      # rótulo para o dialog --gauge

    local file_size
    file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)

    log "rclone_upload: $file ($file_size bytes) → $dest_url"

    # Cria um remote HTTP temporário na config em memória do rclone
    local rclone_remote="rommsync_tmp"
    local rclone_conf="${TMP_DIR}/rclone_tmp.conf"

    # Extrai host base da URL de destino
    local base_url
    base_url=$(echo "$dest_url" | grep -oP '^https?://[^/]+')
    local endpoint_path
    endpoint_path="${dest_url#"$base_url"}"

    # Grava config temporária do rclone (nunca persiste em disco além do /tmp)
    cat > "$rclone_conf" <<EOF
[${rclone_remote}]
type = http
url = ${base_url}
EOF

    # Executa upload com rclone copyto, autenticação via header
    # --retries 3: retentativas automáticas em falhas de rede
    # --buffer-size 4M: buffer adequado para ARM com pouca RAM
    # --progress: saída de progresso parseável
    local exit_code=0
    rclone copyto \
        --config "$rclone_conf" \
        --header "Authorization: Basic $ROMM_AUTH_B64" \
        --retries 3 \
        --low-level-retries 5 \
        --buffer-size 4M \
        --no-check-certificate \
        --progress \
        --stats 1s \
        "$file" \
        "${rclone_remote}:${endpoint_path}" \
        2>&1 | \
    # Parseia saída do rclone para extrair % e alimentar --gauge
    grep --line-buffered -oP '\d+(?=%)' | \
    while IFS= read -r pct; do
        echo "$pct"
    done | \
    dialog --backtitle "$BACKTITLE" \
           --title "Enviando (rclone)..." \
           --gauge "$label" \
           7 $DLG_W 0 || exit_code=$?

    rm -f "$rclone_conf"

    if [ "$exit_code" -ne 0 ]; then
        log "ERRO: rclone_upload falhou (exit $exit_code)"
        return 1
    fi

    log "rclone_upload: concluído com sucesso."
    return 0
}

# Escolhe entre curl e rclone baseado no tamanho do arquivo e disponibilidade
smart_upload() {
    local endpoint="$1"   # ex: /api/saves/upload
    local file="$2"
    local extra_curl_args="${3:-}"

    local file_size
    file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)

    local full_url="${ROMM_URL}${endpoint}"

    if [ "${RCLONE_AVAILABLE:-0}" = "1" ] && [ "$file_size" -gt "$RCLONE_THRESHOLD" ]; then
        log "smart_upload: arquivo grande ($file_size bytes) → usando rclone"
        rclone_upload "$file" "$full_url" "Enviando $(basename "$file")…"
    else
        log "smart_upload: arquivo pequeno ou rclone indisponível → usando curl"
        # shellcheck disable=SC2086
        api_post_file "$endpoint" "$file" $extra_curl_args
    fi
}

# --- Backup de Saves ------------------------------------------------------

# ---------------------------------------------------------------------------
# collect_saves_index
# Percorre ROMS_ROOTS (/roms e /roms2) buscando saves de forma recursiva.
# Os saves podem estar:
#   - Na raiz da pasta do console:  /roms/snes/JogoA.srm
#   - Em subpastas dentro do console: /roms/snes/JogoA/JogoA.state
#
# Saída (stdout): linhas no formato "root|console|count"
#   Ex: /roms|snes|3
#       /roms2|psx|1
# ---------------------------------------------------------------------------
collect_saves_index() {
    local root console count
    for root in "${ROMS_ROOTS[@]}"; do
        [ -d "$root" ] || continue
        # Cada subpasta direta de $root é um console
        while IFS= read -r -d '' console_dir; do
            console=$(basename "$console_dir")
            # Busca saves recursivamente até 3 níveis abaixo do console
            # (console/save.srm  ou  console/subpasta/save.srm)
            count=$(find "$console_dir" \
                        -mindepth 1 -maxdepth 3 -type f \
                        \( -name "*.srm" \
                           -o -name "*.state" \
                           -o -name "*.state[0-9]*" \
                           -o -name "*.sav" \) \
                        2>/dev/null | wc -l | tr -d ' ')
            if [ "${count:-0}" -gt 0 ]; then
                printf '%s|%s|%s\n' "$root" "$console" "$count"
            fi
        done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    done
}

# ---------------------------------------------------------------------------
# backup_saves
# Menu para selecionar console(s) e fazer backup dos saves encontrados
# pela collect_saves_index. O zip preserva a estrutura de pastas relativa
# para que o RomM identifique a qual console cada save pertence.
# ---------------------------------------------------------------------------
backup_saves() {
    ensure_tmp
    log "Iniciando backup de saves..."

    dialog --backtitle "$BACKTITLE" \
           --infobox "Buscando saves em ${ROMS_ROOTS[*]}..." \
           5 $DLG_W > "$CURR_TTY"

    # ── Constrói índice: arrays paralelos root[] / console[] / count[] ────────
    local -a idx_root idx_console idx_count
    local idx=0

    while IFS='|' read -r r c n; do
        idx_root[$idx]="$r"
        idx_console[$idx]="$c"
        idx_count[$idx]="$n"
        idx=$((idx + 1))
    done < <(collect_saves_index)

    if [ "$idx" -eq 0 ]; then
        dialog --backtitle "$BACKTITLE" \
               --title "Backup de Saves" \
               --msgbox "Nenhum save encontrado em:\n${ROMS_ROOTS[*]}\n\nExtensões buscadas: .srm .state .sav" \
               $DLG_H $DLG_W > "$CURR_TTY"
        return
    fi

    # ── Monta menu ─────────────────────────────────────────────────────────────
    # Chave: índice numérico; label: "console (N saves) [/root]"
    local -a menu_entries=("all" "★ Todos os sistemas")
    local i
    for i in $(seq 0 $((idx - 1))); do
        local root_short
        root_short=$(basename "${idx_root[$i]}")
        menu_entries+=("$i" "${idx_console[$i]}  (${idx_count[$i]} saves) [/${root_short}/]")
    done

    local choice
    choice=$(dialog --output-fd 1 --backtitle "$BACKTITLE" \
                    --title "Backup de Saves" \
                    --menu "Selecione o console para backup:" \
                    $DLG_H $DLG_W 10 \
                    "${menu_entries[@]}" \
                    2>"$CURR_TTY") || return

    # ── Determina quais entradas processar ─────────────────────────────────────
    local -a sel_indices
    if [ "$choice" = "all" ]; then
        for i in $(seq 0 $((idx - 1))); do sel_indices+=("$i"); done
    else
        sel_indices=("$choice")
    fi

    # ── Processa cada console selecionado ──────────────────────────────────────
    local total=${#sel_indices[@]}
    local current=0
    local ok_count=0
    local fail_count=0

    for i in "${sel_indices[@]}"; do
        current=$((current + 1))
        local pct=$(( (current * 90) / total ))
        local root="${idx_root[$i]}"
        local console="${idx_console[$i]}"
        local console_dir="${root}/${console}"
        local zip_file="${TMP_DIR}/saves_${console}_$(date '+%Y%m%d_%H%M%S').zip"

        echo "$pct" | dialog --backtitle "$BACKTITLE" \
                              --title "Backup: $console" \
                              --gauge "Compactando saves de '$console'..." \
                              7 $DLG_W 0 > "$CURR_TTY"

        log "Compactando saves de $console (root: $root)..."

        # Zip com estrutura de pastas preservada:
        # cd no root faz com que o zip armazene 'console/save.srm'
        # e 'console/subpasta/save.srm' — sem colisões de nomes.
        (
            cd "$root" || exit 1
            find "$console" \
                 -mindepth 1 -maxdepth 3 -type f \
                 \( -name "*.srm" \
                    -o -name "*.state" \
                    -o -name "*.state[0-9]*" \
                    -o -name "*.sav" \) \
                 -print0 2>/dev/null \
            | xargs -0 zip "$zip_file" &>/dev/null
        )

        local zip_ok=$?
        if [ "$zip_ok" -ne 0 ] || [ ! -s "$zip_file" ]; then
            log "AVISO: Falha ao compactar saves de $console"
            fail_count=$((fail_count + 1))
            rm -f "$zip_file"
            continue
        fi

        echo "$pct" | dialog --backtitle "$BACKTITLE" \
                              --title "Backup: $console" \
                              --gauge "Enviando '$console' para o RomM..." \
                              7 $DLG_W "$pct" > "$CURR_TTY"

        log "Enviando $zip_file para o RomM (smart_upload)..."

        local response
        response=$(smart_upload \
            "/api/saves/upload" \
            "$zip_file" \
            "-F platform_slug=$console")

        log "Resposta do servidor: $response"
        ok_count=$((ok_count + 1))
        rm -f "$zip_file"
    done

    echo "100" | dialog --backtitle "$BACKTITLE" \
                         --title "Backup" \
                         --gauge "Concluído!" \
                         7 $DLG_W 100 > "$CURR_TTY"
    sleep 1

    local summary="✓ Backup concluído!\n\n"
    summary+="Enviados: $ok_count console(s)\n"
    [ "$fail_count" -gt 0 ] && summary+="Falhas:   $fail_count (veja o log)"

    dialog --backtitle "$BACKTITLE" \
           --title "Backup Concluído" \
           --msgbox "$summary" \
           $DLG_H $DLG_W > "$CURR_TTY"
}

# --- Download de Jogos ----------------------------------------------------

# Converte slug do RomM para pasta do ArkOS
romm_slug_to_arkos() {
    local slug="$1"
    local slug_lower
    slug_lower=$(echo "$slug" | tr '[:upper:]' '[:lower:]')

    # Tenta mapeamento direto
    if [ -n "${PLATFORM_MAP[$slug_lower]+x}" ]; then
        echo "${PLATFORM_MAP[$slug_lower]}"
        return 0
    fi

    # Tenta slug normalizado (substitui espaços e hífen por nada)
    local normalized
    normalized=$(echo "$slug_lower" | tr -d ' -_')
    for key in "${!PLATFORM_MAP[@]}"; do
        local key_norm
        key_norm=$(echo "$key" | tr -d ' -_')
        if [ "$key_norm" = "$normalized" ]; then
            echo "${PLATFORM_MAP[$key]}"
            return 0
        fi
    done

    # Fallback: usa o slug original em minúsculas
    echo "$slug_lower"
}

list_platforms() {
    dialog --backtitle "$BACKTITLE" \
           --infobox "Carregando plataformas do RomM..." \
           5 $DLG_W > "$CURR_TTY"

    local response
    response=$(api_get "/api/platforms")

    if [ -z "$response" ] || echo "$response" | grep -q '"detail"'; then
        dialog --backtitle "$BACKTITLE" \
               --title "Erro" \
               --msgbox "Erro ao carregar plataformas:\n$(echo "$response" | jq -r '.detail // "Sem resposta do servidor"' 2>/dev/null)" \
               $DLG_H $DLG_W > "$CURR_TTY"
        return 1
    fi

    # ─── SKILL: JSON-to-Menu Mapping ────────────────────────────────────────
    # Usa json_to_menu_entries para converter o JSON de plataformas em pares
    # [id, "Nome → /roms/pasta/"] de forma robusta (sem split de palavras,
    # sem quebra por espaços em nomes de plataformas).
    # ─────────────────────────────────────────────────────────────────────────

    # Verifica se há dados válidos
    local platform_count
    platform_count=$(echo "$response" | jq '. | length' 2>/dev/null || echo 0)
    if [ "$platform_count" = "0" ]; then
        dialog --backtitle "$BACKTITLE" \
               --title "Aviso" \
               --msgbox "Nenhuma plataforma encontrada no servidor." \
               $DLG_H $DLG_W > "$CURR_TTY"
        return 1
    fi

    # Monta menu via json_to_menu_entries
    # Label: "Nome da Plataforma  →  /roms/pasta/"
    # O label_tpl usa jq para calcular a pasta ArkOS inline:
    # Como o mapeamento está no bash, fazemos a resolução em dois passos:
    #   passo 1: extraímos id+slug+nome em uma linha por objeto
    #   passo 2: resolvemos a pasta ArkOS em bash
    local menu_entries=()
    local ids_arr=()
    local slugs_arr=()

    # Extrai linhas "id|slug|nome" de forma segura
    while IFS='|' read -r pid pslug pname; do
        [ -z "$pid" ] || [ "$pid" = "null" ] && continue
        local arkos_folder
        arkos_folder=$(romm_slug_to_arkos "$pslug")
        ids_arr+=("$pid")
        slugs_arr+=("$pslug")
        menu_entries+=("$pid" "${pname:0:30}  →  /roms/${arkos_folder}/")
    done < <(
        echo "$response" | jq -r \
            '.[] | (.id | tostring) + "|" + .slug + "|" + .name' \
            2>/dev/null
    )

    if [ ${#menu_entries[@]} -eq 0 ]; then
        dialog --backtitle "$BACKTITLE" \
               --title "Aviso" \
               --msgbox "Falha ao processar lista de plataformas." \
               $DLG_H $DLG_W > "$CURR_TTY"
        return 1
    fi

    local choice
    choice=$(dialog --output-fd 1 --backtitle "$BACKTITLE" \
                    --title "Selecionar Plataforma" \
                    --menu "Escolha uma plataforma:" \
                    $DLG_H $DLG_W 8 \
                    "${menu_entries[@]}" \
                    2>"$CURR_TTY") || return

    # Encontra o slug correspondente ao ID escolhido
    local selected_slug=""
    local selected_name=""
    for i in "${!ids_arr[@]}"; do
        if [ "${ids_arr[$i]}" = "$choice" ]; then
            selected_slug="${slugs_arr[$i]}"
            selected_name=$(echo "$response" | \
                jq -r --arg id "$choice" \
                '.[] | select((.id | tostring) == $id) | .name' 2>/dev/null)
            break
        fi
    done

    list_games "$choice" "$selected_slug" "$selected_name"
}

list_games() {
    local platform_id="$1"
    local platform_slug="$2"
    local platform_name="$3"

    dialog --backtitle "$BACKTITLE" \
           --infobox "Carregando jogos de '$platform_name'..." \
           5 $DLG_W > "$CURR_TTY"

    local response
    response=$(api_get "/api/roms?platform_id=${platform_id}&limit=200&offset=0")

    if [ -z "$response" ] || echo "$response" | grep -q '"detail"'; then
        dialog --backtitle "$BACKTITLE" \
               --title "Erro" \
               --msgbox "Erro ao carregar jogos:\n$(echo "$response" | jq -r '.detail // "Sem resposta"' 2>/dev/null)" \
               $DLG_H $DLG_W > "$CURR_TTY"
        return
    fi

    # Extrai jogos
    local total
    total=$(echo "$response" | jq '.items | length' 2>/dev/null || echo "0")

    if [ "$total" = "0" ]; then
        dialog --backtitle "$BACKTITLE" \
               --title "Aviso" \
               --msgbox "Nenhum jogo encontrado para '$platform_name'." \
               $DLG_H $DLG_W > "$CURR_TTY"
        return
    fi

    # ─── SKILL: JSON-to-Menu Mapping (lista de ROMs) ─────────────────────────
    # Extrai id | file_name | nome | tamanho em uma única passagem pelo jq,
    # evitando múltiplos jq por linha (lentíssimo no ARM com listas grandes).
    # Delimitador interno: ASCII SOH (\x01) — não aparece em nomes de arquivo.
    # ─────────────────────────────────────────────────────────────────────────
    local menu_entries=()
    local rom_ids=()
    local rom_names=()
    local rom_files=()

    while IFS=$'\x01' read -r rid rfile rname rsize; do
        [ -z "$rid" ] || [ "$rid" = "null" ] && continue

        # Formata tamanho de forma eficiente (sem bc — usa aritmética bash)
        local size_str
        if   [ "$rsize" -gt 1073741824 ] 2>/dev/null; then
            size_str="$(( rsize / 1073741824 ))GB"
        elif [ "$rsize" -gt 1048576 ] 2>/dev/null; then
            size_str="$(( rsize / 1048576 ))MB"
        elif [ "$rsize" -gt 1024 ] 2>/dev/null; then
            size_str="$(( rsize / 1024 ))KB"
        else
            size_str="${rsize}B"
        fi

        rom_ids+=("$rid")
        rom_names+=("$rname")
        rom_files+=("$rfile")
        # Label: nome truncado + tamanho — sem quebra por espaço
        menu_entries+=("$rid" "${rname:0:36}  [${size_str}]")
    done < <(
        # Uma única chamada ao jq por toda a lista — eficiente no ARM
        echo "$response" | jq -r \
            '.items[] | (.id | tostring)
                + "\u0001" + .file_name
                + "\u0001" + (.name // .file_name)
                + "\u0001" + ((.file_size_bytes // 0) | tostring)' \
            2>/dev/null
    )

    local choice
    choice=$(dialog --output-fd 1 --backtitle "$BACKTITLE" \
                    --title "$platform_name ($total jogos)" \
                    --menu "Selecione o jogo para baixar:" \
                    $DLG_H $DLG_W 8 \
                    "${menu_entries[@]}" \
                    2>"$CURR_TTY") || return

    # Encontra o arquivo do jogo
    local selected_file=""
    local selected_name=""
    for i in "${!rom_ids[@]}"; do
        if [ "${rom_ids[$i]}" = "$choice" ]; then
            selected_file="${rom_files[$i]}"
            selected_name="${rom_names[$i]}"
            break
        fi
    done

    download_rom "$choice" "$selected_file" "$selected_name" "$platform_slug"
}

download_rom() {
    local rom_id="$1"
    local file_name="$2"
    local rom_name="$3"
    local platform_slug="$4"

    # Determina pasta de destino
    # Usa ROMS_ROOTS[0] (/roms) como destino padrão de download.
    # Se /roms não existir mas /roms2 existir, usa /roms2.
    local arkos_folder
    arkos_folder=$(romm_slug_to_arkos "$platform_slug")
    local dest_root="${ROMS_ROOTS[0]}"
    if [ ! -d "$dest_root" ] && [ -d "${ROMS_ROOTS[1]:-}" ]; then
        dest_root="${ROMS_ROOTS[1]}"
    fi
    local dest_dir="${dest_root}/${arkos_folder}"
    local dest_file="${dest_dir}/${file_name}"

    # Cria pasta se não existir
    mkdir -p "$dest_dir"

    # Verifica se já existe
    if [ -f "$dest_file" ]; then
        dialog --backtitle "$BACKTITLE" \
               --title "Arquivo Existente" \
               --yesno "O arquivo já existe:\n${dest_file}\n\nDeseja substituir?" \
               $DLG_H $DLG_W > "$CURR_TTY" || return
    fi

    log "Baixando ROM: $rom_name → $dest_file"

    local download_url="${ROMM_URL}/api/roms/${rom_id}/content/${file_name}"
    local tmp_file="${TMP_DIR}/download_${rom_id}_${file_name}"

    ensure_tmp

    # Download com barra de progresso usando wget
    # wget mostra progresso na stderr, redirecionamos para dialog --gauge
    (
        wget -q --show-progress \
             --header="Authorization: Basic $ROMM_AUTH_B64" \
             -O "$tmp_file" \
             "$download_url" 2>&1 | \
        grep --line-buffered "%" | \
        sed -u 's/.*\([0-9]\+\)%.*/\1/' | \
        while IFS= read -r pct; do
            echo "$pct"
        done
    ) | dialog --backtitle "$BACKTITLE" \
               --title "Baixando..." \
               --gauge "Baixando: ${rom_name:0:40}\n\nDestino: $dest_dir/" \
               9 $DLG_W 0 > "$CURR_TTY"

    local exit_code=${PIPESTATUS[0]}

    if [ "$exit_code" = "0" ] && [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
        mv "$tmp_file" "$dest_file"
        log "Download concluído: $dest_file"

        dialog --backtitle "$BACKTITLE" \
               --title "Download Concluído" \
               --msgbox "✓ Jogo baixado com sucesso!\n\n$rom_name\n\nSalvo em:\n$dest_file" \
               $DLG_H $DLG_W > "$CURR_TTY"
    else
        rm -f "$tmp_file"
        log "ERRO: Falha no download de $rom_name"

        dialog --backtitle "$BACKTITLE" \
               --title "Erro no Download" \
               --msgbox "✗ Falha ao baixar:\n$rom_name\n\nVerifique o log em:\n$LOG_FILE" \
               $DLG_H $DLG_W > "$CURR_TTY"
    fi
}

# --- Configurações Via Menu -----------------------------------------------

reconfigure() {
    dialog --backtitle "$BACKTITLE" \
           --title "Reconfigurar" \
           --yesno "Deseja reconfigurar a conexão com o servidor RomM?\n\nAs configurações atuais serão substituídas." \
           $DLG_H $DLG_W > "$CURR_TTY" || return

    setup_config
}

show_status() {
    if load_config; then
        local server_status="Desconhecido"
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                         -H "Authorization: Basic $ROMM_AUTH_B64" \
                         "${ROMM_URL}/api/heartbeat" 2>/dev/null || echo "000")

        case "$http_code" in
            200) server_status="✓ Online" ;;
            401) server_status="✗ Credenciais inválidas" ;;
            000) server_status="✗ Sem conexão" ;;
            *) server_status="✗ HTTP $http_code" ;;
        esac

        dialog --backtitle "$BACKTITLE" \
               --title "Status da Conexão" \
               --msgbox "Servidor:  $ROMM_URL\nUsuário:   $ROMM_USER\nStatus:    $server_status\n\nLog: $LOG_FILE" \
               $DLG_H $DLG_W > "$CURR_TTY"
    else
        dialog --backtitle "$BACKTITLE" \
               --title "Status" \
               --msgbox "Nenhuma configuração encontrada.\n\nExecute a configuração inicial primeiro." \
               $DLG_H $DLG_W > "$CURR_TTY"
    fi
}

# --- Auto-atualização -------------------------------------------------------

# self_update
# Baixa a versão mais recente do script diretamente do GitHub (branch main).
# Compara a versão remota com a local antes de substituir; faz backup do
# arquivo atual e só sobrescreve após confirmação do usuário.
self_update() {
    local REPO="fernandodimas/ArkOS_RomM-Sync-Tool"
    local BRANCH="main"
    local SCRIPT_NAME_FILE="RomMSync.sh"
    local RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${SCRIPT_NAME_FILE}"
    local SELF
    SELF=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")
    local TMP_NEW="${TMP_DIR}/RomMSync_new.sh"

    dialog --backtitle "$BACKTITLE" \
           --infobox "Verificando atualização em GitHub..." \
           5 $DLG_W > "$CURR_TTY"

    log "Verificando atualização: $RAW_URL"

    # Baixa nova versão
    if ! wget -q -O "$TMP_NEW" "$RAW_URL" 2>/dev/null; then
        dialog --backtitle "$BACKTITLE" \
               --title "Erro" \
               --msgbox "✗ Falha ao conectar ao GitHub.\nVerifique sua conexão Wi-Fi." \
               $DLG_H $DLG_W > "$CURR_TTY"
        rm -f "$TMP_NEW"
        return 1
    fi

    if [ ! -s "$TMP_NEW" ]; then
        dialog --backtitle "$BACKTITLE" \
               --title "Erro" \
               --msgbox "✗ Arquivo baixado está vazio." \
               $DLG_H $DLG_W > "$CURR_TTY"
        rm -f "$TMP_NEW"
        return 1
    fi

    # Extrai versão do arquivo baixado
    local remote_ver
    remote_ver=$(grep -m1 '^readonly VERSION=' "$TMP_NEW" \
                 | sed 's/.*VERSION="\([^"]*\)".*/\1/' 2>/dev/null || echo "?")

    if [ "$remote_ver" = "$VERSION" ]; then
        dialog --backtitle "$BACKTITLE" \
               --title "Sem atualizações" \
               --msgbox "✓ Você já está na versão mais recente!\n\nVersão atual: $VERSION" \
               $DLG_H $DLG_W > "$CURR_TTY"
        rm -f "$TMP_NEW"
        return 0
    fi

    # Pede confirmação antes de sobrescrever
    dialog --backtitle "$BACKTITLE" \
           --title "Atualização Disponível" \
           --yesno "Nova versão encontrada!\n\nAtual:  v$VERSION\nNova:   v$remote_ver\n\nDeseja atualizar agora?" \
           $DLG_H $DLG_W > "$CURR_TTY" || {
        rm -f "$TMP_NEW"
        return 0
    }

    # Backup da versão atual
    local backup_file="${SELF}.bak_v${VERSION}"
    cp -f "$SELF" "$backup_file" 2>/dev/null && \
        log "Backup criado: $backup_file"

    # Substitui o script e garante permissão de execução
    if mv -f "$TMP_NEW" "$SELF" && chmod +x "$SELF"; then
        log "Script atualizado para v$remote_ver com sucesso."
        dialog --backtitle "$BACKTITLE" \
               --title "Atualização Concluída" \
               --msgbox "✓ Script atualizado para v$remote_ver!\n\nBackup salvo em:\n$backup_file\n\nO script será encerrado para aplicar a atualização." \
               $DLG_H $DLG_W > "$CURR_TTY"
        # Sai para forçar releitura da nova versão
        exit 0
    else
        log "ERRO: Falha ao substituir o script."
        dialog --backtitle "$BACKTITLE" \
               --title "Erro" \
               --msgbox "✗ Falha ao gravar a nova versão.\nVerifique permissões em:\n$SELF" \
               $DLG_H $DLG_W > "$CURR_TTY"
        rm -f "$TMP_NEW"
        return 1
    fi
}

# --- Menu Principal -------------------------------------------------------

main_menu() {
    while true; do
        local choice
        choice=$(dialog --output-fd 1 --backtitle "$SCRIPT_NAME v$VERSION" \
                        --title "Menu Principal" \
                        --menu "Use D-Pad para navegar:" \
                        $DLG_H $DLG_W 8 \
                        "1" "⬆  Backup de Saves → RomM" \
                        "2" "⬇  Download de Jogos ← RomM" \
                        "3" "⚙  Reconfigurar Servidor" \
                        "4" "📶 Status da Conexão" \
                        "5" "📋 Ver Log" \
                        "6" "🔄 Atualizar Script" \
                        "7" "🚪 Sair" \
                        2>"$CURR_TTY") || break

        case "$choice" in
            1) backup_saves ;;
            2) list_platforms ;;
            3) reconfigure ;;
            4) show_status ;;
            5)
                if [ -f "$LOG_FILE" ]; then
                    dialog --backtitle "$BACKTITLE" \
                           --title "Log" \
                           --textbox "$LOG_FILE" \
                           $DLG_H $DLG_W > "$CURR_TTY"
                else
                    dialog --backtitle "$BACKTITLE" \
                           --title "Log" \
                           --msgbox "Nenhum log disponível ainda." \
                           $DLG_H $DLG_W > "$CURR_TTY"
                fi
                ;;
            6) self_update ;;
            7)
                dialog --backtitle "$BACKTITLE" \
                       --title "Sair" \
                       --yesno "Deseja sair do $SCRIPT_NAME?" \
                       7 $DLG_W > "$CURR_TTY" && break
                ;;
        esac
    done
}

# Encerra gptokeyb ao sair
_cleanup_gptokeyb() {
    pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null || true
    GPTOKEYB_PID=""
}

# --- Auto-update via GitHub -----------------------------------------------

# _ver_gt v1 v2 → retorna 0 se v1 > v2 (puro bash, sem sort -V)
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
    return 1  # iguais
}

check_update() {
    log "Verificando atualizações em $GITHUB_RAW ..."
    dialog --backtitle "$BACKTITLE" \
           --infobox "Verificando atualizações..." \
           3 45 > "$CURR_TTY"

    # Extrai versão do script no GitHub (linha: readonly VERSION="x.y.z")
    local latest_ver
    latest_ver=$(curl -sf --connect-timeout 6 --max-time 12 "$GITHUB_RAW" \
                 | grep -m1 'readonly VERSION=' \
                 | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' \
                 | tr -d '"')

    if [ -z "$latest_ver" ]; then
        log "Auto-update: sem resposta do GitHub. Continuando."
        return 0
    fi

    log "Auto-update: instalado=$VERSION  disponível=$latest_ver"

    if ! _ver_gt "$latest_ver" "$VERSION"; then
        dialog --backtitle "$BACKTITLE" \
               --infobox "✓ Versão atual (v$VERSION) está atualizada." \
               3 50 > "$CURR_TTY"
        sleep 1
        return 0
    fi

    # Há versão mais nova — pergunta ao usuário
    dialog --backtitle "$BACKTITLE" \
           --title "Atualização Disponível" \
           --yesno "Nova versão encontrada!\n\n  Instalado:   v$VERSION\n  Disponível:  v$latest_ver\n\nDeseja atualizar agora?" \
           11 $DLG_W > "$CURR_TTY"
    [ $? -ne 0 ] && { log "Usuário recusou atualização."; return 0; }

    dialog --backtitle "$BACKTITLE" \
           --infobox "Baixando v$latest_ver do GitHub..." \
           3 45 > "$CURR_TTY"

    local tmp_new
    tmp_new="${TMP_DIR}/RomMSync_update.sh"
    mkdir -p "$TMP_DIR"

    if ! curl -sf --connect-timeout 10 --max-time 60 "$GITHUB_RAW" -o "$tmp_new"; then
        dialog --backtitle "$BACKTITLE" \
               --title "Erro de Download" \
               --msgbox "Falha ao baixar v$latest_ver.\nContinuando com v$VERSION." \
               $DLG_H $DLG_W > "$CURR_TTY"
        return 1
    fi

    # Valida sintaxe antes de instalar
    if ! bash -n "$tmp_new" 2>/dev/null; then
        dialog --backtitle "$BACKTITLE" \
               --title "Erro" \
               --msgbox "Arquivo baixado inválido.\nMantenha v$VERSION." \
               $DLG_H $DLG_W > "$CURR_TTY"
        rm -f "$tmp_new"
        return 1
    fi

    chmod +x "$tmp_new"
    local script_path
    script_path=$(realpath "$0" 2>/dev/null || echo "$0")
    sudo cp "$tmp_new" "$script_path" 2>/dev/null || cp "$tmp_new" "$script_path"
    rm -f "$tmp_new"

    dialog --backtitle "$BACKTITLE" \
           --title "Atualizado!" \
           --msgbox "✓ Atualizado para v$latest_ver!\n\nFeche e reabra o aplicativo para usar a nova versão." \
           $DLG_H $DLG_W > "$CURR_TTY"

    log "Atualizado de v$VERSION para v$latest_ver. Encerrando para aplicar."
    exit 0
}

# --- Ponto de Entrada -----------------------------------------------------

main() {
    ensure_tmp
    log "=== $SCRIPT_NAME v$VERSION iniciado ==="

    # --- Inicialização do terminal -------------------------------------------
    if [ -c "$CURR_TTY" ]; then
        export TERM=linux
        unset FBTERM
        # Permissões (igual Plymouth Theme Changer.sh do ArkOS4clone)
        sudo chmod 666 "$CURR_TTY"  2>/dev/null || true
        sudo chmod 666 /dev/uinput  2>/dev/null || true
        printf "\033c" > "$CURR_TTY"
        setfont /usr/share/consolefonts/Lat7-Terminus16.psf.gz > "$CURR_TTY" 2>&1 || true
        printf "\033c" > "$CURR_TTY"
        printf "$SCRIPT_NAME v$VERSION\nAguarde..." > "$CURR_TTY"
    fi

    # --- Controles (gptokeyb em /opt/inttools — ArkOS4clone) -----------------
    if [ -x "$GPTOKEYB_BIN" ]; then
        # Mata instância anterior se existir
        pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null || true
        [ -f "$GPTOKEYB_DB" ] && export SDL_GAMECONTROLLERCONFIG_FILE="$GPTOKEYB_DB"
        "$GPTOKEYB_BIN" -1 "RomMSync.sh" -c "$GPTOKEYB_CFG" > /dev/null 2>&1 &
        GPTOKEYB_PID=$!
        log "gptokeyb iniciado: PID=$GPTOKEYB_PID  config=$GPTOKEYB_CFG"
        printf "\033c" > "$CURR_TTY"
    else
        log "AVISO: gptokeyb não encontrado em $GPTOKEYB_BIN — controles via teclado apenas."
    fi

    # Registra limpeza para qualquer forma de saída
    trap '_cleanup_gptokeyb; clear; log "=== Encerrado ==="' EXIT INT TERM

    check_dependencies
    check_wifi
    check_update || log "AVISO: check_update falhou, continuando sem atualização."

    # Configuração inicial se não existir
    if ! load_config; then
        dialog --backtitle "$BACKTITLE" \
               --title "Primeira Execução" \
               --msgbox "Configuração não encontrada.\nVamos configurar o servidor RomM agora." \
               $DLG_H $DLG_W > "$CURR_TTY"
        setup_config || {
            dialog --backtitle "$BACKTITLE" \
                   --title "Cancelado" \
                   --msgbox "Configuração cancelada. O script será encerrado." \
                   $DLG_H $DLG_W > "$CURR_TTY"
            exit 0
        }
        # Recarrega config após salvar
        load_config || exit 1
    fi

    main_menu
}

main "$@"
