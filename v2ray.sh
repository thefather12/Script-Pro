#!/bin/bash

# =======================================================
# SCRIPT UNIFICADO DE GESTIÓN XRAY/V2RAY (VERSIÓN AVANZADA)
# =======================================================

INSTALL_DIR="/usr/local/etc/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
JQ_PATH=$(which jq)

# --- Variables de Configuración Global ---
SERVER_PORT=""
SERVER_DOMAIN=""
TRANSPORT_NETWORK="tcp" # Default: tcp
SECURITY_TYPE="none"    # Default: none

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
        sudo $PKG_MANAGER install -y wget curl unzip jq bc
    else
        echo -e "${ROJO}[ERROR]${NORMAL} Gestor de paquetes no soportado. Instala manualmente: wget, curl, unzip, jq, bc."
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
        # Usa jq para cargar variables de configuración global
        SERVER_PORT=$(${JQ_PATH} '.inbounds[0].port' "${CONFIG_FILE}" 2>/dev/null)
        TRANSPORT_NETWORK=$(${JQ_PATH} '.inbounds[0].streamSettings.network' "${CONFIG_FILE}" 2>/dev/null | tr -d '"')
        SECURITY_TYPE=$(${JQ_PATH} '.inbounds[0].streamSettings.security' "${CONFIG_FILE}" 2>/dev/null | tr -d '"')
        SERVER_DOMAIN=$(${JQ_PATH} '.inbounds[0].streamSettings.tlsSettings.serverName' "${CONFIG_FILE}" 2>/dev/null | tr -d '"')
        
        # Si SERVER_DOMAIN es nulo (ej. si no usa TLS), intenta obtener la IP pública
        if [ -z "$SERVER_DOMAIN" ] || [ "$SERVER_DOMAIN" == "null" ]; then
            SERVER_DOMAIN=$(curl -s icanhazip.com || hostname -I | awk '{print $1}')
        fi
        
        # Si SERVER_PORT es nulo (configuración base vacía), usa un valor por defecto
        if [ -z "$SERVER_PORT" ] || [ "$SERVER_PORT" == "null" ]; then
             SERVER_PORT="443"
        fi

    fi
}

# --- Funciones de Configuración de Red ---

function update_config_file() {
    # Esta función actualiza el config.json con las variables globales
    local INBOUND_SETTINGS=$(${JQ_PATH} '.inbounds[0].settings' "${CONFIG_FILE}" 2>/dev/null)
    
    # Manejo de TLS
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

    # Manejo de Transportes (ws, grpc, http, etc.)
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

    # Reconstruir el archivo JSON con los nuevos streamSettings
    local NEW_CONFIG=$(cat << EOF_CONFIG
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": ${SERVER_PORT},
      "protocol": "vmess",
      "settings": ${INBOUND_SETTINGS},
      "streamSettings": {
        ${STREAM_SETTINGS}
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} },
    { "protocol": "blackhole", "tag": "block", "settings": {} }
  ]
}
EOF_CONFIG
)

    echo "$NEW_CONFIG" > "$CONFIG_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Archivo ${CONFIG_FILE} actualizado."
        systemctl restart xray
        echo -e "${AZUL}[INFO]${NORMAL} Servicio Xray reiniciado."
    else
        echo -e "${ROJO}[ERROR]${NORMAL} Falló la actualización del archivo. Revísalo manualmente."
    fi
}

function change_port() {
    banner
    echo -e "${AMARILLO}--- CAMBIAR PUERTO ---${NORMAL}"
    echo -e "Puerto actual: ${BLANCO}${SERVER_PORT}${NORMAL}"
    read -p "Ingrese el nuevo puerto: " NEW_PORT
    
    if [[ ! "$NEW_PORT" =~ ^[0-9]+$ || "$NEW_PORT" -lt 1 || "$NEW_PORT" -gt 65535 ]]; then
        echo -e "${ROJO}[ERROR]${NORMAL} Puerto inválido."
        pause
        return
    fi
    
    SERVER_PORT="$NEW_PORT"
    update_config_file
    pause
}

