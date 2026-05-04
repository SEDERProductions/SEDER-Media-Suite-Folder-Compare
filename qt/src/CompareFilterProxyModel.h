// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <QSortFilterProxyModel>

class CompareFilterProxyModel final : public QSortFilterProxyModel {
    Q_OBJECT
    Q_PROPERTY(int filterMode READ filterMode WRITE setFilterMode NOTIFY filterModeChanged)

  public:
    enum FilterMode { All = 0, Matching = 1, Changed = 2, OnlyA = 3, OnlyB = 4, Folders = 5 };
    Q_ENUM(FilterMode)

    explicit CompareFilterProxyModel(QObject* parent = nullptr);

    int filterMode() const;
    void setFilterMode(int mode);

  signals:
    void filterModeChanged();

  protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex& sourceParent) const override;

  private:
    int m_filterMode = All;
};
