// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: window
    width: Screen ? Math.min(1320, Screen.desktopAvailableWidth * 0.9) : 1320
    height: Screen ? Math.min(860, Screen.desktopAvailableHeight * 0.9) : 860
    minimumWidth: Qt.platform.os === "osx" ? 980 : 960
    minimumHeight: Qt.platform.os === "osx" ? 620 : 600
    visible: true
    title: "SEDER Folder Compare"
    x: Screen ? (Screen.desktopAvailableWidth - width) / 2 : 0
    y: Screen ? (Screen.desktopAvailableHeight - height) / 2 : 0

    property bool darkMode: folderController.effectiveDark
    property int activeFilter: 0
    readonly property string monoFont: Qt.platform.os === "osx" ? "Menlo" : (Qt.platform.os === "windows" ? "Consolas" : "monospace")
    readonly property string uiFont: "Manrope, Segoe UI, sans-serif"
    readonly property bool showChecksums: folderController.mode === 2
    readonly property real railWidthRatio: width < 1200 ? 0.34 : 0.3
    readonly property int leftRailWidth: Math.max(300, Math.min(420, Math.round(width * railWidthRatio)))
    readonly property string appVersionLabel: Qt.application.version && Qt.application.version.length > 0 ? Qt.application.version : ""

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
                id: sidebarScroll
                anchors.fill: parent
                anchors.margins: 16
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: sidebarScroll.availableWidth
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
                            text: "v" + Qt.application.version
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
                        label: qsTr("Folder A")
                        path: folderController.folderA
                        pickAction: function() { folderController.chooseFolderA() }
                        onDroppedFolder: function(folder) { folderController.folderA = folder }
                        recentList: folderController.recentFoldersA
                        useRecent: function(folder) { folderController.useRecentFolderA(folder) }
                    }
                    FolderPicker {
                        label: qsTr("Folder B")
                        path: folderController.folderB
                        pickAction: function() { folderController.chooseFolderB() }
                        onDroppedFolder: function(folder) { folderController.folderB = folder }
                        recentList: folderController.recentFoldersB
                        useRecent: function(folder) { folderController.useRecentFolderB(folder) }
                    }

                    Label {
                        text: "Open A: " + window.hintText("Ctrl+O") + "  •  Open B: " + window.hintText(window.openFolderBShortcut)
                        color: colors.muted
                        font.pixelSize: 11
                        font.family: window.monoFont
                    }

                    // ── Profiles ──────────────────────────────────────────────
                    Label {
                        text: qsTr("PROFILES")
                        color: colors.muted
                        font.pixelSize: 12
                        font.family: window.monoFont
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        ComboBox {
                            id: profileCombo
                            Layout.fillWidth: true
                            model: folderController.listProfiles()
                            enabled: !folderController.busy && model.length > 0
                            displayText: model.length > 0 ? (currentText || qsTr("Select…")) : qsTr("(none saved)")
                            Accessible.name: qsTr("Saved profile")

                            background: Rectangle {
                                radius: 5
                                color: colors.panelAlt
                                border.color: colors.line
                                border.width: 1
                            }
                            contentItem: Text {
                                text: profileCombo.displayText
                                color: colors.text
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                            }
                            onActivated: function() {
                                if (currentText.length > 0) {
                                    folderController.loadProfile(currentText)
                                }
                            }
                        }

                        Button {
                            text: qsTr("Save…")
                            enabled: !folderController.busy
                            Accessible.name: qsTr("Save current settings as a profile")
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
                            onClicked: profileSaveDialog.open()
                        }

                        Button {
                            text: "✕"
                            enabled: !folderController.busy && profileCombo.currentText.length > 0
                            Accessible.name: qsTr("Delete profile")
                            background: Rectangle {
                                radius: 5
                                color: parent.down ? colors.accentDark : colors.panelAlt
                                border.color: colors.line
                                border.width: 1
                            }
                            contentItem: Text {
                                text: parent.text
                                color: parent.enabled ? colors.text : colors.faint
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 12
                            }
                            onClicked: {
                                folderController.deleteProfile(profileCombo.currentText)
                                profileCombo.model = folderController.listProfiles()
                            }
                        }
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
                        Accessible.name: qsTr("Comparison mode")
                        model: [
                            qsTr("Path + size"),
                            qsTr("Path + size + modified time"),
                            qsTr("Path + size + checksum"),
                            qsTr("Media metadata (dimensions / duration / codec)"),
                            qsTr("Perceptual hash (similar images)")
                        ]
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
                        text: qsTr("Ignore hidden/system files")
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

                    CheckBox {
                        id: followSymlinksCheck
                        text: qsTr("Follow symlinks")
                        checked: folderController.followSymlinks
                        enabled: !folderController.busy
                        onToggled: folderController.followSymlinks = checked

                        contentItem: Text {
                            text: followSymlinksCheck.text
                            color: colors.text
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: followSymlinksCheck.indicator.width + followSymlinksCheck.spacing
                        }

                        indicator: Rectangle {
                            implicitWidth: 18
                            implicitHeight: 18
                            x: followSymlinksCheck.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 3
                            color: followSymlinksCheck.checked ? colors.accent : colors.panelAlt
                            border.color: colors.line
                            border.width: 1
                            Text {
                                visible: followSymlinksCheck.checked
                                anchors.centerIn: parent
                                text: "\u2713"
                                color: "#fff"
                                font.pixelSize: 12
                            }
                        }
                    }

                    CheckBox {
                        id: detectRenamesCheck
                        text: qsTr("Detect renames")
                        checked: folderController.detectRenames
                        enabled: !folderController.busy
                        onToggled: folderController.detectRenames = checked

                        contentItem: Text {
                            text: detectRenamesCheck.text
                            color: colors.text
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: detectRenamesCheck.indicator.width + detectRenamesCheck.spacing
                        }

                        indicator: Rectangle {
                            implicitWidth: 18
                            implicitHeight: 18
                            x: detectRenamesCheck.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 3
                            color: detectRenamesCheck.checked ? colors.accent : colors.panelAlt
                            border.color: colors.line
                            border.width: 1
                            Text {
                                visible: detectRenamesCheck.checked
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
                                Layout.preferredWidth: 1
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
                                    elide: Text.ElideRight
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
                            text: folderController.busy ? qsTr("Cancel Comparison (Esc)") : qsTr("Start Comparison") + " (" + window.hintText(window.startShortcut) + ")"
                            Accessible.name: folderController.busy ? qsTr("Cancel the running comparison") : qsTr("Start a new comparison")
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
                            Layout.preferredWidth: 1
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
                                elide: Text.ElideRight
                            }
                            ToolTip.visible: hovered && !enabled
                            ToolTip.text: "Run a comparison first"
                        }
                        Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
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
                                elide: Text.ElideRight
                            }
                            ToolTip.visible: hovered && !enabled
                            ToolTip.text: "Run a comparison first"
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: qsTr("Sync planner…")
                        enabled: folderController.hasReport && !folderController.busy
                        Accessible.name: qsTr("Open the sync planner")
                        onClicked: {
                            syncDialog.rebuild()
                            syncDialog.open()
                        }
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
                        ToolTip.text: qsTr("Run a comparison first")
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

                    RowLayout {
                        Layout.fillWidth: true
                        visible: folderController.busy
                        spacing: 8

                        ProgressBar {
                            Layout.fillWidth: true
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

                        Text {
                            text: folderController.etaText
                            visible: folderController.etaText.length > 0
                            color: colors.faint
                            font.pixelSize: 12
                            font.family: window.monoFont
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
                                Accessible.name: qsTr("Filter: %1").arg(filterLabel(index))
                                Accessible.checkable: true
                                Accessible.checked: checked
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

                    Rectangle { Layout.fillWidth: true; height: 1; color: colors.line }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: folderController.hasSelection || folderController.canUndo

                        Button {
                            Layout.fillWidth: true
                            text: "\u25C0 Copy to A"
                            enabled: folderController.canCopyToA
                            onClicked: folderController.copySelectedToA()
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
                                font.pixelSize: 12
                                font.family: window.monoFont
                            }
                            ToolTip.visible: hovered && !enabled
                            ToolTip.text: "Select items with content in B to copy to A"
                        }
                        Button {
                            Layout.fillWidth: true
                            text: "Copy to B \u25B6"
                            enabled: folderController.canCopyToB
                            onClicked: folderController.copySelectedToB()
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
                                font.pixelSize: 12
                                font.family: window.monoFont
                            }
                            ToolTip.visible: hovered && !enabled
                            ToolTip.text: "Select items with content in A to copy to B"
                        }
                        Button {
                            Layout.fillWidth: true
                            text: "\u25C0 Move to A"
                            enabled: folderController.canMoveToA
                            onClicked: folderController.moveSelectedToA()
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
                                font.pixelSize: 12
                                font.family: window.monoFont
                            }
                            ToolTip.visible: hovered && !enabled
                            ToolTip.text: "Copy selected items from B to A, then delete originals"
                        }
                        Button {
                            Layout.fillWidth: true
                            text: "Move to B \u25B6"
                            enabled: folderController.canMoveToB
                            onClicked: folderController.moveSelectedToB()
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
                                font.pixelSize: 12
                                font.family: window.monoFont
                            }
                            ToolTip.visible: hovered && !enabled
                            ToolTip.text: "Copy selected items from A to B, then delete originals"
                        }
                        Button {
                            Layout.fillWidth: true
                            text: "Undo"
                            enabled: folderController.canUndo
                            onClicked: folderController.undoLastTransfer()
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
                                font.pixelSize: 12
                                font.family: window.monoFont
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
                    anchors.margins: 0
                    spacing: 0

                    Row {
                        Layout.fillWidth: true
                        height: 30
                        Rectangle { width: 30; height: 30; color: colors.panelAlt; border.color: colors.line; border.width: 1 }
                        Rectangle {
                            width: parent.width - 250; height: 30; color: colors.panelAlt
                            border.color: colors.line; border.width: 1
                            Label {
                                anchors.fill: parent; anchors.leftMargin: 8; text: "Name"
                                color: colors.muted; verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 12; font.family: window.monoFont
                            }
                        }
                        Rectangle { width: 80; height: 30; color: colors.panelAlt; border.color: colors.line; border.width: 1
                            Label { anchors.fill: parent; anchors.leftMargin: 8; text: "Size A"
                                color: colors.muted; verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 12; font.family: window.monoFont }
                        }
                        Rectangle { width: 80; height: 30; color: colors.panelAlt; border.color: colors.line; border.width: 1
                            Label { anchors.fill: parent; anchors.leftMargin: 8; text: "Size B"
                                color: colors.muted; verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 12; font.family: window.monoFont }
                        }
                        Rectangle { width: 90; height: 30; color: colors.panelAlt; border.color: colors.line; border.width: 1
                            Label { anchors.fill: parent; anchors.leftMargin: 8; text: "Status"
                                color: colors.muted; verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 12; font.family: window.monoFont }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListView {
                            id: treeView
                            anchors.fill: parent
                            clip: true
                            model: treeModel.flatItems
                            boundsBehavior: Flickable.StopAtBounds
                            spacing: 0

                            delegate: Rectangle {
                                required property int index
                                required property var modelData
                                readonly property var node: modelData
                                readonly property bool hovered: rowMouse.containsMouse
                                readonly property color baseColor: index % 2 === 0 ? colors.panel : colors.panelAlt
                                readonly property color hoverColor: window.darkMode ? Qt.lighter(baseColor, 1.08) : Qt.darker(baseColor, 1.05)
                                implicitWidth: treeView.width
                                implicitHeight: 30
                                color: hovered ? hoverColor : baseColor
                                border.color: colors.line
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 90 } }

                                Row {
                                    anchors.fill: parent

                                    Item {
                                        width: 30; height: parent.height
                                        Text {
                                            anchors.centerIn: parent
                                            text: node.isFolder ? (node.expanded ? "\u25BC" : "\u25B6") : ""
                                            color: colors.muted
                                            font.pixelSize: 10
                                            visible: node.isFolder && node.children.length > 0
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: node.isFolder && node.children.length > 0
                                            onClicked: treeModel.toggleExpanded(node.relPath)
                                        }
                                    }

                                    Item {
                                        width: parent.width - 250; height: parent.height
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 6; spacing: 4
                                            Rectangle {
                                                width: 10; height: 10; radius: 5
                                                Layout.alignment: Qt.AlignVCenter
                                                color: {
                                                    var s = node.aggregateStatus !== undefined ? node.aggregateStatus : node.status
                                                    if (s === 0) return colors.good
                                                    if (s === 1) return colors.bad
                                                    if (s === 2 || s === 4) return colors.warn
                                                    if (s === 3 || s === 5) return "#a47a3a"
                                                    return colors.faint
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: node.name
                                                color: colors.text
                                                elide: Text.ElideMiddle
                                                verticalAlignment: Text.AlignVCenter
                                                font.pixelSize: 12
                                                font.family: window.monoFont
                                                leftPadding: node.depth * 16
                                            }
                                        }
                                    }

                                    Rectangle { width: 80; height: parent.height; color: "transparent"
                                        Text {
                                            anchors.fill: parent; anchors.leftMargin: 8
                                            text: node.sizeA || ""
                                            color: node.sizeA ? colors.text : colors.faint
                                            elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                                            font.pixelSize: 11; font.family: window.monoFont
                                        }
                                    }

                                    Rectangle { width: 80; height: parent.height; color: "transparent"
                                        Text {
                                            anchors.fill: parent; anchors.leftMargin: 8
                                            text: node.sizeB || ""
                                            color: node.sizeB ? colors.text : colors.faint
                                            elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                                            font.pixelSize: 11; font.family: window.monoFont
                                        }
                                    }

                                    Rectangle { width: 90; height: parent.height; color: "transparent"
                                        Text {
                                            anchors.fill: parent; anchors.leftMargin: 6
                                            text: {
                                                var s = node.status
                                                if (s === 0) return "\u2713 Match"
                                                if (s === 1) return "\u2717 Changed"
                                                if (s === 2) return "\u25B8 Only A"
                                                if (s === 3) return "\u25B8 Only B"
                                                if (s === 4) return "Folder (A)"
                                                if (s === 5) return "Folder (B)"
                                                return ""
                                            }
                                            color: {
                                                var s = node.status
                                                if (s === 0) return colors.good
                                                if (s === 1) return colors.bad
                                                if (s >= 2) return colors.warn
                                                return colors.faint
                                            }
                                            elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                                            font.pixelSize: 11; font.family: window.monoFont
                                        }
                                    }
                                }

                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: function(mouse) {
                                        if (node.isFolder && node.children.length > 0) {
                                            treeModel.toggleExpanded(node.relPath)
                                        }
                                        if (mouse.button === Qt.RightButton) {
                                            contextMenu.targetRelPath = node.relPath
                                            contextMenu.targetIsFolder = node.isFolder
                                            contextMenu.targetHasA = node.status === 0 || node.status === 1 || node.status === 2 || node.status === 4
                                            contextMenu.targetHasB = node.status === 0 || node.status === 1 || node.status === 3 || node.status === 4
                                            contextMenu.popup()
                                        }
                                    }
                                }
                            }

                            ScrollBar.vertical: ScrollBar {}
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: treeModel.flatItems.length === 0
                            color: colors.bg
                            border.color: colors.line; border.width: 1
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

    // ── Context menu ─────────────────────────────────────────────────────

    Menu {
        id: contextMenu
        title: qsTr("Actions")

        property string targetRelPath: ""
        property bool targetIsFolder: false
        property bool targetHasA: false
        property bool targetHasB: false

        function pathA() {
            if (!targetRelPath || !folderController.folderA) return "";
            return folderController.folderA + "/" + targetRelPath;
        }
        function pathB() {
            if (!targetRelPath || !folderController.folderB) return "";
            return folderController.folderB + "/" + targetRelPath;
        }

        MenuItem {
            text: "\u25C0 " + qsTr("Copy to A")
            enabled: folderController.canCopyToA
            onTriggered: folderController.copySelectedToA()
        }
        MenuItem {
            text: qsTr("Copy to B") + " \u25B6"
            enabled: folderController.canCopyToB
            onTriggered: folderController.copySelectedToB()
        }
        MenuSeparator {}
        MenuItem {
            text: "\u25C0 " + qsTr("Move to A")
            enabled: folderController.canMoveToA
            onTriggered: folderController.moveSelectedToA()
        }
        MenuItem {
            text: qsTr("Move to B") + " \u25B6"
            enabled: folderController.canMoveToB
            onTriggered: folderController.moveSelectedToB()
        }
        MenuSeparator {}
        MenuItem {
            text: qsTr("Open file (A side)")
            enabled: contextMenu.targetHasA && !contextMenu.targetIsFolder
            onTriggered: folderController.openFile(contextMenu.pathA())
        }
        MenuItem {
            text: qsTr("Open file (B side)")
            enabled: contextMenu.targetHasB && !contextMenu.targetIsFolder
            onTriggered: folderController.openFile(contextMenu.pathB())
        }
        MenuItem {
            text: qsTr("Reveal in file manager (A)")
            enabled: contextMenu.targetHasA
            onTriggered: folderController.revealInFileManager(contextMenu.pathA())
        }
        MenuItem {
            text: qsTr("Reveal in file manager (B)")
            enabled: contextMenu.targetHasB
            onTriggered: folderController.revealInFileManager(contextMenu.pathB())
        }
        MenuItem {
            text: qsTr("Copy relative path")
            enabled: contextMenu.targetRelPath.length > 0
            onTriggered: folderController.copyToClipboard(contextMenu.targetRelPath)
        }
        MenuItem {
            text: qsTr("Copy path (A)")
            enabled: contextMenu.targetHasA
            onTriggered: folderController.copyToClipboard(contextMenu.pathA())
        }
        MenuItem {
            text: qsTr("Copy path (B)")
            enabled: contextMenu.targetHasB
            onTriggered: folderController.copyToClipboard(contextMenu.pathB())
        }
        MenuSeparator {}
        MenuItem {
            text: qsTr("Diff content (A vs B)")
            enabled: contextMenu.targetHasA && contextMenu.targetHasB && !contextMenu.targetIsFolder
            onTriggered: contentDiffDialog.open2(contextMenu.pathA(), contextMenu.pathB())
        }
    }

    // ── Profile save dialog ───────────────────────────────────────────────

    Dialog {
        id: profileSaveDialog
        title: qsTr("Save Profile")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: 360

        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Label {
                text: qsTr("Profile name")
                color: colors.text
            }
            TextField {
                id: profileNameField
                Layout.fillWidth: true
                placeholderText: qsTr("e.g. card-A vs backup")
                color: colors.text
                background: Rectangle {
                    radius: 5
                    color: colors.panelAlt
                    border.color: profileNameField.focus ? colors.accent : colors.line
                }
            }
        }

        onAccepted: {
            if (profileNameField.text.length > 0) {
                folderController.saveProfile(profileNameField.text)
                profileCombo.model = folderController.listProfiles()
                profileCombo.currentIndex = profileCombo.find(profileNameField.text)
                profileNameField.text = ""
            }
        }
        onRejected: profileNameField.text = ""
    }

    // ── Sync planner dialog ───────────────────────────────────────────────

    Dialog {
        id: syncDialog
        title: qsTr("Sync Planner")
        modal: true
        standardButtons: Dialog.Close
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(parent.width * 0.8, 720)
        height: Math.min(parent.height * 0.8, 560)

        property var planRows: []
        property int chosenMode: 0          // SfcSyncMode
        property bool propagateDeletes: false
        property int conflict: 0            // SfcConflictStrategy
        property bool dryRun: true

        function rebuild() {
            planRows = folderController.buildSyncPlan(chosenMode, propagateDeletes, conflict)
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12
                rowSpacing: 6

                Label { text: qsTr("Mode:"); color: colors.text }
                ComboBox {
                    Layout.fillWidth: true
                    model: [
                        qsTr("Mirror A → B"),
                        qsTr("Mirror B → A"),
                        qsTr("Two-way (newer wins)"),
                        qsTr("Two-way (manual)")
                    ]
                    currentIndex: syncDialog.chosenMode
                    onActivated: { syncDialog.chosenMode = currentIndex; syncDialog.rebuild() }
                }

                Label { text: qsTr("Conflicts:"); color: colors.text }
                ComboBox {
                    Layout.fillWidth: true
                    model: [qsTr("Newer wins"), qsTr("Larger wins"), qsTr("Ask"), qsTr("Skip")]
                    currentIndex: syncDialog.conflict
                    onActivated: { syncDialog.conflict = currentIndex; syncDialog.rebuild() }
                }

                CheckBox {
                    text: qsTr("Propagate deletes")
                    checked: syncDialog.propagateDeletes
                    onToggled: { syncDialog.propagateDeletes = checked; syncDialog.rebuild() }
                }
                CheckBox {
                    text: qsTr("Dry run (preview only, no file changes)")
                    checked: syncDialog.dryRun
                    onToggled: syncDialog.dryRun = checked
                }
            }

            Label {
                text: qsTr("Planned actions: %1").arg(syncDialog.planRows.length)
                color: colors.muted
                font.family: window.monoFont
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: syncDialog.planRows
                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 30
                    color: index % 2 === 0 ? colors.panel : colors.panelAlt

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        Text {
                            width: 60
                            verticalAlignment: Text.AlignVCenter
                            height: parent.height
                            text: ["Copy", "Delete", "Rename", "Skip"][modelData.kind] || ""
                            color: modelData.kind === 1 ? colors.bad : colors.text
                            font.family: window.monoFont
                            font.pixelSize: 11
                        }
                        Text {
                            width: parent.width - 80
                            verticalAlignment: Text.AlignVCenter
                            height: parent.height
                            text: modelData.path + "  —  " + modelData.reason
                            color: colors.text
                            elide: Text.ElideMiddle
                            font.family: window.monoFont
                            font.pixelSize: 11
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: qsTr("Refresh plan")
                    onClicked: syncDialog.rebuild()
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: syncDialog.dryRun ? qsTr("Preview run") : qsTr("Execute")
                    enabled: syncDialog.planRows.length > 0
                    onClicked: folderController.executeSyncPlan(syncDialog.dryRun)
                }
            }
        }
    }

    // ── Content diff dialog ───────────────────────────────────────────────

    Dialog {
        id: contentDiffDialog
        title: qsTr("Content Diff")
        modal: true
        standardButtons: Dialog.Close
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(parent.width * 0.9, 900)
        height: Math.min(parent.height * 0.85, 640)

        property string pathA: ""
        property string pathB: ""
        property var diffLines: []
        property bool textMode: true
        property string hexA: ""
        property string hexB: ""

        function open2(a, b) {
            pathA = a
            pathB = b
            textMode = folderController.isTextFile(a) && folderController.isTextFile(b)
            if (textMode) {
                diffLines = folderController.loadTextDiff(a, b)
            } else {
                hexA = folderController.hexWindow(a, 0, 4096)
                hexB = folderController.hexWindow(b, 0, 4096)
            }
            open()
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: contentDiffDialog.pathA + "  ⟷  " + contentDiffDialog.pathB
                color: colors.muted
                font.family: window.monoFont
                font.pixelSize: 11
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            ListView {
                visible: contentDiffDialog.textMode
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: contentDiffDialog.diffLines
                clip: true
                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 18
                    color: modelData.kind === 1 ? "#1e4a2a"     // insert (green-ish bg)
                           : modelData.kind === 2 ? "#4a1e1e"   // delete (red-ish bg)
                           : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        spacing: 8
                        Text {
                            width: 50
                            text: modelData.lineA > 0 ? modelData.lineA : ""
                            color: colors.faint
                            font.family: window.monoFont
                            font.pixelSize: 11
                        }
                        Text {
                            width: 50
                            text: modelData.lineB > 0 ? modelData.lineB : ""
                            color: colors.faint
                            font.family: window.monoFont
                            font.pixelSize: 11
                        }
                        Text {
                            width: parent.width - 130
                            text: (modelData.kind === 1 ? "+ " : modelData.kind === 2 ? "- " : "  ") + modelData.text
                            color: colors.text
                            font.family: window.monoFont
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            RowLayout {
                visible: !contentDiffDialog.textMode
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    TextArea {
                        readOnly: true
                        text: contentDiffDialog.hexA
                        font.family: window.monoFont
                        font.pixelSize: 11
                        color: colors.text
                        background: Rectangle { color: colors.panelAlt }
                    }
                }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    TextArea {
                        readOnly: true
                        text: contentDiffDialog.hexB
                        font.family: window.monoFont
                        font.pixelSize: 11
                        color: colors.text
                        background: Rectangle { color: colors.panelAlt }
                    }
                }
            }
        }
    }

    // ── Overwrite confirmation dialog ─────────────────────────────────────

    Dialog {
        id: overwriteDialog
        title: "File Already Exists"
        standardButtons: Dialog.NoButton
        modal: true
        closePolicy: Popup.CloseOnEscape
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(parent.width * 0.6, 520)

        property var pendingInfo: ({})

        ColumnLayout {
            spacing: 12
            Layout.fillWidth: true

            Label {
                text: "The destination already contains:"
                font.bold: true
                color: colors.text
            }
            Label {
                text: overwriteDialog.pendingInfo.relativePath ? overwriteDialog.pendingInfo.relativePath : ""
                color: colors.accent
                font.family: window.monoFont
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Rectangle { height: 1; color: colors.line; Layout.fillWidth: true }

            GridLayout {
                columns: 2
                columnSpacing: 16
                rowSpacing: 4
                Layout.fillWidth: true

                Label { text: "Source:"; color: colors.muted }
                Label {
                    text: overwriteDialog.pendingInfo.sourceInfo ? overwriteDialog.pendingInfo.sourceInfo : ""
                    font.family: window.monoFont
                    color: colors.text
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Label { text: "Destination:"; color: colors.muted }
                Label {
                    text: overwriteDialog.pendingInfo.destInfo ? overwriteDialog.pendingInfo.destInfo : ""
                    font.family: window.monoFont
                    color: colors.text
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Rectangle { height: 1; color: colors.line; Layout.fillWidth: true }

            Label {
                text: "How do you want to proceed?"
                color: colors.muted
                font.pixelSize: 12
            }

            RowLayout {
                spacing: 6
                Layout.fillWidth: true

                Button {
                    Layout.fillWidth: true
                    text: "Overwrite"
                    onClicked: { folderController.confirmOverwrite("overwrite"); overwriteDialog.close() }
                    background: Rectangle {
                        radius: 5
                        color: colors.accent
                        border.color: colors.accentDark
                        border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text; color: "#fff7ee"
                        horizontalAlignment: Text.AlignHCenter; font.bold: true
                    }
                }
                Button {
                    Layout.fillWidth: true
                    text: "Overwrite All"
                    onClicked: { folderController.confirmOverwrite("overwriteAll"); overwriteDialog.close() }
                    background: Rectangle {
                        radius: 5
                        color: colors.panelAlt; border.color: colors.line; border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text; color: colors.text
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                Button {
                    Layout.fillWidth: true
                    text: "Skip"
                    onClicked: { folderController.confirmOverwrite("skip"); overwriteDialog.close() }
                    background: Rectangle {
                        radius: 5
                        color: colors.panelAlt; border.color: colors.line; border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text; color: colors.text
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                Button {
                    Layout.fillWidth: true
                    text: "Skip All"
                    onClicked: { folderController.confirmOverwrite("skipAll"); overwriteDialog.close() }
                    background: Rectangle {
                        radius: 5
                        color: colors.panelAlt; border.color: colors.line; border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text; color: colors.text
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                Button {
                    Layout.fillWidth: true
                    text: "Cancel"
                    onClicked: { folderController.confirmOverwrite("cancel"); overwriteDialog.close() }
                    background: Rectangle {
                        radius: 5
                        color: colors.panelAlt; border.color: colors.line; border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text; color: colors.text
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    // ── Controller signal connections ────────────────────────────────────

    Connections {
        target: folderController
        function onOverwriteNeeded(info) {
            overwriteDialog.pendingInfo = info
            overwriteDialog.open()
        }
    }

    // ── Tree model for comparison results ─────────────────────────────────

    QtObject {
        id: treeModel

        property var fullTree: []
        property var expandedPaths: ({})
        property var flatItems: []

        function rebuild() {
            fullTree = folderController.buildComparisonTree()
            expandedPaths = {}
            flattenTree()
        }

        function toggleExpanded(relPath) {
            if (expandedPaths[relPath] !== undefined) {
                delete expandedPaths[relPath]
            } else {
                expandedPaths[relPath] = true
            }
            flattenTree()
        }

        function flattenTree() {
            var items = []
            function walk(nodes, depth) {
                for (var i = 0; i < nodes.length; i++) {
                    var node = nodes[i]
                    items.push({
                        name: node.name,
                        relPath: node.relPath,
                        status: node.status,
                        aggregateStatus: node.aggregateStatus,
                        sizeA: node.sizeA,
                        sizeB: node.sizeB,
                        checksumA: node.checksumA,
                        checksumB: node.checksumB,
                        isFolder: node.isFolder,
                        children: node.children,
                        depth: depth,
                        expanded: expandedPaths[node.relPath] !== undefined
                    })
                    if (items[items.length - 1].isFolder && node.children.length > 0 && items[items.length - 1].expanded) {
                        walk(node.children, depth + 1)
                    }
                }
            }
            walk(fullTree, 0)
            flatItems = items
        }
    }

    Connections {
        target: folderController
        function onHasReportChanged() { if (folderController.hasReport) treeModel.rebuild() }
    }

    // ── FolderPicker component ──────────────────────────────────────────────

    component FolderPicker: ColumnLayout {
        id: picker
        property string label
        property string path
        property var pickAction
        property var onDroppedFolder
        property var recentList: []
        property var useRecent
        property string validationError: ""

        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                text: picker.label
                enabled: !folderController.busy
                onClicked: picker.pickAction()
                Accessible.name: qsTr("Choose %1").arg(picker.label)
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

            Button {
                id: recentButton
                text: "▾"
                enabled: !folderController.busy && picker.recentList.length > 0
                Accessible.name: qsTr("Recent folders for %1").arg(picker.label)
                background: Rectangle {
                    radius: 5
                    color: parent.down ? colors.accentDark : colors.panelAlt
                    border.color: colors.line
                    border.width: 1
                }
                contentItem: Text {
                    text: parent.text
                    color: parent.enabled ? colors.text : colors.faint
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 12
                }
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
                        validationError = ""
                        if (!drop.hasUrls || drop.urls.length === 0) {
                            validationError = "Drop a folder from your file manager."
                            return
                        }

                        var accepted = false
                        for (var i = 0; i < drop.urls.length; i++) {
                            var result = folderController.parseDroppedFolderUrl(drop.urls[i].toString())
                            if (result.path) {
                                onDroppedFolder(result.path)
                                accepted = true
                                break
                            }
                        }

                        if (!accepted) {
                            validationError = "Dropped item is not a valid folder path."
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: validationError.length > 0
                text: validationError
                color: colors.bad
                font.pixelSize: 10
                wrapMode: Text.WordWrap
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

}
