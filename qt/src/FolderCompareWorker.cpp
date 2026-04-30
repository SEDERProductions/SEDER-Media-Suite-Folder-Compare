// SPDX-License-Identifier: GPL-3.0-only

#include "FolderCompareWorker.h"

#include <QByteArray>

namespace {
QString takeError(char *error)
{
    if (!error) {
        return {};
    }
    const QString message = QString::fromUtf8(error);
    sfc_string_free(error);
    return message;
}
}

FolderCompareWorker::FolderCompareWorker(
    QString folderA,
    QString folderB,
    int mode,
    bool ignoreHiddenSystem,
    QString ignorePatterns,
    QObject *parent)
    : QObject(parent)
    , m_folderA(std::move(folderA))
    , m_folderB(std::move(folderB))
    , m_mode(mode)
    , m_ignoreHiddenSystem(ignoreHiddenSystem)
    , m_ignorePatterns(std::move(ignorePatterns))
{
}

bool FolderCompareWorker::isCanceled() const
{
    return m_canceled.load(std::memory_order_relaxed);
}

void FolderCompareWorker::run()
{
    const QByteArray folderA = m_folderA.toUtf8();
    const QByteArray folderB = m_folderB.toUtf8();
    const QByteArray patterns = m_ignorePatterns.toUtf8();

    SfcCompareRequest request {};
    request.folder_a = folderA.constData();
    request.folder_b = folderB.constData();
    request.mode = modeFromIndex(m_mode);
    request.ignore_hidden_system = m_ignoreHiddenSystem;
    request.ignore_patterns = patterns.constData();
    request.progress = &FolderCompareWorker::progressCallback;
    request.cancel = &FolderCompareWorker::cancelCallback;
    request.user_data = this;

    char *error = nullptr;
    SfcReport *report = sfc_compare_folders(&request, &error);
    const QString errorMessage = takeError(error);
    const bool canceled = isCanceled() || errorMessage.contains(QStringLiteral("canceled"), Qt::CaseInsensitive);
    emit finished(report, errorMessage, canceled);
}

void FolderCompareWorker::cancel()
{
    m_canceled.store(true, std::memory_order_relaxed);
}

void FolderCompareWorker::progressCallback(
    SfcProgressStage stage,
    uint64_t current,
    uint64_t total,
    const char *path,
    void *userData)
{
    auto *worker = static_cast<FolderCompareWorker *>(userData);
    if (!worker) {
        return;
    }
    emit worker->progress(
        static_cast<int>(stage),
        static_cast<qulonglong>(current),
        static_cast<qulonglong>(total),
        path ? QString::fromUtf8(path) : QString());
}

bool FolderCompareWorker::cancelCallback(void *userData)
{
    auto *worker = static_cast<FolderCompareWorker *>(userData);
    return worker && worker->isCanceled();
}

SfcCompareMode FolderCompareWorker::modeFromIndex(int mode)
{
    switch (mode) {
    case 1:
        return SFC_COMPARE_PATH_SIZE_MODIFIED;
    case 2:
        return SFC_COMPARE_PATH_SIZE_CHECKSUM;
    case 0:
    default:
        return SFC_COMPARE_PATH_SIZE;
    }
}
