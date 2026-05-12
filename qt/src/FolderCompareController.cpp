// SPDX-License-Identifier: GPL-3.0-only

#include "FolderCompareController.h"
#include "FolderCompareUtils.h"

#include <QApplication>
#include <QDateTime>
#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QSettings>
#include <QStyleHints>
#include <QThread>
#include <QUrl>

#include <algorithm>
#include <functional>

namespace {
constexpr auto defaultPatterns = ".DS_Store, Thumbs.db, desktop.ini, .Spotlight-V100, .Trashes";
constexpr auto reportTitle = "SEDER Media Suite Folder Compare Report";

template <typename T, typename ChangedSignal>
bool assignPropertyIfChanged(T& current, const T& next, ChangedSignal changedSignal,
                             FolderCompareController* controller) {
    if (current == next) {
        return false;
    }
    current = next;
    (controller->*changedSignal)();
    return true;
}

template <typename T, typename ChangedSignal>
bool assignAndPersistPropertyIfChanged(T& current, const T& next, const QString& settingsKey,
                                       ChangedSignal changedSignal,
                                       FolderCompareController* controller) {
    if (current == next) {
        return false;
    }
    current = next;
    QSettings().setValue(settingsKey, QVariant::fromValue(next));
    (controller->*changedSignal)();
    return true;
}
} // namespace

FolderCompareController::FolderCompareController(QObject* parent)
    : QObject(parent), m_statusText(QStringLiteral("Ready to compare two folders.")),
      m_progressText(QStringLiteral("Idle")) {
    QSettings settings;
    m_theme = settings.value(QStringLiteral("theme"), QStringLiteral("system")).toString();
    m_ignorePatterns =
        settings.value(QStringLiteral("ignorePatterns"), QString::fromUtf8(defaultPatterns))
            .toString();
    m_ignoreHiddenSystem = settings.value(QStringLiteral("ignoreHiddenSystem"), true).toBool();
    m_filterModel.setSourceModel(&m_tableModel);
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    connect(qApp->styleHints(), &QStyleHints::colorSchemeChanged, this, [this] {
        if (m_theme == QStringLiteral("system")) {
            emit effectiveDarkChanged();
        }
    });
#endif
    resetSummary();
    addLog(QStringLiteral("Folder Compare ready."));
}

FolderCompareController::~FolderCompareController() {
    if (m_worker) {
        m_worker->cancel();
    }
    if (m_thread) {
        m_thread->quit();
        if (!m_thread->wait(30000)) {
            m_thread->terminate();
            m_thread->wait();
        }
    }
    if (m_transferWorker) {
        m_transferWorker->cancel();
    }
    if (m_transferThread) {
        m_transferThread->quit();
        if (!m_transferThread->wait(30000)) {
            m_transferThread->terminate();
            m_transferThread->wait();
        }
    }
    if (m_report) {
        sfc_report_free(m_report);
    }
}

QString FolderCompareController::folderA() const {
    return m_folderA;
}
QString FolderCompareController::folderB() const {
    return m_folderB;
}
int FolderCompareController::mode() const {
    return m_mode;
}
bool FolderCompareController::ignoreHiddenSystem() const {
    return m_ignoreHiddenSystem;
}
QString FolderCompareController::ignorePatterns() const {
    return m_ignorePatterns;
}
bool FolderCompareController::busy() const {
    return m_busy;
}
QString FolderCompareController::statusText() const {
    return m_statusText;
}
QString FolderCompareController::progressText() const {
    return m_progressText;
}
QString FolderCompareController::theme() const {
    return m_theme;
}
bool FolderCompareController::effectiveDark() const {
    if (m_theme == QStringLiteral("dark")) {
        return true;
    }
    if (m_theme == QStringLiteral("light")) {
        return false;
    }
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    return qApp->styleHints()->colorScheme() == Qt::ColorScheme::Dark;
#else
    return false;
#endif
}
QStringList FolderCompareController::logEntries() const {
    return m_logEntries;
}
QObject* FolderCompareController::tableModel() {
    return &m_tableModel;
}
QObject* FolderCompareController::filterModel() {
    return &m_filterModel;
}
int FolderCompareController::matchingCount() const {
    return m_matchingCount;
}
int FolderCompareController::changedCount() const {
    return m_changedCount;
}
int FolderCompareController::onlyACount() const {
    return m_onlyACount;
}
int FolderCompareController::onlyBCount() const {
    return m_onlyBCount;
}
int FolderCompareController::folderDiffCount() const {
    return m_folderDiffCount;
}
QString FolderCompareController::totalSizeText() const {
    return m_totalSizeText;
}

