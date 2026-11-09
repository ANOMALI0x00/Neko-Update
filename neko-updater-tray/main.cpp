#include <QApplication>
#include <QSystemTrayIcon>
#include <QMenu>
#include <QTimer>
#include <QProcess>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QAction>
#include <QIcon>
#include <QFileSystemWatcher>
#include <QTranslator>
#include <QLocale>
#include <QMessageBox>
#include <QPixmap>
#include <memory>
#include <unistd.h>

#if defined(__GLIBC__)
#include <malloc.h>
#endif

class NekoTray : public QObject {
    Q_OBJECT
public:
    NekoTray() : isWorking(false), lastNotifiedCount(-1) {
        loadIcons();
        createActions();
        createTrayIcon();

        watcher = new QFileSystemWatcher(this);
        QFile file("/tmp/neko_updates_count");
        if (!file.exists()) {
            if (file.open(QIODevice::WriteOnly)) {
                file.write("-1\n");
                file.close();
            }
        }
        watcher->addPath("/tmp/neko_updates_count");
        connect(watcher, &QFileSystemWatcher::fileChanged, this, &NekoTray::onFileChanged);

        scheduledTimer = new QTimer(this);
        connect(scheduledTimer, &QTimer::timeout, this, &NekoTray::triggerSilentCheck);

#if defined(__GLIBC__)
        heapTimer = new QTimer(this);
        connect(heapTimer, &QTimer::timeout, this, []() {
            malloc_trim(0);
        });
        heapTimer->start(15 * 60 * 1000);
#endif

        updateStatus();
        trayIcon->show();

        // Liberar heap inicial tras el renderizado de la bandeja
        QTimer::singleShot(300, this, []() {
#if defined(__GLIBC__)
            malloc_trim(0);
#endif
        });
    }

    ~NekoTray() override {
        delete trayMenu;
    }

private slots:
    void onFileChanged(const QString &path) {
        Q_UNUSED(path);
        if (!watcher->files().contains("/tmp/neko_updates_count")) {
            watcher->addPath("/tmp/neko_updates_count");
        }
        if (!isWorking) {
            updateStatus();
        }
    }

    QString findCoreBinary() {
        if (QFile::exists("/usr/bin/neko-updater-core")) {
            return "/usr/bin/neko-updater-core";
        }
        QString local = QApplication::applicationDirPath() + "/../neko-updater-core/target/release/neko-updater-core";
        if (QFile::exists(local)) {
            return local;
        }
        return "/usr/bin/neko-updater-core";
    }

