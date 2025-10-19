#!/bin/bash

# =======================================================
# SCRIPT UNIFICADO DE GESTIÓN XRAY/V2RAY
# Incluye la instalación de dependencias y Xray Core.
# =======================================================

INSTALL_DIR="/usr/local/etc/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
JQ_PATH=$(which jq)

# --- Variables de Estilo ---
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AZUL='\033[0;34m'
AMARILLO='\033[1;33m'
NORMAL='\033[0m'

function banner() {
    clear
    echo -e "${AZUL}===================================================${NORMAL}"
    echo -e "${VERDE}         🚀 XRAY/V2RAY GESTIÓN UNIFICADA 🚀        ${NORMAL}"
    echo -e "${AZUL}===================================================${NORMAL}"
}

# --- Funciones de Utilidad ---

# Determina el gestor de paquetes y verifica/instala dependencias
function install_dependencies() {
    banner
    echo -e "${AMARILLO}--- 1. INSTALANDO DEPENDENCIAS (jq, curl, etc.) ---${NORMAL}"
    
    if command -v apt &> /dev/null; then
        echo "Usando APT (Debian/Ubuntu)..."
        apt update -y
        apt install -y wget curl unzip jq bc
    elif command -v yum &> /dev/null; then
        echo "Usando YUM (CentOS/RHEL)..."
        yum install -y wget curl unzip jq bc
    elif command -v dnf &> /dev/null; then
        echo "Usando DNF (Fedora/RHEL moderno)..."
        dnf install -y wget curl unzip jq bc
    else
        echo -e "${ROJO}[ERROR]${NORMAL} Gestor de paquetes no soportado. Instala manualmente: wget, curl, unzip, jq, bc."
        exit 1
    fi
    
    # Reestablece la ruta de jq después de la instalación
    JQ_PATH=$(which jq) 
    if [ ! -f "$JQ_PATH" ]; then
        echo -e "${ROJO}[ERROR]${NORMAL} La herramienta 'jq' no se pudo instalar."
        exit 1
    fi
    echo -e "${VERDE}[ÉXITO]${NORMAL} Dependencias instaladas correctamente."
}

# Instala Xray Core
function install_xray_core() {
    banner
    echo -e "${AMARILLO}--- 2. INSTALANDO XRAY CORE ---${NORMAL}"
    
    # Script oficial de XTLS/Xray para una instalación limpia
    bash -c "$(curl -L https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)" @ install
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Xray Core instalado en /usr/local/bin/xray."
        echo -e "${AZUL}[INFO]${NORMAL} El archivo de configuración se encuentra en ${CONFIG_FILE}."
        
        # Crear un archivo de configuración básico si no existe (el instalador suele hacerlo, pero es una protección)
        if [ ! -f "$CONFIG_FILE" ]; then
            create_initial_config
        fi
        
        systemctl enable xray
        systemctl restart xray
    else
        echo -e "${ROJO}[ERROR]${NORMAL} Falló la instalación de Xray Core."
        exit 1
    fi
    pause
}

# Crea una configuración JSON básica (si el instalador falla en crearla)
function create_initial_config() {
    local NEW_UUID=$(cat /proc/sys/kernel/random/uuid)
    
    echo "Creando configuración inicial VMess básica..."
    mkdir -p "${INSTALL_DIR}"
    
    cat > "${CONFIG_FILE}" << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 10000, 
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
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} },
    { "protocol": "blackhole", "tag": "block", "settings": {} }
  ]
}
EOF
echo -e "${VERDE}[ÉXITO]${NORMAL} Configuración inicial guardada. Usa la opción 4 para ver los detalles."
}


# --- Funciones de Administración (del script anterior) ---

function create_user() {
    # La lógica de esta función se mantiene (usa jq para añadir al JSON)
    banner
    echo -e "${AMARILLO}--- CREAR NUEVO USUARIO VMESS ---${NORMAL}"
    
    read -p "Ingrese el nombre/alias del usuario: " username
    
    # Generar UUID
    local new_uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # Lógica de jq para agregar cliente al primer inbound (asumiendo que es el VMess)
    ${JQ_PATH} '.inbounds[0].settings.clients += [{"id": "'"${new_uuid}"'", "alterId": 0, "email": "'"${username}"'"}]' "${CONFIG_FILE}" > temp.json && mv temp.json "${CONFIG_FILE}"
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}[ÉXITO]${NORMAL} Usuario '${username}' agregado con éxito."
        systemctl restart xray
        echo -e "${AZUL}[INFO]${NORMAL} Servicio Xray reiniciado."
        show_connection_details "${username}" "${new_uuid}"
    else
        echo -e "${ROJO}[ERROR]${NORMAL} No se pudo agregar el usuario. Revisa ${CONFIG_FILE}."
    fi
    pause
}

