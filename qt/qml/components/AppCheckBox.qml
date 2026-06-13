// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import Seder.UI

// Themed CheckBox. Replaces the three duplicated indicator definitions.
CheckBox {
    id: control

    font.family: Theme.typography.ui
    font.pixelSize: Theme.typography.label

    indicator: Rectangle {
        implicitWidth: 18
        implicitHeight: 18
        x: control.leftPadding
        y: control.height / 2 - height / 2
        radius: Theme.radius.sm
        color: control.checked ? Theme.accent : Theme.panelAlt
        border.color: Theme.line
        border.width: 1

        Text {
            visible: control.checked
            anchors.centerIn: parent
            text: "✓"
            color: Theme.onAccent
            font.pixelSize: Theme.typography.body
        }
    }

    contentItem: Text {
        text: control.text
        color: control.enabled ? Theme.text : Theme.faint
        font: control.font
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
    }
}
