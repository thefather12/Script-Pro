#!/bin/bash

# =======================================================
# SCRIPT UNIFICADO DE GESTIÓN XRAY/V2RAY (FINAL)
# Incluye selección de protocolos, instalación y generación de enlaces.
# =======================================================

INSTALL_DIR="/usr/local/etc/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
JQ_PATH=$(which jq)

# --- Variables de Configuración Global ---
SERVER_PORT=""
SERVER_DOMAIN=""
TRANSPORT_NETWORK="tcp" # Default: tcp
SECURITY_TYPE="none"    # Default: none
SECRET_PATH="/vmess_path_secreto" 

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

# --- Configuración Inicial de Red y Archivo ---

function setup_initial_config() {
    banner
    echo -e "${AMARILLO}--- 3. CONFIGURACIÓN INICIAL DE LA RED Y PROTOCOLOS ---${NORMAL}"

    # 1. Pedir Puerto y Dominio
    read -p "¿En qué puerto desea que se conecten los usuarios (ej. 443): " SERVER_PORT
    read -p "¿Cuál es el Dominio (Host) del servidor (ej. tu-vps.com): " SERVER_DOMAIN
    if [[ -z "$SERVER_PORT" || -z "$SERVER_DOMAIN" ]]; then
        echo -e "${ROJO}[ERROR]${NORMAL} Puerto y/o Dominio inválidos. Saliendo."
        exit 1
    fi

    # 2. Selección de Transporte
    echo -e "\n${BLANCO}--- SELECCIÓN DE TRANSPORTE ---${NORMAL}"
    echo "1) ${VERDE}WebSocket (ws)${NORMAL} - Recomendado para ofuscación web (simula tráfico HTTP)."
    echo "2) ${AZUL}TCP${NORMAL} - Simple y rápido, pero fácil de detectar."
    read -p "Selecciona el tipo de transporte (1 o 2, default: 1): " TRANSPORT_CHOICE
    TRANSPORT_NETWORK="ws"
    if [ "$TRANSPORT_CHOICE" == "2" ]; then
        TRANSPORT_NETWORK="tcp"
    fi
    
    # 3. Selección de Seguridad (TLS)
    echo -e "\n${BLANCO}--- SELECCIÓN DE SEGURIDAD ---${NORMAL}"
    echo "1) ${VERDE}TLS${NORMAL} - Recomendado para cifrado y ofuscación (requiere dominio y certificado)."
    echo "2) ${ROJO}Ninguno (none)${NORMAL} - Sin cifrado (¡NO RECOMENDADO!)."
    read -p "Selecciona el tipo de seguridad (1 o 2, default: 1): " SECURITY_CHOICE
    SECURITY_TYPE="tls"
    if [ "$SECURITY_CHOICE" == "2" ]; then
        SECURITY_TYPE="none"
    fi

    # 4. Configuración de TLS (si se seleccionó)
    CERT_CONFIG=""
    if [ "$SECURITY_TYPE" == "tls" ]; then
        echo -e "\n${AMARILLO}--- CONFIGURACIÓN DE CERTIFICADOS TLS ---${NORMAL}"
        read -p "¿Ruta al archivo .cer (ej. /etc/ssl/fullchain.cer): " CERT_FILE
        read -p "¿Ruta al archivo .key (ej. /etc/ssl/private.key): " KEY_FILE
        
        if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
            echo -e "${ROJO}[ADVERTENCIA]${NORMAL} ¡Archivos de certificado/llave no encontrados! Esto fallará a menos que los coloques."
            CERT_FILE="/dev/null" 
            KEY_FILE="/dev/null"
        fi
        
        CERT_CONFIG=$(cat << EOF_CERT
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
    
    # 5. Generación de Configuración JSON
    local NEW_UUID=$(cat /proc/sys/kernel/random/uuid)
    
    mkdir -p "${INSTALL_DIR}"
    
    # Contenido JSON: La clave está en la variable $CERT_CONFIG para incluir/excluir TLS
    cat > "${CONFIG_FILE}" << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": ${SERVER_PORT},
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${NEW_UUID}",
            "alterId": 0,
            "email": "default_admin"
          }
        ]
      },
      "streamSettings": {
        "network": "${TRANSPORT_NETWORK}",
        ${CERT_CONFIG}
        "wsSettings": {
          "path": "${SECRET_PATH}"
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} },
    { "protocol": "blackhole", "tag": "block", "settings": {} }
  ]
}
EOF
    echo -e "${VERDE}[ÉXITO]${NORMAL} Configuración inicial guardada."
    systemctl enable xray
    systemctl restart xray
    pause
    # Recargar variables globales después de la configuración
    load_global_config
}