void FolderCompareController::setFolderA(const QString& folder) {
    assignPropertyIfChanged(m_folderA, folder, &FolderCompareController::folderAChanged, this);
}

void FolderCompareController::setFolderB(const QString& folder) {
    assignPropertyIfChanged(m_folderB, folder, &FolderCompareController::folderBChanged, this);
}

void FolderCompareController::setMode(int mode) {
    if (mode < 0 || mode > 2) {
        addLog(QStringLiteral("Invalid compare mode ignored: %1").arg(mode));
        return;
    }
    assignPropertyIfChanged(m_mode, mode, &FolderCompareController::modeChanged, this);
}

void FolderCompareController::setIgnoreHiddenSystem(bool ignore) {
    assignAndPersistPropertyIfChanged(m_ignoreHiddenSystem, ignore,
                                      QStringLiteral("ignoreHiddenSystem"),
                                      &FolderCompareController::ignoreHiddenSystemChanged, this);
}

void FolderCompareController::setIgnorePatterns(const QString& patterns) {
    assignAndPersistPropertyIfChanged(m_ignorePatterns, patterns, QStringLiteral("ignorePatterns"),
                                      &FolderCompareController::ignorePatternsChanged, this);
}

void FolderCompareController::setTheme(const QString& theme) {
    const QString safeTheme = (theme == QStringLiteral("light") || theme == QStringLiteral("dark"))
                                  ? theme
                                  : QStringLiteral("system");
    if (assignAndPersistPropertyIfChanged(m_theme, safeTheme, QStringLiteral("theme"),
                                          &FolderCompareController::themeChanged, this)) {
        emit effectiveDarkChanged();
    }
}

void FolderCompareController::chooseFolderA() {
    const QString selected = pickFolder(QStringLiteral("Choose Folder A"), m_folderA);
    if (!selected.isEmpty()) {
        setFolderA(selected);
    }
}

void FolderCompareController::chooseFolderB() {
    const QString selected = pickFolder(QStringLiteral("Choose Folder B"), m_folderB);
    if (!selected.isEmpty()) {
        setFolderB(selected);
    }
}

void FolderCompareController::startComparison() {
    if (m_busy) {
        return;
    }
    if (m_folderA.isEmpty() || m_folderB.isEmpty()) {
        setStatusText(QStringLiteral("Choose Folder A and Folder B before starting."));
        addLog(QStringLiteral("Start blocked: missing folder selection."), LogSeverity::Warning);
        return;
    }

    const bool hadReport = hasReport();
    if (m_report) {
        sfc_report_free(m_report);
        m_report = nullptr;
        if (hadReport) {
            emit hasReportChanged();
        }
    }
    m_tableModel.clear();
    emit totalRowsChanged();
    m_progressCurrent = 0;
    m_progressTotal = 0;
    emit progressChanged();
    resetSummary();

    auto* thread = new QThread(this);
    auto* worker = new FolderCompareWorker(m_folderA, m_folderB, m_mode, m_ignoreHiddenSystem,
                                           m_ignorePatterns);
    worker->moveToThread(thread);
    m_thread = thread;
    m_worker = worker;

    connect(thread, &QThread::started, worker, &FolderCompareWorker::run);
    connect(worker, &FolderCompareWorker::progress, this, &FolderCompareController::handleProgress);
    connect(worker, &FolderCompareWorker::finished, this, &FolderCompareController::handleFinished);
    connect(worker, &FolderCompareWorker::finished, thread, &QThread::quit);
    connect(worker, &FolderCompareWorker::finished, worker, &QObject::deleteLater);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);

    setBusy(true);
    setStatusText(QStringLiteral("Comparing folders..."));
    setProgressText(QStringLiteral("Starting comparison"));
    addLog(QStringLiteral("Comparison started."));
    thread->start();
}

void FolderCompareController::cancelComparison() {
    if (!m_busy || !m_worker) {
        return;
    }
    m_worker->cancel();
    setStatusText(QStringLiteral("Canceling comparison..."));
    addLog(QStringLiteral("Cancellation requested."), LogSeverity::Warning);
}

