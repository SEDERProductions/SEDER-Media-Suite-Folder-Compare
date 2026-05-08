// SPDX-License-Identifier: GPL-3.0-only

#include "FolderCompareController.h"

#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

#ifndef APP_VERSION
#define APP_VERSION "0.1.4"
#endif

int main(int argc, char* argv[]) {
    QApplication app(argc, argv);
    QApplication::setOrganizationName(QStringLiteral("Seder Productions"));
    QApplication::setOrganizationDomain(QStringLiteral("sederproductions.com"));
    QApplication::setApplicationName(QStringLiteral("SEDER Media Suite Folder Compare"));
    QApplication::setApplicationVersion(QStringLiteral(APP_VERSION));
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
