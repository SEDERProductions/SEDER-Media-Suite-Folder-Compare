// SPDX-License-Identifier: GPL-3.0-only

#include "FolderCompareController.h"

#include <QDateTime>
#include <QFileDialog>
#include <QApplication>
#include <QLocale>
#include <QSettings>
#include <QStyleHints>
#include <QThread>

namespace {
constexpr auto defaultPatterns = ".DS_Store, Thumbs.db, desktop.ini, .Spotlight-V100, .Trashes";
constexpr auto reportTitle = "SEDER Media Suite Folder Compare Report";
}

FolderCompareController::FolderCompareController(QObject *parent)
    : QObject(parent)
    , m_statusText(QStringLiteral("Ready to compare two folders."))
    , m_progressText(QStringLiteral("Idle"))
{
    QSettings settings;
    m_theme = settings.value(QStringLiteral("theme"), QStringLiteral("system")).toString();
    m_ignorePatterns = settings.value(QStringLiteral("ignorePatterns"), QString::fromUtf8(defaultPatterns)).toString();
    m_ignoreHiddenSystem = settings.value(QStringLiteral("ignoreHiddenSystem"), true).toBool();
    m_filterModel.setSourceModel(&m_tableModel);
    connect(qApp->styleHints(), &QStyleHints::colorSchemeChanged, this, [this] {
        if (m_theme == QStringLiteral("system")) {
            emit effectiveDarkChanged();
        }
    });
    resetSummary();
    addLog(QStringLiteral("Folder Compare ready."));
}

FolderCompareController::~FolderCompareController()
{
    if (m_worker) {
        m_worker->cancel();
    }
    if (m_thread) {
        m_thread->quit();
        m_thread->wait(1500);
    }
    if (m_report) {
        sfc_report_free(m_report);
    }
}

QString FolderCompareController::folderA() const { return m_folderA; }
QString FolderCompareController::folderB() const { return m_folderB; }
int FolderCompareController::mode() const { return m_mode; }
bool FolderCompareController::ignoreHiddenSystem() const { return m_ignoreHiddenSystem; }
QString FolderCompareController::ignorePatterns() const { return m_ignorePatterns; }
bool FolderCompareController::busy() const { return m_busy; }
QString FolderCompareController::statusText() const { return m_statusText; }
QString FolderCompareController::progressText() const { return m_progressText; }
QString FolderCompareController::theme() const { return m_theme; }
bool FolderCompareController::effectiveDark() const
{
    if (m_theme == QStringLiteral("dark")) {
        return true;
    }
    if (m_theme == QStringLiteral("light")) {
        return false;
    }
    return qApp->styleHints()->colorScheme() == Qt::ColorScheme::Dark;
}
QStringList FolderCompareController::logEntries() const { return m_logEntries; }
QObject *FolderCompareController::tableModel() { return &m_tableModel; }
QObject *FolderCompareController::filterModel() { return &m_filterModel; }
int FolderCompareController::matchingCount() const { return m_matchingCount; }
int FolderCompareController::changedCount() const { return m_changedCount; }
int FolderCompareController::onlyACount() const { return m_onlyACount; }
int FolderCompareController::onlyBCount() const { return m_onlyBCount; }
int FolderCompareController::folderDiffCount() const { return m_folderDiffCount; }
QString FolderCompareController::totalSizeText() const { return m_totalSizeText; }

void FolderCompareController::setFolderA(const QString &folder)
{
    if (m_folderA == folder) {
        return;
    }
    m_folderA = folder;
    emit folderAChanged();
}

void FolderCompareController::setFolderB(const QString &folder)
{
    if (m_folderB == folder) {
        return;
    }
    m_folderB = folder;
    emit folderBChanged();
}

void FolderCompareController::setMode(int mode)
{
    if (m_mode == mode) {
        return;
    }
    m_mode = mode;
    emit modeChanged();
}

void FolderCompareController::setIgnoreHiddenSystem(bool ignore)
{
    if (m_ignoreHiddenSystem == ignore) {
        return;
    }
    m_ignoreHiddenSystem = ignore;
    QSettings().setValue(QStringLiteral("ignoreHiddenSystem"), ignore);
    emit ignoreHiddenSystemChanged();
}