void FolderCompareController::exportTxt() {
    if (!hasReport()) {
        setStatusText(QStringLiteral("No comparison report to export."));
        return;
    }
    const QString path = savePath(QStringLiteral("Export TXT Report"),
                                  QStringLiteral("seder-folder-compare-report.txt"),
                                  QStringLiteral("Text report (*.txt)"));
    if (path.isEmpty()) {
        addLog(QStringLiteral("TXT export canceled."));
        setStatusText(QStringLiteral("Export canceled."));
        return;
    }

    const QByteArray outputPath = path.toUtf8();
    const QByteArray title = QByteArray(reportTitle);
    char* error = nullptr;
    if (sfc_report_write_txt(m_report, outputPath.constData(), title.constData(), &error)) {
        addLog(QStringLiteral("TXT exported: %1").arg(path));
        setStatusText(QStringLiteral("TXT export complete."));
    } else {
        const QString message = takeError(error);
        addLog(QStringLiteral("TXT export failed: %1").arg(message), LogSeverity::Error);
        setStatusText(message);
    }
}

void FolderCompareController::exportCsv() {
    if (!hasReport()) {
        setStatusText(QStringLiteral("No comparison report to export."));
        return;
    }
    const QString path = savePath(QStringLiteral("Export CSV Report"),
                                  QStringLiteral("seder-folder-compare-report.csv"),
                                  QStringLiteral("CSV report (*.csv)"));
    if (path.isEmpty()) {
        addLog(QStringLiteral("CSV export canceled."));
        setStatusText(QStringLiteral("Export canceled."));
        return;
    }

    const QByteArray outputPath = path.toUtf8();
    char* error = nullptr;
    if (sfc_report_write_csv(m_report, outputPath.constData(), &error)) {
        addLog(QStringLiteral("CSV exported: %1").arg(path));
        setStatusText(QStringLiteral("CSV export complete."));
    } else {
        const QString message = takeError(error);
        addLog(QStringLiteral("CSV export failed: %1").arg(message), LogSeverity::Error);
        setStatusText(message);
    }
}

void FolderCompareController::setFilterMode(int mode) {
    m_filterModel.setFilterMode(mode);
}

void FolderCompareController::clearLog() {
    m_logEntries.clear();
    emit logEntriesChanged();
}

QVariantMap FolderCompareController::parseDroppedFolderUrl(const QString& droppedUrl) const {
    const QUrl url = QUrl::fromUserInput(droppedUrl.trimmed());
    if (!url.isValid() || !url.isLocalFile()) {
        return {
            {QStringLiteral("error"), QStringLiteral("Dropped item is not a local folder URL.")}};
    }

    const QString localPath = QDir::cleanPath(url.toLocalFile());
    if (localPath.isEmpty()) {
        return {{QStringLiteral("error"),
                 QStringLiteral("Could not read a local folder path from drop data.")}};
    }

    const QFileInfo info(localPath);
    if (!info.exists() || !info.isDir()) {
        return {{QStringLiteral("error"),
                 QStringLiteral("Dropped item is not an existing folder path.")}};
    }

    return {{QStringLiteral("path"), QDir::toNativeSeparators(localPath)}};
}

int FolderCompareController::totalRows() const {
    return m_tableModel.totalRows();
}

qulonglong FolderCompareController::progressCurrent() const {
    return m_progressCurrent;
}

qulonglong FolderCompareController::progressTotal() const {
    return m_progressTotal;
}

void FolderCompareController::handleProgress(SfcProgressStage stage, qulonglong current,
                                             qulonglong total, const QString& path) {
    m_progressCurrent = current;
    m_progressTotal = total;
    emit progressChanged();

    const QString label = progressLabel(stage, current, total, path);
    setProgressText(label);
    if (isTerminalStage(stage)) {
        addLog(label);
    }
}

void FolderCompareController::handleFinished(SfcReport* report, const QString& errorMessage,
                                             SfcProgressStage terminalStage) {
    setBusy(false);
    m_progressCurrent = 0;
    m_progressTotal = 0;
    emit progressChanged();
    m_worker = nullptr;
    m_thread = nullptr;

    if (terminalStage == SFC_PROGRESS_CANCELED) {
        if (report) {
            sfc_report_free(report);
        }
        setStatusText(QStringLiteral("Comparison canceled."));
        setProgressText(QStringLiteral("Canceled"));
        addLog(QStringLiteral("Comparison canceled."), LogSeverity::Warning);
        return;
    }

    if (!errorMessage.isEmpty() || !report) {
        if (report) {
            sfc_report_free(report);
        }
        const QString message =
            errorMessage.isEmpty() ? QStringLiteral("Comparison failed.") : errorMessage;
        setStatusText(message);
        setProgressText(QStringLiteral("Failed"));
        addLog(QStringLiteral("Comparison failed: %1").arg(message), LogSeverity::Error);
        return;
    }

    if (m_report) {
        sfc_report_free(m_report);
    }
    m_report = report;
    m_tableModel.loadFromReport(m_report);
    emit totalRowsChanged();
    emit hasReportChanged();
    loadSummary(m_report);
    setStatusText(QStringLiteral("Comparison complete."));
    setProgressText(QStringLiteral("Complete"));
    addLog(QStringLiteral("Comparison complete: %1 rows.").arg(m_tableModel.totalRows()));
}

