// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import Seder.UI

// The single themed button used across the app. Replaces ~15 inline Button
// background/contentItem definitions. Variants map to the prior ad-hoc styles:
//   Primary   – accent fill (Start, primary dialog actions)
//   Secondary – panelAlt fill with line border (default)
//   Ghost     – transparent until pressed
//   Danger    – destructive accent (bad)
Button {
    id: control

    enum Variant {
        Primary,
        Secondary,
        Ghost,
        Danger
    }

    property int variant: AppButton.Secondary
    property bool mono: false
    // When true, a disabled button recedes into the window background instead
    // of keeping its panel surface (matches the prior export/copy/move look).
    property bool flatDisabled: false
    // Reserved for Phase B iconography; ignored until Icon.qml exists.
    property string iconName: ""

    readonly property bool _accentFill: variant === AppButton.Primary || (checkable && checked)
    readonly property bool _danger: variant === AppButton.Danger
    readonly property color _contentColor: !control.enabled ? Theme.faint : ((control._accentFill || control._danger) ? Theme.accentText : Theme.text)

    font.family: control.mono ? Theme.typography.mono : Theme.typography.ui
    font.pixelSize: Theme.typography.body
    hoverEnabled: true

    background: Rectangle {
        radius: Theme.radius.md
        color: {
            if (!control.enabled)
                return control.flatDisabled ? Theme.bg : Theme.panelAlt;
            if (control._accentFill)
                return control.down ? Theme.accentDark : Theme.accent;
            if (control._danger)
                return control.down ? Qt.darker(Theme.bad, 1.15) : Theme.bad;
            if (control.variant === AppButton.Ghost)
                return control.down ? Theme.panelAlt : "transparent";
            return control.down ? Theme.accentDark : Theme.panelAlt;
        }
        border.width: 1
        border.color: {
            if (!control.enabled)
                return control.flatDisabled ? Theme.bg : Theme.line;
            if (control._accentFill || control._danger)
                return Theme.accentDark;
            if (control.variant === AppButton.Ghost)
                return "transparent";
            return Theme.line;
        }
    }

    contentItem: Item {
        implicitWidth: control.iconName.length > 0 ? iconRow.implicitWidth : plainText.implicitWidth
        implicitHeight: control.iconName.length > 0 ? iconRow.implicitHeight : plainText.implicitHeight

        // Icon-less buttons keep the original fill-and-elide centering.
        Text {
            id: plainText
            visible: control.iconName.length === 0
            anchors.fill: parent
            text: control.text
            color: control._contentColor
            font: control.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        // Icon buttons center the icon+label group.
        Row {
            id: iconRow
            visible: control.iconName.length > 0
            anchors.centerIn: parent
            spacing: Theme.space.xs

            Icon {
                name: control.iconName
                color: control._contentColor
                size: 15
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: control.text.length > 0
                text: control.text
                color: control._contentColor
                font: control.font
                verticalAlignment: Text.AlignVCenter
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
