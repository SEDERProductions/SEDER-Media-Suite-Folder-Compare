// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Seder.UI

// A docked panel: a titled, framed surface that floats on the workspace gutter
// with a header (icon + title + optional collapse/float controls) and a content
// area. Place instances directly inside a SplitView; set the SplitView size
// hints on the instance. Children are assigned to the content area and should
// anchor-fill it (one root child per panel).
//
// "Float" tears the panel's content into a separate Window and shows a dock-back
// placeholder in the docked slot; closing the window (or "Dock back") returns it.
Item {
    id: root

    property string title: ""
    property string iconName: ""
    property bool collapsible: false
    property bool collapsed: false
    property bool floatable: false
    property bool floating: false
    readonly property int headerHeight: 32
    readonly property int collapsedSize: headerHeight + 2 * frame.anchors.margins

    default property alias content: contentHost.data
    // The single content root, captured so it can be reparented to the float
    // window and back.
    property Item contentItem: null

    signal floatRequested
    signal collapseToggled

    implicitWidth: 320
    implicitHeight: 200

    Component.onCompleted: {
        if (contentHost.children.length > 0)
            contentItem = contentHost.children[0];
    }

    onFloatingChanged: {
        if (!contentItem)
            return;
        contentItem.parent = floating ? floatHost : contentHost;
    }

    // Small square header control (collapse / float).
    component HeaderBtn: Item {
        id: hb
        property string glyph: ""
        signal clicked
        implicitWidth: 24
        implicitHeight: 24
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.sm
            color: hbMouse.containsMouse ? Theme.panel : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: Theme.motion.fast
                }
            }
        }
        Icon {
            anchors.centerIn: parent
            name: hb.glyph
            size: 14
            color: hbMouse.containsMouse ? Theme.text : Theme.muted
        }
        MouseArea {
            id: hbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hb.clicked()
        }
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        anchors.margins: 3
        radius: Theme.radius.md
        color: Theme.panel
        border.color: Theme.line
        border.width: 1
        clip: true

        Rectangle {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.headerHeight
            color: Theme.panelAlt
            radius: Theme.radius.md

            // Square off the header's bottom corners against the content area.
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: parent.radius
                color: Theme.panelAlt
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.line
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space.md
                anchors.rightMargin: Theme.space.xs
                spacing: Theme.space.xs

                Icon {
                    visible: root.iconName.length > 0
                    name: root.iconName
                    size: 13
                    color: Theme.muted
                    Layout.alignment: Qt.AlignVCenter
                }
                Label {
                    text: root.title
                    color: Theme.muted
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.caption
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    Layout.fillWidth: true
                }
                HeaderBtn {
                    visible: root.floatable && !root.floating
                    glyph: "external"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        root.floating = true;
                        root.floatRequested();
                    }
                }
                HeaderBtn {
                    visible: root.collapsible && !root.floating
                    glyph: root.collapsed ? "chevron-down" : "chevron-up"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        root.collapsed = !root.collapsed;
                        root.collapseToggled();
                    }
                }
            }
        }

        Item {
            id: contentHost
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            visible: !root.collapsed && !root.floating
        }

        // Placeholder shown in the docked slot while the panel is floating.
        ColumnLayout {
            anchors.centerIn: parent
            visible: root.floating
            spacing: Theme.space.sm
            Icon {
                Layout.alignment: Qt.AlignHCenter
                name: "external"
                size: 28
                color: Theme.faint
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Floating window")
                color: Theme.muted
                font.pixelSize: Theme.typography.label
            }
            AppButton {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Dock back")
                onClicked: root.floating = false
            }
        }
    }

    // Floating window host for this panel's content.
    Window {
        id: floatWindow
        title: "SEDER — " + root.title
        width: 640
        height: 460
        minimumWidth: 320
        minimumHeight: 200
        color: Theme.panel
        visible: root.floating
        onClosing: root.floating = false

        Rectangle {
            anchors.fill: parent
            color: Theme.panel

            Rectangle {
                id: floatHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.headerHeight
                color: Theme.panelAlt
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.line
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space.md
                    anchors.rightMargin: Theme.space.xs
                    spacing: Theme.space.xs
                    Icon {
                        visible: root.iconName.length > 0
                        name: root.iconName
                        size: 13
                        color: Theme.muted
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Label {
                        text: root.title
                        color: Theme.muted
                        font.family: Theme.typography.mono
                        font.pixelSize: Theme.typography.caption
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    HeaderBtn {
                        glyph: "panel-bottom"
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: root.floating = false
                    }
                }
            }

            Item {
                id: floatHost
                anchors.top: floatHeader.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
            }
        }
    }
}