void FolderCompareController::setBusy(bool busy) {
    if (m_busy == busy) {
        return;
    }
    m_busy = busy;
    emit busyChanged();
}

void FolderCompareController::setStatusText(const QString& status) {
    if (m_statusText == status) {
        return;
    }
    m_statusText = status;
    emit statusTextChanged();
}

void FolderCompareController::setProgressText(const QString& progress) {
    if (m_progressText == progress) {
        return;
    }
    m_progressText = progress;
    emit progressTextChanged();
}

void FolderCompareController::addLog(const QString& message, LogSeverity severity,
                                     bool includeTimestamp) {
    const QString severityLabel = [severity]() {
        switch (severity) {
        case LogSeverity::Warning:
            return QStringLiteral("WARN");
        case LogSeverity::Error:
            return QStringLiteral("ERROR");
        case LogSeverity::Info:
        default:
            return QStringLiteral("INFO");
        }
    }();

    QStringList parts;
    if (includeTimestamp) {
        parts.append(QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")));
    }
    parts.append(QStringLiteral("[%1]").arg(severityLabel));
    parts.append(message);
    m_logEntries.prepend(parts.join(QStringLiteral("  ")));
    while (m_logEntries.size() > 200) {
        m_logEntries.removeLast();
    }
    emit logEntriesChanged();
}

void FolderCompareController::resetSummary() {
    m_matchingCount = 0;
    m_changedCount = 0;
    m_onlyACount = 0;
    m_onlyBCount = 0;
    m_folderDiffCount = 0;
    m_totalSizeText = formatBytes(0);
    emit summaryChanged();
}

void FolderCompareController::loadSummary(const SfcReport* report) {
    m_matchingCount = static_cast<int>(sfc_report_matching_count(report));
    m_changedCount = static_cast<int>(sfc_report_changed_count(report));
    m_onlyACount = static_cast<int>(sfc_report_only_a_count(report));
    m_onlyBCount = static_cast<int>(sfc_report_only_b_count(report));
    m_folderDiffCount = static_cast<int>(sfc_report_folder_diff_count(report));
    m_totalSizeText = formatBytes(sfc_report_total_size(report));
    emit summaryChanged();
}

bool FolderCompareController::hasReport() const {
    return m_report != nullptr;
}

QString FolderCompareController::pickFolder(const QString& title, const QString& current) {
    return QFileDialog::getExistingDirectory(nullptr, title, current);
}

QString FolderCompareController::savePath(const QString& title, const QString& defaultName,
                                          const QString& filter) {
    return QFileDialog::getSaveFileName(nullptr, title, defaultName, filter);
}

QString FolderCompareController::formatBytes(qulonglong bytes) {
    return QLocale().formattedDataSize(bytes, 1, QLocale::DataSizeTraditionalFormat);
}

bool FolderCompareController::isTerminalStage(SfcProgressStage stage) {
    return stage == SFC_PROGRESS_FAILED || stage == SFC_PROGRESS_CANCELED ||
           stage == SFC_PROGRESS_COMPLETE;
}

QString FolderCompareController::progressLabel(SfcProgressStage stage, qulonglong current,
                                               qulonglong total, const QString& path) {
    const QString count =
        total > 0 ? QStringLiteral("%1 / %2").arg(current).arg(total) : QString::number(current);
    const QString suffix = path.isEmpty() ? QString() : QStringLiteral(" - %1").arg(path);
    switch (stage) {
    case SFC_PROGRESS_SCANNING_A:
        return QStringLiteral("Scanning A %1%2").arg(count, suffix);
    case SFC_PROGRESS_SCANNING_B:
        return QStringLiteral("Scanning B %1%2").arg(count, suffix);
    case SFC_PROGRESS_CHECKSUMMING:
        return QStringLiteral("Checksumming %1%2").arg(count, suffix);
    case SFC_PROGRESS_COMPARING:
        return QStringLiteral("Comparing %1%2").arg(count, suffix);
    case SFC_PROGRESS_TRANSFERRING:
        return QStringLiteral("Transferring %1%2").arg(count, suffix);
    case SFC_PROGRESS_COMPLETE:
        return QStringLiteral("Complete");
    case SFC_PROGRESS_CANCELED:
        return QStringLiteral("Canceled%1").arg(suffix);
    case SFC_PROGRESS_FAILED:
        return QStringLiteral("Failed%1").arg(suffix);
    default:
        return QStringLiteral("Working %1%2").arg(count, suffix);
    }
}

// ── Selection ──────────────────────────────────────────────────────────────

bool FolderCompareController::hasSelection() const {
    return !m_selectedRows.isEmpty();
}

int FolderCompareController::selectedCount() const {
    return m_selectedRows.size();
}

void FolderCompareController::toggleRowSelection(int rowIndex, int modifiers) {
    if (rowIndex < 0 || rowIndex >= m_tableModel.totalRows()) {
        return;
    }

    const Qt::KeyboardModifiers mods = static_cast<Qt::KeyboardModifiers>(modifiers);

    if (mods & Qt::ControlModifier) {
        if (m_selectedRows.contains(rowIndex)) {
            m_selectedRows.remove(rowIndex);
        } else {
            m_selectedRows.insert(rowIndex);
        }
        m_lastSelectedRow = rowIndex;
    } else if (mods & Qt::ShiftModifier && m_lastSelectedRow >= 0) {
        const int from = qMin(m_lastSelectedRow, rowIndex);
        const int to = qMax(m_lastSelectedRow, rowIndex);
        for (int i = from; i <= to; ++i) {
            m_selectedRows.insert(i);
        }
    } else {
        m_selectedRows.clear();
        m_selectedRows.insert(rowIndex);
        m_lastSelectedRow = rowIndex;
    }

    emitSelectionChanged();
}

void FolderCompareController::clearSelection() {
    m_selectedRows.clear();
    m_lastSelectedRow = -1;
    emitSelectionChanged();
}

bool FolderCompareController::isRowSelected(int rowIndex) const {
    return m_selectedRows.contains(rowIndex);
}

void FolderCompareController::emitSelectionChanged() {
    emit selectionChanged();
}

bool FolderCompareController::canTransferInDirection(int direction) const {
    if (m_selectedRows.isEmpty() || m_transferBusy) {
        return false;
    }
    for (int row : m_selectedRows) {
        const int status = m_tableModel.statusForSourceRow(row);
        if (direction == 1) {
            if (!(status == CompareRow::OnlyInA || status == CompareRow::Changed ||
                  status == CompareRow::Matching || status == CompareRow::FolderOnlyInA)) {
                return false;
            }
        } else {
            if (!(status == CompareRow::OnlyInB || status == CompareRow::Changed ||
                  status == CompareRow::Matching || status == CompareRow::FolderOnlyInB)) {
                return false;
            }
        }
    }
    return true;
}

bool FolderCompareController::canMoveInDirection(int direction) const {
    if (m_selectedRows.isEmpty() || m_transferBusy) {
        return false;
    }
    for (int row : m_selectedRows) {
        const int status = m_tableModel.statusForSourceRow(row);
        if (direction == 1) {
            if (status == CompareRow::OnlyInA && !m_tableModel.isFolderRow(row)) {
                continue;
            }
            if (status == CompareRow::Changed || status == CompareRow::Matching) {
                continue;
            }
            return false;
        } else {
            if (status == CompareRow::OnlyInB && !m_tableModel.isFolderRow(row)) {
                continue;
            }
            if (status == CompareRow::Changed || status == CompareRow::Matching) {
                continue;
            }
            return false;
        }
    }
    return canTransferInDirection(direction);
}

bool FolderCompareController::canCopyToA() const {
    return canTransferInDirection(0);
}

bool FolderCompareController::canCopyToB() const {
    return canTransferInDirection(1);
}

bool FolderCompareController::canMoveToA() const {
    return canMoveInDirection(0);
}

bool FolderCompareController::canMoveToB() const {
    return canMoveInDirection(1);
}

bool FolderCompareController::canUndo() const {
    return !m_undoStack.isEmpty() && !m_transferBusy;
}

bool FolderCompareController::transferBusy() const {
    return m_transferBusy;
}

int FolderCompareController::transferCurrent() const {
    return m_transferCurrent;
}

int FolderCompareController::transferTotal() const {
    return m_transferTotal;
}

// ── Transfer execution ─────────────────────────────────────────────────────

QString FolderCompareController::sourcePath(int direction, const QString& relPath) const {
    const QString base = (direction == 1) ? m_folderA : m_folderB;
    return base + QStringLiteral("/") + relPath;
}

QString FolderCompareController::destPath(int direction, const QString& relPath) const {
    const QString base = (direction == 1) ? m_folderB : m_folderA;
    return base + QStringLiteral("/") + relPath;
}

void FolderCompareController::buildTransferQueue(int direction, bool isMove) {
    m_transferQueue.clear();
    for (int row : m_selectedRows) {
        const int status = m_tableModel.statusForSourceRow(row);
        const bool isFolder = m_tableModel.isFolderRow(row);
        const QString relPath = m_tableModel.relativePathForRow(row);

        bool valid = false;
        if (direction == 1) {
            valid = (status == CompareRow::OnlyInA || status == CompareRow::Changed ||
                     status == CompareRow::Matching || status == CompareRow::FolderOnlyInA);
        } else {
            valid = (status == CompareRow::OnlyInB || status == CompareRow::Changed ||
                     status == CompareRow::Matching || status == CompareRow::FolderOnlyInB);
        }
        if (valid) {
            m_transferQueue.append({relPath, status, isFolder, direction, isMove});
        }
    }
}

void FolderCompareController::copySelectedToA() {
    buildTransferQueue(0, false);
    m_transferSucceeded = 0;
    m_transferFailed = 0;
    m_batchOverwriteState = OverwriteBatchState::NotSet;
    setTransferProgress(0, m_transferQueue.size());
    addLog(QStringLiteral("Copy to A: %1 items").arg(m_transferQueue.size()));
    startNextTransfer();
}

void FolderCompareController::copySelectedToB() {
    buildTransferQueue(1, false);
    m_transferSucceeded = 0;
    m_transferFailed = 0;
    m_batchOverwriteState = OverwriteBatchState::NotSet;
    setTransferProgress(0, m_transferQueue.size());
    addLog(QStringLiteral("Copy to B: %1 items").arg(m_transferQueue.size()));
    startNextTransfer();
}

void FolderCompareController::moveSelectedToA() {
    buildTransferQueue(0, true);
    m_transferSucceeded = 0;
    m_transferFailed = 0;
    m_batchOverwriteState = OverwriteBatchState::NotSet;
    setTransferProgress(0, m_transferQueue.size());
    addLog(QStringLiteral("Move to A: %1 items").arg(m_transferQueue.size()));
    startNextTransfer();
}

void FolderCompareController::moveSelectedToB() {
    buildTransferQueue(1, true);
    m_transferSucceeded = 0;
    m_transferFailed = 0;
    m_batchOverwriteState = OverwriteBatchState::NotSet;
    setTransferProgress(0, m_transferQueue.size());
    addLog(QStringLiteral("Move to B: %1 items").arg(m_transferQueue.size()));
    startNextTransfer();
}

void FolderCompareController::startNextTransfer() {
    while (!m_transferQueue.isEmpty()) {
        m_currentOp = m_transferQueue.takeFirst();

        const QString srcPath = sourcePath(m_currentOp.direction, m_currentOp.relativePath);
        const QString dstPath = destPath(m_currentOp.direction, m_currentOp.relativePath);
        m_currentSourcePath = srcPath;
        m_currentDestPath = dstPath;

        QFileInfo destInfo(dstPath);
        if (destInfo.exists()) {
            if (m_batchOverwriteState == OverwriteBatchState::OverwriteAll) {
                proceedWithTransfer();
                return;
            }
            if (m_batchOverwriteState == OverwriteBatchState::SkipAll) {
                continue;
            }
            if (m_batchOverwriteState == OverwriteBatchState::Canceled) {
                m_transferQueue.clear();
                break;
            }

            QFileInfo srcInfo(srcPath);
            QVariantMap info;
            info[QStringLiteral("relativePath")] = m_currentOp.relativePath;
            info[QStringLiteral("sourceInfo")] =
                QStringLiteral("Modified: %1, Size: %2")
                    .arg(srcInfo.lastModified().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss")),
                         QLocale().formattedDataSize(srcInfo.size(), 1,
                                                     QLocale::DataSizeTraditionalFormat));
            info[QStringLiteral("destInfo")] =
                QStringLiteral("Modified: %1, Size: %2")
                    .arg(destInfo.lastModified().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss")),
                         QLocale().formattedDataSize(destInfo.size(), 1,
                                                     QLocale::DataSizeTraditionalFormat));
            info[QStringLiteral("sourceModified")] = srcInfo.lastModified().toMSecsSinceEpoch();
            info[QStringLiteral("destModified")] = destInfo.lastModified().toMSecsSinceEpoch();
            emit overwriteNeeded(info);
            return;
        }

        proceedWithTransfer();
        return;
    }

    finishBatch();
}

void FolderCompareController::proceedWithTransfer() {
    setTransferBusy(true);

    auto* thread = new QThread(this);
    auto* worker = new FolderTransferWorker(m_currentSourcePath, m_currentDestPath,
                                            m_currentOp.isFolder, m_currentOp.isMove);
    worker->moveToThread(thread);
    m_transferThread = thread;
    m_transferWorker = worker;

    connect(thread, &QThread::started, worker, &FolderTransferWorker::run);
    connect(worker, &FolderTransferWorker::finished, this,
            &FolderCompareController::handleTransferFinished);
    connect(worker, &FolderTransferWorker::finished, thread, &QThread::quit);
    connect(worker, &FolderTransferWorker::finished, worker, &QObject::deleteLater);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);

    addLog(QStringLiteral("Transferring %1").arg(m_currentOp.relativePath));
    thread->start();
}