    void triggerSilentCheck() {
        if (isWorking) return;
        isWorking = true;
        updateStatus();

        QProcess *process = new QProcess(this);
        auto cleaned = std::make_shared<bool>(false);
        auto cleanup = [this, process, cleaned]() {
            if (*cleaned) return;
            *cleaned = true;
            isWorking = false;
            updateStatus();
            process->deleteLater();
        };
        connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, cleanup);
        connect(process, &QProcess::errorOccurred, this, [cleanup](QProcess::ProcessError) { cleanup(); });
        process->start(findCoreBinary(), QStringList());
    }

    void updateStatus() {
        QFile file("/tmp/neko_updates_count");
        int count = -1;
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&file);
            QString content = in.readAll().trimmed();
            if (!content.isEmpty()) {
                bool ok = false;
                int val = content.toInt(&ok);
                if (ok) {
                    count = val;
                }
            }
        }

        if (isWorking) {
            trayIcon->setIcon(workingIcon);
            trayIcon->setToolTip(tr("Neko: Trabajando..."));
            statusAction->setText(tr("Estado: Trabajando..."));
        } else if (count > 0) {
            trayIcon->setIcon(warningIcon);
            trayIcon->setToolTip(tr("Neko: %1 actualizaciones disponibles").arg(count));
            statusAction->setText(tr("Actualizaciones: %1").arg(count));

            if (count != lastNotifiedCount) {
                lastNotifiedCount = count;
                trayIcon->showMessage(
                    tr("Actualizaciones disponibles"),
                    tr("Se encontraron %1 actualizaciones para tu sistema.").arg(count),
                    warningIcon,
                    5000
                );
            }
        } else if (count == 0) {
            lastNotifiedCount = 0;
            trayIcon->setIcon(normalIcon);
            trayIcon->setToolTip(tr("Neko: Sistema actualizado"));
            statusAction->setText(tr("Sistema actualizado"));
        } else {
            trayIcon->setIcon(normalIcon);
            trayIcon->setToolTip(tr("Neko: Estado desconocido"));
            statusAction->setText(tr("Estado desconocido"));
        }

        QString freq = "1d";
        QFile conf(QDir::homePath() + "/.config/NekoVoid/Updater.conf");
        if (conf.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&conf);
            while (!in.atEnd()) {
                QString line = in.readLine().trimmed();
                if (line.startsWith("frequency=")) {
                    freq = line.split("=").last();
                }
            }
        }

        if (f12h && f1d && f3d && f1w && fman) {
            f12h->setChecked(freq == "12h");
            f12h->setEnabled(freq != "12h");
            
            f1d->setChecked(freq == "1d");
            f1d->setEnabled(freq != "1d");
            
            f3d->setChecked(freq == "3d");
            f3d->setEnabled(freq != "3d");
            
            f1w->setChecked(freq == "1w");
            f1w->setEnabled(freq != "1w");
            
            fman->setChecked(freq == "manual");
            fman->setEnabled(freq != "manual");
        }

        applyTimerFrequency(freq);

        checkAction->setEnabled(!isWorking);
        applyAction->setEnabled(!isWorking && count > 0);
        cleanAction->setEnabled(!isWorking);

#if defined(__GLIBC__)
        malloc_trim(0);
