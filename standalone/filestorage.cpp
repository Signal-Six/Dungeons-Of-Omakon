// filestorage.cpp — see filestorage.h for the design contract.
#include "filestorage.h"

#include <QDir>
#include <QFile>
#include <QSaveFile>
#include <QStandardPaths>

FileStorage::FileStorage(QObject *parent) : QObject(parent) {}

QString FileStorage::dir() const
{
    // QStandardPaths::AppDataLocation already resolves to:
    //   Windows: %APPDATA%/<org>/<app>   (we set app = "omakon" in main.cpp)
    //   Linux:   ~/.local/share/<org>/<app>
    //   macOS:   ~/Library/Application Support/<org>/<app>
    QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir d(base);
    if (!d.exists())
        d.mkpath(QStringLiteral("."));
    return base;
}

QString FileStorage::readRun() const
{
    QFile f(dir() + QStringLiteral("/run.json"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();
    return QString::fromUtf8(f.readAll());
}

QString FileStorage::readArchive() const
{
    QFile f(dir() + QStringLiteral("/archive.json"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QStringLiteral("[]");
    return QString::fromUtf8(f.readAll());
}

bool FileStorage::writeAtomic(const QString &filePath, const QString &payload)
{
    QSaveFile f(filePath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;
    if (f.write(payload.toUtf8()) < 0)
        return false;
    return f.commit();
}

bool FileStorage::writeRun(const QString &text)
{
    return writeAtomic(dir() + QStringLiteral("/run.json"), text);
}

bool FileStorage::writeArchive(const QString &text)
{
    return writeAtomic(dir() + QStringLiteral("/archive.json"), text);
}

void FileStorage::clearRun()
{
    QFile::remove(dir() + QStringLiteral("/run.json"));
}

QString FileStorage::readResource(const QString &path) const
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();
    return QString::fromUtf8(f.readAll());
}
