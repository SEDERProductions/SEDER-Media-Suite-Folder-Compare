// SPDX-License-Identifier: GPL-3.0-only

#include "FolderCompareController.h"

#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

int main(int argc, char* argv[]) {
    QApplication app(argc, argv);
    QApplication::setOrganizationName(QStringLiteral("Seder Productions"));
    QApplication::setOrganizationDomain(QStringLiteral("sederproductions.com"));
    QApplication::setApplicationName(QStringLiteral("SEDER Media Suite Folder Compare"));
#ifdef SEDER_APP_VERSION
    QApplication::setApplicationVersion(QStringLiteral(SEDER_APP_VERSION));
#endif
    QApplication::setWindowIcon(QIcon(QStringLiteral(":/assets/icon.svg")));

    QQuickStyle::setStyle(QStringLiteral("Fusion"));
    qRegisterMetaType<SfcReport*>("SfcReport*");

    FolderCompareController controller;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("folderController"), &controller);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }

    return app.exec();
}
