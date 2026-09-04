// main.cpp — standalone desktop entry point.
//
// Hosts the game scene from ../Panel.qml inside a plain ApplicationWindow.
// This is the "Option A" port target: the QML/JS game logic is untouched
// (it still assumes a 640×480 frame); only the shell-integration surface
// is replaced with a window + QSaveFile-backed persistence.
#include <QGuiApplication>
#include <QFontDatabase>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDebug>

#include "filestorage.h"

// The game's icon glyphs are PUA characters from JetBrainsMono Nerd Font.
// The TTFs are embedded in the binary as Qt resources (see CMakeLists) so
// fresh machines (Windows, CI, etc.) render icons without the font being
// installed system-wide. Register them into the application font database
// before QML loads; the family name "JetBrainsMono Nerd Font" then resolves
// from anywhere in the QML tree.
static void loadBundledFonts()
{
    const char *resources[] = {
        ":/qt/qml/Omakon/fonts/JetBrainsMonoNerdFont-Regular.ttf",
        ":/qt/qml/Omakon/fonts/JetBrainsMonoNerdFont-Bold.ttf",
    };
    for (const char *path : resources) {
        if (QFontDatabase::addApplicationFont(path) < 0) {
            qWarning("bundled font failed to load: %s", path);
        }
    }
    if (!QFontDatabase::families().contains(QStringLiteral("JetBrainsMono Nerd Font"))) {
        qWarning("JetBrainsMono Nerd Font not registered; icons may render as tofu");
    }
}

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName(QStringLiteral("SignalSix"));
    QGuiApplication::setApplicationName(QStringLiteral("omakon"));
    QGuiApplication::setApplicationVersion(QStringLiteral("0.1.0"));

    loadBundledFonts();

    FileStorage storage;

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() {
            qWarning("QML object creation failed; see diagnostics above");
            QCoreApplication::exit(2);
        },
        Qt::QueuedConnection);
    engine.rootContext()->setContextProperty(QStringLiteral("storage"), &storage);
    // Quick sanity check on the packaged data: confirm qrc paths resolve.
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/Omakon/main.qml")));

    if (engine.rootObjects().isEmpty()) {
        qWarning("QML engine produced no root objects");
        return 2;
    }

    return QGuiApplication::exec();
}
