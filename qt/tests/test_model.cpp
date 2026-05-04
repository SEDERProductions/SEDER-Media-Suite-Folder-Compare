// SPDX-License-Identifier: GPL-3.0-only

#include "CompareFilterProxyModel.h"
#include "CompareResultTableModel.h"

#include <QSignalSpy>
#include <QtTest/QtTest>

class CompareModelTests final : public QObject {
    Q_OBJECT

private slots:
    void exposesRowsAndRoles()
    {
        CompareResultTableModel model;
        QVector<CompareRow> rows;
        rows.push_back(CompareRow{QStringLiteral("A001/clip.mov"),
                                  QStringLiteral("Matching"),
                                  QStringLiteral("4 B"),
                                  QStringLiteral("4 B"),
                                  {},
                                  {},
                                  QString{},
                                  QString{},
                                  CompareRow::Matching,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("A001/audio.wav"),
                                  QStringLiteral("Changed"),
                                  QStringLiteral("8 B"),
                                  QStringLiteral("12 B"),
                                  {},
                                  {},
                                  QString{},
                                  QString{},
                                  CompareRow::Changed,
                                  false});
        model.setRows(rows);

        QCOMPARE(model.rowCount(), 2);
        QCOMPARE(model.columnCount(), 6);
        QCOMPARE(model.data(model.index(0, 1), Qt::DisplayRole).toString(),
                 QStringLiteral("A001/clip.mov"));
        QCOMPARE(
            model.data(model.index(1, 0), CompareResultTableModel::StatusCodeRole).toInt(),
            CompareRow::Changed);
    }

    void filtersByOperationalState()
    {
        CompareResultTableModel model;
        QVector<CompareRow> rows;
        rows.push_back(CompareRow{QStringLiteral("match.mov"),
                                  QStringLiteral("Matching"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  QString{},
                                  QString{},
                                  CompareRow::Matching,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("changed.mov"),
                                  QStringLiteral("Changed"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  QString{},
                                  QString{},
                                  CompareRow::Changed,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("only-a.mov"),
                                  QStringLiteral("Only in A"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  QString{},
                                  QString{},
                                  CompareRow::OnlyInA,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("only-b.mov"),
                                  QStringLiteral("Only in B"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  QString{},
                                  QString{},
                                  CompareRow::OnlyInB,
                                  false});
        rows.push_back(CompareRow{QStringLiteral("folder"),
                                  QStringLiteral("Folder only in A"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  QString{},
                                  QString{},
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

    void emitsRowsChangedOnReset()
    {
        CompareResultTableModel model;
        QSignalSpy spy(&model, &CompareResultTableModel::rowsChanged);
        model.setRows({CompareRow{QStringLiteral("clip.mov"),
                                  QStringLiteral("Matching"),
                                  {},
                                  {},
                                  {},
                                  {},
                                  QString{},
                                  QString{},
                                  CompareRow::Matching,
                                  false}});
        QCOMPARE(spy.count(), 1);
    }
};

QTEST_MAIN(CompareModelTests)

#include "test_model.moc"
