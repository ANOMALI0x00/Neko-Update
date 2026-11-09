#!/bin/bash

# Neko Void Updater - Universal Installer
# Compatible with Void Linux and derivatives

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta el instalador como root (doas ./install.sh o sudo ./install.sh)"
  exit 1
fi

echo "󰄛 Iniciando instalación de Neko Void Updater..."

# 1. Rutas de directorios
BIN_DIR="/usr/bin"
DATA_DIR="/usr/share/neko-void"
ICON_DIR="/usr/share/icons/hicolor/scalable/apps"
POLICY_DIR="/usr/share/polkit-1/actions"
AUTOSTART_DIR="/etc/xdg/autostart"
DESKTOP_DIR="/usr/share/applications"

# 2. Crear directorios necesarios
mkdir -p "$DATA_DIR"
mkdir -p "$ICON_DIR"
mkdir -p "$POLICY_DIR"

# 3. Compilar (si es necesario) y mover binarios
echo "󰚰 Instalando binarios..."
if [ -L /var/service/neko-void-sync ]; then
    sv down neko-void-sync 2>/dev/null || true
    killall neko-updater-core 2>/dev/null || true
fi
if [ -f "neko-updater-core/target/release/neko-updater-core" ]; then
    cp -f "neko-updater-core/target/release/neko-updater-core" "$BIN_DIR/neko-updater-core"
else
    echo "Aviso: No se encontró el binario de core compilado. Compílalo con 'cargo build --release' primero."
fi

if [ -f "neko-updater-tray/neko-updater-tray" ]; then
    cp -f "neko-updater-tray/neko-updater-tray" "$BIN_DIR/neko-updater-tray"
elif [ -f "neko-updater-tray/build/neko-updater-tray" ]; then
    cp -f "neko-updater-tray/build/neko-updater-tray" "$BIN_DIR/neko-updater-tray"
else
    echo "Aviso: No se encontró el binario del tray compilado. Compílalo con cmake y make primero."
fi

chmod +x "$BIN_DIR/neko-updater-core"
chmod +x "$BIN_DIR/neko-updater-tray"

# 4. Instalar iconos y recursos
echo "󰄛 Instalando recursos visuales..."
cp -r neko-updater-core/Data/* "$DATA_DIR/"
# Usar el logo en SVG como icono de la app
cp neko-updater-core/Data/logo.png "/usr/share/pixmaps/neko-updater.png"

# Instalar traducciones (.qm)
if [ -d "neko-updater-tray/build/translations" ]; then
    echo "󰄛 Instalando traducciones..."
    mkdir -p "$DATA_DIR/translations"
    cp -f neko-updater-tray/build/translations/*.qm "$DATA_DIR/translations/" 2>/dev/null || true
fi

# 5. Instalar Política de Polkit
echo "󰒓 Configurando permisos de sistema (Polkit)..."
cp files/void.pkexec.xbps.policy "$POLICY_DIR/org.neko_void.updater.policy"

# 6. Instalar archivos Desktop y Autostart
echo "󱐋 Configurando lanzadores..."
cp files/neko-void-updater.desktop "$DESKTOP_DIR/"
cp files/neko-void-updater.desktop "$AUTOSTART_DIR/"

# 7. Instalar servicio Runit
echo "󰒓 Instalando servicio de sincronización (Runit)..."
mkdir -p /etc/sv/neko-void-sync/log
cp files/neko-void-sync/run /etc/sv/neko-void-sync/run
cp files/neko-void-sync/log/run /etc/sv/neko-void-sync/log/run
chmod +x /etc/sv/neko-void-sync/run
chmod +x /etc/sv/neko-void-sync/log/run

# 8. Actualizar base de datos de iconos
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true

echo ""
echo "󰄛 ¡Instalación completada!"
echo "Puedes lanzar el programa desde tu menú de aplicaciones como 'Neko Void Updater'."
echo "Para habilitar el servicio de sincronización automática, ejecuta:"
echo "sudo ln -s /etc/sv/neko-void-sync /var/service/"
echo "Los logs se guardarán en /tmp/neko_updater.log para depuración."
