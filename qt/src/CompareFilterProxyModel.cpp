// SPDX-License-Identifier: GPL-3.0-only

#include "CompareFilterProxyModel.h"

#include "CompareResultTableModel.h"

CompareFilterProxyModel::CompareFilterProxyModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setDynamicSortFilter(false);
}

int CompareFilterProxyModel::filterMode() const
{
    return m_filterMode;
}

void CompareFilterProxyModel::setFilterMode(int mode)
{
    if (m_filterMode == mode) {
        return;
    }
    m_filterMode = mode;
    invalidateFilter();
    emit filterModeChanged();
}

bool CompareFilterProxyModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    Q_UNUSED(sourceParent)

    const auto *model = qobject_cast<const CompareResultTableModel *>(sourceModel());
    if (!model) {
        return true;
    }

    const int status = model->statusForSourceRow(sourceRow);
    switch (m_filterMode) {
    case All:
        return true;
    case Matching:
        return status == CompareRow::Matching;
    case Changed:
        return status == CompareRow::Changed;
    case OnlyA:
        return status == CompareRow::OnlyInA;
    case OnlyB:
        return status == CompareRow::OnlyInB;
    case Folders:
        return status == CompareRow::FolderOnlyInA || status == CompareRow::FolderOnlyInB;
    default:
        return true;
    }
}