void FolderCompareController::setIgnorePatterns(const QString &patterns)
{
    if (m_ignorePatterns == patterns) {
        return;
    }
    m_ignorePatterns = patterns;
    QSettings().setValue(QStringLiteral("ignorePatterns"), patterns);
    emit ignorePatternsChanged();
}

void FolderCompareController::setTheme(const QString &theme)
{
    const QString safeTheme = (theme == QStringLiteral("light") || theme == QStringLiteral("dark"))
        ? theme
        : QStringLiteral("system");
    if (m_theme == safeTheme) {
        return;
    }
    m_theme = safeTheme;
    QSettings().setValue(QStringLiteral("theme"), safeTheme);
    emit themeChanged();
    emit effectiveDarkChanged();
}

void FolderCompareController::chooseFolderA()
{
    const QString selected = pickFolder(QStringLiteral("Choose Folder A"), m_folderA);
    if (!selected.isEmpty()) {
        setFolderA(selected);
    }
}

void FolderCompareController::chooseFolderB()
{
    const QString selected = pickFolder(QStringLiteral("Choose Folder B"), m_folderB);
    if (!selected.isEmpty()) {
        setFolderB(selected);
    }
}

void FolderCompareController::startComparison()
{
    if (m_busy) {
        return;
    }
    if (m_folderA.isEmpty() || m_folderB.isEmpty()) {
        setStatusText(QStringLiteral("Choose Folder A and Folder B before starting."));
        addLog(QStringLiteral("Start blocked: missing folder selection."));
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
    resetSummary();

    auto *thread = new QThread(this);
    auto *worker = new FolderCompareWorker(m_folderA, m_folderB, m_mode, m_ignoreHiddenSystem, m_ignorePatterns);
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

void FolderCompareController::cancelComparison()
{
    if (!m_busy || !m_worker) {
        return;
    }
    m_worker->cancel();
    setStatusText(QStringLiteral("Canceling comparison..."));
    addLog(QStringLiteral("Cancellation requested."));
}

void FolderCompareController::exportTxt()
{
    if (!hasReport()) {
        setStatusText(QStringLiteral("No comparison report to export."));
        return;
    }
    const QString path = savePath(
        QStringLiteral("Export TXT Report"),
        QStringLiteral("seder-folder-compare-report.txt"),
        QStringLiteral("Text report (*.txt)"));
    if (path.isEmpty()) {
        addLog(QStringLiteral("TXT export canceled."));
        setStatusText(QStringLiteral("Export canceled."));
        return;
    }

    const QByteArray outputPath = path.toUtf8();
    const QByteArray title = QByteArray(reportTitle);
    char *error = nullptr;
    if (sfc_report_write_txt(m_report, outputPath.constData(), title.constData(), &error)) {
        addLog(QStringLiteral("TXT exported: %1").arg(path));
        setStatusText(QStringLiteral("TXT export complete."));
    } else {
        const QString message = takeError(error);
        addLog(QStringLiteral("TXT export failed: %1").arg(message));
        setStatusText(message);
    }
}

void FolderCompareController::exportCsv()
{
    if (!hasReport()) {
        setStatusText(QStringLiteral("No comparison report to export."));
        return;
    }
    const QString path = savePath(
        QStringLiteral("Export CSV Report"),
        QStringLiteral("seder-folder-compare-report.csv"),
        QStringLiteral("CSV report (*.csv)"));
    if (path.isEmpty()) {
        addLog(QStringLiteral("CSV export canceled."));
        setStatusText(QStringLiteral("Export canceled."));
        return;
    }

    const QByteArray outputPath = path.toUtf8();
    char *error = nullptr;
    if (sfc_report_write_csv(m_report, outputPath.constData(), &error)) {
        addLog(QStringLiteral("CSV exported: %1").arg(path));
        setStatusText(QStringLiteral("CSV export complete."));
    } else {
        const QString message = takeError(error);
        addLog(QStringLiteral("CSV export failed: %1").arg(message));
        setStatusText(message);
    }
}

void FolderCompareController::setFilterMode(int mode)
{
    m_filterModel.setFilterMode(mode);
}

void FolderCompareController::clearLog()
{
    m_logEntries.clear();
    emit logEntriesChanged();
}

int FolderCompareController::totalRows() const
{
    return m_tableModel.totalRows();
}

void FolderCompareController::handleProgress(int stage, qulonglong current, qulonglong total, const QString &path)
{
    const QString label = progressLabel(stage, current, total, path);
    setProgressText(label);
    if (stage == SFC_PROGRESS_FAILED || stage == SFC_PROGRESS_CANCELED || stage == SFC_PROGRESS_COMPLETE) {
        addLog(label);
    }
}

void FolderCompareController::handleFinished(SfcReport *report, const QString &errorMessage, bool canceled)
{
    setBusy(false);
    m_worker = nullptr;
    m_thread = nullptr;

    if (canceled) {
        if (report) {
            sfc_report_free(report);
        }
        setStatusText(QStringLiteral("Comparison canceled."));
        setProgressText(QStringLiteral("Canceled"));
        addLog(QStringLiteral("Comparison canceled."));
        return;
    }

    if (!errorMessage.isEmpty() || !report) {
        if (report) {
            sfc_report_free(report);
        }
        const QString message = errorMessage.isEmpty() ? QStringLiteral("Comparison failed.") : errorMessage;
        setStatusText(message);
        setProgressText(QStringLiteral("Failed"));
        addLog(QStringLiteral("Comparison failed: %1").arg(message));
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

void FolderCompareController::setBusy(bool busy)
{
    if (m_busy == busy) {
        return;
    }
    m_busy = busy;
    emit busyChanged();
}

void FolderCompareController::setStatusText(const QString &status)
{
    if (m_statusText == status) {
        return;
    }
    m_statusText = status;
    emit statusTextChanged();
}

void FolderCompareController::setProgressText(const QString &progress)
{
    if (m_progressText == progress) {
        return;
    }
    m_progressText = progress;
    emit progressTextChanged();
}

void FolderCompareController::addLog(const QString &message)
{
    const QString timestamp = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss"));
    m_logEntries.prepend(QStringLiteral("%1  %2").arg(timestamp, message));
    while (m_logEntries.size() > 200) {
        m_logEntries.removeLast();
    }
    emit logEntriesChanged();
}

void FolderCompareController::resetSummary()
{
    m_matchingCount = 0;
    m_changedCount = 0;
    m_onlyACount = 0;
    m_onlyBCount = 0;
    m_folderDiffCount = 0;
    m_totalSizeText = formatBytes(0);
    emit summaryChanged();
}

void FolderCompareController::loadSummary(const SfcReport *report)
{
    m_matchingCount = static_cast<int>(sfc_report_matching_count(report));
    m_changedCount = static_cast<int>(sfc_report_changed_count(report));
    m_onlyACount = static_cast<int>(sfc_report_only_a_count(report));
    m_onlyBCount = static_cast<int>(sfc_report_only_b_count(report));
    m_folderDiffCount = static_cast<int>(sfc_report_folder_diff_count(report));
    m_totalSizeText = formatBytes(sfc_report_total_size(report));
    emit summaryChanged();
}

bool FolderCompareController::hasReport() const
{
    return m_report != nullptr;
}

QString FolderCompareController::pickFolder(const QString &title, const QString &current)
{
    return QFileDialog::getExistingDirectory(qApp->activeWindow(), title, current);
}

QString FolderCompareController::savePath(const QString &title, const QString &defaultName, const QString &filter)
{
    return QFileDialog::getSaveFileName(qApp->activeWindow(), title, defaultName, filter);
}

QString FolderCompareController::formatBytes(qulonglong bytes)
{
    return QLocale().formattedDataSize(bytes, 1, QLocale::DataSizeTraditionalFormat);
}

QString FolderCompareController::takeError(char *error)
{
    if (!error) {
        return {};
    }
    const QString message = QString::fromUtf8(error);
    sfc_string_free(error);
    return message;
}

QString FolderCompareController::progressLabel(int stage, qulonglong current, qulonglong total, const QString &path)
{
    const QString count = total > 0
        ? QStringLiteral("%1 / %2").arg(current).arg(total)
        : QString::number(current);
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
