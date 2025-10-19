#!/bin/bash

# =======================================================
# SCRIPT DE GESTIÓN AVANZADA DE XRAY/V2RAY (VMess + WS + TLS)
# REQUISITOS: Xray instalado y 'jq' (manipulador de JSON)
# =======================================================

INSTALL_DIR="/usr/local/etc/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
JQ_PATH=$(which jq)

# --- Funciones de Estilo ---
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AZUL='\033[0;34m'
AMARILLO='\033[1;33m'
NORMAL='\033[0m'

function banner() {
    clear
    echo -e "${AZUL}===================================================${NORMAL}"
    echo -e "${VERDE}         🚀 XRAY/V2RAY GESTIÓN RÁPIDA 🚀          ${NORMAL}"
    echo -e "${AZUL}===================================================${NORMAL}"
}

# --- Funciones Core de Xray ---

# 1. Función para verificar el requisito 'jq'
function check_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${ROJO}[ERROR]${NORMAL} 'jq' no está instalado. Es necesario para manipular el JSON."
        echo "Instálalo con 'sudo apt install jq' o 'sudo yum install jq'."
        exit 1
    fi
}

# 2. Función para crear un nuevo usuario VMess
function create_user() {
    banner
    echo -e "${AMARILLO}--- CREAR NUEVO USUARIO VMESS ---${NORMAL}"
    
    # 1. Obtener detalles
    read -p "Ingrese el nombre/alias del usuario: " username
    
    # Generar UUID
    new_uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # 2. Agregar el nuevo cliente al archivo config.json usando jq
    
    # Nota: El índice [0] debe apuntar al inbound VMess principal en tu config.json
    ${JQ_PATH} '.inbounds[0].settings.clients += [{"id": "'"${new_uuid}"'", "alterId": 0, "email": "'"${username}"'"}]' "${CONFIG_FILE}" > temp.json && mv temp.json "${CONFIG_FILE}"
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Usuario '${username}' agregado con éxito."
        systemctl restart xray
        echo -e "${AZUL}[INFO]${NORMAL} Servicio Xray reiniciado."
        
        # Opcional: Mostrar datos de conexión para facilitar el enlace
        show_connection_details "${username}" "${new_uuid}"
    else
        echo -e "${ROJO}[ERROR]${NORMAL} No se pudo agregar el usuario. Revisa tu archivo ${CONFIG_FILE}."
    fi
    pause
}

# 3. Función para eliminar usuario
function delete_user() {
    banner
    echo -e "${AMARILLO}--- ELIMINAR USUARIO VMESS ---${NORMAL}"
    
    # Mostrar clientes actuales para facilitar la selección
    echo -e "${AZUL}Clientes Activos (UUID/Email):${NORMAL}"
    ${JQ_PATH} '.inbounds[0].settings.clients[] | "\(.id) | \(.email)"' "${CONFIG_FILE}" 2>/dev/null
    echo "-----------------------------------"

    read -p "Ingrese el UUID del usuario a eliminar (Cópialo de la lista): " uuid_to_delete

    if [[ -z "${uuid_to_delete}" ]]; then
        echo -e "${ROJO}[ALERTA]${NORMAL} UUID no puede estar vacío."
        pause
        return
    fi
    
    # Eliminar el cliente del archivo config.json usando jq
    ${JQ_PATH} 'del(.inbounds[0].settings.clients[] | select(.id == "'"${uuid_to_delete}"'"))' "${CONFIG_FILE}" > temp.json && mv temp.json "${CONFIG_FILE}"
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Usuario con UUID ${uuid_to_delete} eliminado."
        systemctl restart xray
        echo -e "${AZUL}[INFO]${NORMAL} Servicio Xray reiniciado."
    else
        echo -e "${ROJO}[ERROR]${NORMAL} No se pudo eliminar el usuario. El UUID puede no existir."
    fi
    pause
}

