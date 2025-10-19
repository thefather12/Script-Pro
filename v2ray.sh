#!/bin/bash

# =======================================================
# SCRIPT UNIFICADO DE GESTIÓN XRAY/V2RAY (VERSIÓN DEFINITIVA)
# Incluye Multi-Puerto CORREGIDO, Monitoreo de GB y Emojis.
# =======================================================

INSTALL_DIR="/usr/local/etc/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
JQ_PATH=$(which jq)
XRAY_API_SERVER="127.0.0.1:10085"

# --- Variables de Configuración Global (Se cargan desde load_global_config) ---
SERVER_PORT="" # Usado solo para mostrar el puerto principal o un rango
SERVER_DOMAIN=""
TRANSPORT_NETWORK="tcp"
SECURITY_TYPE="none"

# --- Variables de Estilo ---
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AZUL='\033[0;34m'
AMARILLO='\033[1;33m'
NORMAL='\033[0m'
BLANCO='\033[1;37m'
CIAN='\033[0;36m'

function banner() {
    clear
    echo -e "${CIAN}=====================================================${NORMAL}"
    echo -e "${VERDE}         🚀 XRAY/V2RAY GESTIÓN UNIFICADA 🚀          ${NORMAL}"
    echo -e "${CIAN}=====================================================${NORMAL}"
}

# --- Funciones de Utilidad ---

function pause() {
    echo ""
    read -p "Presiona [Enter] para continuar..."
}

function get_system_package_manager() {
    if command -v apt &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    else
        echo "none"
    fi
}

function install_dependencies() {
    banner
    echo -e "${AMARILLO}--- 1. INSTALANDO DEPENDENCIAS (jq, curl, etc.) ---${NORMAL}"
    local PKG_MANAGER=$(get_system_package_manager)
    
    if [ "$PKG_MANAGER" != "none" ]; then
        echo "Usando $PKG_MANAGER..."
        sudo $PKG_MANAGER update -y
        # 'bc' es necesario para los cálculos de GB
        sudo $PKG_MANAGER install -y wget curl unzip jq bc
    else
        echo -e "${ROJO}[ERROR]${NORMAL} Gestor de paquetes no soportado."
        exit 1
    fi
    
    JQ_PATH=$(which jq) 
    if [ ! -f "$JQ_PATH" ]; then
        echo -e "${ROJO}[ERROR]${NORMAL} La herramienta 'jq' no se pudo instalar."
        exit 1
    fi
    echo -e "${VERDE}[ÉXITO]${NORMAL} Dependencias instaladas correctamente."
}

function install_xray_core() {
    banner
    echo -e "${AMARILLO}--- 2. INSTALANDO XRAY CORE ---${NORMAL}"
    
    bash -c "$(curl -L https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)" @ install
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Xray Core instalado."
    else
        echo -e "${ROJO}[ERROR]${NORMAL} Falló la instalación de Xray Core."
        exit 1
    fi
    pause
}

# Carga la configuración actual del JSON a las variables globales
function load_global_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # Carga variables esenciales
        local PORTS=$(${JQ_PATH} '.inbounds[0].port' "${CONFIG_FILE}" 2>/dev/null)
        
        # Determinar SERVER_PORT para mostrar en el banner (maneja número o array)
        if echo "$PORTS" | grep -q '\['; then
            # Es un array de puertos
            SERVER_PORT=$(${JQ_PATH} '.inbounds[0].port | join(", ")' "${CONFIG_FILE}" 2>/dev/null | tr -d '"')
        else
            # Es un puerto simple (número)
            SERVER_PORT=$PORTS
        fi

        TRANSPORT_NETWORK=$(${JQ_PATH} '.inbounds[0].streamSettings.network' "${CONFIG_FILE}" 2>/dev/null | tr -d '"')
        SECURITY_TYPE=$(${JQ_PATH} '.inbounds[0].streamSettings.security' "${CONFIG_FILE}" 2>/dev/null | tr -d '"')
        SERVER_DOMAIN=$(${JQ_PATH} '.inbounds[0].streamSettings.tlsSettings.serverName' "${CONFIG_FILE}" 2>/dev/null | tr -d '"')
        
        # Si no hay dominio/TLS, usa IP pública como fallback
        if [ -z "$SERVER_DOMAIN" ] || [ "$SERVER_DOMAIN" == "null" ]; then
            SERVER_DOMAIN=$(curl -s icanhazip.com || hostname -I | awk '{print $1}')
        fi
        
        if [ -z "$SERVER_PORT" ] || [ "$SERVER_PORT" == "null" ]; then
             SERVER_PORT="443"
        fi
    fi
}

