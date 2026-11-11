# Neko Void Updater

**Neko Void Updater** is a lightweight, high-performance system update notifier and daemon designed specifically for **Void Linux**. Written in **Rust** and **C++ (Qt 5/6)**, it features native desktop tray integration, configurable background synchronization, and an atomic, lock-protected execution core.

![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)
![Language](https://img.shields.io/badge/rust-2021-orange.svg)
![GUI](https://img.shields.io/badge/Qt-5%20%7C%206-green.svg)

---

## Architecture

The suite consists of two specialized components:

* **`neko-updater-core` (Rust):** A high-speed, zero-bloat CLI backend and background daemon. It handles XBPS synchronization (`xbps-install -S`), system updates (`xbps-install -Suy`), Flatpak updates (both `--system` and `--user`), and cache/orphan cleanup safely using file locks (`/run/neko-updater.lock`) and atomic writes.
* **`neko-updater-tray` (C++ / Qt):** A minimal system tray daemon that monitors available updates and interacts directly via its context menu:
  * **Supported Package Managers:** XBPS (System) and Flatpak (System & User applications).
  * **Localization:** Native Spanish with translations for English (`en`), German (`de`), Portuguese (`pt`), Italian (`it`), and Japanese (`ja`) via automatic system locale detection.

---

## Build Requirements

Make sure you have the development libraries and compilers installed on your Void Linux system:

```bash
# Toolchain & dependencies (choose qt6-* or qt5-*)
sudo xbps-install -S rust cargo cmake base-devel qt6-base-devel qt6-tools
```
*(Qt 5 with `qt5-devel` and `qt5-tools` is also supported as an automatic CMake fallback.)*

---

## Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/ANOMALI0x00/Neko-Update.git
   cd Neko-Update
   ```

2. **Compile and install:**
   ```bash
   make build
   doas make install
   ```
   *(Or use `sudo ./install.sh` directly.)*

3. **Enable the Runit background sync service:**
   ```bash
   doas ln -s /etc/sv/neko-void-sync /var/service/
   ```

---

## Uninstallation

To cleanly stop the Runit service, terminate running instances, and remove all installed binaries and configuration assets:

```bash
doas ./uninstall.sh
```
*(Or `doas make uninstall`.)*

---

## Features

* **Configurable Background Daemon:** Runs as a Runit service (`/etc/sv/neko-void-sync`) with configurable sync intervals (`12h`, `1d`, `3d`, `1w`, or `manual`) via `/etc/neko-void-updater.conf` or the tray menu.
* **Interactive Tray Controls:**
  * **Right/Context Click:** Check for updates now, apply updates, change sync interval, clean XBPS/Flatpak cache & orphans, open Void Linux update news, or quit.
  * **Dynamic Tray Icons:** Visually indicates up-to-date, checking, updating, or pending-updates states.
* **Privilege Escalation:** Works seamlessly with Polkit (`pkexec`), `doas`, or `sudo`, and detects your desktop terminal automatically.

---

## Credits

* **Author & Maintainer:** [ANOMALI0x00](https://github.com/ANOMALI0x00)
* **Co-Author:** ErzaGOD19 - Trinity Community
* **License:** GPL-3.0-or-later
