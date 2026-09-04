// filestorage.h — platform save/archive persistence for the standalone build.
//
// Replaces the shell plugin's secret-tool keyring pipeline with plain JSON
// files under the platform app-data dir:
//   Windows:  %APPDATA%/omakon/run.json, %APPDATA%/omakon/archive.json
//   Linux:    ~/.local/share/omakon/...
//   macOS:    ~/Library/Application Support/omakon/...
// All writes use QSaveFile (atomic rename) — a crash mid-save cannot
// corrupt the run, which is the same guarantee the keyring pipeline gave.
#pragma once

#include <QObject>
#include <QString>

class FileStorage : public QObject
{
    Q_OBJECT
public:
    explicit FileStorage(QObject *parent = nullptr);

    Q_INVOKABLE QString readRun() const;
    Q_INVOKABLE QString readArchive() const;
    Q_INVOKABLE bool writeRun(const QString &text);
    Q_INVOKABLE bool writeArchive(const QString &text);
    Q_INVOKABLE void clearRun();

    // Reads a bundled Qt-resource file (":/data/monsters.json" etc) so the
    // QML layer never has to know where the JSON lives on disk.
    Q_INVOKABLE QString readResource(const QString &path) const;

private:
    QString dir() const;
    bool writeAtomic(const QString &filePath, const QString &payload);
};
