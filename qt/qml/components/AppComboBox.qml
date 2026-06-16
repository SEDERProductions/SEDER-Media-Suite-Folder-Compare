// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import Seder.UI

// Themed ComboBox. Centralizes the background / popup / delegate styling that
// was duplicated for the compare-mode and profile selectors.
ComboBox {
    id: control

    font.family: Theme.typography.ui
    font.pixelSize: Theme.typography.label
    hoverEnabled: true

    background: Rectangle {
        radius: Theme.radius.md
        color: Theme.panelAlt
        border.color: (control.activeFocus || control.popup.visible) ? Theme.accent : (control.hovered ? Qt.lighter(Theme.line, 1.3) : Theme.line)
        border.width: 1
        Behavior on border.color {
            ColorAnimation {
                duration: Theme.motion.fast
            }
        }
    }

    indicator: Icon {
        name: "chevron-down"
        color: control.popup.visible ? Theme.accent : Theme.faint
        size: 14
        x: control.width - width - Theme.space.sm
        y: control.topPadding + (control.availableHeight - height) / 2
        rotation: control.popup.visible ? 180 : 0
        Behavior on rotation {
            NumberAnimation {
                duration: Theme.motion.fast
                easing.type: Theme.motion.easeStandard
            }
        }
    }

    contentItem: Text {
        text: control.displayText
        color: Theme.text
        font: control.font
        verticalAlignment: Text.AlignVCenter
        leftPadding: Theme.space.sm
        rightPadding: Theme.space.xl + Theme.space.xs
        elide: Text.ElideRight
    }

    delegate: ItemDelegate {
        width: control.width - Theme.space.sm
        contentItem: Text {
            text: modelData
            color: Theme.text
            font.pixelSize: Theme.typography.label
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: control.highlightedIndex === index ? Theme.accent : "transparent"
            radius: Theme.radius.sm
        }
        highlighted: control.highlightedIndex === index
    }

    popup: Popup {
        y: control.height
        width: control.width
        implicitHeight: contentItem.implicitHeight + 10
        padding: Theme.space.xs

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.delegateModel
            currentIndex: control.highlightedIndex
            ScrollBar.vertical: ScrollBar {}
        }

        background: Rectangle {
            radius: Theme.radius.md
            color: Theme.panel
            border.color: Theme.line
            border.width: 1
        }
    }
}
