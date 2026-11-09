#!/bin/bash
# Neko Void Updater - Uninstaller
# Compatible with Void Linux and derivatives

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta el desinstalador como root (doas ./uninstall.sh o sudo ./uninstall.sh)"
  exit 1
fi

echo "󰄛 Desinstalando Neko Void Updater..."

# 1. Detener procesos y servicio Runit
if [ -L /var/service/neko-void-sync ]; then
    echo "󰒓 Deshabilitando servicio Runit..."
    rm -f /var/service/neko-void-sync
    sv down /etc/sv/neko-void-sync 2>/dev/null || true
fi
killall neko-updater-tray 2>/dev/null || true
killall neko-updater-core 2>/dev/null || true

# 2. Eliminar binarios
echo "󰚰 Eliminando binarios..."
rm -f /usr/bin/neko-updater-core
rm -f /usr/bin/neko-updater-tray

# 3. Eliminar recursos y lanzadores
echo "󰒓 Eliminando recursos y accesos directos..."
rm -rf /usr/share/neko-void
rm -f /usr/share/pixmaps/neko-updater.png
rm -f /usr/share/polkit-1/actions/org.neko_void.updater.policy
rm -f /usr/share/applications/neko-void-updater.desktop
rm -f /etc/xdg/autostart/neko-void-updater.desktop

# 4. Eliminar definición de servicio Runit
rm -rf /etc/sv/neko-void-sync

# 5. Limpiar archivos temporales
rm -f /tmp/neko_updater.lock /tmp/neko_updates_count /tmp/neko_updater.log

gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true

echo "󰄛 ¡Neko Void Updater ha sido desinstalado correctamente!"
