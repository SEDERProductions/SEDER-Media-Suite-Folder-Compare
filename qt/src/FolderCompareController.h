// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "CompareFilterProxyModel.h"
#include "CompareResultTableModel.h"
#include "FolderCompareWorker.h"
#include "FolderTransferWorker.h"

#include <QObject>
#include <QPointer>
#include <QSet>
#include <QStringList>
#include <QVariantMap>

class QThread;

struct TransferOp {
    QString relativePath;
    int originalStatus = CompareRow::Changed;
    bool isFolder = false;
    int direction = 1; // 0 = to A, 1 = to B
    bool isMove = false;
};

struct UndoEntry {
    QString relativePath;
    int originalStatus = CompareRow::Changed;
    QString sourceFolder;
    QString destFolder;
    bool wasMove = false;
    bool isFolder = false;
};

class FolderCompareController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString folderA READ folderA WRITE setFolderA NOTIFY folderAChanged)
    Q_PROPERTY(QString folderB READ folderB WRITE setFolderB NOTIFY folderBChanged)
    Q_PROPERTY(int mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(bool ignoreHiddenSystem READ ignoreHiddenSystem WRITE setIgnoreHiddenSystem NOTIFY
                   ignoreHiddenSystemChanged)
    Q_PROPERTY(QString ignorePatterns READ ignorePatterns WRITE setIgnorePatterns NOTIFY
                   ignorePatternsChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(QString progressText READ progressText NOTIFY progressTextChanged)
    Q_PROPERTY(QString theme READ theme WRITE setTheme NOTIFY themeChanged)
    Q_PROPERTY(bool effectiveDark READ effectiveDark NOTIFY effectiveDarkChanged)
    Q_PROPERTY(QStringList logEntries READ logEntries NOTIFY logEntriesChanged)
    Q_PROPERTY(QObject* tableModel READ tableModel CONSTANT)
    Q_PROPERTY(QObject* filterModel READ filterModel CONSTANT)
    Q_PROPERTY(int matchingCount READ matchingCount NOTIFY summaryChanged)
    Q_PROPERTY(int changedCount READ changedCount NOTIFY summaryChanged)
    Q_PROPERTY(int onlyACount READ onlyACount NOTIFY summaryChanged)
    Q_PROPERTY(int onlyBCount READ onlyBCount NOTIFY summaryChanged)
    Q_PROPERTY(int folderDiffCount READ folderDiffCount NOTIFY summaryChanged)
    Q_PROPERTY(QString totalSizeText READ totalSizeText NOTIFY summaryChanged)
    Q_PROPERTY(bool hasReport READ hasReport NOTIFY hasReportChanged)
    Q_PROPERTY(int totalRows READ totalRows NOTIFY totalRowsChanged)
    Q_PROPERTY(qulonglong progressCurrent READ progressCurrent NOTIFY progressChanged)
    Q_PROPERTY(qulonglong progressTotal READ progressTotal NOTIFY progressChanged)
    Q_PROPERTY(bool hasSelection READ hasSelection NOTIFY selectionChanged)
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY selectionChanged)
    Q_PROPERTY(bool canCopyToA READ canCopyToA NOTIFY selectionChanged)
    Q_PROPERTY(bool canCopyToB READ canCopyToB NOTIFY selectionChanged)
    Q_PROPERTY(bool canMoveToA READ canMoveToA NOTIFY selectionChanged)
    Q_PROPERTY(bool canMoveToB READ canMoveToB NOTIFY selectionChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY undoChanged)
    Q_PROPERTY(bool transferBusy READ transferBusy NOTIFY transferBusyChanged)
    Q_PROPERTY(int transferCurrent READ transferCurrent NOTIFY transferProgressChanged)
    Q_PROPERTY(int transferTotal READ transferTotal NOTIFY transferProgressChanged)

  public:
    explicit FolderCompareController(QObject* parent = nullptr);
    ~FolderCompareController() override;

    QString folderA() const;
    QString folderB() const;
    int mode() const;
    bool ignoreHiddenSystem() const;
    QString ignorePatterns() const;
    bool busy() const;
    QString statusText() const;
    QString progressText() const;
    QString theme() const;
    bool effectiveDark() const;
    QStringList logEntries() const;
    QObject* tableModel();
    QObject* filterModel();
    int matchingCount() const;
    int changedCount() const;
    int onlyACount() const;
    int onlyBCount() const;
    int folderDiffCount() const;
    QString totalSizeText() const;
    bool hasReport() const;
    int totalRows() const;
    qulonglong progressCurrent() const;
    qulonglong progressTotal() const;

    bool hasSelection() const;
    int selectedCount() const;
    bool canCopyToA() const;
    bool canCopyToB() const;
    bool canMoveToA() const;
    bool canMoveToB() const;
    bool canUndo() const;
    bool transferBusy() const;
    int transferCurrent() const;
    int transferTotal() const;

    void setFolderA(const QString& folder);
    void setFolderB(const QString& folder);
    void setMode(int mode);
    void setIgnoreHiddenSystem(bool ignore);
    void setIgnorePatterns(const QString& patterns);
    void setTheme(const QString& theme);

    Q_INVOKABLE void chooseFolderA();
    Q_INVOKABLE void chooseFolderB();

    Q_INVOKABLE void toggleRowSelection(int rowIndex, int modifiers);
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE bool isRowSelected(int rowIndex) const;
    Q_INVOKABLE void copySelectedToA();
    Q_INVOKABLE void copySelectedToB();
    Q_INVOKABLE void moveSelectedToA();
    Q_INVOKABLE void moveSelectedToB();
    Q_INVOKABLE void confirmOverwrite(const QString& response);
    Q_INVOKABLE void undoLastTransfer();
    Q_INVOKABLE QVariantList buildComparisonTree() const;

  signals:
    void folderAChanged();
    void folderBChanged();
    void modeChanged();
    void ignoreHiddenSystemChanged();
    void ignorePatternsChanged();
    void busyChanged();
    void statusTextChanged();
    void progressTextChanged();
    void themeChanged();
    void effectiveDarkChanged();
    void logEntriesChanged();
    void summaryChanged();
    void hasReportChanged();
    void totalRowsChanged();
    void progressChanged();
    void selectionChanged();
    void undoChanged();
    void transferBusyChanged();
    void transferProgressChanged();
    void overwriteNeeded(QVariantMap fileInfo);
    void transferOperationFinished(int succeeded, int failed);

  private slots:
    void handleProgress(SfcProgressStage stage, qulonglong current, qulonglong total,
                        const QString& path);
    void handleFinished(SfcReport* report, const QString& errorMessage,
                        SfcProgressStage terminalStage);

  private:
    enum class LogSeverity { Info, Warning, Error };
    enum class OverwriteBatchState { NotSet, OverwriteAll, SkipAll, Canceled };

    void setBusy(bool busy);
    void setStatusText(const QString& status);
    void setProgressText(const QString& progress);
    void addLog(const QString& message, LogSeverity severity = LogSeverity::Info,
                bool includeTimestamp = true);
    void resetSummary();
    void loadSummary(const SfcReport* report);
    QString pickFolder(const QString& title, const QString& current);
    QString savePath(const QString& title, const QString& defaultName, const QString& filter);
    static QString formatBytes(qulonglong bytes);
    static bool isTerminalStage(SfcProgressStage stage);
    static QString progressLabel(SfcProgressStage stage, qulonglong current, qulonglong total,
                                 const QString& path);

    // Transfer
    void buildTransferQueue(int direction, bool isMove);
    void startNextTransfer();
    void proceedWithTransfer();
    void finishBatch();
    void setTransferBusy(bool busy);
    void setTransferProgress(int current, int total);
    void emitSelectionChanged();
    bool canTransferInDirection(int direction) const;
    bool canMoveInDirection(int direction) const;
    QString sourcePath(int direction, const QString& relPath) const;
    QString destPath(int direction, const QString& relPath) const;
    static QString formatTimestamp(qulonglong secs);
    void handleTransferFinished(bool success, const QString& errorMessage);

    QString m_folderA;
    QString m_folderB;
    int m_mode = 0;
    bool m_ignoreHiddenSystem = true;
    QString m_ignorePatterns;
    bool m_busy = false;
    QString m_statusText;
    QString m_progressText;
    QString m_theme;
    QStringList m_logEntries;
    CompareResultTableModel m_tableModel;
    CompareFilterProxyModel m_filterModel;
    SfcReport* m_report = nullptr;
    QPointer<FolderCompareWorker> m_worker;
    QPointer<QThread> m_thread;
    int m_matchingCount = 0;
    int m_changedCount = 0;
    int m_onlyACount = 0;
    int m_onlyBCount = 0;
    int m_folderDiffCount = 0;
    QString m_totalSizeText;
    qulonglong m_progressCurrent = 0;
    qulonglong m_progressTotal = 0;

    // Selection and transfer
    QSet<int> m_selectedRows;
    int m_lastSelectedRow = -1;
    QVector<TransferOp> m_transferQueue;
    int m_transferSucceeded = 0;
    int m_transferFailed = 0;
    OverwriteBatchState m_batchOverwriteState = OverwriteBatchState::NotSet;
    TransferOp m_currentOp;
    QString m_currentSourcePath;
    QString m_currentDestPath;
    QVector<UndoEntry> m_undoStack;
    bool m_transferBusy = false;
    int m_transferCurrent = 0;
    int m_transferTotal = 0;
    QPointer<FolderTransferWorker> m_transferWorker;
    QPointer<QThread> m_transferThread;
    static constexpr int m_maxUndo = 50;
};
