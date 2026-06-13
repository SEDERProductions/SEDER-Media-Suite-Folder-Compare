// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Seder.UI

// Summary metric tile (e.g. "MATCHING 1,204"). Extracted from Main.qml.
Rectangle {
    id: root

    property string label: ""
    property var value
    property color accent: Theme.faint

    Layout.fillWidth: true
    Layout.preferredHeight: 48
    radius: Theme.radius.md
    color: Theme.panel
    border.color: Theme.line
    border.width: 1

    Column {
        anchors.fill: parent
        anchors.margins: Theme.space.sm
        spacing: 3

        Label {
            text: root.label.toUpperCase()
            color: Theme.muted
            font.pixelSize: Theme.typography.body
            font.family: Theme.typography.mono
        }
        Label {
            text: String(root.value)
            color: root.accent
            elide: Text.ElideRight
            font.pixelSize: Theme.typography.title
            font.bold: true
        }
    }
}