# --- Funciones de Configuración Crítica (Protocolo, Puerto, TLS) ---

function update_config_file() {
    # Esta función actualiza el config.json con las variables globales y asegura la API y HandlerStat
    local INBOUND_SETTINGS=$(${JQ_PATH} '.inbounds[0].settings' "${CONFIG_FILE}" 2>/dev/null)
    local CURRENT_PORT=$(${JQ_PATH} '.inbounds[0].port' "${CONFIG_FILE}" 2>/dev/null) # Preservar puertos existentes
    
    # Manejo de TLS (genera solo si es "tls")
    local TLS_CONFIG=""
    if [ "$SECURITY_TYPE" == "tls" ]; then
        read -p "¿Ruta al archivo .cer (ej. /etc/ssl/fullchain.cer): " CERT_FILE
        read -p "¿Ruta al archivo .key (ej. /etc/ssl/private.key): " KEY_FILE
        
        TLS_CONFIG=$(cat << EOF_CERT
        "security": "tls",
        "tlsSettings": {
          "alpn": ["http/1.1"],
          "serverName": "${SERVER_DOMAIN}", 
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        },
EOF_CERT
)
    fi

    # Manejo de StreamSettings
    local STREAM_SETTINGS=""
    if [ "$TRANSPORT_NETWORK" == "ws" ]; then
        STREAM_SETTINGS=$(cat << EOF_WS
        "network": "ws",
        ${TLS_CONFIG}
        "wsSettings": { "path": "/vmess-path" }
EOF_WS
)
    elif [ "$TRANSPORT_NETWORK" == "grpc" ]; then
        STREAM_SETTINGS=$(cat << EOF_GRPC
        "network": "grpc",
        ${TLS_CONFIG}
        "grpcSettings": { "serviceName": "v2ray-grpc" }
EOF_GRPC
)
    elif [ "$TRANSPORT_NETWORK" == "h2" ]; then
        STREAM_SETTINGS=$(cat << EOF_H2
        "network": "h2",
        ${TLS_CONFIG}
        "httpSettings": { "host": ["${SERVER_DOMAIN}"] }
EOF_H2
)
    elif [ "$TRANSPORT_NETWORK" == "kcp" ]; then
        STREAM_SETTINGS=$(cat << EOF_KCP
        "network": "kcp",
        "kcpSettings": { "header": { "type": "wechat-video" } }
EOF_KCP
)
    else # default: tcp
        STREAM_SETTINGS=$(cat << EOF_TCP
        "network": "tcp",
        ${TLS_CONFIG}
        "tcpSettings": { "header": { "type": "none" } }
EOF_TCP
)
    fi

    # Reconstruir el archivo JSON con API y HandlerStat
    local NEW_CONFIG=$(cat << EOF_CONFIG
{
  "log": { "loglevel": "warning" },
  "stats": {},
  "api": {
    "tag": "api",
    "services": ["HandlerService", "StatsService"]
  },
  "inbounds": [
    {
      "port": ${CURRENT_PORT},
      "protocol": "vmess",
      "settings": ${INBOUND_SETTINGS},
      "streamSettings": {
        ${STREAM_SETTINGS}
      },
      "tag": "vmess-in"
    },
    {
      "listen": "127.0.0.1",
      "port": 10085, 
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {}, "tag": "direct" },
    { "protocol": "blackhole", "settings": {}, "tag": "block" }
  ],
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": { "statsInboundUplink": true, "statsInboundDownlink": true }
    }
}
EOF_CONFIG
)

    echo "$NEW_CONFIG" > "$CONFIG_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Archivo ${CONFIG_FILE} actualizado. API y HandlerStat ACTIVADOS."
        systemctl restart xray
        echo -e "${AZUL}[INFO]${NORMAL} Servicio Xray reiniciado."
    else
        echo -e "${ROJO}[ERROR]${NORMAL} Falló la actualización del archivo. Revísalo manualmente."
    fi
}

