// SPDX-License-Identifier: GPL-3.0-only

#include "FolderCompareWorker.h"
#include "FolderCompareUtils.h"

#include <QByteArray>

FolderCompareWorker::FolderCompareWorker(QString folderA, QString folderB, int mode,
                                         bool ignoreHiddenSystem, QString ignorePatterns,
                                         QObject* parent)
    : QObject(parent), m_folderA(std::move(folderA)), m_folderB(std::move(folderB)), m_mode(mode),
      m_ignoreHiddenSystem(ignoreHiddenSystem), m_ignorePatterns(std::move(ignorePatterns)) {}

bool FolderCompareWorker::isCanceled() const {
    return m_canceled.load(std::memory_order_relaxed);
}

void FolderCompareWorker::run() {
    const QByteArray folderA = m_folderA.toUtf8();
    const QByteArray folderB = m_folderB.toUtf8();
    const QByteArray patterns = m_ignorePatterns.toUtf8();

    SfcCompareRequest request{};
    request.folder_a = folderA.constData();
    request.folder_b = folderB.constData();
    request.mode = modeFromUiValue(m_mode);
    request.ignore_hidden_system = m_ignoreHiddenSystem;
    request.ignore_patterns = patterns.constData();
    request.progress = &FolderCompareWorker::progressCallback;
    request.cancel = &FolderCompareWorker::cancelCallback;
    request.user_data = this;

    char* error = nullptr;
    SfcReport* report = sfc_compare_folders(&request, &error);
    const QString errorMessage = takeError(error);
    emit finished(report, errorMessage, static_cast<SfcProgressStage>(m_terminalStage.load()));
}

void FolderCompareWorker::cancel() {
    m_canceled.store(true, std::memory_order_relaxed);
}

void FolderCompareWorker::progressCallback(SfcProgressStage stage, uint64_t current, uint64_t total,
                                           const char* path, void* userData) {
    auto* worker = static_cast<FolderCompareWorker*>(userData);
    if (!worker) {
        return;
    }
    if (stage == SFC_PROGRESS_CANCELED || stage == SFC_PROGRESS_FAILED ||
        stage == SFC_PROGRESS_COMPLETE) {
        worker->m_terminalStage.store(static_cast<int>(stage), std::memory_order_relaxed);
    }
    emit worker->progress(stage, static_cast<qulonglong>(current), static_cast<qulonglong>(total),
                          path ? QString::fromUtf8(path) : QString());
}

bool FolderCompareWorker::cancelCallback(void* userData) {
    auto* worker = static_cast<FolderCompareWorker*>(userData);
    return worker && worker->isCanceled();
}

SfcCompareMode FolderCompareWorker::modeFromUiValue(int mode) {
    // Rust FFI enum values are the source of truth for compare semantics.
    if (mode < static_cast<int>(SFC_COMPARE_PATH_SIZE) ||
        mode > static_cast<int>(SFC_COMPARE_PATH_SIZE_CHECKSUM)) {
        return SFC_COMPARE_PATH_SIZE;
    }
    return static_cast<SfcCompareMode>(mode);
}
