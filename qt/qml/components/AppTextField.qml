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
    hoverEnabled: true
    placeholderTextColor: Theme.faint
    leftPadding: Theme.space.sm
    rightPadding: Theme.space.sm

    background: Rectangle {
        radius: Theme.radius.md
        color: Theme.panelAlt
        border.color: control.activeFocus ? Theme.accent : (control.hovered ? Qt.lighter(Theme.line, 1.3) : Theme.line)
        border.width: 1
        Behavior on border.color {
            ColorAnimation {
                duration: Theme.motion.fast
            }
        }
    }
}