void FolderCompareController::finishBatch() {
    setTransferBusy(false);
    addLog(QStringLiteral("Transfer batch complete: %1 succeeded, %2 failed")
               .arg(m_transferSucceeded)
               .arg(m_transferFailed));
    emit transferOperationFinished(m_transferSucceeded, m_transferFailed);
    setStatusText(QStringLiteral("%1 transferred, %2 failed.")
                      .arg(m_transferSucceeded)
                      .arg(m_transferFailed));
}

void FolderCompareController::confirmOverwrite(const QString& response) {
    if (response == QStringLiteral("overwrite")) {
        proceedWithTransfer();
    } else if (response == QStringLiteral("overwriteAll")) {
        m_batchOverwriteState = OverwriteBatchState::OverwriteAll;
        proceedWithTransfer();
    } else if (response == QStringLiteral("skip")) {
        startNextTransfer();
    } else if (response == QStringLiteral("skipAll")) {
        m_batchOverwriteState = OverwriteBatchState::SkipAll;
        startNextTransfer();
    } else if (response == QStringLiteral("cancel")) {
        m_batchOverwriteState = OverwriteBatchState::Canceled;
        m_transferQueue.clear();
        finishBatch();
    }
}

void FolderCompareController::handleTransferFinished(bool success, const QString& errorMessage) {
    m_transferThread = nullptr;
    m_transferWorker = nullptr;

    if (success) {
        m_transferSucceeded++;

        UndoEntry entry;
        entry.relativePath = m_currentOp.relativePath;
        entry.originalStatus = m_currentOp.originalStatus;
        entry.wasMove = m_currentOp.isMove;
        entry.isFolder = m_currentOp.isFolder;
        entry.sourceFolder = sourcePath(m_currentOp.direction, m_currentOp.relativePath);
        entry.destFolder = destPath(m_currentOp.direction, m_currentOp.relativePath);
        m_undoStack.prepend(entry);
        if (m_undoStack.size() > m_maxUndo) {
            m_undoStack.removeLast();
        }
        emit undoChanged();

        addLog(QStringLiteral("Transferred: %1").arg(m_currentOp.relativePath));
    } else {
        m_transferFailed++;
        addLog(QStringLiteral("Transfer failed for %1: %2")
                   .arg(m_currentOp.relativePath, errorMessage),
               LogSeverity::Error);
    }

    setTransferProgress(m_transferSucceeded + m_transferFailed, m_transferTotal);
    startNextTransfer();
}