# Carga la configuración actual del JSON a las variables globales
function load_global_config() {
    if [ -f "$CONFIG_FILE" ]; then
        SERVER_PORT=$(${JQ_PATH} '.inbounds[0].port' "${CONFIG_FILE}" 2>/dev/null)
        SERVER_DOMAIN=$(${JQ_PATH} '.inbounds[0].streamSettings.tlsSettings.serverName' "${CONFIG_FILE}" 2>/dev/null | tr -d '"')
        TRANSPORT_NETWORK=$(${JQ_PATH} '.inbounds[0].streamSettings.network' "${CONFIG_FILE}" 2>/dev/null | tr -d '"')
        SECURITY_TYPE=$(${JQ_PATH} '.inbounds[0].streamSettings.security' "${CONFIG_FILE}" 2>/dev/null | tr -d '"')
        SECRET_PATH=$(${JQ_PATH} '.inbounds[0].streamSettings.wsSettings.path' "${CONFIG_FILE}" 2>/dev/null | tr -d '"')
        # Si no hay serverName (no-TLS), intenta obtener el IP
        if [ "$SECURITY_TYPE" == "none" ] || [ -z "$SERVER_DOMAIN" ]; then
            SERVER_DOMAIN=$(curl -s icanhazip.com || hostname -I | awk '{print $1}')
        fi
    fi
}


# --- Funciones de Administración ---

function create_user() {
    banner
    echo -e "${AMARILLO}--- CREAR NUEVO USUARIO VMESS ---${NORMAL}"
    
    read -p "Ingrese el nombre/alias del usuario: " username
    local new_uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # Lógica de jq para agregar cliente al primer inbound
    ${JQ_PATH} '.inbounds[0].settings.clients += [{"id": "'"${new_uuid}"'", "alterId": 0, "email": "'"${username}"'"}]' "${CONFIG_FILE}" > temp.json && mv temp.json "${CONFIG_FILE}"
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Usuario '${username}' agregado con éxito."
        systemctl restart xray
        echo -e "${AZUL}[INFO]${NORMAL} Servicio Xray reiniciado."
        generate_vmess_link "${username}" "${new_uuid}"
    else
        echo -e "${ROJO}[ERROR]${NORMAL} No se pudo agregar el usuario. Revisa ${CONFIG_FILE}."
    fi
    pause
}

# --- Generación de Enlace VMess ---

function generate_vmess_link() {
    local username=$1
    local new_uuid=$2
    
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
  "path": "${SECRET_PATH}",
  "tls": "${SECURITY_TYPE}",
  "scy": "auto",
  "allowInsecure": false
}
EOF
)

    # Codificar el JSON en Base64 y prefijarlo con vmess://
    local vmess_link=$(echo "${client_config}" | base64 -w 0)
    
    echo -e "\n${CIAN}--- ENLACE VMESS GENERADO ---${NORMAL}"
    echo -e "${BLANCO}Dominio: ${SERVER_DOMAIN} | Puerto: ${SERVER_PORT}${NORMAL}"
    echo -e "Transporte: ${TRANSPORT_NETWORK} | Seguridad: ${SECURITY_TYPE}"
    echo -e "\n${VERDE}vmess://${vmess_link}${NORMAL}\n"
    echo -e "Pégalo en V2RayNG/V2RayN o la aplicación cliente compatible."
}


function delete_user() {
    # Se mantiene la lógica de eliminación por UUID
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
    # Función simbólica, ya que requiere API o paneles externos para ser funcional
    banner
    echo -e "${AMARILLO}--- GESTIÓN DE LÍMITE POR GB (AVANZADO) ---${NORMAL}"
    echo -e "${ROJO}[ADVERTENCIA]${NORMAL} Xray no tiene un límite de tráfico nativo en JSON. Esta función es simbólica.${NORMAL}"
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
        echo -e "${AZUL}2)${NORMAL} CONFIGURAR RED Y PROTOCOLOS (Puerto, Dominio, Certificados)"
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
        echo -e "${BLANCO}CONFIGURACIÓN ACTUAL: ${SERVER_DOMAIN}:${SERVER_PORT} [${TRANSPORT_NETWORK}/${SECURITY_TYPE}]${NORMAL}"
        echo -e "---------------------------------------------------"
        echo -e "${AZUL}1)${NORMAL} Crear ${VERDE}NUEVO USUARIO${NORMAL} (Genera VMess Link)"
        echo -e "${AZUL}2)${NORMAL} Eliminar ${ROJO}USUARIO existente${NORMAL} (Por UUID)"
        echo -e "${AZUL}3)${NORMAL} Gestión de Límite de ${AMARILLO}GB (Simulación)${NORMAL}"
        echo -e "${AZUL}4)${NORMAL} Mostrar Usuarios ${AMARILLO}Activos${NORMAL}"
        echo -e "${AZUL}5)${NORMAL} Reiniciar el servicio Xray"
        echo -e "---------------------------------------------------"
        echo -e "${AZUL}0)${NORMAL} Salir del script"
        echo -e "---------------------------------------------------"
        
        read -p "Opción: " choice
        
        case $choice in
            1) create_user ;;
            2) delete_user ;;
            3) manage_traffic_limit ;;
            4) banner; echo -e "${AMARILLO}--- USUARIOS ACTIVOS (UUID | Email) ---${NORMAL}"; ${JQ_PATH} '.inbounds[0].settings.clients[] | "\(.id) | \(.email)"' "${CONFIG_FILE}" 2>/dev/null; pause ;;
            5) systemctl restart xray; echo -e "${VERDE}Servicio Xray reiniciado con éxito.${NORMAL}"; pause ;;
            0) echo -e "${AZUL}¡Adiós!${NORMAL}"; exit 0 ;;
            *) echo -e "${ROJO}Opción no válida. Intenta de nuevo.${NORMAL}"; pause ;;
        esac
    done
}

# Iniciar el script
main_menu
