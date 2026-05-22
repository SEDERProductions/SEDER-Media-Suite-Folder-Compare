// SPDX-License-Identifier: GPL-3.0-only

#include "FolderCompareController.h"

#include <QApplication>
#include <QIcon>
#include <QLocale>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTranslator>
#include <QUrl>

#ifndef SEDER_APP_VERSION
#define SEDER_APP_VERSION "0.0.0"
#endif

int main(int argc, char* argv[]) {
    QApplication app(argc, argv);
    QApplication::setOrganizationName(QStringLiteral("Seder Productions"));
    QApplication::setOrganizationDomain(QStringLiteral("sederproductions.com"));
    QApplication::setApplicationName(QStringLiteral("SEDER Media Suite Folder Compare"));
    QApplication::setApplicationVersion(QStringLiteral(SEDER_APP_VERSION));
    QApplication::setWindowIcon(QIcon(QStringLiteral(":/assets/icon.svg")));

    QQuickStyle::setStyle(QStringLiteral("Fusion"));
    qRegisterMetaType<SfcReport*>("SfcReport*");

    // Install a translator that matches the system locale. .qm files are
    // bundled under qrc:/i18n/ via qt_add_lrelease in CMakeLists.txt. If no
    // match exists the app simply uses the source strings (English).
    QTranslator translator;
    const QStringList uiLanguages = QLocale().uiLanguages();
    for (const QString& locale : uiLanguages) {
        const QString baseName =
            QStringLiteral("seder_") + QLocale(locale).name().section('_', 0, 0);
        if (translator.load(QStringLiteral(":/i18n/") + baseName)) {
            QApplication::installTranslator(&translator);
            break;
        }
    }

    FolderCompareController controller;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("folderController"), &controller);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }

    return app.exec();
}