#endif
    }

    void applyTimerFrequency(const QString &freq) {
        if (freq == "manual") {
            scheduledTimer->stop();
            return;
        }
        qint64 intervalMs = 24 * 3600 * 1000ULL; // 1d default
        if (freq == "12h") intervalMs = 12 * 3600 * 1000ULL;
        else if (freq == "3d") intervalMs = 3 * 24 * 3600 * 1000ULL;
        else if (freq == "1w") intervalMs = 7 * 24 * 3600 * 1000ULL;

        if (!scheduledTimer->isActive() || scheduledTimer->interval() != intervalMs) {
            scheduledTimer->start(intervalMs);
        }
    }

    QString findTerminal() {
        const char *envTerm = getenv("TERMINAL");
        if (envTerm && strlen(envTerm) > 0) {
            QString t = QString::fromUtf8(envTerm).trimmed();
            if (QFile::exists(t)) return t;
            if (QFile::exists("/usr/bin/" + t) || QFile::exists("/usr/local/bin/" + t)) {
                return t;
            }
        }

        static const QStringList terms = {
            "alacritty", "foot", "kitty", "ghostty", "wezterm",
            "konsole", "gnome-terminal", "xfce4-terminal",
            "mate-terminal", "qterminal", "st", "xterm"
        };
        for (const QString &t : terms) {
            if (QFile::exists("/usr/bin/" + t) || QFile::exists("/usr/local/bin/" + t)) {
                return t;
            }
        }
        return QString();
    }

    void launchBashInTerminal(const QStringList &bashArgs, const QString &fallbackArg) {
        QProcess *process = new QProcess(this);
        auto cleaned = std::make_shared<bool>(false);
        auto cleanup = [this, process, cleaned]() {
            if (*cleaned) return;
            *cleaned = true;
            isWorking = false;
            updateStatus();
            process->deleteLater();
        };
        connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, cleanup);
        connect(process, &QProcess::errorOccurred, this, [cleanup](QProcess::ProcessError) { cleanup(); });

        QString termCmd = findTerminal();
        if (termCmd.isEmpty()) {
            if (!fallbackArg.isEmpty()) {
                QString escalator = "pkexec";
                if (!QFile::exists("/usr/bin/pkexec")) {
                    if (QFile::exists("/usr/bin/doas") && QFile::exists("/etc/doas.conf")) {
                        escalator = "doas";
                    } else if (QFile::exists("/usr/bin/sudo")) {
                        escalator = "sudo";
                    }
                }
                process->start(escalator, {findCoreBinary(), fallbackArg});
            } else {
                process->start(findCoreBinary(), QStringList());
            }
            return;
        }

        QStringList fullArgs;
        if (termCmd.endsWith("gnome-terminal") || termCmd.endsWith("mate-terminal") || termCmd.endsWith("xfce4-terminal")) {
            fullArgs << "--" << "bash";
        } else {
            fullArgs << "-e" << "bash";
        }
        fullArgs.append(bashArgs);
        process->start(termCmd, fullArgs);
    }

    void runCoreCommand(const QString &arg) {
        if (isWorking) return;
        // Validación estricta: solo permitir banderas autorizadas
        if (arg != "--apply" && arg != "--clean") {
            return;
        }
        isWorking = true;
        updateStatus();

        QString core = findCoreBinary();
        static const char *script =
            "CORE=\"$1\"; ARG=\"$2\"; MSG_FAIL=\"$3\"; MSG_DONE=\"$4\"; "
            "if command -v pkexec >/dev/null 2>&1; then "
            "    pkexec \"$CORE\" \"$ARG\"; "
            "elif command -v doas >/dev/null 2>&1 && [ -f /etc/doas.conf ]; then "
            "    doas \"$CORE\" \"$ARG\"; "
            "elif command -v sudo >/dev/null 2>&1 && [ -f /etc/sudoers ]; then "
            "    sudo \"$CORE\" \"$ARG\"; "
            "else "
            "    printf '%s\\n' \"$MSG_FAIL\"; sleep 5; exit 1; "
            "fi; "
            "printf '%s\\n' \"$MSG_DONE\"; read -r _";

        QStringList bashArgs = {
            "-c",
            QString::fromUtf8(script),
            "neko-worker",
            core,
            arg,
            tr("No escalador de privilegios configurado"),
            tr("Presiona Enter para cerrar...")
        };

        launchBashInTerminal(bashArgs, arg);
    }

    void checkUpdates() {
        if (isWorking) return;
        isWorking = true;
        updateStatus();

        QString core = findCoreBinary();
        static const char *script =
            "\"$1\"; "
            "printf '%s\\n' \"$2\"; "
            "read -r _";

        QStringList bashArgs = {
            "-c",
            QString::fromUtf8(script),
            "neko-worker",
            core,
            tr("Comprobación finalizada. Presiona Enter para cerrar...")
        };

        launchBashInTerminal(bashArgs, "");
    }

    void applyUpdates() {
        runCoreCommand("--apply");
    }

    void cleanSystem() {
        runCoreCommand("--clean");
    }

    void showAbout() {
        QMessageBox about;
        about.setWindowTitle(tr("Acerca de Neko Void Updater"));
        QString logoPath = "/usr/share/neko-void/logo.png";
        if (!QFile::exists(logoPath)) {
            logoPath = "neko-updater-core/Data/logo.png";
        }
        if (QFile::exists(logoPath)) {
            about.setIconPixmap(QPixmap(logoPath));
        }
        about.setTextFormat(Qt::RichText);
        about.setText(
            "<h3>Neko Void Updater</h3>"
            "<p><b>" + tr("Versión") + ":</b> 5.1.0</p>"
            "<p><b>" + tr("Gestor de actualizaciones para Void Linux") + "</b></p>"
            "<p>" + tr("Motor de actualizaciones XBPS y Flatpak con integración en la bandeja del sistema, "
            "actualizaciones automáticas y herramientas de mantenimiento.") + "</p>"
            "<p><b>" + tr("Repositorio") + ":</b> "
            "<a href=\"https://github.com/Neko-Void-Linux/Neko-Update\">github.com/Neko-Void-Linux/Neko-Update</a></p>"
        );
        about.exec();
    }

    void setFrequency(const QString &freq) {
        QString configDir = QDir::homePath() + "/.config/NekoVoid";
        QDir().mkpath(configDir);
        QString confPath = configDir + "/Updater.conf";

        QStringList lines;
        bool found = false;
        QFile fileIn(confPath);
        if (fileIn.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&fileIn);
            while (!in.atEnd()) {
                QString line = in.readLine();
                if (line.trimmed().startsWith("frequency=")) {
                    lines.append("frequency=" + freq);
                    found = true;
                } else {
                    lines.append(line);
                }
            }
            fileIn.close();
        } else {
            lines.append("[General]");
        }
        if (!found) {
            lines.append("frequency=" + freq);
        }

        QFile fileOut(confPath);
        if (fileOut.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream out(&fileOut);
            out << lines.join("\n") << "\n";
            fileOut.close();
            fileOut.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::WriteGroup | QFileDevice::ReadOther | QFileDevice::WriteOther);
        }
        updateStatus();
    }

