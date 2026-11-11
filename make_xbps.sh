#!/bin/bash
# Neko Void Updater - XBPS Package Generator

set -e

echo "󰄛 Preparando construcción del paquete .xbps..."

# 1. Compilar componentes
echo "󰚰 Compilando Core (Rust)..."
if command -v cargo >/dev/null 2>&1; then
    (cd neko-updater-core && cargo build --release)
else
    echo "Aviso: Cargo no encontrado, usando binario preexistente si está disponible."
fi

echo "󰚰 Compilando Tray (C++/Qt)..."
mkdir -p neko-updater-tray/build
(cd neko-updater-tray/build && cmake .. && make)

# 2. Crear estructura del paquete (Root del paquete)
rm -rf pkg
mkdir -p pkg/usr/bin
mkdir -p pkg/usr/share/neko-void/translations
mkdir -p pkg/usr/share/applications
mkdir -p pkg/usr/share/pixmaps
mkdir -p pkg/usr/share/polkit-1/actions
mkdir -p pkg/etc/xdg/autostart
mkdir -p pkg/etc/sv/neko-void-sync/log

# 3. Copiar archivos a la estructura
echo "󱐋 Organizando archivos..."
install -m 755 neko-updater-core/target/release/neko-updater-core pkg/usr/bin/neko-updater-core
install -m 755 neko-updater-tray/build/neko-updater-tray pkg/usr/bin/neko-updater-tray
install -m 644 neko-updater-core/Data/*.png pkg/usr/share/neko-void/
if [ -d neko-updater-tray/build/translations ]; then
    install -m 644 neko-updater-tray/build/translations/*.qm pkg/usr/share/neko-void/translations/ 2>/dev/null || true
fi
install -m 644 neko-updater-core/Data/logo.png pkg/usr/share/pixmaps/neko-updater.png
install -m 644 files/neko-void-updater.desktop pkg/usr/share/applications/neko-void-updater.desktop
install -m 644 files/neko-void-updater.desktop pkg/etc/xdg/autostart/neko-void-updater.desktop
install -m 644 files/void.pkexec.xbps.policy pkg/usr/share/polkit-1/actions/org.neko_void.updater.policy
install -m 755 files/neko-void-sync/run pkg/etc/sv/neko-void-sync/run
install -m 755 files/neko-void-sync/log/run pkg/etc/sv/neko-void-sync/log/run

# 4. Generar el paquete XBPS
echo "󰄛 Generando archivo .xbps final..."
ARCH=$(uname -m)

xbps-create -A "$ARCH" -n "neko-void-updater-5.2.0_1" \
    -s "Modern system updater for Void Linux (XBPS + Flatpak)" \
    -l "GPL-3.0-or-later" \
    -H "https://github.com/ANOMALI0x00/Neko-Update" \
    -m "ANOMALI0x00 <ANOMALI0x00@users.noreply.github.com>" \
    -D "polkit>=0 runit>=0 xbps>=0" \
    pkg/

rm -rf pkg

echo ""
echo "---------------------------------------------------"
echo "¡ÉXITO! Paquete creado para $ARCH"
echo "Para instalarlo localmente:"
echo "  xbps-rindex -a neko-void-updater-5.2.0_1.${ARCH}.xbps"
echo "  doas xbps-install --repository=. neko-void-updater"
echo "---------------------------------------------------"
