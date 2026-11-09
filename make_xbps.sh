#!/bin/bash
# Neko Void Updater - XBPS Package Generator

set -e

echo "󰄛 Preparando construcción del paquete .xbps..."

# 1. Compilar componentes
echo "󰚰 Compilando Core (Rust)..."
if command -v cargo >/dev/null 2>&1; then
    cd neko-updater-core && cargo build --release && cd ..
else
    echo "Aviso: Cargo no encontrado, usando binario preexistente si está disponible."
fi

echo "󰚰 Compilando Tray (C++/Qt)..."
cd neko-updater-tray
mkdir -p build && cd build
cmake ..
make
cd ../..

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
cp neko-updater-core/target/release/neko-updater-core pkg/usr/bin/
cp neko-updater-tray/build/neko-updater-tray pkg/usr/bin/
cp -r neko-updater-core/Data/* pkg/usr/share/neko-void/
if [ -d neko-updater-tray/build/translations ]; then
    cp -f neko-updater-tray/build/translations/*.qm pkg/usr/share/neko-void/translations/ 2>/dev/null || true
fi
cp neko-updater-core/Data/logo.png pkg/usr/share/pixmaps/neko-updater.png
cp files/neko-void-updater.desktop pkg/usr/share/applications/
cp files/neko-void-updater.desktop pkg/etc/xdg/autostart/
cp files/void.pkexec.xbps.policy pkg/usr/share/polkit-1/actions/org.neko_void.updater.policy
cp files/neko-void-sync/run pkg/etc/sv/neko-void-sync/run
cp files/neko-void-sync/log/run pkg/etc/sv/neko-void-sync/log/run
chmod +x pkg/usr/bin/neko-updater-core
chmod +x pkg/usr/bin/neko-updater-tray
chmod +x pkg/etc/sv/neko-void-sync/run
chmod +x pkg/etc/sv/neko-void-sync/log/run

# 4. Generar el paquete XBPS
echo "󰄛 Generando archivo .xbps final..."
ARCH=$(uname -m)

xbps-create -A "$ARCH" -n "neko-void-updater-5.1.0_1" \
    -s "Modern system updater for Neko Void Linux (XBPS + Flatpak)" \
    -m "Alexander <https://github.com/ErzaGOD19>" \
    pkg/
if [ $? -eq 0 ]; then
    echo ""
    echo "---------------------------------------------------"
    echo "¡ÉXITO! Paquete creado para $ARCH"
    echo "Para instalarlo localmente:"
    echo "doas xbps-install --repository=. neko-void-updater"
    echo "o con sudo:"
    echo "sudo xbps-install --repository=. neko-void-updater"
    echo "---------------------------------------------------"
else
    echo "Error: Asegúrate de tener las herramientas de xbps instaladas (xbps-create)."
fi