function change_protocol() {
    banner
    echo -e "${AMARILLO}--- CAMBIAR PROTOCOLO DE TRANSPORTE ---${NORMAL}"
    echo -e "Protocolo actual: ${BLANCO}${TRANSPORT_NETWORK} (${SECURITY_TYPE})${NORMAL}"
    echo "1) ${VERDE}WebSocket (ws)${NORMAL} - Ofuscación web, ideal con TLS."
    echo "2) ${AZUL}TCP (raw)${NORMAL} - Simple, rápido."
    echo "3) ${CIAN}mKCP (kcp)${NORMAL} - Protocolo UDP para entornos inestables."
    echo "4) ${VERDE}gRPC${NORMAL} - Alternativa moderna a WebSocket, ideal con TLS."
    echo "5) ${AZUL}HTTP/2 (h2) (XHTTP)${NORMAL} - Alternativa a WS, requiere TLS."
    
    read -p "Selecciona el transporte (1-5): " CHOICE
    
    case $CHOICE in
        1) TRANSPORT_NETWORK="ws" ;;
        2) TRANSPORT_NETWORK="tcp" ;;
        3) TRANSPORT_NETWORK="kcp"; SECURITY_TYPE="none" ;; # KCP no usa TLS directamente
        4) TRANSPORT_NETWORK="grpc" ;;
        5) TRANSPORT_NETWORK="h2" ;;
        *) echo -e "${ROJO}Opción inválida.${NORMAL}"; pause; return ;;
    esac

    # Para WS, gRPC, h2 forzar a preguntar por TLS
    if [ "$TRANSPORT_NETWORK" == "ws" ] || [ "$TRANSPORT_NETWORK" == "grpc" ] || [ "$TRANSPORT_NETWORK" == "h2" ]; then
        echo -e "\n${BLANCO}--- CONFIGURAR SEGURIDAD ---${NORMAL}"
        echo "1) ${VERDE}TLS${NORMAL} - Recomendado."
        echo "2) ${ROJO}Ninguno (none)${NORMAL}."
        read -p "Selecciona la seguridad (1 o 2, default: 1): " SEC_CHOICE
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

function change_domain() {
    banner
    echo -e "${AMARILLO}--- AGREGAR/CAMBIAR DOMINIO (HOST) ---${NORMAL}"
    echo -e "Dominio actual: ${BLANCO}${SERVER_DOMAIN}${NORMAL}"
    read -p "Ingrese el nuevo Dominio (Host): " NEW_DOMAIN
    
    if [[ -z "$NEW_DOMAIN" ]]; then
        echo -e "${ROJO}[ERROR]${NORMAL} Dominio no puede estar vacío."
        pause
        return
    fi
    
    SERVER_DOMAIN="$NEW_DOMAIN"
    echo -e "${VERDE}[INFO]${NORMAL} Dominio actualizado. Reinicia el servicio para aplicar los cambios de TLS/h2."
    
    # Esto solo actualiza la variable, la configuración JSON se actualiza al cambiar el protocolo o al crear un usuario.
    # Opcional: Llamar a update_config_file aquí si el protocolo actual es TLS/h2/gRPC
    pause
}


# --- Funciones de Administración ---

function generate_random_path() {
    # Genera una cadena aleatoria de 10 caracteres alfanuméricos
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1
}

function create_user() {
    banner
    echo -e "${AMARILLO}--- CREAR NUEVO USUARIO VMESS ---${NORMAL}"
    
    read -p "Ingrese el nombre/alias del usuario: " username
    local new_uuid=$(cat /proc/sys/kernel/random/uuid)
    local random_path="/" # Por defecto
    
    # Generar Path aleatorio solo si el protocolo lo requiere
    if [ "$TRANSPORT_NETWORK" == "ws" ] || [ "$TRANSPORT_NETWORK" == "grpc" ] || [ "$TRANSPORT_NETWORK" == "h2" ]; then
        random_path="/$(generate_random_path)"
        echo -e "${AZUL}[INFO]${NORMAL} Path generado para este usuario: ${random_path}"
    fi

    # Lógica de jq para agregar cliente al primer inbound
    ${JQ_PATH} '.inbounds[0].settings.clients += [{"id": "'"${new_uuid}"'", "alterId": 0, "email": "'"${username}"'"}]' "${CONFIG_FILE}" > temp.json && mv temp.json "${CONFIG_FILE}"
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Usuario '${username}' agregado con éxito."
        systemctl restart xray
        echo -e "${AZUL}[INFO]${NORMAL} Servicio Xray reiniciado."
        generate_vmess_link "${username}" "${new_uuid}" "${random_path}"
    else
        echo -e "${ROJO}[ERROR]${NORMAL} No se pudo agregar el usuario. Revisa ${CONFIG_FILE}."
    fi
    pause
}

# --- Generación de Enlace VMess ---