function change_port() {
    # Redirige a la función de gestión de multi-puerto
    manage_multi_ports
}

function change_protocol() {
    banner
    echo -e "${AMARILLO}--- 8. CAMBIAR PROTOCOLO DE TRANSPORTE ---${NORMAL}"
    echo -e "Protocolo actual: ${BLANCO}${TRANSPORT_NETWORK} (${SECURITY_TYPE})${NORMAL}"
    echo "1) ${VERDE}WebSocket (ws)${NORMAL}"
    echo "2) ${AZUL}TCP (raw)${NORMAL}"
    echo "3) ${CIAN}mKCP (kcp)${NORMAL}"
    echo "4) ${VERDE}gRPC${NORMAL}"
    echo "5) ${AZUL}HTTP/2 (h2)${NORMAL}"
    
    read -p "Selecciona el transporte (1-5): " CHOICE
    
    case $CHOICE in
        1) TRANSPORT_NETWORK="ws" ;;
        2) TRANSPORT_NETWORK="tcp" ;;
        3) TRANSPORT_NETWORK="kcp"; SECURITY_TYPE="none" ;; 
        4) TRANSPORT_NETWORK="grpc" ;;
        5) TRANSPORT_NETWORK="h2" ;;
        *) echo -e "${ROJO}Opción inválida.${NORMAL}"; pause; return ;;
    esac

    # Para WS, gRPC, h2 forzar a preguntar por TLS (si no es TCP o KCP)
    if [ "$TRANSPORT_NETWORK" != "kcp" ] && [ "$TRANSPORT_NETWORK" != "tcp" ]; then
        echo -e "\n${BLANCO}--- CONFIGURAR SEGURIDAD ---${NORMAL}"
        echo "1) ${VERDE}TLS${NORMAL} - Recomendado."
        echo "2) ${ROJO}Ninguno (none)${NORMAL}."
        read -p "Selecciona la seguridad (1 o 2, actual: $SECURITY_TYPE): " SEC_CHOICE
        SECURITY_TYPE="tls"
        if [ "$SEC_CHOICE" == "2" ]; then
            SECURITY_TYPE="none"
        fi
    else
        SECURITY_TYPE="none"
    fi
    
    update_config_file
    pause
}

function change_tls_status() {
    banner
    echo -e "${AMARILLO}--- 6. ACTIVAR/DESACTIVAR TLS ---${NORMAL}"
    echo -e "Estado actual: ${BLANCO}${SECURITY_TYPE}${NORMAL}"
    
    if [ "$TRANSPORT_NETWORK" == "kcp" ] || [ "$TRANSPORT_NETWORK" == "tcp" ]; then
        echo -e "${ROJO}[ERROR]${NORMAL} Protocolo (${TRANSPORT_NETWORK}) no recomendado para TLS. Cámbialo primero."
        pause
        return
    fi

    echo "1) ${VERDE}Activar TLS${NORMAL} (Requiere certificado y dominio)."
    echo "2) ${ROJO}Desactivar TLS${NORMAL}."
    read -p "Selecciona una opción (1 o 2): " TLS_CHOICE
    
    if [ "$TLS_CHOICE" == "1" ]; then
        SECURITY_TYPE="tls"
    elif [ "$TLS_CHOICE" == "2" ]; then
        SECURITY_TYPE="none"
    else
        echo -e "${ROJO}Opción inválida.${NORMAL}"
        pause
        return
    fi
    
    update_config_file
    pause
}

