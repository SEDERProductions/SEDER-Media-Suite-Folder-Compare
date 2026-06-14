// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import Seder.UI

// Themed CheckBox. Replaces the three duplicated indicator definitions.
CheckBox {
    id: control

    font.family: Theme.typography.ui
    font.pixelSize: Theme.typography.label
    hoverEnabled: true

    indicator: Rectangle {
        implicitWidth: 18
        implicitHeight: 18
        x: control.leftPadding
        y: control.height / 2 - height / 2
        radius: Theme.radius.sm
        color: control.checked ? Theme.accent : Theme.panelAlt
        border.color: control.checked ? Theme.accentDark : (control.hovered ? Qt.lighter(Theme.line, 1.3) : Theme.line)
        border.width: 1

        Behavior on color {
            ColorAnimation {
                duration: Theme.motion.fast
            }
        }

        Icon {
            anchors.centerIn: parent
            name: "check"
            size: 13
            color: Theme.accentText
            opacity: control.checked ? 1 : 0
            scale: control.checked ? 1 : 0.6
            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.motion.fast
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Theme.motion.fast
                    easing.type: Theme.motion.easeEmphasized
                }
            }
        }

        // Keyboard focus ring.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: parent.radius + 2
            color: "transparent"
            border.width: 2
            border.color: Theme.focusRing
            visible: control.visualFocus
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
