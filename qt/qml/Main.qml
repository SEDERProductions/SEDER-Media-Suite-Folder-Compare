// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1320
    height: 860
    minimumWidth: Qt.platform.os === "osx" ? 980 : 960
    minimumHeight: Qt.platform.os === "osx" ? 620 : 600
    visible: true
    title: "SEDER Folder Compare"

    property bool darkMode: folderController.effectiveDark
    property int activeFilter: 0
    readonly property string monoFont: Qt.platform.os === "osx" ? "Menlo" : (Qt.platform.os === "windows" ? "Consolas" : "monospace")
    readonly property string uiFont: "Manrope, Segoe UI, sans-serif"
    readonly property bool showChecksums: folderController.mode === 2
    readonly property real railWidthRatio: width < 1200 ? 0.34 : 0.3
    readonly property int leftRailWidth: Math.max(300, Math.min(420, Math.round(width * railWidthRatio)))

    QtObject {
        id: colors
        readonly property color bg: darkMode ? "#12110f" : "#ece6d9"
        readonly property color panel: darkMode ? "#1f1d1a" : "#f8f4ea"
        readonly property color panelAlt: darkMode ? "#282521" : "#e3dccb"
        readonly property color rail: darkMode ? "#16140f" : "#2a261d"
        readonly property color text: darkMode ? "#ece6d9" : "#16140f"
        readonly property color muted: darkMode ? "#c4bcad" : "#3f392e"
        readonly property color faint: darkMode ? "#948b7d" : "#5c5548"
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

    function statusText(statusCode) {
        if (statusCode === 0) return "\u2713 Matching"
        if (statusCode === 1) return "\u2717 Changed"
        if (statusCode === 2) return "\u25b8 Only A"
        if (statusCode === 3) return "\u25b8 Only B"
        if (statusCode === 4) return "Folder"
        return "Unknown"
    }

    function filterLabel(index) {
        return ["All", "Matching", "Changed", "Only A", "Only B", "Folders"][index]
    }

    function filterCount(index) {
        switch (index) {
            case 0: return folderController.totalRows
            case 1: return folderController.matchingCount
            case 2: return folderController.changedCount
            case 3: return folderController.onlyACount
            case 4: return folderController.onlyBCount
            case 5: return folderController.folderDiffCount
        }
        return 0
    }

    color: colors.bg

    readonly property bool isMac: Qt.platform.os === "osx"
    readonly property string openFolderBShortcut: isMac ? "Meta+Shift+O" : "Ctrl+Shift+O"
    readonly property string startShortcut: isMac ? "Meta+R" : "Ctrl+R"
    readonly property string exportTxtShortcut: isMac ? "Meta+Shift+T" : "Ctrl+Shift+T"
    readonly property string exportCsvShortcut: isMac ? "Meta+Shift+C" : "Ctrl+Shift+C"

    function hintText(shortcutText) {
        return isMac ? shortcutText.replace("Meta", "⌘") : shortcutText
    }

    // Keyboard shortcuts
    Shortcut { sequence: StandardKey.Open; onActivated: folderController.chooseFolderA() }
    Shortcut { sequence: window.openFolderBShortcut; onActivated: folderController.chooseFolderB() }
    Shortcut { sequence: StandardKey.Refresh; onActivated: folderController.startComparison() }
    Shortcut {
        sequence: StandardKey.Cancel
        enabled: folderController.busy
        onActivated: folderController.cancelComparison()
    }
    Shortcut { sequence: StandardKey.Save; onActivated: folderController.exportTxt() }
    Shortcut { sequence: StandardKey.SaveAs; onActivated: folderController.exportCsv() }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: window.leftRailWidth
            Layout.minimumWidth: 280
            visible: true
            color: colors.panel
            border.color: colors.line
            border.width: 1
            clip: true

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
                            text: "SEDER Folder Compare"
                            color: colors.text
                            font.pixelSize: 22
                            font.bold: true
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Label {
                            text: "v0.1.4"
                            color: colors.muted
                            font.pixelSize: 12
                            font.family: window.monoFont
                        }
                    }

                    Label {
                        text: "01 / FOLDERS"
                        color: colors.muted
                        font.pixelSize: 12
                        font.family: window.monoFont
                    }

                    FolderPicker {
                        label: "Folder A"
                        path: folderController.folderA
                        action: function() { folderController.chooseFolderA() }
                        onDroppedFolder: function(folder) { folderController.folderA = folder }
                    }
                    FolderPicker {
                        label: "Folder B"
                        path: folderController.folderB
                        action: function() { folderController.chooseFolderB() }
                        onDroppedFolder: function(folder) { folderController.folderB = folder }
                    }

                    Label {
                        text: "Open A: " + window.hintText("Ctrl+O") + "  •  Open B: " + window.hintText(window.openFolderBShortcut)
                        color: colors.muted
                        font.pixelSize: 11
                        font.family: window.monoFont
                    }

                    Label {
                        text: "02 / COMPARE MODE"
                        color: colors.muted
                        font.pixelSize: 12
                        font.family: window.monoFont
                    }

                    ComboBox {
                        id: modeCombo
                        Layout.fillWidth: true
                        model: ["Path + size", "Path + size + modified time", "Path + size + checksum"]
                        currentIndex: folderController.mode
                        enabled: !folderController.busy
                        onActivated: folderController.mode = currentIndex

                        contentItem: Text {
                            text: modeCombo.displayText
                            color: colors.text
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 8
                        }

                        background: Rectangle {
                            radius: 5
                            color: colors.panelAlt
                            border.color: colors.line
                            border.width: 1
                        }

                        popup: Popup {
                            y: modeCombo.height
                            width: modeCombo.width
                            implicitHeight: contentItem.implicitHeight + 10
                            padding: 4

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: modeCombo.delegateModel
                                currentIndex: modeCombo.highlightedIndex
                                ScrollBar.vertical: ScrollBar {}
                            }

                            background: Rectangle {
                                radius: 5
                                color: colors.panel
                                border.color: colors.line
                                border.width: 1
                            }
                        }

                        delegate: ItemDelegate {
                            width: modeCombo.width - 8
                            contentItem: Text {
                                text: modelData
                                color: colors.text
                                font.pixelSize: 13
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: modeCombo.highlightedIndex === index ? colors.accent : "transparent"
                                radius: 3
                            }
                        }
                    }

                    Label {
                        text: "03 / IGNORE"
                        color: colors.muted
                        font.pixelSize: 12
                        font.family: window.monoFont
                    }

                    CheckBox {
                        id: hiddenCheck
                        text: "Ignore hidden/system files"
                        checked: folderController.ignoreHiddenSystem
                        enabled: !folderController.busy
                        onToggled: folderController.ignoreHiddenSystem = checked

                        contentItem: Text {
                            text: hiddenCheck.text
                            color: colors.text
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: hiddenCheck.indicator.width + hiddenCheck.spacing
                        }

                        indicator: Rectangle {
                            implicitWidth: 18
                            implicitHeight: 18
                            x: hiddenCheck.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 3
                            color: hiddenCheck.checked ? colors.accent : colors.panelAlt
                            border.color: colors.line
                            border.width: 1

                            Text {
                                visible: hiddenCheck.checked
                                anchors.centerIn: parent
                                text: "\u2713"
                                color: "#fff"
                                font.pixelSize: 12
                            }
                        }
                    }

                    TextField {
                        id: ignoreField
                        Layout.fillWidth: true
                        text: folderController.ignorePatterns
                        enabled: !folderController.busy
                        selectByMouse: true
                        placeholderText: ".DS_Store, *.tmp"
                        font.family: window.monoFont
                        font.pixelSize: 12
                        color: colors.text
                        onTextEdited: folderController.ignorePatterns = text

                        background: Rectangle {
                            radius: 5
                            color: colors.panelAlt
                            border.color: ignoreField.focus ? colors.accent : colors.line
                            border.width: 1
                        }
                    }

                    Label {
                        text: "04 / THEME"
                        color: colors.muted
                        font.pixelSize: 12
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

                                background: Rectangle {
                                    radius: 5
                                    color: parent.checked ? colors.accent : colors.panelAlt
                                    border.color: parent.checked ? colors.accentDark : colors.line
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: parent.checked ? "#fff7ee" : colors.text
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Button {
                            Layout.fillWidth: true
                            text: folderController.busy ? "Cancel Comparison (Esc)" : "Start Comparison (" + window.hintText(window.startShortcut) + ")"
                            onClicked: folderController.busy ? folderController.cancelComparison() : folderController.startComparison()
                            background: Rectangle {
                                radius: 5
                                color: folderController.busy ? colors.panelAlt : colors.accent
                                border.color: folderController.busy ? colors.line : colors.accentDark
                                border.width: 1
                            }
                            contentItem: Text {
                                text: parent.text
                                color: folderController.busy ? colors.faint : "#fff7ee"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.bold: true
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Button {
                            Layout.fillWidth: true
                            text: "Export TXT (" + window.hintText(window.exportTxtShortcut) + ")"
                            enabled: folderController.hasReport && !folderController.busy
                            onClicked: folderController.exportTxt()
                            background: Rectangle {
                                radius: 5
                                color: parent.enabled ? colors.panelAlt : colors.bg
                                border.color: parent.enabled ? colors.line : colors.bg
                                border.width: 1
                            }
                            contentItem: Text {
                                text: parent.text
                                color: parent.enabled ? colors.text : colors.faint
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            ToolTip.visible: hovered && !enabled
                            ToolTip.text: "Run a comparison first"
                        }
                        Button {
                            Layout.fillWidth: true
                            text: "Export CSV (" + window.hintText(window.exportCsvShortcut) + ")"
                            enabled: folderController.hasReport && !folderController.busy
                            onClicked: folderController.exportCsv()
                            background: Rectangle {
                                radius: 5
                                color: parent.enabled ? colors.panelAlt : colors.bg
                                border.color: parent.enabled ? colors.line : colors.bg
                                border.width: 1
                            }
                            contentItem: Text {
                                text: parent.text
                                color: parent.enabled ? colors.text : colors.faint
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            ToolTip.visible: hovered && !enabled
                            ToolTip.text: "Run a comparison first"
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
                Layout.preferredHeight: Math.max(metricsPanel.implicitHeight + 24, window.height * 0.2)
                Layout.minimumHeight: metricsPanel.implicitHeight + 24
                color: colors.bg
                border.color: colors.line
                border.width: 1

                ColumnLayout {
                    id: metricsPanel
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
                        MetricBox { label: "Scanned"; value: folderController.totalSizeText; accent: colors.faint }
                    }

                    ProgressBar {
                        Layout.fillWidth: true
                        visible: folderController.busy
                        from: 0
                        to: folderController.progressTotal > 0 ? folderController.progressTotal : 100
                        value: folderController.progressTotal > 0 ? folderController.progressCurrent : 0
                        background: Rectangle {
                            radius: 3
                            color: colors.panelAlt
                            border.color: colors.line
                            border.width: 1
                        }
                        contentItem: Rectangle {
                            radius: 3
                            color: colors.accent
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: 6
                            delegate: Button {
                                required property int index
                                Layout.fillWidth: true
                                text: filterLabel(index) + (filterCount(index) > 0 ? " (" + filterCount(index) + ")" : "")
                                checkable: true
                                checked: activeFilter === index
                                enabled: filterCount(index) > 0 || index === 0
                                onClicked: {
                                    activeFilter = index
                                    folderController.setFilterMode(index)
                                }
                                background: Rectangle {
                                    radius: 5
                                    color: parent.checked ? colors.accent : colors.panelAlt
                                    border.color: parent.checked ? colors.accentDark : colors.line
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: parent.enabled ? (parent.checked ? "#fff7ee" : colors.text) : colors.faint
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 12
                                }
                                ToolTip.visible: hovered && !enabled
                                ToolTip.text: "No results for this filter"
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
                            model: ["Status", "Relative Path", "Size A", "Size B", showChecksums ? "Checksum A" : "", showChecksums ? "Checksum B" : ""]
                            delegate: Rectangle {
                                required property string modelData
                                required property int index
                                width: modelData === "" ? 0 : columnWidths[index]
                                height: 30
                                visible: modelData !== ""
                                color: colors.panelAlt
                                border.color: colors.line
                                border.width: 1
                                Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    text: modelData
                                    color: colors.muted
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 12
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
                                return columnWidths[column]
                            }
                            rowHeightProvider: function() { return 34 }

                            delegate: Rectangle {
                                required property int row
                                required property int column
                                required property string display
                                required property int statusCode
                                readonly property bool hovered: mouseArea.containsMouse
                                readonly property color baseColor: row % 2 === 0 ? colors.panel : colors.panelAlt
                                readonly property color hoverColor: darkMode ? Qt.lighter(baseColor, 1.08) : Qt.darker(baseColor, 1.05)
                                implicitWidth: tableView.columnWidthProvider(column)
                                implicitHeight: 34
                                color: hovered ? hoverColor : baseColor
                                border.color: colors.line
                                border.width: 1

                                Behavior on color {
                                    ColorAnimation { duration: 90 }
                                }

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    text: column === 0 ? statusText(statusCode) : display
                                    color: column === 0 ? statusColor(statusCode) : colors.text
                                    elide: column === 1 ? Text.ElideMiddle : Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 12
                                    font.family: column === 1 || column >= 4 ? window.monoFont : window.uiFont

                                    ToolTip.visible: truncated && mouseArea.containsMouse
                                    ToolTip.text: text
                                    ToolTip.delay: 500
                                }

                                MouseArea {
                                    id: mouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
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
                                text: folderController.busy ? "Comparison running..." : "Choose two folders and start comparison."
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
                Layout.preferredHeight: Math.max(statusPanel.implicitHeight + 24, window.height * 0.13)
                Layout.minimumHeight: statusPanel.implicitHeight + 24
                color: colors.panel
                border.color: colors.line
                border.width: 1

                ColumnLayout {
                    id: statusPanel
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Label {
                            text: "STATUS"
                            color: colors.muted
                            font.pixelSize: 12
                            font.family: window.monoFont
                        }
                        Label {
                            Layout.fillWidth: true
                            text: folderController.statusText + "  /  " + folderController.progressText
                            color: colors.text
                            elide: Text.ElideMiddle
                            font.pixelSize: 12
                            font.family: window.monoFont
                            activeFocusOnTab: true

                            ToolTip.visible: (hoverArea.containsMouse || activeFocus) && truncated
                            ToolTip.text: text
                            ToolTip.delay: 300

                            HoverHandler {
                                id: hoverArea
                            }
                        }
                        Button {
                            text: "Clear"
                            onClicked: folderController.clearLog()
                            background: Rectangle {
                                radius: 4
                                color: parent.down ? colors.accentDark : colors.panelAlt
                                border.color: colors.line
                                border.width: 1
                            }
                            contentItem: Text {
                                text: parent.text
                                color: colors.muted
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 12
                            }
                        }
                    }

                    ListView {
                        id: logView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: folderController.logEntries
                        spacing: 4
                        property bool autoScrollToLatest: true

                        onMovementStarted: {
                            if (!atYEnd) {
                                autoScrollToLatest = false
                            }
                        }
                        onMovementEnded: {
                            if (atYEnd) {
                                autoScrollToLatest = true
                            }
                        }
                        onCountChanged: {
                            if (autoScrollToLatest && count > 0) {
                                positionViewAtBeginning()
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AlwaysOn
                        }

                        delegate: Rectangle {
                            required property string modelData
                            width: ListView.view.width
                            radius: 3
                            color: modelData.indexOf("[ERROR]") >= 0
                                   ? (window.isDark ? "#3b2323" : "#f9e8e8")
                                   : (modelData.indexOf("[WARN]") >= 0
                                       ? (window.isDark ? "#3a321f" : "#fcf6df")
                                       : "transparent")

                            implicitHeight: logText.implicitHeight + 6

                            Text {
                                id: logText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                text: modelData
                                color: modelData.indexOf("[ERROR]") >= 0
                                       ? (window.isDark ? "#ff9e9e" : "#8a1c1c")
                                       : (modelData.indexOf("[WARN]") >= 0
                                           ? (window.isDark ? "#ffd88a" : "#7a5a0f")
                                           : colors.text)
                                elide: Text.ElideRight
                                font.pixelSize: 11
                                font.family: window.monoFont
                            }
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
        property var onDroppedFolder

        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                text: label
                enabled: !folderController.busy
                onClicked: action()
                background: Rectangle {
                    radius: 5
                    color: parent.down ? colors.accentDark : colors.panelAlt
                    border.color: colors.line
                    border.width: 1
                }
                contentItem: Text {
                    text: parent.text
                    color: colors.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 12
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 5
                color: path.length > 0 ? colors.panelAlt : colors.bg
                border.color: dragArea.containsDrag ? colors.accent : colors.line
                border.width: dragArea.containsDrag ? 2 : 1

                Label {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    text: path.length > 0 ? path : "Drop folder here or click button"
                    color: path.length > 0 ? colors.text : colors.faint
                    elide: Text.ElideMiddle
                    font.family: window.monoFont
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter

                    ToolTip.visible: truncated && hoverArea.containsMouse
                    ToolTip.text: path
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
                    onDropped: function(drop) {
                        if (drop.hasUrls) {
                            for (var i = 0; i < drop.urls.length; i++) {
                                var url = drop.urls[i]
                                if (url.startsWith("file:///")) {
                                    var localPath = url.substring(8)
                                    if (Qt.platform.os === "windows" && localPath.startsWith("/")) {
                                        localPath = localPath.substring(1)
                                    }
                                    onDroppedFolder(localPath)
                                    break
                                }
                            }
                        }
                    }
                }
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
                font.pixelSize: 12
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

    property var columnWidths: showChecksums ? [110, 320, 80, 80, 170, 170] : [110, 400, 100, 100, 0, 0]
}
