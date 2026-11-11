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
POLICY_DIR="/usr/share/polkit-1/actions"
AUTOSTART_DIR="/etc/xdg/autostart"
DESKTOP_DIR="/usr/share/applications"

# 2. Crear directorios necesarios
mkdir -p "$DATA_DIR/translations"
mkdir -p "$POLICY_DIR"
mkdir -p "$AUTOSTART_DIR"
mkdir -p "$DESKTOP_DIR"

# 3. Detener servicio previo si está activo
echo "󰚰 Instalando binarios..."
if [ -L /var/service/neko-void-sync ]; then
    sv down /var/service/neko-void-sync 2>/dev/null || true
    killall neko-updater-core 2>/dev/null || true
fi

CORE_BIN="neko-updater-core/target/release/neko-updater-core"
if command -v cargo >/dev/null 2>&1; then
    if [ ! -f "$CORE_BIN" ] || [ "neko-updater-core/src/main.rs" -nt "$CORE_BIN" ]; then
        echo "Compilando core (Rust)..."
        (cd neko-updater-core && cargo build --release)
    fi
fi

if [ -f "$CORE_BIN" ]; then
    if [ "neko-updater-core/src/main.rs" -nt "$CORE_BIN" ]; then
        echo "AVISO: El binario de core es anterior a src/main.rs y no se encontró cargo para recompilarlo."
    fi
    install -m 755 "$CORE_BIN" "$BIN_DIR/neko-updater-core"
else
    echo "Error: No se encontró '$CORE_BIN'. Instala cargo y compílalo primero."
    exit 1
fi

if [ -f "neko-updater-tray/build/neko-updater-tray" ]; then
    install -m 755 "neko-updater-tray/build/neko-updater-tray" "$BIN_DIR/neko-updater-tray"
elif [ -f "neko-updater-tray/neko-updater-tray" ]; then
    install -m 755 "neko-updater-tray/neko-updater-tray" "$BIN_DIR/neko-updater-tray"
else
    echo "Error: No se encontró el binario de neko-updater-tray compilado."
    exit 1
fi

# 4. Instalar iconos, recursos y traducciones
echo "󰄛 Instalando recursos visuales y traducciones..."
rm -rf "$DATA_DIR/fonts"
install -m 644 neko-updater-core/Data/*.png "$DATA_DIR/"
install -m 644 neko-updater-core/Data/logo.png "/usr/share/pixmaps/neko-updater.png"

if [ -d "neko-updater-tray/build/translations" ]; then
    install -m 644 neko-updater-tray/build/translations/*.qm "$DATA_DIR/translations/"
fi

# 5. Instalar Política de Polkit (644 obligatorio, no ejecutable)
echo "󰒓 Configurando permisos de sistema (Polkit)..."
install -m 644 files/void.pkexec.xbps.policy "$POLICY_DIR/org.neko_void.updater.policy"

# 6. Instalar archivos Desktop y Autostart
echo "󱐋 Configurando lanzadores..."
install -m 644 files/neko-void-updater.desktop "$DESKTOP_DIR/neko-void-updater.desktop"
install -m 644 files/neko-void-updater.desktop "$AUTOSTART_DIR/neko-void-updater.desktop"

# 7. Instalar servicio Runit
echo "󰒓 Instalando servicio de sincronización (Runit)..."
mkdir -p /etc/sv/neko-void-sync/log
install -m 755 files/neko-void-sync/run /etc/sv/neko-void-sync/run
install -m 755 files/neko-void-sync/log/run /etc/sv/neko-void-sync/log/run

if [ -L /var/service/neko-void-sync ]; then
    sv up /var/service/neko-void-sync 2>/dev/null || true
fi

# 8. Actualizar base de datos de iconos
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true

echo ""
echo "󰄛 ¡Instalación completada!"
echo "Puedes lanzar el programa desde tu menú de aplicaciones como 'Neko Void Updater'."
echo "Para habilitar el servicio de sincronización automática, ejecuta:"
echo "  doas ln -s /etc/sv/neko-void-sync /var/service/"
echo "Los logs se guardarán en /tmp/neko_updater.log para depuración."
