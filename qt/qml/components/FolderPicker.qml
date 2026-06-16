// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Seder.UI

// Folder chooser row: pick button, recent-folders dropdown, and a path field
// that also accepts a dropped folder. Extracted verbatim from Main.qml with
// theming routed through Theme and buttons routed through AppButton.
ColumnLayout {
    id: picker

    property string label
    property string path
    property var pickAction
    property var onDroppedFolder
    property var recentList: []
    property var useRecent
    property string validationError: ""

    Layout.fillWidth: true
    spacing: Theme.space.sm

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space.sm

        AppButton {
            text: picker.label
            enabled: !folderController.busy
            onClicked: picker.pickAction()
            Accessible.name: qsTr("Choose %1").arg(picker.label)
        }

        AppButton {
            id: recentButton
            iconName: "chevron-down"
            enabled: !folderController.busy && picker.recentList.length > 0
            Accessible.name: qsTr("Recent folders for %1").arg(picker.label)
            onClicked: recentMenu.popup()

            Menu {
                id: recentMenu
                Repeater {
                    model: picker.recentList
                    delegate: MenuItem {
                        required property string modelData
                        text: modelData
                        onTriggered: picker.useRecent(modelData)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: Theme.radius.md
            color: picker.path.length > 0 ? Theme.panelAlt : Theme.bg
            border.color: dragArea.containsDrag ? Theme.accent : Theme.line
            border.width: dragArea.containsDrag ? 2 : 1

            Label {
                anchors.fill: parent
                anchors.leftMargin: Theme.space.sm
                anchors.rightMargin: Theme.space.sm
                text: picker.path.length > 0 ? picker.path : qsTr("Drop folder here or click button")
                color: picker.path.length > 0 ? Theme.text : Theme.faint
                elide: Text.ElideMiddle
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.body
                verticalAlignment: Text.AlignVCenter

                ToolTip.visible: truncated && hoverArea.containsMouse
                ToolTip.text: picker.path
                ToolTip.delay: 500
            }

            MouseArea {
                id: hoverArea
                anchors.fill: parent
                hoverEnabled: true
            }

            DropArea {
                id: dragArea
                anchors.fill: parent
                enabled: !folderController.busy
                onDropped: function (drop) {
                    picker.validationError = "";
                    if (!drop.hasUrls || drop.urls.length === 0) {
                        picker.validationError = qsTr("Drop a folder from your file manager.");
                        return;
                    }

                    var accepted = false;
                    for (var i = 0; i < drop.urls.length; i++) {
                        var result = folderController.parseDroppedFolderUrl(drop.urls[i].toString());
                        if (result.path) {
                            picker.onDroppedFolder(result.path);
                            accepted = true;
                            break;
                        }
                    }

                    if (!accepted) {
                        picker.validationError = qsTr("Dropped item is not a valid folder path.");
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: picker.validationError.length > 0
            text: picker.validationError
            color: Theme.bad
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