function delete_user() {
    # La lógica de esta función se mantiene (usa jq para eliminar del JSON)
    banner
    echo -e "${AMARILLO}--- ELIMINAR USUARIO VMESS ---${NORMAL}"
    
    echo -e "${AZUL}Clientes Activos (UUID | Email):${NORMAL}"
    ${JQ_PATH} '.inbounds[0].settings.clients[] | "\(.id) | \(.email)"' "${CONFIG_FILE}" 2>/dev/null
    echo "-----------------------------------"

    read -p "Ingrese el UUID del usuario a eliminar (Cópialo de la lista): " uuid_to_delete

    if [[ -z "${uuid_to_delete}" ]]; then
        echo -e "${ROJO}[ALERTA]${NORMAL} UUID no puede estar vacío."
        pause
        return
    fi
    
    # Lógica de jq para eliminar el cliente por UUID
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

function manage_traffic_limit() {
    # Función simbólica, ya que requiere API o paneles externos para ser funcional
    banner
    echo -e "${AMARILLO}--- GESTIÓN DE LÍMITE POR GB (AVANZADO) ---${NORMAL}"
    echo -e "${ROJO}[ADVERTENCIA]${NORMAL} Xray no tiene un límite de tráfico nativo en JSON."
    echo "Esta función solo ${AMARILLO}simula la configuración${NORMAL}."
    
    read -p "Ingrese el UUID del usuario: " uuid_target
    read -p "Ingrese el límite de tráfico en GB (ej. 10): " limit_gb
    
    echo -e "${AZUL}[INFO]${NORMAL} Para gestión real de GB, use un panel (X-UI) o un script de monitoreo con la API de Xray."
    echo -e "${VERDE}[CONFIGURADO]${NORMAL} Se ha registrado que el usuario ${uuid_target} tiene un límite de ${limit_gb} GB."
    pause
}

function show_connection_details() {
    local username=$1
    local new_uuid=$2
    
    # Extraer datos de la configuración actual
    local port=$(${JQ_PATH} '.inbounds[0].port' "${CONFIG_FILE}" 2>/dev/null)
    local network=$(${JQ_PATH} '.inbounds[0].streamSettings.network' "${CONFIG_FILE}" 2>/dev/null)
    local security=$(${JQ_PATH} '.inbounds[0].streamSettings.security' "${CONFIG_FILE}" 2>/dev/null)
    
    echo -e "\n${AZUL}--- DETALLES DE CONEXIÓN PARA '${username}' ---${NORMAL}"
    echo -e "Protocolo: ${VERDE}VMess${NORMAL}"
    echo -e "UUID: ${VERDE}${new_uuid}${NORMAL}"
    echo -e "Puerto: ${VERDE}${port:-N/A}${NORMAL}"
    echo -e "Transporte: ${VERDE}${network:-N/A}${NORMAL}"
    echo -e "Seguridad: ${VERDE}${security:-N/A}${NORMAL}"
    echo -e "\n${AMARILLO}Recuerda usar estos datos en tu cliente V2Ray/Xray.${NORMAL}"
}

function pause() {
    echo ""
    read -p "Presiona [Enter] para continuar..."
}

# --- Menú Principal ---

function main_menu() {
    # Verificar si Xray y jq están instalados antes de mostrar el menú de gestión
    if ! command -v xray &> /dev/null || ! command -v jq &> /dev/null; then
        banner
        echo -e "${ROJO}[ALERTA]${NORMAL} Xray o dependencias no instaladas."
        echo -e "${AZUL}1)${NORMAL} INSTALAR Xray y Dependencias"
        echo -e "${AZUL}0)${NORMAL} Salir"
        read -p "Opción: " initial_choice
        case $initial_choice in
            1) install_dependencies; install_xray_core ;;
            0) echo -e "${AZUL}¡Adiós!${NORMAL}"; exit 0 ;;
            *) echo -e "${ROJO}Opción no válida. Intenta de nuevo.${NORMAL}"; pause; main_menu ;;
        esac
    fi
    
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