function generate_vmess_link() {
    local username=$1
    local new_uuid=$2
    local user_path=$3
    
    # Parámetros para el cliente VMess (JSON sin codificar)
    local client_config=$(cat << EOF
{
  "v": "2",
  "ps": "${username}",
  "add": "${SERVER_DOMAIN}",
  "port": "${SERVER_PORT}",
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

    # Codificar el JSON en Base64 y prefijarlo con vmess://
    local vmess_link=$(echo "${client_config}" | base64 -w 0)
    
    echo -e "\n${CIAN}--- ENLACE VMESS GENERADO ---${NORMAL}"
    echo -e "${BLANCO}Host: ${SERVER_DOMAIN} | Puerto: ${SERVER_PORT}${NORMAL}"
    echo -e "Transporte: ${TRANSPORT_NETWORK} | Seguridad: ${SECURITY_TYPE} | Path: ${user_path}"
    echo -e "\n${VERDE}vmess://${vmess_link}${NORMAL}\n"
    echo -e "Pégalo en tu aplicación cliente compatible."
}

# --- Funciones de Gestión (se mantienen) ---
function delete_user() {
    # Lógica para eliminar usuario por UUID
    banner
    echo -e "${AMARILLO}--- ELIMINAR USUARIO VMESS ---${NORMAL}"
    
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
        systemctl restart xray
    else
        echo -e "${ROJO}[ERROR]${NORMAL} No se pudo eliminar el usuario."
    fi
    pause
}

function manage_traffic_limit() {
    # Función simbólica
    banner
    echo -e "${AMARILLO}--- GESTIÓN DE LÍMITE POR GB (AVANZADO) ---${NORMAL}"
    echo -e "${ROJO}[ADVERTENCIA]${NORMAL} Xray no tiene un límite de tráfico nativo en JSON. Se necesita un panel (X-UI) o la API para esta función.${NORMAL}"
    pause
}

# --- Flujo Principal ---

function main_menu() {
    # 0. Cargar configuración al inicio
    load_global_config

    # 1. VERIFICACIÓN DE ESTADO INICIAL
    local XRAY_INSTALLED=$(command -v xray &> /dev/null; echo $?)
    local JQ_INSTALLED=$(command -v jq &> /dev/null; echo $?)
    local CONFIG_EXISTS=$(test -f "$CONFIG_FILE"; echo $?)
    
    if [ "$XRAY_INSTALLED" != "0" ] || [ "$JQ_INSTALLED" != "0" ] || [ "$CONFIG_EXISTS" != "0" ]; then
        banner
        echo -e "${ROJO}[ALERTA]${NORMAL} El sistema Xray no está completamente configurado."
        echo -e "${AZUL}1)${NORMAL} INSTALAR TODO (Dependencias y Xray Core)"
        echo -e "${AZUL}2)${NORMAL} CONFIGURAR RED, PUERTO Y PROTOCOLOS"
        echo -e "${AZUL}0)${NORMAL} Salir"
        read -p "Opción: " initial_choice
        case $initial_choice in
            1) install_dependencies; install_xray_core; main_menu ;;
            2) install_dependencies; setup_initial_config; main_menu ;;
            0) echo -e "${AZUL}¡Adiós!${NORMAL}"; exit 0 ;;
            *) echo -e "${ROJO}Opción no válida.${NORMAL}"; pause; main_menu ;;
        esac
    fi
    
    # 2. MENÚ DE GESTIÓN DE USUARIOS
    while true; do
        banner
        echo -e "${BLANCO}HOST: ${SERVER_DOMAIN} | PUERTO: ${SERVER_PORT} | PROTOCOLO: ${TRANSPORT_NETWORK} (${SECURITY_TYPE})${NORMAL}"
        echo -e "---------------------------------------------------"
        echo -e "${AZUL}1)${NORMAL} Crear ${VERDE}NUEVO USUARIO${NORMAL} (Genera UUID/Path/Link)"
        echo -e "${AZUL}2)${NORMAL} Eliminar ${ROJO}USUARIO existente${NORMAL} (Por UUID)"
        echo -e "---------------------------------------------------"
        echo -e "${AZUL}3)${NORMAL} Cambiar PUERTO (${SERVER_PORT})"
        echo -e "${AZUL}4)${NORMAL} Cambiar PROTOCOLO (${TRANSPORT_NETWORK})"
        echo -e "${AZUL}5)${NORMAL} Agregar/Cambiar DOMINIO (${SERVER_DOMAIN})"
        echo -e "---------------------------------------------------"
        echo -e "${AZUL}6)${NORMAL} Mostrar Usuarios ${AMARILLO}Activos${NORMAL}"
        echo -e "${AZUL}7)${NORMAL} Reiniciar el servicio Xray"
        echo -e "${AZUL}0)${NORMAL} Salir del script"
        echo -e "---------------------------------------------------"
        
        read -p "Opción: " choice
        
        case $choice in
            1) create_user ;;
            2) delete_user ;;
            3) change_port ;;
            4) change_protocol ;;
            5) change_domain ;;
            6) banner; echo -e "${AMARILLO}--- USUARIOS ACTIVOS (UUID | Email) ---${NORMAL}"; ${JQ_PATH} '.inbounds[0].settings.clients[] | "\(.id) | \(.email)"' "${CONFIG_FILE}" 2>/dev/null; pause ;;
            7) systemctl restart xray; echo -e "${VERDE}Servicio Xray reiniciado con éxito.${NORMAL}"; pause ;;
            0) echo -e "${AZUL}¡Adiós!${NORMAL}"; exit 0 ;;
            *) echo -e "${ROJO}Opción no válida. Intenta de nuevo.${NORMAL}"; pause ;;
        esac
    done
}

# Iniciar el script
main_menu