private:
    void loadIcons() {
        QString iconPath = "/usr/share/neko-void/";
        if (!QFile::exists(iconPath + "normal.png")) {
            iconPath = QApplication::applicationDirPath() + "/../neko-updater-core/Data/";
            if (!QFile::exists(iconPath + "normal.png")) {
                iconPath = "neko-updater-core/Data/";
            }
        }
        auto loadOptimizedIcon = [](const QString &file) -> QIcon {
            QPixmap p(file);
            if (!p.isNull()) {
                // Escalar a tamaño nativo de bandeja (32x32) para no retener buffers de 256x256 en RAM
                return QIcon(p.scaled(32, 32, Qt::KeepAspectRatio, Qt::SmoothTransformation));
            }
            return QIcon(file);
        };

        normalIcon = loadOptimizedIcon(iconPath + "normal.png");
        warningIcon = loadOptimizedIcon(iconPath + "warnig.png");
        workingIcon = loadOptimizedIcon(iconPath + "working.png");
    }

    void createActions() {
        statusAction = new QAction(tr("Estado"), this);
        statusAction->setEnabled(false);

        checkAction = new QAction(tr("Buscar actualizaciones"), this);
        connect(checkAction, &QAction::triggered, this, &NekoTray::checkUpdates);

        applyAction = new QAction(tr("Actualizar sistema"), this);
        connect(applyAction, &QAction::triggered, this, &NekoTray::applyUpdates);

        cleanAction = new QAction(tr("Limpiar sistema"), this);
        connect(cleanAction, &QAction::triggered, this, &NekoTray::cleanSystem);

        aboutAction = new QAction(tr("Acerca de"), this);
        connect(aboutAction, &QAction::triggered, this, &NekoTray::showAbout);

        quitAction = new QAction(tr("Salir"), this);
        connect(quitAction, &QAction::triggered, qApp, &QCoreApplication::quit);
    }

    void createTrayIcon() {
        trayMenu = new QMenu();
        // Mini-Matugen 3-color palette: Background #282a36, Text #f8f8f2, Accent #50fa7b
        trayMenu->setStyleSheet(
            "QMenu { background-color: #282a36; color: #f8f8f2; border: 1px solid #44475a; }"
            "QMenu::item:selected { background-color: #50fa7b; color: #282a36; }"
            "QMenu::separator { height: 1px; background: #44475a; margin: 4px; }"
        );
        
        trayMenu->addAction(statusAction);
        trayMenu->addSeparator();
        trayMenu->addAction(checkAction);
        trayMenu->addAction(applyAction);
        trayMenu->addAction(cleanAction);
        trayMenu->addSeparator();
        
        // Hereda el estilo del menú padre (evita compilar y almacenar CSS duplicado en memoria)
        freqMenu = new QMenu(tr("Frecuencia"), trayMenu);
        
        f12h = freqMenu->addAction(tr("Cada 12 horas"));
        f12h->setCheckable(true);
        connect(f12h, &QAction::triggered, this, [this]() { setFrequency("12h"); });
        
        f1d = freqMenu->addAction(tr("Diario"));
        f1d->setCheckable(true);
        connect(f1d, &QAction::triggered, this, [this]() { setFrequency("1d"); });
        
        f3d = freqMenu->addAction(tr("Cada 3 días"));
        f3d->setCheckable(true);
        connect(f3d, &QAction::triggered, this, [this]() { setFrequency("3d"); });
        
        f1w = freqMenu->addAction(tr("Semanal"));
        f1w->setCheckable(true);
        connect(f1w, &QAction::triggered, this, [this]() { setFrequency("1w"); });
        
        fman = freqMenu->addAction(tr("Manual"));
        fman->setCheckable(true);
        connect(fman, &QAction::triggered, this, [this]() { setFrequency("manual"); });
        
        trayMenu->addMenu(freqMenu);
        trayMenu->addSeparator();
        trayMenu->addAction(aboutAction);
        trayMenu->addAction(quitAction);

        trayIcon = new QSystemTrayIcon(this);
        trayIcon->setContextMenu(trayMenu);
    }

    QSystemTrayIcon *trayIcon;
    QMenu *trayMenu;
    QMenu *freqMenu;
    QAction *statusAction;
    QAction *checkAction;
    QAction *applyAction;
    QAction *cleanAction;
    QAction *aboutAction;
    QAction *quitAction;
    QAction *f12h;
    QAction *f1d;
    QAction *f3d;
    QAction *f1w;
    QAction *fman;
    QFileSystemWatcher *watcher;
    QTimer *scheduledTimer;
