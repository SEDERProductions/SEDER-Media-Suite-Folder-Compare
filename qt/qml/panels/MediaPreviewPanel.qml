// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Seder.UI

// Side-by-side A/B preview for the selected results row. Images render through
// the "thumb" async image provider; non-image / missing sides show a typed
// placeholder. (Dimensions / codec / duration metadata and audio waveforms are
// layered on in Phase E.2 via the media-probe FFI.)
Item {
    id: root

    // The selected tree node: { relPath, name, status, isFolder }.
    property var node: null

    readonly property string relPath: node ? (node.relPath || "") : ""
    readonly property string fileName: node ? (node.name || "") : ""
    readonly property int status: node && node.status !== undefined ? node.status : -1
    readonly property bool isFolder: node ? (node.isFolder === true) : false
    readonly property bool hasA: status === 0 || status === 1 || status === 2 || status === 4
    readonly property bool hasB: status === 0 || status === 1 || status === 3 || status === 4
    readonly property string absA: (hasA && folderController.folderA.length > 0 && relPath.length > 0) ? folderController.folderA + "/" + relPath : ""
    readonly property string absB: (hasB && folderController.folderB.length > 0 && relPath.length > 0) ? folderController.folderB + "/" + relPath : ""

    function isImage(path) {
        return /\.(png|jpe?g|gif|bmp|webp|tiff?)$/i.test(path);
    }

    // Empty / folder state.
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.node || root.isFolder
        width: Math.min(parent.width - 40, 280)
        spacing: Theme.space.sm
        Icon {
            Layout.alignment: Qt.AlignHCenter
            name: "eye"
            size: 40
            color: Theme.line
        }
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.isFolder ? qsTr("Folders have no preview.") : qsTr("Select a file in the results to preview A vs B.")
            color: Theme.faint
            font.pixelSize: Theme.typography.label
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space.sm
        visible: root.node && !root.isFolder
        spacing: Theme.space.sm

        Label {
            Layout.fillWidth: true
            text: root.fileName
            color: Theme.text
            font.family: Theme.typography.mono
            font.pixelSize: Theme.typography.label
            elide: Text.ElideMiddle
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.space.sm

            Repeater {
                model: [
                    {
                        "side": "A",
                        "path": root.absA,
                        "has": root.hasA
                    },
                    {
                        "side": "B",
                        "path": root.absB,
                        "has": root.hasB
                    }
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    readonly property bool showImage: modelData.has && root.isImage(modelData.path)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: Theme.space.xs

                    Label {
                        text: modelData.side
                        color: Theme.muted
                        font.family: Theme.typography.mono
                        font.pixelSize: Theme.typography.caption
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.bg
                        border.color: Theme.line
                        border.width: 1
                        radius: Theme.radius.sm
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: 4
                            visible: parent.parent.showImage
                            source: parent.parent.showImage ? ("image://thumb/" + encodeURIComponent(modelData.path)) : ""
                            sourceSize.width: 640
                            sourceSize.height: 640
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: !parent.parent.showImage
                            spacing: Theme.space.xs
                            Icon {
                                Layout.alignment: Qt.AlignHCenter
                                size: 30
                                color: Theme.faint
                                name: !modelData.has ? "close" : (root.isImage(modelData.path) ? "image" : "file")
                            }
                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                color: Theme.faint
                                font.pixelSize: Theme.typography.caption
                                text: !modelData.has ? qsTr("Not on this side") : qsTr("No preview")
                            }
                        }
                    }
                }
            }
        }
    }
}