function change_domain() {
    banner
    echo -e "${AMARILLO}--- 9. AGREGAR/CAMBIAR DOMINIO (HOST) ---${NORMAL}"
    echo -e "Dominio actual: ${BLANCO}${SERVER_DOMAIN}${NORMAL}"
    read -p "Ingrese el nuevo Dominio (Host): " NEW_DOMAIN
    
    if [[ -z "$NEW_DOMAIN" ]]; then
        echo -e "${ROJO}[ERROR]${NORMAL} Dominio no puede estar vacío."
        pause
        return
    fi
    
    SERVER_DOMAIN="$NEW_DOMAIN"
    
    if [ "$SECURITY_TYPE" == "tls" ]; then
        update_config_file # Asegura que el serverName se actualice
    else
        echo -e "${VERDE}[INFO]${NORMAL} Dominio actualizado. No se aplica al config.json ya que TLS está desactivado."
    fi
    pause
}

# ⭐️ FUNCIÓN CORREGIDA: Gestión de Múltiples Puertos
function manage_multi_ports() {
    banner
    echo -e "${AMARILLO}--- 7. ADMINISTRAR PUERTOS VMESS ---${NORMAL}"
    
    local current_ports=$(${JQ_PATH} '.inbounds[0].port' "${CONFIG_FILE}" 2>/dev/null)
    local port_array=()

    # Si es un solo número, convertir a array temporalmente
    if echo "$current_ports" | grep -v -q '\['; then
        port_array+=("$current_ports")
    else
        # Si ya es un array, parsearlo
        port_array=($(${JQ_PATH} -r '.inbounds[0].port[]' "${CONFIG_FILE}" 2>/dev/null))
    fi

    echo -e "Puertos actualmente activos: ${VERDE}${port_array[*]}${NORMAL}"
    echo "-------------------------------------------------"
    echo "1) ${VERDE}Agregar Nuevo Puerto ➕${NORMAL}"
    echo "2) ${ROJO}Eliminar Puerto Existente ➖${NORMAL}"
    read -p "Opción (1 o 2): " PORT_CHOICE
    
    if [ "$PORT_CHOICE" == "1" ]; then
        read -p "Ingrese el puerto a AGREGAR: " NEW_PORT
        if [[ ! "$NEW_PORT" =~ ^[0-9]+$ || "$NEW_PORT" -lt 1 || "$NEW_PORT" -gt 65535 ]]; then
            echo -e "${ROJO}[ERROR]${NORMAL} Puerto inválido."
            pause
            return
        fi
        if [[ " ${port_array[*]} " =~ " ${NEW_PORT} " ]]; then
            echo -e "${ROJO}[ERROR]${NORMAL} El puerto ${NEW_PORT} ya está activo."
            pause
            return
        fi
        
        port_array+=("$NEW_PORT")
        echo -e "${VERDE}[ÉXITO]${NORMAL} Puerto ${NEW_PORT} agregado."

    elif [ "$PORT_CHOICE" == "2" ]; then
        read -p "Ingrese el puerto a ELIMINAR: " DEL_PORT
        if [[ ! " ${port_array[*]} " =~ " ${DEL_PORT} " ]]; then
            echo -e "${ROJO}[ERROR]${NORMAL} El puerto ${DEL_PORT} no está en la lista."
            pause
            return
        fi

        # Eliminar el puerto del array
        local new_array=()
        for p in "${port_array[@]}"; do
            if [ "$p" != "$DEL_PORT" ]; then
                new_array+=("$p")
            fi
        done
        port_array=("${new_array[@]}")
        echo -e "${VERDE}[ÉXITO]${NORMAL} Puerto ${DEL_PORT} eliminado."
        
    else
        echo -e "${ROJO}Opción inválida.${NORMAL}"
        pause
        return
    fi
    
    # ⭐️ CORRECCIÓN APLICADA: Construir el JSON de puertos de forma robusta
    local PORT_JSON=""
    if [ ${#port_array[@]} -eq 1 ]; then
        PORT_JSON="${port_array[0]}" # Si solo queda 1, se guarda como número
    else
        # Construir la cadena JSON como "[p1, p2, p3, ...]"
        local json_ports=""
        for p in "${port_array[@]}"; do
            if [ -n "$json_ports" ]; then
                json_ports="${json_ports}, "
            fi
            json_ports="${json_ports}${p}"
        done
        PORT_JSON="[${json_ports}]"
    fi
    
    # Usar jq para actualizar solo la clave 'port' con la nueva variable PORT_JSON
    # Usamos --argjson para que jq interprete PORT_JSON como un número o array
    ${JQ_PATH} --argjson new_port "$PORT_JSON" '.inbounds[0].port = $new_port' "${CONFIG_FILE}" > temp.json && mv temp.json "${CONFIG_FILE}"
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Configuración de puertos actualizada."
        systemctl restart xray
        load_global_config # Recargar el banner
    else
        echo -e "${ROJO}[ERROR]${NORMAL} Falló al guardar la configuración de puertos. Revise el archivo ${CONFIG_FILE}."
    fi
    pause
}


# --- Funciones de Administración ---

function generate_random_path() {
    # Genera una cadena aleatoria de 10 caracteres alfanuméricos
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1
}

function create_user() {
    banner
    echo -e "${AMARILLO}--- 1. CREAR NUEVO USUARIO VMESS ---${NORMAL}"
    
    read -p "Ingrese el nombre/alias del usuario: " username
    local new_uuid=$(cat /proc/sys/kernel/random/uuid)
    local traffic_tag="user-${new_uuid}" # Tag completo para rastreo de tráfico
    local random_path="/" # Por defecto
    
    # ⭐️ INICIO DE LA CORRECCIÓN DE PUERTOS
    local current_ports_raw=$(${JQ_PATH} '.inbounds[0].port' "${CONFIG_FILE}" 2>/dev/null)
    local available_ports=()

    if echo "$current_ports_raw" | grep -q '\['; then
        # Es un array: extrae los números, quita comillas y newlines, y convierte a array Bash
        local ports_string=$(echo "$current_ports_raw" | ${JQ_PATH} -r 'if type == "array" then .[] | tostring else . | tostring end' 2>/dev/null | tr '\n' ' ')
        read -r -a available_ports <<< "$ports_string"
    else
        # Es un puerto simple:
        available_ports+=("$current_ports_raw")
    fi
    # Limpiar cualquier espacio en blanco o valores nulos
    available_ports=($(echo "${available_ports[@]}" | tr ' ' '\n' | grep -vE '^\s*$' | sort -u))

    # Verificar que haya puertos válidos después de la limpieza
    if [ ${#available_ports[@]} -eq 0 ]; then
        echo -e "${ROJO}[ERROR]${NORMAL} No se encontraron puertos activos válidos. Use la opción 7 para configurarlos."
        pause
        return
    fi
    
    echo -e "\n${AZUL}Puertos disponibles:${NORMAL} ${available_ports[*]}"
    read -p "Seleccione el puerto que el usuario usará: " USER_PORT
    
    # ⭐️ FIN DE LA CORRECCIÓN DE PUERTOS
    
    # La comprobación ahora funciona porque 'available_ports' es un array de Bash limpio
    if [[ ! " ${available_ports[*]} " =~ " ${USER_PORT} " ]]; then
        echo -e "${ROJO}[ERROR]${NORMAL} Puerto ${USER_PORT} no está activo o es inválido. Por favor, seleccione uno de la lista."
        pause
        return
    fi

    # Generar Path aleatorio solo si el protocolo lo requiere
    if [ "$TRANSPORT_NETWORK" == "ws" ] || [ "$TRANSPORT_NETWORK" == "grpc" ] || [ "$TRANSPORT_NETWORK" == "h2" ]; then
        random_path="/$(generate_random_path)"
        echo -e "${AZUL}[INFO]${NORMAL} Path generado para este usuario: ${random_path}"
    fi

    # Lógica de jq para agregar cliente al primer inbound
    ${JQ_PATH} '.inbounds[0].settings.clients += [{"id": "'"${new_uuid}"'", "alterId": 0, "email": "'"${username}"'", "level": 0, "flow": "'"${traffic_tag}"'"}]' "${CONFIG_FILE}" > temp.json && mv temp.json "${CONFIG_FILE}"
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Usuario '${username}' agregado con éxito."
        systemctl restart xray
        echo -e "${AZUL}[INFO]${NORMAL} Servicio Xray reiniciado."
        # Pasar el puerto elegido al generador de enlace
        generate_vmess_link "${username}" "${new_uuid}" "${random_path}" "${USER_PORT}"
    else
        echo -e "${ROJO}[ERROR]${NORMAL} No se pudo agregar el usuario. Revisa ${CONFIG_FILE}."
    fi
    pause
}

# --- Generación de Enlace VMess (Corregido) ---

function generate_vmess_link() {
    local username=$1
    local new_uuid=$2
    local user_path=$3
    local user_port=$4 # Puerto elegido por el usuario
    
    # 1. Parámetros para el cliente VMess (JSON sin codificar)
    local client_config=$(cat << EOF
{
  "v": "2",
  "ps": "${username}",
  "add": "${SERVER_DOMAIN}",
  "port": "${user_port}",
  "id": "${new_uuid}",
  "aid": "0",
  "net": "${TRANSPORT_NETWORK}",
  "type": "none",
  "host": "${SERVER_DOMAIN}",
  "path": "${user_path}",
  "tls": "${SECURITY_TYPE}",
  "scy": "auto",
  "allowInsecure": false
}
EOF
)

    # 2. Codificar el JSON en Base64 sin saltos de línea (-w 0)
    local vmess_link=$(echo "${client_config}" | base64 -w 0)
    
    echo -e "\n${CIAN}--- ENLACE VMESS GENERADO ---${NORMAL}"
    echo -e "${BLANCO}Host: ${SERVER_DOMAIN} | Puerto: ${user_port}${NORMAL}"
    echo -e "Transporte: ${TRANSPORT_NETWORK} | Seguridad: ${SECURITY_TYPE} | Path: ${user_path}"
    
    # 3. La reparación: Imprimir la URL completa con el prefijo vmess://
    echo -e "\n${VERDE}vmess://${vmess_link}${NORMAL}\n"
    
    echo -e "Pégalo en tu aplicación cliente compatible."
}


function delete_user() {
    banner
    echo -e "${AMARILLO}--- 2. ELIMINAR USUARIO VMESS ---${NORMAL}"
    
    echo -e "${AZUL}Clientes Activos (UUID | Email):${NORMAL}"
    ${JQ_PATH} '.inbounds[0].settings.clients[] | "\(.id) | \(.email)"' "${CONFIG_FILE}" 2>/dev/null
    echo "-----------------------------------"

    read -p "Ingrese el UUID del usuario a eliminar: " uuid_to_delete
    if [[ -z "${uuid_to_delete}" ]]; then
        echo -e "${ROJO}[ALERTA]${NORMAL} UUID no puede estar vacío."
        pause
        return
    fi
    
    ${JQ_PATH} 'del(.inbounds[0].settings.clients[] | select(.id == "'"${uuid_to_delete}"'"))' "${CONFIG_FILE}" > temp.json && mv temp.json "${CONFIG_FILE}"
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Usuario con UUID ${uuid_to_delete} eliminado."
        # Limpiar estadísticas del usuario
        /usr/local/bin/xray api stats --server ${XRAY_API_SERVER} -m "user>>>${uuid_to_delete}>>>traffic>>>uplink" 2>/dev/null
        /usr/local/bin/xray api stats --server ${XRAY_API_SERVER} -m "user>>>${uuid_to_delete}>>>traffic>>>downlink" 2>/dev/null
        systemctl restart xray
    else
        echo -e "${ROJO}[ERROR]${NORMAL} No se pudo eliminar el usuario."
    fi
    pause
}

function manage_traffic_limit() {
    banner
    echo -e "${AMARILLO}--- 3. GESTIÓN DE LÍMITE DE GB POR USUARIO (API) ---${NORMAL}"
    echo -e "${ROJO}[ADVERTENCIA]${NORMAL} La API solo CONSULTA/REINICIA el tráfico. El BLOQUEO DEBE hacerse con un script externo.${NORMAL}"
    
    echo -e "${AZUL}Clientes Activos (UUID | Email):${NORMAL}"
    ${JQ_PATH} '.inbounds[0].settings.clients[] | "\(.id) | \(.email)"' "${CONFIG_FILE}" 2>/dev/null
    echo "-----------------------------------"

    read -p "Ingrese el UUID del usuario a gestionar: " target_uuid
    if [[ -z "${target_uuid}" ]]; then
        echo -e "${ROJO}[ALERTA]${NORMAL} UUID no puede estar vacío."
        pause
        return
    fi
    
    echo -e "\n1) ${VERDE}Consultar Tráfico Actual (U/D)${NORMAL}."
    echo "2) ${ROJO}Reiniciar (Reset) Tráfico${NORMAL}."
    read -p "Selecciona una opción (1 o 2): " LIMIT_CHOICE

    case $LIMIT_CHOICE in
        1)
            echo "Uplink:"
            /usr/local/bin/xray api stats --server ${XRAY_API_SERVER} -r "user>>>${target_uuid}>>>traffic>>>uplink"
            echo "Downlink:"
            /usr/local/bin/xray api stats --server ${XRAY_API_SERVER} -r "user>>>${target_uuid}>>>traffic>>>downlink"
            ;;
        2)
            echo "Reiniciando el tráfico (Uplink/Downlink) para ${target_uuid}..."
            /usr/local/bin/xray api stats --server ${XRAY_API_SERVER} -m "user>>>${target_uuid}>>>traffic>>>uplink"
            /usr/local/bin/xray api stats --server ${XRAY_API_SERVER} -m "user>>>${target_uuid}>>>traffic>>>downlink"
            echo -e "${VERDE}[ÉXITO]${NORMAL} Tráfico reiniciado."
            ;;
        *)
            echo -e "${ROJO}Opción inválida.${NORMAL}"
            ;;
    esac
    pause
}


function show_traffic_stats() {
    banner
    echo -e "${AMARILLO}--- 4. CONSUMO DE GB POR USUARIO ---${NORMAL}"
    
    if ! command -v xray &> /dev/null; then
        echo -e "${ROJO}[ERROR]${NORMAL} Xray no encontrado. Reinstala Xray Core."
        pause
        return
    fi
    
    echo -e "${CIAN}UID               | Consumo Total (GB) | UPLINK (GB) | DOWNLINK (GB) | Email${NORMAL}"
    echo "-------------------------------------------------------------------------------------"
    
    local users_data=$(${JQ_PATH} '.inbounds[0].settings.clients[] | {id: .id, email: .email}' "${CONFIG_FILE}" 2>/dev/null)
    
    if [ -z "$users_data" ]; then
        echo -e "${ROJO}[ALERTA]${NORMAL} No hay usuarios configurados."
        pause
        return
    fi

    local API_CALL="/usr/local/bin/xray api stats --server ${XRAY_API_SERVER}"
    
    echo "$users_data" | ${JQ_PATH} -c '. | select(has("id"))' | while read user; do
        local uuid=$(echo "$user" | ${JQ_PATH} -r '.id')
        local email=$(echo "$user" | ${JQ_PATH} -r '.email')
        
        local up_bytes=$($API_CALL -r "user>>>${uuid}>>>traffic>>>uplink" 2>/dev/null | awk '{print $NF}' | grep -oE '[0-9]+')
        local down_bytes=$($API_CALL -r "user>>>${uuid}>>>traffic>>>downlink" 2>/dev/null | awk '{print $NF}' | grep -oE '[0-9]+')

        up_bytes=${up_bytes:-0}
        down_bytes=${down_bytes:-0}
        
        local GB_DIVISOR="1073741824"
        
        local total_bytes=$(echo "$up_bytes + $down_bytes" | bc)
        local up_gb=$(echo "scale=3; $up_bytes / $GB_DIVISOR" | bc)
        local down_gb=$(echo "scale=3; $down_bytes / $GB_DIVISOR" | bc)
        local total_gb=$(echo "scale=3; $total_bytes / $GB_DIVISOR" | bc)
        
        printf "${AZUL}%-15s ${NORMAL}| ${AMARILLO}%-18s ${NORMAL}| %-11s | %-11s | %s\n" \
               "${uuid:0:15}..." \
               "${total_gb}" \
               "${up_gb}" \
               "${down_gb}" \
               "${email}"
    done
    
    echo "-------------------------------------------------------------------------------------"
    echo -e "${CIAN}[NOTA]${NORMAL} Los datos son el consumo desde el último reinicio (manual o automático)."
    pause
}


# --- Flujo Principal ---

function main_menu() {
    load_global_config

    # 1. VERIFICACIÓN DE ESTADO INICIAL
    local XRAY_INSTALLED=$(command -v xray &> /dev/null; echo $?)
    local JQ_INSTALLED=$(command -v jq &> /dev/null; echo $?)
    local CONFIG_EXISTS=$(test -f "$CONFIG_FILE"; echo $?)
    
    if [ "$XRAY_INSTALLED" != "0" ] || [ "$JQ_INSTALLED" != "0" ] || [ "$CONFIG_EXISTS" != "0" ]; then
        banner
        echo -e "${ROJO}[ALERTA]${NORMAL} El sistema Xray no está completamente configurado."
        echo -e "${AZUL}1) ⚙️ INSTALAR TODO (Dependencias y Xray Core)"
        echo -e "${AZUL}2) 🌐 CONFIGURAR RED, PUERTO Y PROTOCOLOS"
        echo -e "${AZUL}0) 🚪 Salir"
        read -p "Opción: " initial_choice
        case $initial_choice in
            1) install_dependencies; install_xray_core; main_menu ;;
            2) install_dependencies; update_config_file; main_menu ;;
            0) echo -e "${AZUL}¡Adiós! 👋${NORMAL}"; exit 0 ;;
            *) echo -e "${ROJO}Opción no válida.${NORMAL}"; pause; main_menu ;;
        esac
    fi
    
    # 2. MENÚ DE GESTIÓN DE USUARIOS CON EMOTICONOS
    while true; do
        banner
        echo -e "${BLANCO}HOST: ${SERVER_DOMAIN} | PUERTO(S): ${SERVER_PORT} | PROTOCOLO: ${TRANSPORT_NETWORK} | SEGURIDAD: ${SECURITY_TYPE}${NORMAL}"
        echo -e "---------------------------------------------------"
        echo -e "${AZUL}1) ➕ Crear ${VERDE}NUEVO USUARIO${NORMAL}"
        echo -e "${AZUL}2) ➖ Eliminar ${ROJO}USUARIO${NORMAL}"
        echo -e "${AZUL}3) 📊 Limitar/Reiniciar GB"
        echo -e "${AZUL}4) 📈 Consultar Consumo de GB ${VERDE}⭐${NORMAL}"
        echo -e "${AZUL}5) 👤 Mostrar Usuarios Activos"
        echo -e "---------------------------------------------------"
        echo -e "${AZUL}6) 🔒 Activar/Desactivar TLS"
        echo -e "${AZUL}7) 🔢 Administrar Múltiples Puertos"
        echo -e "${AZUL}8) 📡 Cambiar PROTOCOLO"
        echo -e "${AZUL}9) 🌐 Cambiar DOMINIO/HOST"
        echo -e "---------------------------------------------------"
        echo -e "${AZUL}0) 🚪 Salir del script"
        echo -e "---------------------------------------------------"
        
        read -p "Opción: " choice
        
        case $choice in
            1) create_user ;;
            2) delete_user ;;
            3) manage_traffic_limit ;;
            4) show_traffic_stats ;;
            5) banner; echo -e "${AMARILLO}--- 👤 USUARIOS ACTIVOS (UUID | Email) ---${NORMAL}"; ${JQ_PATH} '.inbounds[0].settings.clients[] | "\(.id) | \(.email)"' "${CONFIG_FILE}" 2>/dev/null; pause ;;
            6) change_tls_status ;;
            7) manage_multi_ports ;;
            8) change_protocol ;;
            9) change_domain ;;
            0) echo -e "${AZUL}¡Adiós! 👋${NORMAL}"; systemctl status xray; exit 0 ;;
            *) echo -e "${ROJO}Opción no válida. Intenta de nuevo.${NORMAL}"; pause ;;
        esac
    done
}

# Iniciar el script
main_menu
