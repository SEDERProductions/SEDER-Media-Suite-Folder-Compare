// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1320
    height: 860
    minimumWidth: 1040
    minimumHeight: 720
    visible: true
    title: "SEDER Media Suite Folder Compare"

    property bool darkMode: folderController.effectiveDark
    property int activeFilter: 0
    readonly property string monoFont: Qt.platform.os === "osx" ? "Menlo" : (Qt.platform.os === "windows" ? "Consolas" : "monospace")

    QtObject {
        id: colors
        readonly property color bg: darkMode ? "#12110f" : "#ece6d9"
        readonly property color panel: darkMode ? "#1f1d1a" : "#f8f4ea"
        readonly property color panelAlt: darkMode ? "#282521" : "#e3dccb"
        readonly property color rail: darkMode ? "#16140f" : "#2a261d"
        readonly property color text: darkMode ? "#ece6d9" : "#16140f"
        readonly property color muted: darkMode ? "#ada596" : "#4a4438"
        readonly property color faint: darkMode ? "#716a5f" : "#7a7363"
        readonly property color line: darkMode ? "#3b362e" : "#d6cfbe"
        readonly property color accent: "#c63b13"
        readonly property color accentDark: "#8a3a16"
        readonly property color good: darkMode ? "#4cab7e" : "#1f7a4d"
        readonly property color warn: "#a47a3a"
        readonly property color bad: darkMode ? "#d25645" : "#c63b13"
    }

    function statusColor(statusCode) {
        if (statusCode === 0) return colors.good
        if (statusCode === 1) return colors.bad
        if (statusCode === 2 || statusCode === 3) return colors.warn
        return colors.faint
    }

    function filterLabel(index) {
        return ["All", "Matching", "Changed", "Only A", "Only B", "Folders"][index]
    }

    color: colors.bg

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 86
            color: colors.rail

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 14

                Label {
                    text: "SEDER"
                    color: "#ece6d9"
                    font.pixelSize: 13
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    radius: 6
                    color: colors.accent
                    border.color: "#d8653e"
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "FC"
                            color: "#fff7ee"
                            font.pixelSize: 18
                            font.bold: true
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "COMPARE"
                            color: "#fff7ee"
                            font.pixelSize: 8
                            font.family: window.monoFont
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Label {
                    text: "LOCAL"
                    color: "#b8ae9b"
                    font.pixelSize: 10
                    font.family: window.monoFont
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 368
            color: colors.panel
            border.color: colors.line
            border.width: 1

            ScrollView {
                anchors.fill: parent
                anchors.margins: 16
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Label {
                            text: "SEDER Media Suite Folder Compare"
                            color: colors.text
                            font.pixelSize: 22
                            font.bold: true
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Label {
                            text: "VOL. 04 / FOLDER AUDIT"
                            color: colors.muted
                            font.pixelSize: 10
                            font.family: window.monoFont
                        }
                    }

                    Label {
                        text: "01 / FOLDERS"
                        color: colors.muted
                        font.pixelSize: 10
                        font.family: window.monoFont
                    }

                    FolderPicker {
                        label: "Folder A"
                        path: folderController.folderA
                        action: function() { folderController.chooseFolderA() }
                    }
                    FolderPicker {
                        label: "Folder B"
                        path: folderController.folderB
                        action: function() { folderController.chooseFolderB() }
                    }

                    Label {
                        text: "02 / COMPARE MODE"
                        color: colors.muted
                        font.pixelSize: 10
                        font.family: window.monoFont
                    }

                    ComboBox {
                        Layout.fillWidth: true
                        model: ["Path + size", "Path + size + modified time", "Path + size + checksum"]
                        currentIndex: folderController.mode
                        enabled: !folderController.busy
                        onActivated: folderController.mode = currentIndex
                    }

                    Label {
                        text: "03 / IGNORE"
                        color: colors.muted
                        font.pixelSize: 10
                        font.family: window.monoFont
                    }

                    CheckBox {
                        text: "Ignore hidden/system files"
                        checked: folderController.ignoreHiddenSystem
                        enabled: !folderController.busy
                        onToggled: folderController.ignoreHiddenSystem = checked
                    }

                    TextField {
                        Layout.fillWidth: true
                        text: folderController.ignorePatterns
                        enabled: !folderController.busy
                        selectByMouse: true
                        placeholderText: ".DS_Store, *.tmp"
                        font.family: window.monoFont
                        font.pixelSize: 12
                        onTextEdited: folderController.ignorePatterns = text
                    }

                    Label {
                        text: "04 / THEME"
                        color: colors.muted
                        font.pixelSize: 10
                        font.family: window.monoFont
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: ["system", "light", "dark"]
                            delegate: Button {
                                required property string modelData
                                Layout.fillWidth: true
                                text: modelData.toUpperCase()
                                checkable: true
                                checked: folderController.theme === modelData
                                onClicked: folderController.theme = modelData
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Button {
                            Layout.fillWidth: true
                            text: folderController.busy ? "Comparing..." : "Start Comparison"
                            enabled: !folderController.busy
                            onClicked: folderController.startComparison()
                            background: Rectangle {
                                radius: 5
                                color: parent.enabled ? colors.accent : colors.panelAlt
                                border.color: colors.accentDark
                            }
                            contentItem: Text {
                                text: parent.text
                                color: parent.enabled ? "#fff7ee" : colors.faint
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.bold: true
                            }
                        }
                        Button {
                            text: "Cancel"
                            enabled: folderController.busy
                            onClicked: folderController.cancelComparison()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Button {
                            Layout.fillWidth: true
                            text: "Export TXT"
                            enabled: !folderController.busy
                            onClicked: folderController.exportTxt()
                        }
                        Button {
                            Layout.fillWidth: true
                            text: "Export CSV"
                            enabled: !folderController.busy
                            onClicked: folderController.exportCsv()
                        }
                    }

                    Item { Layout.preferredHeight: 8 }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 118
                color: colors.bg
                border.color: colors.line
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        MetricBox { label: "Only A"; value: folderController.onlyACount; accent: colors.warn }
                        MetricBox { label: "Only B"; value: folderController.onlyBCount; accent: colors.warn }
                        MetricBox { label: "Changed"; value: folderController.changedCount; accent: colors.bad }
                        MetricBox { label: "Matching"; value: folderController.matchingCount; accent: colors.good }
                        MetricBox { label: "Folders"; value: folderController.folderDiffCount; accent: colors.faint }
                        MetricBox { label: "Size"; value: folderController.totalSizeText; accent: colors.faint }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: 6
                            delegate: Button {
                                required property int index
                                text: filterLabel(index)
                                checkable: true
                                checked: activeFilter === index
                                onClicked: {
                                    activeFilter = index
                                    folderController.setFilterMode(index)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: colors.bg

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 0

                    Row {
                        Layout.fillWidth: true
                        height: 30
                        Repeater {
                            model: ["Status", "Relative Path", "Size A", "Size B", "Checksum A", "Checksum B"]
                            delegate: Rectangle {
                                required property string modelData
                                required property int index
                                width: [110, 360, 80, 80, 200, 200][index]
                                height: 30
                                color: colors.panelAlt
                                border.color: colors.line
                                Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    text: modelData
                                    color: colors.muted
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 10
                                    font.family: window.monoFont
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TableView {
                            id: tableView
                            anchors.fill: parent
                            clip: true
                            model: folderController.filterModel
                            boundsBehavior: Flickable.StopAtBounds
                            columnSpacing: 0
                            rowSpacing: 0
                            columnWidthProvider: function(column) {
                                return [110, 360, 80, 80, 200, 200][column]
                            }
                            rowHeightProvider: function() { return 34 }

                            delegate: Rectangle {
                                required property int row
                                required property int column
                                required property string display
                                required property int statusCode
                                implicitWidth: tableView.columnWidthProvider(column)
                                implicitHeight: 34
                                color: row % 2 === 0 ? colors.panel : colors.panelAlt
                                border.color: colors.line
                                border.width: 1

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    text: display
                                    color: column === 0 ? statusColor(statusCode) : colors.text
                                    elide: column === 1 ? Text.ElideMiddle : Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 12
                                    font.family: column === 1 || column >= 4 ? window.monoFont : "Manrope"
                                }
                            }

                            ScrollBar.vertical: ScrollBar {}
                            ScrollBar.horizontal: ScrollBar {}
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: tableView.rows === 0
                            color: colors.bg
                            border.color: colors.line
                            border.width: 1
                            Label {
                                anchors.centerIn: parent
                                width: Math.min(parent.width - 80, 520)
                                text: folderController.busy ? "Comparison running." : "Choose two folders and start comparison."
                                color: colors.muted
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.pixelSize: 15
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 128
                color: colors.panel
                border.color: colors.line
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "STATUS"
                            color: colors.muted
                            font.pixelSize: 10
                            font.family: window.monoFont
                        }
                        Label {
                            Layout.fillWidth: true
                            text: folderController.statusText + "  /  " + folderController.progressText
                            color: colors.text
                            elide: Text.ElideMiddle
                            font.pixelSize: 12
                            font.family: window.monoFont
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: folderController.logEntries
                        delegate: Text {
                            required property string modelData
                            width: ListView.view.width
                            text: modelData
                            color: colors.faint
                            elide: Text.ElideMiddle
                            font.pixelSize: 11
                            font.family: window.monoFont
                        }
                    }
                }
            }
        }
    }

    component FolderPicker: ColumnLayout {
        property string label
        property string path
        property var action

        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Button {
                text: label
                enabled: !folderController.busy
                onClicked: action()
            }
            Label {
                Layout.fillWidth: true
                text: path.length > 0 ? path : "No folder selected"
                color: path.length > 0 ? colors.text : colors.faint
                elide: Text.ElideMiddle
                font.family: window.monoFont
                font.pixelSize: 11
            }
        }
    }

    component MetricBox: Rectangle {
        property string label
        property var value
        property color accent

        Layout.fillWidth: true
        Layout.preferredHeight: 48
        radius: 5
        color: colors.panel
        border.color: colors.line
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 3
            Label {
                text: label.toUpperCase()
                color: colors.muted
                font.pixelSize: 9
                font.family: window.monoFont
            }
            Label {
                text: String(value)
                color: accent
                elide: Text.ElideRight
                font.pixelSize: 17
                font.bold: true
            }
        }
    }
}
