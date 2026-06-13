// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import Seder.UI

// Themed single-line text input with an accent focus border.
TextField {
    id: control

    color: Theme.text
    font.family: Theme.typography.ui
    font.pixelSize: Theme.typography.body
    selectByMouse: true
    placeholderTextColor: Theme.faint
    leftPadding: Theme.space.sm
    rightPadding: Theme.space.sm

    background: Rectangle {
        radius: Theme.radius.md
        color: Theme.panelAlt
        border.color: control.activeFocus ? Theme.accent : Theme.line
        border.width: 1
    }
}
