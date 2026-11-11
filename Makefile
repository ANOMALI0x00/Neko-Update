# Neko Void Updater - Core (Rust) & Tray (Qt) Makefile
# Copyright (C) 2024-2026 ANOMALI0x00 & ErzaGOD19

CORE_DIR = neko-updater-core
CORE_BIN = $(CORE_DIR)/target/release/neko-updater-core
TRAY_DIR = neko-updater-tray
TRAY_BIN = $(TRAY_DIR)/neko-updater-tray

all: $(CORE_BIN) $(TRAY_BIN)

$(CORE_BIN): $(CORE_DIR)/src/main.rs $(CORE_DIR)/Cargo.toml
	@echo "Compilando Core (Rust)..."
	cd $(CORE_DIR) && cargo build --release

$(TRAY_BIN): $(TRAY_DIR)/main.cpp $(TRAY_DIR)/CMakeLists.txt
	@echo "Compilando Tray (Qt con CMake)..."
	mkdir -p $(TRAY_DIR)/build
	cd $(TRAY_DIR)/build && cmake .. && $(MAKE)
	cp $(TRAY_DIR)/build/neko-updater-tray $(TRAY_BIN)

clean:
	rm -f $(TRAY_BIN)
	rm -rf $(TRAY_DIR)/build pkg *.xbps
	-cd $(CORE_DIR) && cargo clean

install: all
	@echo "Instalando Neko Void Updater..."
	./install.sh

uninstall:
	./uninstall.sh

.PHONY: all clean install uninstall
