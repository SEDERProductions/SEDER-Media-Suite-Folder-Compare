// SPDX-License-Identifier: GPL-3.0-only

#include "CompareResultTableModel.h"

#include <QLocale>

namespace {
QString fromCString(const char *value)
{
    return value ? QString::fromUtf8(value) : QString();
}

QString formatBytes(bool present, quint64 bytes)
{
    if (!present) {
        return QString();
    }
    return QLocale().formattedDataSize(bytes, 1, QLocale::DataSizeTraditionalFormat);
}

CompareRow::Status fromStatus(SfcFileStatus status)
{
    switch (status) {
    case SFC_STATUS_MATCHING:
        return CompareRow::Matching;
    case SFC_STATUS_CHANGED:
        return CompareRow::Changed;
    case SFC_STATUS_ONLY_IN_A:
        return CompareRow::OnlyInA;
    case SFC_STATUS_ONLY_IN_B:
        return CompareRow::OnlyInB;
    }
    return CompareRow::Changed;
}

QString statusLabel(int status)
{
    switch (status) {
    case CompareRow::Matching:
        return QStringLiteral("Matching");
    case CompareRow::Changed:
        return QStringLiteral("Changed");
    case CompareRow::OnlyInA:
        return QStringLiteral("Only in A");
    case CompareRow::OnlyInB:
        return QStringLiteral("Only in B");
    case CompareRow::FolderOnlyInA:
        return QStringLiteral("Folder only in A");
    case CompareRow::FolderOnlyInB:
        return QStringLiteral("Folder only in B");
    }
    return QStringLiteral("Changed");
}
}

CompareResultTableModel::CompareResultTableModel(QObject *parent)
    : QAbstractTableModel(parent)
{
}

int CompareResultTableModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

int CompareResultTableModel::columnCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : 6;
}

QVariant CompareResultTableModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size()) {
        return {};
    }

    const CompareRow &row = m_rows.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
        return columnDisplay(row, index.column());
    case StatusCodeRole:
        return row.status;
    case StatusLabelRole:
        return row.statusLabel;
    case RelativePathRole:
        return row.relativePath;
    case SizeARole:
        return row.sizeA;
    case SizeBRole:
        return row.sizeB;
    case ChecksumARole:
        return row.checksumA;
    case ChecksumBRole:
        return row.checksumB;
    case Xxh64ARole:
        return row.xxh64A;
    case Xxh64BRole:
        return row.xxh64B;
    case IsFolderRole:
        return row.folder;
    default:
        return {};
    }
}

QVariant CompareResultTableModel::headerData(int section, Qt::Orientation orientation, int role) const
{
    if (orientation != Qt::Horizontal || role != Qt::DisplayRole) {
        return {};
    }

    switch (section) {
    case 0:
        return QStringLiteral("Status");
    case 1:
        return QStringLiteral("Relative Path");
    case 2:
        return QStringLiteral("Size A");
    case 3:
        return QStringLiteral("Size B");
    case 4:
        return QStringLiteral("Checksum A");
    case 5:
        return QStringLiteral("Checksum B");
    default:
        return {};
    }
}

QHash<int, QByteArray> CompareResultTableModel::roleNames() const
{
    return {
        {StatusCodeRole, "statusCode"},
        {StatusLabelRole, "statusLabel"},
        {RelativePathRole, "relativePath"},
        {SizeARole, "sizeA"},
        {SizeBRole, "sizeB"},
        {ChecksumARole, "checksumA"},
        {ChecksumBRole, "checksumB"},
        {Xxh64ARole, "xxh64A"},
        {Xxh64BRole, "xxh64B"},
        {IsFolderRole, "isFolder"},
    };
}

int CompareResultTableModel::totalRows() const
{
    return m_rows.size();
}

int CompareResultTableModel::statusForSourceRow(int row) const
{
    if (row < 0 || row >= m_rows.size()) {
        return CompareRow::Changed;
    }
    return m_rows.at(row).status;
}

bool CompareResultTableModel::isFolderRow(int row) const
{
    if (row < 0 || row >= m_rows.size()) {
        return false;
    }
    return m_rows.at(row).folder;
}

void CompareResultTableModel::clear()
{
    beginResetModel();
    m_rows.clear();
    endResetModel();
    emit rowsChanged();
}

void CompareResultTableModel::loadFromReport(const SfcReport *report)
{
    QVector<CompareRow> rows;
    if (report) {
        const qsizetype fileRows = static_cast<qsizetype>(sfc_report_row_count(report));
        rows.reserve(fileRows + static_cast<qsizetype>(sfc_report_folder_diff_count(report)));

        for (qsizetype index = 0; index < fileRows; ++index) {
            const auto status = fromStatus(sfc_report_row_status(report, static_cast<size_t>(index)));
            CompareRow row;
            row.relativePath = fromCString(sfc_report_row_path(report, static_cast<size_t>(index)));
            row.status = status;
            row.statusLabel = statusLabel(status);
            row.sizeA = formatBytes(
                sfc_report_row_size_a_present(report, static_cast<size_t>(index)),
                sfc_report_row_size_a(report, static_cast<size_t>(index)));
            row.sizeB = formatBytes(
                sfc_report_row_size_b_present(report, static_cast<size_t>(index)),
                sfc_report_row_size_b(report, static_cast<size_t>(index)));
            row.checksumA = fromCString(sfc_report_row_checksum_a(report, static_cast<size_t>(index)));
            row.checksumB = fromCString(sfc_report_row_checksum_b(report, static_cast<size_t>(index)));
            row.xxh64A = fromCString(sfc_report_row_xxh64_a(report, static_cast<size_t>(index)));
            row.xxh64B = fromCString(sfc_report_row_xxh64_b(report, static_cast<size_t>(index)));
            rows.push_back(row);
        }

        const qsizetype foldersA = static_cast<qsizetype>(sfc_report_folder_count(report, 0));
        for (qsizetype index = 0; index < foldersA; ++index) {
            CompareRow row;
            row.relativePath = fromCString(sfc_report_folder_path(report, 0, static_cast<size_t>(index)));
            row.status = CompareRow::FolderOnlyInA;
            row.statusLabel = statusLabel(row.status);
            row.folder = true;
            rows.push_back(row);
        }

        const qsizetype foldersB = static_cast<qsizetype>(sfc_report_folder_count(report, 1));
        for (qsizetype index = 0; index < foldersB; ++index) {
            CompareRow row;
            row.relativePath = fromCString(sfc_report_folder_path(report, 1, static_cast<size_t>(index)));
            row.status = CompareRow::FolderOnlyInB;
            row.statusLabel = statusLabel(row.status);
            row.folder = true;
            rows.push_back(row);
        }
    }

    setRows(std::move(rows));
}

void CompareResultTableModel::setRows(QVector<CompareRow> rows)
{
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
    emit rowsChanged();
}

QVariant CompareResultTableModel::columnDisplay(const CompareRow &row, int column) const
{
    switch (column) {
    case 0:
        return row.statusLabel;
    case 1:
        return row.relativePath;
    case 2:
        return row.sizeA;
    case 3:
        return row.sizeB;
    case 4:
        return row.checksumA;
    case 5:
        return row.checksumB;
    default:
        return {};
    }
}