# 4. Función para la gestión de límite de tráfico (Simulación/Lógica)
function manage_traffic_limit() {
    banner
    echo -e "${AMARILLO}--- GESTIÓN DE LÍMITE POR GB (AVANZADO) ---${NORMAL}"
    echo -e "${ROJO}[ADVERTENCIA]${NORMAL} V2Ray/Xray no tiene un límite de tráfico nativo en JSON."
    echo "Esta función solo ${AMARILLO}simula la configuración${NORMAL} para una implementación futura."
    
    read -p "Ingrese el UUID del usuario: " uuid_target
    read -p "Ingrese el límite de tráfico en GB (ej. 10): " limit_gb
    
    echo -e "${AZUL}[INFO]${NORMAL} Para una gestión real de GB, necesitarías un script externo o un panel (como X-UI) que use la API de Xray para monitorear el tráfico y deshabilitar el usuario al alcanzar el límite."
    echo -e "${VERDE}[CONFIGURADO]${NORMAL} Se ha registrado que el usuario ${uuid_target} tiene un límite de ${limit_gb} GB."
    pause
}

# 5. Función para mostrar la configuración completa del usuario
function show_connection_details() {
    local username=$1
    local new_uuid=$2
    
    # 1. Extraer datos del config.json (Asumiendo que es VMess con WS/TLS)
    local port=$(${JQ_PATH} '.inbounds[0].port' "${CONFIG_FILE}")
    local path=$(${JQ_PATH} '.inbounds[0].streamSettings.wsSettings.path' "${CONFIG_FILE}")
    
    echo -e "\n${AZUL}--- DETALLES DE CONEXIÓN PARA '${username}' ---${NORMAL}"
    echo -e "Protocolo: ${VERDE}VMess${NORMAL}"
    echo -e "UUID: ${VERDE}${new_uuid}${NORMAL}"
    echo -e "Puerto: ${VERDE}${port}${NORMAL}"
    echo -e "Transporte: ${VERDE}WebSocket + TLS${NORMAL}"
    echo -e "Path (Ruta): ${VERDE}${path}${NORMAL}"
    echo -e "Dominio (Host): ${VERDE}[TU DOMINIO AQUÍ]${NORMAL}"
    
    echo -e "\n${AMARILLO}¡ADVERTENCIA! DEBES REEMPLAZAR '[TU DOMINIO AQUÍ]' CON EL DOMINIO REAL DE TU SERVIDOR.${NORMAL}"
    # No se genera el link vmess:// completo aquí ya que requiere el dominio/IP real.
}

# 6. Función de pausa
function pause() {
    echo ""
    read -p "Presiona [Enter] para continuar..."
}

# --- Menú Principal ---

function main_menu() {
    check_jq
    while true; do
        banner
        echo -e "Selecciona una opción de gestión:"
        echo -e "---------------------------------------------------"
        echo -e "${AZUL}1)${NORMAL} Crear ${VERDE}NUEVO USUARIO${NORMAL} (Genera UUID)"
        echo -e "${AZUL}2)${NORMAL} Eliminar ${ROJO}USUARIO existente${NORMAL} (Por UUID)"
        echo -e "${AZUL}3)${NORMAL} Gestión de Límite de ${AMARILLO}GB (Solo lógica)${NORMAL}"
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
            4) banner; echo -e "${AMARILLO}--- USUARIOS ACTIVOS ---${NORMAL}"; ${JQ_PATH} '.inbounds[0].settings.clients[] | "\(.id) | \(.email)"' "${CONFIG_FILE}" 2>/dev/null; pause ;;
            5) systemctl restart xray; echo -e "${VERDE}Servicio Xray reiniciado con éxito.${NORMAL}"; pause ;;
            0) echo -e "${AZUL}¡Adiós!${NORMAL}"; exit 0 ;;
            *) echo -e "${ROJO}Opción no válida. Intenta de nuevo.${NORMAL}"; pause ;;
        esac
    done
}

# Iniciar el script
main_menu
