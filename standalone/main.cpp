// main.cpp — standalone desktop entry point.
//
// Hosts the game scene from ../Panel.qml inside a plain ApplicationWindow.
// This is the "Option A" port target: the QML/JS game logic is untouched
// (it still assumes a 640×480 frame); only the shell-integration surface
// is replaced with a window + QSaveFile-backed persistence.
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFile>
#include <QDebug>

#include "filestorage.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName(QStringLiteral("SignalSix"));
    QGuiApplication::setApplicationName(QStringLiteral("omakon"));
    QGuiApplication::setApplicationVersion(QStringLiteral("0.1.0"));

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
    qInfo() << "monsters.json exists (qrc:/)?" << QFile::exists(":/qt/qml/Omakon/data/monsters.json")
            << "; also as (qrc no prefix)?" << QFile::exists(":/data/monsters.json");
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/Omakon/main.qml")));

    if (engine.rootObjects().isEmpty()) {
        qWarning("QML engine produced no root objects");
        return 2;
    }

    return QGuiApplication::exec();
}
