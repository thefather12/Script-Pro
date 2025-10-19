#!/bin/bash

# =======================================================
# SCRIPT UNIFICADO DE GESTIÓN XRAY/V2RAY (VERSIÓN DEFINITIVA)
# Incluye Multi-Puerto, Monitoreo de GB y Emojis en el Menú.
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

# --- Funciones de Utilidad y Dependencias (Sin cambios) ---

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
    # ... (Instalación de dependencias: wget, curl, unzip, jq, bc)
    banner
    echo -e "${AMARILLO}--- 1. INSTALANDO DEPENDENCIAS (jq, curl, etc.) ---${NORMAL}"
    local PKG_MANAGER=$(get_system_package_manager)
    
    if [ "$PKG_MANAGER" != "none" ]; then
        echo "Usando $PKG_MANAGER..."
        sudo $PKG_MANAGER update -y
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
    # ... (Instalación de Xray Core)
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
        
        # Determinar SERVER_PORT para mostrar en el banner
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

# --- Gestión de Múltiples Puertos ---
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
    echo "1) ${VERDE}Agregar Nuevo Puerto${NORMAL}"
    echo "2) ${ROJO}Eliminar Puerto Existente${NORMAL}"
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
    
    # Aplicar los cambios al config.json
    local PORT_JSON=""
    if [ ${#port_array[@]} -eq 1 ]; then
        PORT_JSON="${port_array[0]}" # Si solo queda 1, se guarda como número
    else
        PORT_JSON=$(${JQ_PATH} -n --argjson arr "$(printf '%s\n' "${port_array[@]}" | ${JQ_PATH} -R . | ${JQ_PATH} -slR .)" '[$arr | .[] | tonumber]')
    fi
    
    ${JQ_PATH} '.inbounds[0].port = '"$PORT_JSON" "${CONFIG_FILE}" > temp.json && mv temp.json "${CONFIG_FILE}"
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Configuración de puertos actualizada."
        systemctl restart xray
        load_global_config # Recargar el banner
    else
        echo -e "${ROJO}[ERROR]${NORMAL} Falló al guardar la configuración de puertos."
    fi
    pause
}

# (Las demás funciones de configuración y administración se mantienen sin cambios,
# excepto que `update_config_file` ya no gestiona el puerto, solo los `streamSettings`).

# --- Funciones de Administración ---

function create_user() {
    banner
    echo -e "${AMARILLO}--- 1. CREAR NUEVO USUARIO VMESS ---${NORMAL}"
    
    read -p "Ingrese el nombre/alias del usuario: " username
    local new_uuid=$(cat /proc/sys/kernel/random/uuid)
    local traffic_tag="user-${new_uuid}"
    local random_path="/" 

    # 🛑 NUEVO: Pedir el puerto de la lista
    local current_ports=$(${JQ_PATH} '.inbounds[0].port' "${CONFIG_FILE}" 2>/dev/null)
    local available_ports=()
    if echo "$current_ports" | grep -v -q '\['; then
        available_ports+=("$current_ports")
    else
        available_ports=($(${JQ_PATH} -r '.inbounds[0].port[]' "${CONFIG_FILE}" 2>/dev/null))
    fi

    echo -e "\n${AZUL}Puertos disponibles:${NORMAL} ${available_ports[*]}"
    read -p "Seleccione el puerto que el usuario usará: " USER_PORT
    
    if [[ ! " ${available_ports[*]} " =~ " ${USER_PORT} " ]]; then
        echo -e "${ROJO}[ERROR]${NORMAL} Puerto ${USER_PORT} no está activo. Use la opción 7 para activarlo."
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

# --- Generación de Enlace VMess (Actualizada para aceptar puerto) ---

function generate_vmess_link() {
    local username=$1
    local new_uuid=$2
    local user_path=$3
    local user_port=$4 # Puerto elegido por el usuario
    
    # Parámetros para el cliente VMess (JSON sin codificar)
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

    # Codificar el JSON en Base64 y prefijarlo con vmess://
    local vmess_link=$(echo "${client_config}" | base64 -w 0)
    
    echo -e "\n${CIAN}--- ENLACE VMESS GENERADO ---${NORMAL}"
    echo -e "${BLANCO}Host: ${SERVER_DOMAIN} | Puerto: ${user_port}${NORMAL}"
    echo -e "Transporte: ${TRANSPORT_NETWORK} | Seguridad: ${SECURITY_TYPE} | Path: ${user_path}"
    echo -e "\n${VERDE}vmess://${vmess_link}${NORMAL}\n"
    echo -e "Pégalo en tu aplicación cliente compatible."
}


# (El resto de las funciones de administración y monitoreo de GB se mantienen.)
# (Solo la función change_port se reemplaza por manage_multi_ports, y la opción '5' del menú se mueve.)


# --- Flujo Principal ---

function main_menu() {
    load_global_config

    # 1. VERIFICACIÓN DE ESTADO INICIAL
    local XRAY_INSTALLED=$(command -v xray &> /dev/null; echo $?)
    local JQ_INSTALLED=$(command -v jq &> /dev/null; echo $?)
    local CONFIG_EXISTS=$(test -f "$CONFIG_FILE"; echo $?)
    
    if [ "$XRAY_INSTALLED" != "0" ] || [ "$JQ_INSTALLED" != "0" ] || [ "$CONFIG_EXISTS" != "0" ]; then
        # ... (código de instalación inicial)
        banner
        echo -e "${ROJO}[ALERTA]${NORMAL} El sistema Xray no está completamente configurado."
        echo -e "${AZUL}1)${NORMAL} ⚙️ INSTALAR TODO (Dependencias y Xray Core)"
        echo -e "${AZUL}2)${NORMAL} 🌐 CONFIGURAR RED, PUERTO Y PROTOCOLOS"
        echo -e "${AZUL}0)${NORMAL} 🚪 Salir"
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
        echo -e "${AZUL}1)${NORMAL} ➕ Crear ${VERDE}NUEVO USUARIO${NORMAL} (UUID, Path y Link)"
        echo -e "${AZUL}2)${NORMAL} ➖ Eliminar ${ROJO}USUARIO existente${NORMAL} (Por UUID)"
        echo -e "${AZUL}3)${NORMAL} 📊 Limitar/Reiniciar GB (vía API)"
        echo -e "${AZUL}4)${NORMAL} 📈 ${BLANCO}Consultar Consumo de GB (API) ${VERDE}⭐${NORMAL}"
        echo -e "${AZUL}5)${NORMAL} 👤 Mostrar Usuarios ${AMARILLO}Activos${NORMAL}"
        echo -e "---------------------------------------------------"
        echo -e "${AZUL}6)${NORMAL} 🔒 Activar/Desactivar TLS"
        echo -e "${AZUL}7)${NORMAL} 🔢 Administrar Múltiples Puertos (${SERVER_PORT})"
        echo -e "${AZUL}8)${NORMAL} 📡 Cambiar PROTOCOLO (${TRANSPORT_NETWORK})"
        echo -e "${AZUL}9)${NORMAL} 🌐 Cambiar DOMINIO/HOST (${SERVER_DOMAIN})"
        echo -e "---------------------------------------------------"
        echo -e "${AZUL}0)${NORMAL} 🚪 Salir del script"
        echo -e "---------------------------------------------------"
        
        read -p "Opción: " choice
        
        case $choice in
            1) create_user ;;
            2) delete_user ;;
            3) manage_traffic_limit ;;
            4) banner; echo -e "${AMARILLO}--- 👤 USUARIOS ACTIVOS (UUID | Email) ---${NORMAL}"; ${JQ_PATH} '.inbounds[0].settings.clients[] | "\(.id) | \(.email)"' "${CONFIG_FILE}" 2>/dev/null; pause ;;
            5) show_traffic_stats ;;
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
