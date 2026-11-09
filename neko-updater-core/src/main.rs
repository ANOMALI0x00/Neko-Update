/*
 * Neko Void Updater - Core
 * Copyright (C) 2024 ErzaGOD19 - Trinity Community
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

use fs2::FileExt;
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::net::TcpStream;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::Path;
use std::process::{Command, ExitStatus, Stdio};
use std::time::Duration;

const LOCK_PATH: &str = "/tmp/neko_updater.lock";
const COUNT_PATH: &str = "/tmp/neko_updates_count";
const LOG_PATH: &str = "/tmp/neko_updater.log";
// O_NOFOLLOW (0o400000 en Linux) para prevenir TOCTOU symlink attacks
const O_NOFOLLOW: i32 = 0o400000;

fn log(msg: &str) {
    let path = Path::new(LOG_PATH);
    if let Ok(meta) = path.symlink_metadata() {
        // Truncar o rotar si supera 1MB o es un symlink
        if meta.file_type().is_symlink() || meta.len() > 1_000_000 {
            let _ = fs::remove_file(path);
        }
    }
    let now = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
    let line = format!("[{}] {}\n", now, msg);
    if let Ok(mut file) = OpenOptions::new()
        .create(true)
        .append(true)
        .custom_flags(O_NOFOLLOW)
        .open(path)
    {
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o666));
        let _ = file.write_all(line.as_bytes());
    }
}

fn main() {
    log("Iniciando neko-updater-core");
    if let Err(err) = run() {
        log(&format!("ERROR FATAL: {}", err));
        eprintln!("neko-updater-core: {}", err);
        std::process::exit(1);
    }
}

fn run() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.iter().any(|arg| arg == "--apply") {
        log("Acción: Aplicar actualizaciones");
        apply_updates()
    } else if args.iter().any(|arg| arg == "--clean") {
        log("Acción: Limpieza de sistema");
        clean_system()
    } else if args.iter().any(|arg| arg == "--sync-daemon") {
        log("Acción: Modo Demonio de Sincronización");
        sync_daemon()
    } else {
        log("Acción: Comprobar actualizaciones");
        let checked = check_updates()?;
        if checked {
            let now = chrono::Local::now().timestamp();
            let _ = update_config_last_check(now);
        }
        Ok(())
    }
}

fn sync_daemon() -> io::Result<()> {
    log("Iniciando demonio de sincronización en segundo plano...");
    loop {
        let frequency = read_config_value("frequency").unwrap_or_else(|| "1d".to_string());
        let last_check = read_config_value("lastCheck")
            .and_then(|v| v.parse::<i64>().ok())
            .unwrap_or(0);

        if frequency == "manual" {
            std::thread::sleep(Duration::from_secs(300));
            continue;
        }

        let interval_secs = match frequency.as_str() {
            "12h" => 12 * 3600,
            "1d" => 24 * 3600,
            "3d" => 3 * 24 * 3600,
            "1w" => 7 * 24 * 3600,
            _ => 24 * 3600, // Default 1d
        };

        let now = chrono::Local::now().timestamp();
        let elapsed = now - last_check;

        if elapsed >= interval_secs {
            log(&format!("Sincronización programada iniciada (frecuencia: {}, última: {})", frequency, last_check));
            match check_updates() {
                Ok(true) => {
                    log("Sincronización del demonio completada exitosamente.");
                    let _ = update_config_last_check(now);
                }
                Ok(false) => {
                    log("Sincronización pospuesta (sin conexión o gestor ocupado). Reintentando en breve.");
                }
                Err(e) => {
                    log(&format!("Error en sincronización del demonio: {}", e));
                }
            }
        }

        // Dormir hasta un máximo de 5 minutos (o el tiempo restante si es menor) para responder a cambios de config
        let remaining = if elapsed < interval_secs {
            (interval_secs - elapsed) as u64
        } else {
            300
        };
        let sleep_secs = remaining.clamp(60, 300);
        std::thread::sleep(Duration::from_secs(sleep_secs));
    }
}

fn get_config_path() -> std::path::PathBuf {
    // 1. Si corremos bajo sudo/doas, consultar la config del usuario que invocó el comando
    if let Ok(user) = env::var("SUDO_USER").or_else(|_| env::var("DOAS_USER")) {
        let p = Path::new("/home").join(user).join(".config/NekoVoid/Updater.conf");
        if p.exists() {
            return p;
        }
    }
    // 2. Si corremos como usuario de escritorio normal (HOME no root)
    let home = env::var("HOME").unwrap_or_else(|_| "/root".to_string());
    let default_path = Path::new(&home).join(".config/NekoVoid/Updater.conf");
    if default_path.exists() || home != "/root" {
        return default_path;
    }
    // 3. Si corre como demonio del sistema (root), buscar la config del usuario de escritorio
    if let Ok(entries) = fs::read_dir("/home") {
        for entry in entries.flatten() {
            let user_conf = entry.path().join(".config/NekoVoid/Updater.conf");
            if user_conf.exists() {
                return user_conf;
            }
        }
    }
    // 4. Fallback a configuración global del sistema
    let system_conf = Path::new("/etc/neko-void/updater.conf");
    if system_conf.exists() {
        return system_conf.to_path_buf();
    }
    default_path
}

fn read_config_value(key: &str) -> Option<String> {
    let config_path = get_config_path();
    let prefix = format!("{}=", key);

    if let Ok(content) = fs::read_to_string(config_path) {
        for line in content.lines() {
            let line = line.trim();
            if line.starts_with(&prefix) {
                return Some(line[prefix.len()..].trim().to_string());
            }
        }
    }
    None
}

fn update_config_last_check(timestamp: i64) -> io::Result<()> {
    let config_path = get_config_path();
    let config_dir = config_path.parent().unwrap_or_else(|| Path::new("/etc/neko-void"));

    // 1. Si config_dir es un enlace simbólico, abortar por seguridad (evitar symlink traversal)
    if let Ok(meta) = config_dir.symlink_metadata() {
        if meta.file_type().is_symlink() {
            log("Alerta de seguridad: el directorio de configuración es un enlace simbólico. Omitiendo.");
            return Ok(());
        }
    }

    // 2. Si config_path es un enlace simbólico, eliminarlo para no sobrescribir archivos del sistema
    if let Ok(meta) = config_path.symlink_metadata() {
        if meta.file_type().is_symlink() {
            let _ = fs::remove_file(&config_path);
        }
    }

    let mut lines: Vec<String> = if config_path.exists() {
        fs::read_to_string(&config_path)?.lines().map(|s| s.to_string()).collect()
    } else {
        let _ = fs::create_dir_all(config_dir);
        vec!["[General]".to_string()]
    };

    let mut found = false;
    let prefix = "lastCheck=";
    for line in lines.iter_mut() {
        if line.trim().starts_with(prefix) {
            *line = format!("lastCheck={}", timestamp);
            found = true;
            break;
        }
    }

    if !found {
        lines.push(format!("lastCheck={}", timestamp));
    }

    let mut content = lines.join("\n");
    content.push('\n');

    // 3. Escribir usando O_NOFOLLOW para garantizar que no se siga ningún symlink creado concurrentemente
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .custom_flags(O_NOFOLLOW)
        .open(&config_path)?;
    file.write_all(content.as_bytes())?;
    let _ = fs::set_permissions(&config_path, fs::Permissions::from_mode(0o666));

    // 4. Si somos root y el directorio pertenece a un usuario regular, preservar su ownership usando lchown
    if let Ok(dir_meta) = config_dir.symlink_metadata() {
        if !dir_meta.file_type().is_symlink() {
            let uid = dir_meta.uid();
            let gid = dir_meta.gid();
            let _ = std::os::unix::fs::lchown(&config_path, Some(uid), Some(gid));
        }
    }

    Ok(())
}


fn run_command(program: &str, args: &[&str], capture: bool) -> io::Result<(ExitStatus, String)> {
    log(&format!("Ejecutando: {} {:?}", program, args));
    let mut cmd = Command::new(program);
    cmd.args(args);

    if capture {
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());
    } else {
        cmd.stdout(Stdio::inherit());
        cmd.stderr(Stdio::inherit());
    }

    let output = cmd.output()?;
    let stdout = if capture {
        String::from_utf8_lossy(&output.stdout).into_owned()
    } else {
        String::new()
    };

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        log(&format!("Comando falló con código {}: {}", output.status.code().unwrap_or(-1), stderr.trim()));
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!(
                "Command `{}` failed with code {}: {}",
                program,
                output.status.code().unwrap_or(-1),
                stderr.trim()
            ),
        ));
    }

    Ok((output.status, stdout))
}

fn has_internet() -> bool {
    let targets = ["1.1.1.1:53", "8.8.8.8:53", "9.9.9.9:53"];
    let timeout = Duration::from_millis(1500);
    for target in targets {
        if let Ok(addr) = target.parse() {
            if TcpStream::connect_timeout(&addr, timeout).is_ok() {
                return true;
            }
        }
    }
    false
}

fn check_updates() -> io::Result<bool> {
    // Si XBPS ya está en uso por otro proceso (instalación o actualización en curso), no interferir
    if let Ok(xbps_lock) = OpenOptions::new().read(true).open("/var/db/xbps/lock") {
        if xbps_lock.try_lock_shared().is_err() {
            log("Aviso: XBPS se encuentra bloqueado por otro proceso. Saltando comprobación.");
            return Ok(false);
        }
    }

    // Si apply_updates() tiene el lock de actualización en curso, no interferir
    let lock_path = Path::new(LOCK_PATH);
    if lock_path.exists() {
        if let Ok(file) = OpenOptions::new().read(true).open(lock_path) {
            if file.try_lock_shared().is_err() {
                log("Aviso: Hay una actualización en curso (lock activo). Saltando comprobación.");
                return Ok(false);
            }
        }
    }

    if !has_internet() {
        log("Error: No hay conexión a internet. Saltando comprobación.");
        return Ok(false);
    }

    log("Comprobando actualizaciones de XBPS y Flatpak en paralelo...");

    // 1. Hilo de consulta XBPS
    let xbps_handle = std::thread::spawn(|| {
        run_command("xbps-install", &["-Mun"], true)
    });

    // 2. Hilo de consulta Flatpak (sólo lectura de remotos)
    let flatpak_handle = std::thread::spawn(|| {
        if !Path::new("/usr/bin/flatpak").exists() {
            return (0, String::new());
        }
        let mut count = 0;
        let mut combined = String::new();
        for scope in &["--system", "--user"] {
            if let Ok((_, output)) = run_command("flatpak", &["remote-ls", scope, "--updates"], true) {
                let updates: Vec<&str> = output.lines().filter(|l| !l.trim().is_empty()).collect();
                if !updates.is_empty() {
                    count += updates.len();
                    combined.push_str(&format!("[Flatpak ({})]\n{}\n", scope, output));
                }
            }
        }
        (count, combined)
    });

    let mut total_count = 0;

    // Recoger resultados de XBPS
    if let Ok(res) = xbps_handle.join() {
        match res {
            Ok((_, output)) => {
                let (count, has_kernel) = parse_xbps_details(&output);
                log(&format!("XBPS encontró {} paquetes para actualizar", count));
                total_count += count;
                print_update_output("XBPS", &output);
                if has_kernel {
                    println!("󰄛 Aviso: Hay una actualización de Kernel disponible (se requerirá reiniciar tras actualizar).");
                }
            }
            Err(e) => {
                log(&format!("Error comprobando actualizaciones XBPS: {}", e));
            }
        }
    }

    // Recoger resultados de Flatpak
    if let Ok((flatpak_count, flatpak_out)) = flatpak_handle.join() {
        if flatpak_count > 0 {
            log(&format!("Flatpak encontró {} actualizaciones", flatpak_count));
            total_count += flatpak_count;
            print!("{}", flatpak_out);
        }
    }

    log(&format!("Total actualizaciones encontradas: {}", total_count));
    write_count_file(total_count)?;
    Ok(true)
}

fn parse_xbps_details(output: &str) -> (usize, bool) {
    // xbps-install -un genera líneas como:
    // <pkgname-version> <action> <arch> <repo> <dl_size> <installed_size>
    let mut count = 0;
    let mut has_kernel = false;
    for line in output.lines() {
        let line = line.trim();
        if line.is_empty() { continue; }
        let lower = line.to_lowercase();
        // Si no hay paquetes pendientes o ya está al día
        if lower.contains("nothing to do") || lower.contains("no packages") || lower.contains("0 downloaded") {
            continue;
        }
        let parts: Vec<&str> = line.split_whitespace().collect();
        // Formato estándar de transacción de xbps: la segunda columna indica la acción
        if parts.len() >= 6 {
            let action = parts[1];
            if action == "update" || action == "install" {
                count += 1;
                let pkgname = parts[0];
                if pkgname.starts_with("linux") || pkgname.starts_with("base-system") {
                    let is_excluded = pkgname.contains("headers")
                        || pkgname.contains("firmware")
                        || pkgname.contains("-base")
                        || pkgname.contains("-tools")
                        || pkgname.contains("-docs")
                        || pkgname.contains("-dbg");
                    if !is_excluded {
                        has_kernel = true;
                    }
                }
                continue;
            }
        }
        // Compatibilidad con formatos alternativos o mensajes de transición
        if line.contains(" update ") || line.contains(" -> ") {
            count += 1;
        }
    }
    (count, has_kernel)
}

fn print_update_output(label: &str, output: &str) {
    if !output.trim().is_empty() {
        println!("[{}]", label);
        println!("{}", output);
    }
}

fn write_count_file(count: usize) -> io::Result<()> {
    let path = Path::new(COUNT_PATH);
    if let Ok(meta) = path.symlink_metadata() {
        if meta.file_type().is_symlink() {
            let _ = fs::remove_file(path);
        }
    }
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }

    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .custom_flags(O_NOFOLLOW)
        .open(path)?;

    let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o666));
    writeln!(file, "{}", count)?;
    Ok(())
}

fn clean_system() -> io::Result<()> {
    log("Iniciando limpieza profunda (huérfanos, caché y kernels)...");
    let _ = run_command("xbps-remove", &["-Ooy"], false);

    // En Void Linux, vkpurge elimina los kernels antiguos en /boot
    if Path::new("/usr/bin/vkpurge").exists() {
        log("Purgando kernels antiguos no utilizados con vkpurge...");
        let _ = run_command("vkpurge", &["rm", "all"], false);
    }

    if Path::new("/usr/bin/flatpak").exists() {
        log("Limpiando dependencias huérfanas de Flatpak (sistema)...");
        let _ = run_command("flatpak", &["uninstall", "--unused", "--system", "-y"], false);
    }

    let mut users_to_clean: Vec<String> = Vec::new();
    if let Ok(user) = env::var("SUDO_USER").or_else(|_| env::var("DOAS_USER")) {
        users_to_clean.push(user);
    } else if let Ok(entries) = fs::read_dir("/home") {
        for entry in entries.flatten() {
            if let Ok(ft) = entry.file_type() {
                if ft.is_dir() {
                    users_to_clean.push(entry.file_name().to_string_lossy().into_owned());
                }
            }
        }
    }

    for user in users_to_clean {
        // Validación estricta del nombre de usuario para prevenir path traversal
        if user.is_empty() || !user.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') {
            continue;
        }

        // Si tenemos flatpak instalado, limpiar dependencias de usuario
        if Path::new("/usr/bin/flatpak").exists() {
            let _ = run_command("su", &["-", &user, "-c", "flatpak uninstall --unused -y 2>/dev/null || true"], false);
        }

        let thumb_path = format!("/home/{}/.cache/thumbnails", user);
        let p = Path::new(&thumb_path);
        if let Ok(meta) = p.symlink_metadata() {
            // Protección contra symlink attacks: nunca seguir enlaces simbólicos como root
            if meta.file_type().is_symlink() {
                log(&format!("Aviso de seguridad: {} es un enlace simbólico. Omitiendo.", thumb_path));
                continue;
            }
            if meta.is_dir() {
                log(&format!("Limpiando caché de miniaturas de {}...", user));
                let _ = fs::remove_dir_all(p);
            }
        }
    }

    log("Limpieza completada");
    Ok(())
}

fn apply_updates() -> io::Result<()> {
    let path = Path::new(LOCK_PATH);
    if let Ok(meta) = path.symlink_metadata() {
        if meta.file_type().is_symlink() {
            let _ = fs::remove_file(path);
        }
    }

    let lock_file = OpenOptions::new()
        .create(true)
        .write(true)
        .custom_flags(O_NOFOLLOW)
        .open(path)?;

    let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o666));

    lock_file.try_lock_exclusive().map_err(|_| {
        log("Error: Otro proceso ya tiene el lock de actualización");
        io::Error::new(
            io::ErrorKind::AlreadyExists,
            "Otro proceso de actualización ya se está ejecutando",
        )
    })?;

    // En Void Linux, si xbps tiene actualización pendiente debe actualizarse primero
    log("Verificando si xbps requiere actualización preliminar...");
    let _ = run_command("xbps-install", &["-uy", "xbps"], false);

    log("Sincronizando repositorios y aplicando actualizaciones XBPS (-Suy)...");
    run_command("xbps-install", &["-Suy"], false)?;

    if Path::new("/usr/bin/flatpak").exists() {
        log("Aplicando actualizaciones Flatpak del sistema...");
        let _ = run_command("flatpak", &["update", "-y", "--system"], false);

        // Si se invocó con doas/sudo, actualizar también las aplicaciones de usuario
        if let Ok(user) = env::var("SUDO_USER").or_else(|_| env::var("DOAS_USER")) {
            if !user.is_empty() && user.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') {
                log(&format!("Aplicando actualizaciones Flatpak de usuario para {}...", user));
                let _ = run_command("su", &["-", &user, "-c", "flatpak update -y --user 2>/dev/null || true"], false);
            }
        }
    }

    log("Actualización completada exitosamente");
    let _ = write_count_file(0);
    
    Ok(())
}
