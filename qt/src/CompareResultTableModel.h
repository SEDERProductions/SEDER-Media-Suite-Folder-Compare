// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "seder_folder_compare.h"

#include <QAbstractTableModel>
#include <QVector>

struct CompareRow {
    enum Status {
        Matching = 0,
        Changed = 1,
        OnlyInA = 2,
        OnlyInB = 3,
        FolderOnlyInA = 4,
        FolderOnlyInB = 5
    };

    QString relativePath;
    QString statusLabel;
    QString sizeA;
    QString sizeB;
    QString checksumA;
    QString checksumB;
    QString xxh64A;
    QString xxh64B;
    int status = Changed;
    bool folder = false;
};

class CompareResultTableModel final : public QAbstractTableModel {
    Q_OBJECT
    Q_PROPERTY(int totalRows READ totalRows NOTIFY rowsChanged)

public:
    enum Roles {
        StatusCodeRole = Qt::UserRole + 1,
        StatusLabelRole,
        RelativePathRole,
        SizeARole,
        SizeBRole,
        ChecksumARole,
        ChecksumBRole,
        Xxh64ARole,
        Xxh64BRole,
        IsFolderRole
    };

    explicit CompareResultTableModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    int columnCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QVariant headerData(int section, Qt::Orientation orientation, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int totalRows() const;
    int statusForSourceRow(int row) const;
    bool isFolderRow(int row) const;

    void clear();
    void loadFromReport(const SfcReport *report);
    void setRows(QVector<CompareRow> rows);

signals:
    void rowsChanged();

private:
    QVariant columnDisplay(const CompareRow &row, int column) const;
    QVector<CompareRow> m_rows;
};
