// SPDX-License-Identifier: GPL-3.0-only

#include "CompareFilterProxyModel.h"
#include "CompareResultTableModel.h"

#include <QSignalSpy>
#include <QtTest/QtTest>

class CompareModelTests final : public QObject {
    Q_OBJECT

  private slots:
    void exposesRowsAndRoles() {
        CompareResultTableModel model;
        QVector<CompareRow> rows;
        rows.push_back(CompareRow{QStringLiteral("A001/clip.mov"),
                                  QStringLiteral("Matching"),
                                  QStringLiteral("4 B"),
                                  QStringLiteral("4 B"),
                                  {},
                                  {},
                                  CompareRow::Matching,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("A001/audio.wav"),
                                  QStringLiteral("Changed"),
                                  QStringLiteral("8 B"),
                                  QStringLiteral("12 B"),
                                  {},
                                  {},
                                  CompareRow::Changed,
                                  false});
        model.setRows(rows);

        QCOMPARE(model.rowCount(), 2);
        QCOMPARE(model.columnCount(), 6);
        QCOMPARE(model.data(model.index(0, 1), Qt::DisplayRole).toString(),
                 QStringLiteral("A001/clip.mov"));
        QCOMPARE(model.data(model.index(1, 0), CompareResultTableModel::StatusCodeRole).toInt(),
                 CompareRow::Changed);
    }

    void filtersByOperationalState() {
        CompareResultTableModel model;
        QVector<CompareRow> rows;
        rows.push_back(CompareRow{QStringLiteral("match.mov"),
                                  QStringLiteral("Matching"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  CompareRow::Matching,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("changed.mov"),
                                  QStringLiteral("Changed"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  CompareRow::Changed,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("only-a.mov"),
                                  QStringLiteral("Only in A"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  CompareRow::OnlyInA,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("only-b.mov"),
                                  QStringLiteral("Only in B"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  CompareRow::OnlyInB,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("folder"),
                                  QStringLiteral("Folder only in A"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  CompareRow::FolderOnlyInA,
                                  true});
        model.setRows(rows);

        CompareFilterProxyModel proxy;
        proxy.setSourceModel(&model);

        proxy.setFilterMode(CompareFilterProxyModel::All);
        QCOMPARE(proxy.rowCount(), 5);

        proxy.setFilterMode(CompareFilterProxyModel::Matching);
        QCOMPARE(proxy.rowCount(), 1);
        QCOMPARE(proxy.data(proxy.index(0, 1), Qt::DisplayRole).toString(),
                 QStringLiteral("match.mov"));

        proxy.setFilterMode(CompareFilterProxyModel::Changed);
        QCOMPARE(proxy.rowCount(), 1);
        QCOMPARE(proxy.data(proxy.index(0, 1), Qt::DisplayRole).toString(),
                 QStringLiteral("changed.mov"));

        proxy.setFilterMode(CompareFilterProxyModel::OnlyA);
        QCOMPARE(proxy.rowCount(), 1);
        QCOMPARE(proxy.data(proxy.index(0, 1), Qt::DisplayRole).toString(),
                 QStringLiteral("only-a.mov"));

        proxy.setFilterMode(CompareFilterProxyModel::OnlyB);
        QCOMPARE(proxy.rowCount(), 1);
        QCOMPARE(proxy.data(proxy.index(0, 1), Qt::DisplayRole).toString(),
                 QStringLiteral("only-b.mov"));

        proxy.setFilterMode(CompareFilterProxyModel::Folders);
        QCOMPARE(proxy.rowCount(), 1);
        QCOMPARE(proxy.data(proxy.index(0, 1), Qt::DisplayRole).toString(),
                 QStringLiteral("folder"));
    }

    void mapsFilteredProxyRowsToSourceRows() {
        // Guards the mechanism FolderCompareController::buildComparisonTree() relies on:
        // iterate the FILTERED proxy, map each row back to its SOURCE row, and use that
        // source row for paths/status and (critically) selection. A regression here would
        // make the result tree ignore the active filter, or hand the wrong row index to
        // the selection/transfer code that is keyed by source row.
        CompareResultTableModel model;
        QVector<CompareRow> rows;
        rows.push_back(CompareRow{QStringLiteral("match.mov"),
                                  QStringLiteral("Matching"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  CompareRow::Matching,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("changed.mov"),
                                  QStringLiteral("Changed"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  CompareRow::Changed,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("only-a.mov"),
                                  QStringLiteral("Only in A"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  CompareRow::OnlyInA,
                                  false});
        model.setRows(rows);

        CompareFilterProxyModel proxy;
        proxy.setSourceModel(&model);

        proxy.setFilterMode(CompareFilterProxyModel::Changed);
        QCOMPARE(proxy.rowCount(), 1);
        const int changedRow = proxy.mapToSource(proxy.index(0, 0)).row();
        QCOMPARE(changedRow, 1); // "changed.mov" is source row 1
        QCOMPARE(model.relativePathForRow(changedRow), QStringLiteral("changed.mov"));
        QCOMPARE(model.statusForSourceRow(changedRow), static_cast<int>(CompareRow::Changed));

        // Switching the filter changes which source rows survive the mapping.
        proxy.setFilterMode(CompareFilterProxyModel::OnlyA);
        QCOMPARE(proxy.rowCount(), 1);
        const int onlyARow = proxy.mapToSource(proxy.index(0, 0)).row();
        QCOMPARE(onlyARow, 2);
        QCOMPARE(model.relativePathForRow(onlyARow), QStringLiteral("only-a.mov"));
    }

    void emitsRowsChangedOnReset() {
        CompareResultTableModel model;
        QSignalSpy spy(&model, &CompareResultTableModel::rowsChanged);
        model.setRows({CompareRow{QStringLiteral("clip.mov"),
                                  QStringLiteral("Matching"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  CompareRow::Matching,
                                  false}});
        QCOMPARE(spy.count(), 1);
    }
};

QTEST_MAIN(CompareModelTests)

#include "test_model.moc"