#if defined(__GLIBC__)
    QTimer *heapTimer;
#endif
    QIcon normalIcon;
    QIcon warningIcon;
    QIcon workingIcon;
    bool isWorking;
    int lastNotifiedCount;
};

int main(int argc, char *argv[]) {
    // Evitar cargar módulos pesados de input (fcitx/ibus) y OpenGL en una bandeja sin campos de texto
    qputenv("QT_IM_MODULE", "none");
    qputenv("QT_QUICK_BACKEND", "software");
    qputenv("QSG_RHI_BACKEND", "software");

    QApplication app(argc, argv);
    app.setApplicationName("Neko Void Updater");
    app.setQuitOnLastWindowClosed(false);
    app.setAttribute(Qt::AA_DontCreateNativeWidgetSiblings);

    // i18n: detect system locale and load matching translation automatically.
    // Supported: English (default), German, Portuguese, Italian, Spanish, Japanese.
    QString lang = QLocale::system().name().left(2).toLower();
    QStringList supported = {"de", "pt", "it", "es", "ja"};
    QTranslator translator;
    bool loaded = false;
    if (supported.contains(lang)) {
        QString qmName = QString("neko_%1.qm").arg(lang);
        QStringList qmCandidates = {
            QApplication::applicationDirPath() + "/../share/neko-void/translations/" + qmName,
            "/usr/share/neko-void/translations/" + qmName,
            QApplication::applicationDirPath() + "/translations/" + qmName,
            "neko-updater-tray/translations/" + qmName,
            "translations/" + qmName,
        };
        for (const QString &path : qmCandidates) {
            if (QFile::exists(path) && translator.load(path)) {
                loaded = true;
                break;
            }
        }
    }
    if (loaded) {
        app.installTranslator(&translator);
    }

    NekoTray tray;
    return app.exec();
}

#include "main.moc"
