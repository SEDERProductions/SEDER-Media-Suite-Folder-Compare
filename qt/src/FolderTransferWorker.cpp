// SPDX-License-Identifier: GPL-3.0-only

#include "FolderTransferWorker.h"
#include "FolderCompareUtils.h"

#include <QByteArray>
#include <QDir>

FolderTransferWorker::FolderTransferWorker(QString source, QString dest, bool isFolder, bool isMove,
                                           QObject* parent)
    : QObject(parent), m_source(std::move(source)), m_dest(std::move(dest)), m_isFolder(isFolder),
      m_isMove(isMove) {}

bool FolderTransferWorker::isCanceled() const {
    return m_canceled.load(std::memory_order_acquire);
}

void FolderTransferWorker::run() {
    const QByteArray source = m_source.toUtf8();
    const QByteArray dest = m_dest.toUtf8();

    char* error = nullptr;
    bool copyOk = false;

    if (m_isFolder) {
        copyOk = sfc_copy_folder(source.constData(), dest.constData(),
                                 &FolderTransferWorker::progressCallback,
                                 &FolderTransferWorker::cancelCallback, this, &error);
    } else {
        copyOk = sfc_copy_file(source.constData(), dest.constData(),
                               &FolderTransferWorker::progressCallback,
                               &FolderTransferWorker::cancelCallback, this, &error);
    }

    const QString copyError = takeError(error);

    if (!copyOk) {
        emit finished(false, copyError.isEmpty() ? QStringLiteral("Copy failed.") : copyError);
        return;
    }

    if (m_isMove && !m_canceled.load()) {
        const QByteArray sourcePath = m_source.toUtf8();
        char* removeError = nullptr;
        bool removeOk = false;

        if (m_isFolder) {
            removeOk = sfc_remove_folder(sourcePath.constData(), &removeError);
        } else {
            removeOk = sfc_remove_file(sourcePath.constData(), &removeError);
        }

        const QString removeErrorMsg = takeError(removeError);

        if (!removeOk) {
            emit finished(
                false,
                QStringLiteral("Copied but failed to remove source: %1").arg(removeErrorMsg));
            return;
        }
    }

    emit finished(true, QString());
}

void FolderTransferWorker::cancel() {
    m_canceled.store(true, std::memory_order_release);
}

void FolderTransferWorker::progressCallback(SfcProgressStage stage, uint64_t current,
                                            uint64_t total, const char* path, void* userData) {
    auto* worker = static_cast<FolderTransferWorker*>(userData);
    if (!worker) {
        return;
    }
    emit worker->progress(stage, static_cast<qulonglong>(current), static_cast<qulonglong>(total),
                          path ? QString::fromUtf8(path) : QString());
}

bool FolderTransferWorker::cancelCallback(void* userData) {
    auto* worker = static_cast<FolderTransferWorker*>(userData);
    return worker && worker->isCanceled();
}
