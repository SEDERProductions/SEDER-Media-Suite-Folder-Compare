// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "seder_folder_compare.h"

#include <QObject>
#include <QString>
#include <atomic>

Q_DECLARE_OPAQUE_POINTER(SfcReport*)

class FolderCompareWorker final : public QObject {
    Q_OBJECT

  public:
    FolderCompareWorker(QString folderA, QString folderB, int mode, bool ignoreHiddenSystem,
                        QString ignorePatterns, QObject* parent = nullptr);

    bool isCanceled() const;

  public slots:
    void run();
    void cancel();

  signals:
    void progress(SfcProgressStage stage, qulonglong current, qulonglong total, QString path);
    void finished(SfcReport* report, QString errorMessage, SfcProgressStage terminalStage);

  private:
    static void progressCallback(SfcProgressStage stage, uint64_t current, uint64_t total,
                                 const char* path, void* userData);
    static bool cancelCallback(void* userData);
    static SfcCompareMode modeFromUiValue(int mode);

    QString m_folderA;
    QString m_folderB;
    int m_mode = 0;
    bool m_ignoreHiddenSystem = true;
    QString m_ignorePatterns;
    std::atomic_bool m_canceled = false;
    std::atomic<int> m_terminalStage {static_cast<int>(SFC_PROGRESS_COMPLETE)};
};
