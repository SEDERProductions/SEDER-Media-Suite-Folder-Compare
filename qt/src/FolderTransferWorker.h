// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "seder_folder_compare.h"

#include <QObject>
#include <QString>
#include <atomic>

class FolderTransferWorker final : public QObject {
    Q_OBJECT

  public:
    FolderTransferWorker(QString source, QString dest, bool isFolder, bool isMove,
                         QObject* parent = nullptr);

    bool isCanceled() const;

  public slots:
    void run();
    void cancel();

  signals:
    void progress(SfcProgressStage stage, qulonglong current, qulonglong total, QString path);
    void finished(bool success, QString errorMessage);

  private:
    static void progressCallback(SfcProgressStage stage, uint64_t current, uint64_t total,
                                 const char* path, void* userData);
    static bool cancelCallback(void* userData);

    QString m_source;
    QString m_dest;
    bool m_isFolder = false;
    bool m_isMove = false;
    std::atomic_bool m_canceled = false;
};
