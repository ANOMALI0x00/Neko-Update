#!/bin/bash
# Neko Void Updater - Uninstaller
# Compatible with Void Linux and derivatives

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta el desinstalador como root (doas ./uninstall.sh o sudo ./uninstall.sh)"
  exit 1
fi

echo "󰄛 Desinstalando Neko Void Updater..."

# 1. Detener ordenadamente el servicio Runit antes de remover su definición
if [ -L /var/service/neko-void-sync ]; then
    echo "󰒓 Deshabilitando servicio Runit..."
    sv down /var/service/neko-void-sync 2>/dev/null || true
    sv exit /var/service/neko-void-sync 2>/dev/null || true
    rm -f /var/service/neko-void-sync
    # Esperar hasta 6s a que runsvdir libere supervise/ y evite warnings
    for _ in 1 2 3 4 5 6; do
        pgrep -f "runsv neko-void-sync" >/dev/null 2>&1 || break
        sleep 1
    done
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

# 5. Limpiar archivos temporales y locks
rm -f /run/neko-updater.lock /tmp/neko_updater.lock /tmp/neko_updates_count /tmp/neko_updates_count.*.tmp /tmp/neko_updater.log

gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true

echo "󰄛 ¡Neko Void Updater ha sido desinstalado correctamente!"
