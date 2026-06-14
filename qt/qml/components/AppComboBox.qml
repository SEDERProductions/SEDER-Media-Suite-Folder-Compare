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

    background: Rectangle {
        radius: Theme.radius.md
        color: Theme.panelAlt
        border.color: Theme.line
        border.width: 1
    }

    indicator: Icon {
        name: "chevron-down"
        color: Theme.faint
        size: 14
        x: control.width - width - Theme.space.sm
        y: control.topPadding + (control.availableHeight - height) / 2
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