void FolderCompareController::undoLastTransfer() {
    if (m_undoStack.isEmpty() || m_transferBusy) {
        return;
    }

    const UndoEntry entry = m_undoStack.takeFirst();
    emit undoChanged();

    if (entry.wasMove) {
        addLog(QStringLiteral("Undo not supported for move operations yet: %1")
                   .arg(entry.relativePath),
               LogSeverity::Warning);
        m_undoStack.prepend(entry);
        emit undoChanged();
        return;
    }

    bool ok = false;
    char* error = nullptr;
    const QByteArray destPathBytes = entry.destFolder.toUtf8();

    if (entry.isFolder) {
        ok = sfc_remove_folder(destPathBytes.constData(), &error);
    } else {
        ok = sfc_remove_file(destPathBytes.constData(), &error);
    }

    const QString errorMsg = takeError(error);

    if (ok) {
        addLog(QStringLiteral("Undo: removed %1").arg(entry.relativePath));
    } else {
        addLog(QStringLiteral("Undo failed for %1: %2").arg(entry.relativePath, errorMsg),
               LogSeverity::Error);
        m_undoStack.prepend(entry);
        emit undoChanged();
    }
}

QString FolderCompareController::formatTimestamp(qulonglong secs) {
    const QDateTime dt = QDateTime::fromSecsSinceEpoch(static_cast<qint64>(secs));
    return dt.toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"));
}

void FolderCompareController::setTransferBusy(bool busy) {
    if (m_transferBusy == busy) {
        return;
    }
    m_transferBusy = busy;
    emit transferBusyChanged();
    emit selectionChanged();
}

void FolderCompareController::setTransferProgress(int current, int total) {
    m_transferCurrent = current;
    m_transferTotal = total;
    emit transferProgressChanged();
}

QVariantList FolderCompareController::buildComparisonTree() const {
    struct Node {
        QString name;
        QString relPath;
        int status = -1;
        QString sizeA;
        QString sizeB;
        QString checksumA;
        QString checksumB;
        bool isFolder = false;
        QMap<QString, Node> children;
    };

    Node root;
    root.isFolder = true;

    for (int i = 0; i < m_tableModel.totalRows(); ++i) {
        const QString path = m_tableModel.relativePathForRow(i);
        const QStringList parts = path.split(QLatin1Char('/'), Qt::SkipEmptyParts);
        if (parts.isEmpty()) {
            continue;
        }

        Node* current = &root;
        for (int j = 0; j < parts.size(); ++j) {
            const QString& part = parts[j];
            if (!current->children.contains(part)) {
                Node child;
                child.name = part;
                child.relPath = (current == &root) ? part
                                    : current->relPath + QLatin1Char('/') + part;
                current->children[part] = child;
            }
            current = &current->children[part];
        }

        current->status = m_tableModel.statusForSourceRow(i);
        current->isFolder = m_tableModel.isFolderRow(i);

        const int lastCol = m_tableModel.columnCount(QModelIndex()) - 1;
        const QModelIndex baseIdx = m_tableModel.index(i, 0);
        for (int col = 2; col <= lastCol; ++col) {
            const QModelIndex idx = m_tableModel.index(i, col);
            const QString display = m_tableModel.data(idx, Qt::DisplayRole).toString();
            switch (col) {
            case 2:
                current->sizeA = display;
                break;
            case 3:
                current->sizeB = display;
                break;
            case 4:
                current->checksumA = display;
                break;
            case 5:
                current->checksumB = display;
                break;
            }
        }
    }

    std::function<void(const Node&, QVariantList&)> collect;
    collect = [&collect](const Node& node, QVariantList& list) {
        QStringList keys = node.children.keys();
        std::sort(keys.begin(), keys.end(), [](const QString& a, const QString& b) {
            return QString::compare(a, b, Qt::CaseInsensitive) < 0;
        });

        for (const QString& key : keys) {
            const Node& childNode = node.children[key];
            QVariantMap item;
            item[QStringLiteral("name")] = childNode.name;
            item[QStringLiteral("relPath")] = childNode.relPath;
            item[QStringLiteral("status")] = childNode.status;
            item[QStringLiteral("sizeA")] = childNode.sizeA;
            item[QStringLiteral("sizeB")] = childNode.sizeB;
            item[QStringLiteral("checksumA")] = childNode.checksumA;
            item[QStringLiteral("checksumB")] = childNode.checksumB;
            item[QStringLiteral("isFolder")] = childNode.isFolder || !childNode.children.isEmpty();

            QVariantList children;
            collect(childNode, children);
            item[QStringLiteral("children")] = children;

            int worstStatus = childNode.status;
            if (childNode.isFolder || !childNode.children.isEmpty()) {
                for (const QVariant& c : children) {
                    const QVariantMap cm = c.toMap();
                    const int cs = cm.value(QStringLiteral("status")).toInt();
                    if (cs > worstStatus && cs >= 0) {
                        worstStatus = cs;
                    }
                }
            }
            item[QStringLiteral("aggregateStatus")] = worstStatus;

            list.append(item);
        }
    };

    QVariantList result;
    collect(root, result);
    return result;
}
