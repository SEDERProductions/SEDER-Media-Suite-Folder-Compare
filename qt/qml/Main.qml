// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Seder.UI

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
    readonly property bool showChecksums: folderController.mode === 2
    readonly property real railWidthRatio: width < 1200 ? 0.34 : 0.3
    readonly property int leftRailWidth: Math.max(300, Math.min(420, Math.round(width * railWidthRatio)))
    readonly property string appVersionLabel: Qt.application.version && Qt.application.version.length > 0 ? Qt.application.version : ""

    color: Theme.gutter

    property string activeWorkspace: "Compare"
    property var previewNode: null
    property string resultsView: "list"

    // Drive the global design-token theme from the controller's resolved mode.
    Binding {
        target: Theme
        property: "dark"
        value: folderController.effectiveDark
    }

    // ── Workspace layout (presets + persistence) ──────────────────────────
    function applyWorkspace(name) {
        if (name === "Review") {
            // Media-review focus: wide preview, collapsed console.
            settingsPanel.SplitView.preferredWidth = Math.max(280, Math.round(width * 0.2));
            mediaPanel.SplitView.preferredWidth = Math.round(width * 0.34);
            consolePanel.collapsed = true;
        } else if (name === "Triage") {
            // Emphasize the log/console for sorting through issues.
            settingsPanel.SplitView.preferredWidth = window.leftRailWidth;
            mediaPanel.SplitView.preferredWidth = 240;
            consolePanel.collapsed = false;
            consolePanel.expandedHeight = Math.round(height * 0.4);
        } else {
            // Compare (default): balanced layout.
            settingsPanel.SplitView.preferredWidth = window.leftRailWidth;
            mediaPanel.SplitView.preferredWidth = 340;
            consolePanel.collapsed = false;
            consolePanel.expandedHeight = Math.max(160, Math.round(height * 0.18));
        }
        consolePanel.SplitView.preferredHeight = consolePanel.collapsed ? consolePanel.collapsedSize : consolePanel.expandedHeight;
        activeWorkspace = name;
        persistLayout();
    }

    function persistLayout() {
        var consoleH = consolePanel.collapsed ? consolePanel.expandedHeight : consolePanel.height;
        if (!consolePanel.collapsed && consoleH > consolePanel.collapsedSize)
            consolePanel.expandedHeight = consoleH;
        folderController.saveLayout({
            "workspace": activeWorkspace,
            "settingsWidth": settingsPanel.SplitView.preferredWidth,
            "mediaWidth": mediaPanel.SplitView.preferredWidth,
            "consoleHeight": consolePanel.expandedHeight,
            "consoleCollapsed": consolePanel.collapsed
        });
    }

    Component.onCompleted: {
        // QSettings (INI) returns values untyped (as strings), so coerce here.
        var saved = folderController.loadLayout();
        if (saved && saved.workspace !== undefined) {
            activeWorkspace = saved.workspace;
            if (saved.settingsWidth !== undefined)
                settingsPanel.SplitView.preferredWidth = Number(saved.settingsWidth);
            if (saved.mediaWidth !== undefined)
                mediaPanel.SplitView.preferredWidth = Number(saved.mediaWidth);
            consolePanel.collapsed = (saved.consoleCollapsed === true || saved.consoleCollapsed === "true");
            if (saved.consoleHeight !== undefined)
                consolePanel.expandedHeight = Number(saved.consoleHeight);
            consolePanel.SplitView.preferredHeight = consolePanel.collapsed ? consolePanel.collapsedSize : consolePanel.expandedHeight;
        } else {
            applyWorkspace("Compare");
        }
    }

    onClosing: persistLayout()

    function filterCount(index) {
        switch (index) {
        case 0:
            return folderController.totalRows;
        case 1:
            return folderController.matchingCount;
        case 2:
            return folderController.changedCount;
        case 3:
            return folderController.onlyACount;
        case 4:
            return folderController.onlyBCount;
        case 5:
            return folderController.folderDiffCount;
        }
        return 0;
    }

    function isImageName(n) {
        return /\.(png|jpe?g|gif|bmp|webp|tiff?)$/i.test(n);
    }

    // Absolute path of a tree node for thumbnailing, preferring the A side.
    function rowThumbPath(node) {
        var rel = node.relPath || "";
        var hasA = node.status === 0 || node.status === 1 || node.status === 2 || node.status === 4;
        if (hasA && folderController.folderA.length > 0)
            return folderController.folderA + "/" + rel;
        if (folderController.folderB.length > 0)
            return folderController.folderB + "/" + rel;
        return "";
    }

    readonly property bool isMac: Qt.platform.os === "osx"
    readonly property string openFolderBShortcut: isMac ? "Meta+Shift+O" : "Ctrl+Shift+O"
    readonly property string startShortcut: isMac ? "Meta+R" : "Ctrl+R"
    readonly property string exportTxtShortcut: isMac ? "Meta+Shift+T" : "Ctrl+Shift+T"
    readonly property string exportCsvShortcut: isMac ? "Meta+Shift+C" : "Ctrl+Shift+C"

    function hintText(shortcutText) {
        return isMac ? shortcutText.replace("Meta", "⌘") : shortcutText;
    }

    // Keyboard shortcuts
    Shortcut {
        sequence: StandardKey.Open
        onActivated: folderController.chooseFolderA()
    }
    Shortcut {
        sequence: window.openFolderBShortcut
        onActivated: folderController.chooseFolderB()
    }
    Shortcut {
        sequence: window.startShortcut
        onActivated: folderController.startComparison()
    }
    Shortcut {
        sequence: StandardKey.Cancel
        enabled: folderController.busy
        onActivated: folderController.cancelComparison()
    }
    Shortcut {
        sequence: window.exportTxtShortcut
        enabled: folderController.hasReport && !folderController.busy
        onActivated: folderController.exportTxt()
    }
    Shortcut {
        sequence: window.exportCsvShortcut
        enabled: folderController.hasReport && !folderController.busy
        onActivated: folderController.exportCsv()
    }

    // Shared themed split handle (gutter strip that lights up on hover/drag).
    Component {
        id: splitHandle
        Rectangle {
            implicitWidth: 6
            implicitHeight: 6
            color: SplitHandle.pressed ? Theme.accent : (SplitHandle.hovered ? Qt.lighter(Theme.gutter, 1.6) : Theme.gutter)
            Behavior on color {
                ColorAnimation {
                    duration: Theme.motion.fast
                }
            }
        }
    }

    // ── Dockable workspace ────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Workspace switcher (mirrors Premiere's workspace bar).
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            color: Theme.gutter

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space.md
                anchors.rightMargin: Theme.space.sm
                spacing: Theme.space.xs

                Label {
                    text: qsTr("WORKSPACE")
                    color: Theme.faint
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.caption
                    Layout.rightMargin: Theme.space.sm
                }
                Repeater {
                    model: ["Compare", "Review", "Triage"]
                    delegate: AppButton {
                        required property string modelData
                        variant: AppButton.Ghost
                        checkable: true
                        checked: window.activeWorkspace === modelData
                        text: modelData
                        onClicked: window.applyWorkspace(modelData)
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                AppButton {
                    variant: AppButton.Ghost
                    iconName: "undo"
                    text: qsTr("Reset")
                    onClicked: window.applyWorkspace(window.activeWorkspace)
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Reset this workspace to its default layout")
                }
            }
        }

        SplitView {
            id: workspace
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal
            handle: splitHandle

        DockPanel {
            id: settingsPanel
            title: qsTr("SETTINGS")
            iconName: "settings"
            floatable: true
            SplitView.preferredWidth: window.leftRailWidth
            SplitView.minimumWidth: 280
            SplitView.maximumWidth: 520

            ScrollView {
                id: sidebarScroll
                anchors.fill: parent
                anchors.margins: Theme.space.lg
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: sidebarScroll.availableWidth
                    spacing: Theme.space.lg

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Label {
                            text: "SEDER Folder Compare"
                            color: Theme.text
                            font.pixelSize: Theme.typography.display
                            font.bold: true
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Label {
                            text: "v" + Qt.application.version
                            color: Theme.muted
                            font.pixelSize: Theme.typography.body
                            font.family: Theme.typography.mono
                        }
                    }

                    SectionLabel {
                        text: "01 / FOLDERS"
                    }

                    FolderPicker {
                        label: qsTr("Folder A")
                        path: folderController.folderA
                        pickAction: function () {
                            folderController.chooseFolderA();
                        }
                        onDroppedFolder: function (folder) {
                            folderController.folderA = folder;
                        }
                        recentList: folderController.recentFoldersA
                        useRecent: function (folder) {
                            folderController.useRecentFolderA(folder);
                        }
                    }
                    FolderPicker {
                        label: qsTr("Folder B")
                        path: folderController.folderB
                        pickAction: function () {
                            folderController.chooseFolderB();
                        }
                        onDroppedFolder: function (folder) {
                            folderController.folderB = folder;
                        }
                        recentList: folderController.recentFoldersB
                        useRecent: function (folder) {
                            folderController.useRecentFolderB(folder);
                        }
                    }

                    Label {
                        text: "Open A: " + window.hintText("Ctrl+O") + "  •  Open B: " + window.hintText(window.openFolderBShortcut)
                        color: Theme.muted
                        font.pixelSize: Theme.typography.caption
                        font.family: Theme.typography.mono
                    }

                    // ── Profiles ──────────────────────────────────────────────
                    SectionLabel {
                        text: qsTr("PROFILES")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.sm

                        AppComboBox {
                            id: profileCombo
                            Layout.fillWidth: true
                            model: folderController.listProfiles()
                            enabled: !folderController.busy && model.length > 0
                            displayText: model.length > 0 ? (currentText || qsTr("Select…")) : qsTr("(none saved)")
                            Accessible.name: qsTr("Saved profile")
                            onActivated: function () {
                                if (currentText.length > 0) {
                                    folderController.loadProfile(currentText);
                                }
                            }
                        }

                        AppButton {
                            iconName: "save"
                            text: qsTr("Save…")
                            enabled: !folderController.busy
                            Accessible.name: qsTr("Save current settings as a profile")
                            onClicked: profileSaveDialog.open()
                        }

                        AppButton {
                            iconName: "trash"
                            enabled: !folderController.busy && profileCombo.currentText.length > 0
                            Accessible.name: qsTr("Delete profile")
                            onClicked: {
                                folderController.deleteProfile(profileCombo.currentText);
                                profileCombo.model = folderController.listProfiles();
                            }
                        }
                    }

                    SectionLabel {
                        text: "02 / COMPARE MODE"
                    }

                    AppComboBox {
                        id: modeCombo
                        Layout.fillWidth: true
                        Accessible.name: qsTr("Comparison mode")
                        model: [qsTr("Path + size"), qsTr("Path + size + modified time"), qsTr("Path + size + checksum"), qsTr("Media metadata (dimensions / duration / codec)"), qsTr("Perceptual hash (similar images)")]
                        currentIndex: folderController.mode
                        enabled: !folderController.busy
                        onActivated: folderController.mode = currentIndex
                    }

                    SectionLabel {
                        text: "03 / IGNORE"
                    }

                    AppCheckBox {
                        id: hiddenCheck
                        text: qsTr("Ignore hidden/system files")
                        checked: folderController.ignoreHiddenSystem
                        enabled: !folderController.busy
                        onToggled: folderController.ignoreHiddenSystem = checked
                    }

                    AppCheckBox {
                        id: followSymlinksCheck
                        text: qsTr("Follow symlinks")
                        checked: folderController.followSymlinks
                        enabled: !folderController.busy
                        onToggled: folderController.followSymlinks = checked
                    }

                    AppCheckBox {
                        id: detectRenamesCheck
                        text: qsTr("Detect renames")
                        checked: folderController.detectRenames
                        enabled: !folderController.busy
                        onToggled: folderController.detectRenames = checked
                    }

                    AppTextField {
                        id: ignoreField
                        Layout.fillWidth: true
                        text: folderController.ignorePatterns
                        enabled: !folderController.busy
                        placeholderText: ".DS_Store, *.tmp"
                        font.family: Theme.typography.mono
                        font.pixelSize: Theme.typography.body
                        onTextEdited: folderController.ignorePatterns = text
                    }

                    SectionLabel {
                        text: "04 / THEME"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.sm
                        Repeater {
                            model: ["system", "light", "dark"]
                            delegate: AppButton {
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                iconName: "theme-" + modelData
                                text: modelData.toUpperCase()
                                checkable: true
                                checked: folderController.theme === modelData
                                onClicked: folderController.theme = modelData
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.sm
                        AppButton {
                            Layout.fillWidth: true
                            iconName: folderController.busy ? "stop" : "play"
                            variant: folderController.busy ? AppButton.Secondary : AppButton.Primary
                            text: folderController.busy ? qsTr("Cancel Comparison (Esc)") : qsTr("Start Comparison") + " (" + window.hintText(window.startShortcut) + ")"
                            Accessible.name: folderController.busy ? qsTr("Cancel the running comparison") : qsTr("Start a new comparison")
                            onClicked: folderController.busy ? folderController.cancelComparison() : folderController.startComparison()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.sm
                        AppButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            flatDisabled: true
                            text: "Export TXT (" + window.hintText(window.exportTxtShortcut) + ")"
                            enabled: folderController.hasReport && !folderController.busy
                            onClicked: folderController.exportTxt()
                            ToolTip.visible: hovered && !enabled
                            ToolTip.text: "Run a comparison first"
                        }
                        AppButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            flatDisabled: true
                            text: "Export CSV (" + window.hintText(window.exportCsvShortcut) + ")"
                            enabled: folderController.hasReport && !folderController.busy
                            onClicked: folderController.exportCsv()
                            ToolTip.visible: hovered && !enabled
                            ToolTip.text: "Run a comparison first"
                        }
                    }

                    AppButton {
                        Layout.fillWidth: true
                        flatDisabled: true
                        iconName: "sync"
                        text: qsTr("Sync planner…")
                        enabled: folderController.hasReport && !folderController.busy
                        Accessible.name: qsTr("Open the sync planner")
                        onClicked: {
                            syncDialog.rebuild();
                            syncDialog.open();
                        }
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: qsTr("Run a comparison first")
                    }

                    Item {
                        Layout.preferredHeight: Theme.space.sm
                    }
                }
            }
        }

        SplitView {
            id: rightColumn
            orientation: Qt.Vertical
            handle: splitHandle
            SplitView.fillWidth: true

            SplitView {
                id: centerRow
                orientation: Qt.Horizontal
                handle: splitHandle
                SplitView.fillHeight: true

                DockPanel {
                    id: resultsPanel
                    title: qsTr("RESULTS")
                    iconName: "folder-tree"
                    floatable: true
                    SplitView.fillWidth: true
                    SplitView.minimumWidth: 360

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Metrics + filters + transfer toolbar
                    ColumnLayout {
                        id: metricsPanel
                        Layout.fillWidth: true
                        Layout.margins: Theme.space.lg
                        spacing: Theme.space.md

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            MetricBox {
                                label: "Only A"
                                value: folderController.onlyACount
                                accent: Theme.warn
                            }
                            MetricBox {
                                label: "Only B"
                                value: folderController.onlyBCount
                                accent: Theme.warn
                            }
                            MetricBox {
                                label: "Changed"
                                value: folderController.changedCount
                                accent: Theme.bad
                            }
                            MetricBox {
                                label: "Matching"
                                value: folderController.matchingCount
                                accent: Theme.good
                            }
                            MetricBox {
                                label: "Folders"
                                value: folderController.folderDiffCount
                                accent: Theme.faint
                            }
                            MetricBox {
                                label: "Scanned"
                                value: folderController.totalSizeText
                                accent: Theme.faint
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: folderController.busy
                            spacing: Theme.space.sm

                            ProgressBar {
                                id: progressBar
                                Layout.fillWidth: true
                                from: 0
                                to: folderController.progressTotal > 0 ? folderController.progressTotal : 100
                                value: folderController.progressTotal > 0 ? folderController.progressCurrent : 0
                                background: Rectangle {
                                    implicitHeight: 6
                                    radius: Theme.radius.sm
                                    color: Theme.panelAlt
                                    border.color: Theme.line
                                    border.width: 1
                                }
                                contentItem: Item {
                                    implicitHeight: 6
                                    Rectangle {
                                        width: progressBar.visualPosition * parent.width
                                        height: parent.height
                                        radius: Theme.radius.sm
                                        color: Theme.accent
                                        Behavior on width {
                                            NumberAnimation {
                                                duration: Theme.motion.fast
                                                easing.type: Theme.motion.easeStandard
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                text: folderController.etaText
                                visible: folderController.etaText.length > 0
                                color: Theme.faint
                                font.pixelSize: Theme.typography.body
                                font.family: Theme.typography.mono
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.sm
                            Repeater {
                                model: 6
                                delegate: AppButton {
                                    required property int index
                                    Layout.fillWidth: true
                                    text: Theme.filterLabel(index) + (window.filterCount(index) > 0 ? " (" + window.filterCount(index) + ")" : "")
                                    Accessible.name: qsTr("Filter: %1").arg(Theme.filterLabel(index))
                                    Accessible.checkable: true
                                    Accessible.checked: checked
                                    checkable: true
                                    checked: window.activeFilter === index
                                    enabled: window.filterCount(index) > 0 || index === 0
                                    onClicked: {
                                        window.activeFilter = index;
                                        folderController.setFilterMode(index);
                                    }
                                    ToolTip.visible: hovered && !enabled
                                    ToolTip.text: "No results for this filter"
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Theme.line
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.sm
                            visible: folderController.hasSelection || folderController.canUndo

                            AppButton {
                                Layout.fillWidth: true
                                flatDisabled: true
                                iconName: "arrow-left"
                                text: "Copy to A"
                                enabled: folderController.canCopyToA
                                onClicked: folderController.copySelectedToA()
                                ToolTip.visible: hovered && !enabled
                                ToolTip.text: "Select items with content in B to copy to A"
                            }
                            AppButton {
                                Layout.fillWidth: true
                                flatDisabled: true
                                iconName: "arrow-right"
                                text: "Copy to B"
                                enabled: folderController.canCopyToB
                                onClicked: folderController.copySelectedToB()
                                ToolTip.visible: hovered && !enabled
                                ToolTip.text: "Select items with content in A to copy to B"
                            }
                            AppButton {
                                Layout.fillWidth: true
                                flatDisabled: true
                                iconName: "move-left"
                                text: "Move to A"
                                enabled: folderController.canMoveToA
                                onClicked: folderController.moveSelectedToA()
                                ToolTip.visible: hovered && !enabled
                                ToolTip.text: "Copy selected items from B to A, then delete originals"
                            }
                            AppButton {
                                Layout.fillWidth: true
                                flatDisabled: true
                                iconName: "move-right"
                                text: "Move to B"
                                enabled: folderController.canMoveToB
                                onClicked: folderController.moveSelectedToB()
                                ToolTip.visible: hovered && !enabled
                                ToolTip.text: "Copy selected items from A to B, then delete originals"
                            }
                            AppButton {
                                Layout.fillWidth: true
                                flatDisabled: true
                                iconName: "undo"
                                text: "Undo"
                                enabled: folderController.canUndo
                                onClicked: folderController.undoLastTransfer()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.line
                    }

                    // Results tree
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.space.sm
                            Layout.rightMargin: Theme.space.sm
                            Layout.topMargin: Theme.space.xs
                            Layout.bottomMargin: Theme.space.xs
                            spacing: Theme.space.xs
                            Item {
                                Layout.fillWidth: true
                            }
                            AppButton {
                                variant: AppButton.Ghost
                                checkable: true
                                checked: window.resultsView === "list"
                                iconName: "panel-bottom"
                                text: qsTr("List")
                                onClicked: window.resultsView = "list"
                            }
                            AppButton {
                                variant: AppButton.Ghost
                                checkable: true
                                checked: window.resultsView === "grid"
                                iconName: "split"
                                text: qsTr("Grid")
                                onClicked: window.resultsView = "grid"
                            }
                        }

                        Row {
                            Layout.fillWidth: true
                            visible: window.resultsView === "list"
                            height: 30
                            Rectangle {
                                width: 30
                                height: 30
                                color: Theme.panelAlt
                                border.color: Theme.line
                                border.width: 1
                            }
                            Rectangle {
                                width: parent.width - 270
                                height: 30
                                color: Theme.panelAlt
                                border.color: Theme.line
                                border.width: 1
                                Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space.sm
                                    text: "Name"
                                    color: Theme.muted
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Theme.typography.body
                                    font.family: Theme.typography.mono
                                }
                            }
                            Rectangle {
                                width: 80
                                height: 30
                                color: Theme.panelAlt
                                border.color: Theme.line
                                border.width: 1
                                Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space.sm
                                    text: "Size A"
                                    color: Theme.muted
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Theme.typography.body
                                    font.family: Theme.typography.mono
                                }
                            }
                            Rectangle {
                                width: 80
                                height: 30
                                color: Theme.panelAlt
                                border.color: Theme.line
                                border.width: 1
                                Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space.sm
                                    text: "Size B"
                                    color: Theme.muted
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Theme.typography.body
                                    font.family: Theme.typography.mono
                                }
                            }
                            Rectangle {
                                width: 110
                                height: 30
                                color: Theme.panelAlt
                                border.color: Theme.line
                                border.width: 1
                                Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space.sm
                                    text: "Status"
                                    color: Theme.muted
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Theme.typography.body
                                    font.family: Theme.typography.mono
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ListView {
                                id: treeView
                                anchors.fill: parent
                                visible: window.resultsView === "list"
                                clip: true
                                model: treeModel.flatItems
                                boundsBehavior: Flickable.StopAtBounds
                                spacing: 0
                                currentIndex: -1
                                keyNavigationEnabled: true
                                activeFocusOnTab: true
                                highlightMoveDuration: 0

                                function activateCurrent() {
                                    var n = treeModel.flatItems[currentIndex];
                                    if (!n)
                                        return;
                                    if (n.isFolder && n.children.length > 0)
                                        treeModel.toggleExpanded(n.relPath);
                                    else
                                        folderController.openFile(folderController.folderA + "/" + n.relPath);
                                }
                                onCurrentIndexChanged: {
                                    if (currentIndex >= 0 && currentIndex < treeModel.flatItems.length)
                                        window.previewNode = treeModel.flatItems[currentIndex];
                                }
                                Keys.onReturnPressed: activateCurrent()
                                Keys.onEnterPressed: activateCurrent()
                                Keys.onRightPressed: {
                                    var n = treeModel.flatItems[currentIndex];
                                    if (n && n.isFolder && !n.expanded && n.children.length > 0)
                                        treeModel.toggleExpanded(n.relPath);
                                }
                                Keys.onLeftPressed: {
                                    var n = treeModel.flatItems[currentIndex];
                                    if (n && n.isFolder && n.expanded)
                                        treeModel.toggleExpanded(n.relPath);
                                }

                                delegate: Rectangle {
                                    required property int index
                                    required property var modelData
                                    readonly property var node: modelData
                                    readonly property bool hovered: rowMouse.containsMouse
                                    readonly property bool current: ListView.isCurrentItem
                                    readonly property color baseColor: index % 2 === 0 ? Theme.panel : Theme.panelAlt
                                    readonly property color hoverColor: window.darkMode ? Qt.lighter(baseColor, 1.08) : Qt.darker(baseColor, 1.05)
                                    implicitWidth: treeView.width
                                    implicitHeight: 30
                                    color: current ? (window.darkMode ? Qt.lighter(baseColor, 1.2) : Qt.darker(baseColor, 1.12)) : (hovered ? hoverColor : baseColor)
                                    border.color: Theme.line
                                    border.width: 1

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 3
                                        color: Theme.accent
                                        visible: parent.current
                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Theme.motion.fast
                                        }
                                    }

                                    Row {
                                        anchors.fill: parent

                                        Item {
                                            width: 30
                                            height: parent.height
                                            Icon {
                                                anchors.centerIn: parent
                                                name: node.expanded ? "chevron-down" : "chevron-right"
                                                color: Theme.muted
                                                size: 14
                                                visible: node.isFolder && node.children.length > 0
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: node.isFolder && node.children.length > 0
                                                onClicked: treeModel.toggleExpanded(node.relPath)
                                            }
                                        }

                                        Item {
                                            width: parent.width - 270
                                            height: parent.height
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 6
                                                spacing: Theme.space.xs
                                                Rectangle {
                                                    width: 10
                                                    height: 10
                                                    radius: 5
                                                    Layout.alignment: Qt.AlignVCenter
                                                    color: {
                                                        var s = node.aggregateStatus !== undefined ? node.aggregateStatus : node.status;
                                                        if (s === 0)
                                                            return Theme.good;
                                                        if (s === 1)
                                                            return Theme.bad;
                                                        if (s === 2 || s === 4)
                                                            return Theme.warn;
                                                        if (s === 3 || s === 5)
                                                            return Theme.warn;
                                                        return Theme.faint;
                                                    }
                                                }
                                                Image {
                                                    Layout.alignment: Qt.AlignVCenter
                                                    visible: !node.isFolder && window.isImageName(node.name)
                                                    Layout.preferredWidth: visible ? 22 : 0
                                                    Layout.preferredHeight: 22
                                                    sourceSize.width: 44
                                                    sourceSize.height: 44
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                    cache: true
                                                    source: visible ? ("image://thumb/" + encodeURIComponent(window.rowThumbPath(node))) : ""
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: node.name
                                                    color: Theme.text
                                                    elide: Text.ElideMiddle
                                                    verticalAlignment: Text.AlignVCenter
                                                    font.pixelSize: Theme.typography.body
                                                    font.family: Theme.typography.mono
                                                    leftPadding: node.depth * 16
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: 80
                                            height: parent.height
                                            color: "transparent"
                                            Text {
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.space.sm
                                                text: node.sizeA || ""
                                                color: node.sizeA ? Theme.text : Theme.faint
                                                elide: Text.ElideRight
                                                verticalAlignment: Text.AlignVCenter
                                                font.pixelSize: Theme.typography.caption
                                                font.family: Theme.typography.mono
                                            }
                                        }

                                        Rectangle {
                                            width: 80
                                            height: parent.height
                                            color: "transparent"
                                            Text {
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.space.sm
                                                text: node.sizeB || ""
                                                color: node.sizeB ? Theme.text : Theme.faint
                                                elide: Text.ElideRight
                                                verticalAlignment: Text.AlignVCenter
                                                font.pixelSize: Theme.typography.caption
                                                font.family: Theme.typography.mono
                                            }
                                        }

                                        Rectangle {
                                            id: statusCell
                                            width: 110
                                            height: parent.height
                                            color: "transparent"
                                            readonly property color statusTint: {
                                                var s = node.status;
                                                if (s === 0)
                                                    return Theme.good;
                                                if (s === 1)
                                                    return Theme.bad;
                                                if (s >= 2)
                                                    return Theme.warn;
                                                return Theme.faint;
                                            }
                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 6
                                                spacing: Theme.space.xs
                                                Icon {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    size: 13
                                                    visible: name.length > 0
                                                    color: statusCell.statusTint
                                                    name: {
                                                        var s = node.status;
                                                        if (s === 0)
                                                            return "check";
                                                        if (s === 1)
                                                            return "diff";
                                                        if (s === 2)
                                                            return "arrow-left";
                                                        if (s === 3)
                                                            return "arrow-right";
                                                        if (s === 4 || s === 5)
                                                            return "folder";
                                                        return "";
                                                    }
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: statusCell.statusTint
                                                    text: {
                                                        var s = node.status;
                                                        if (s === 0)
                                                            return "Match";
                                                        if (s === 1)
                                                            return "Changed";
                                                        if (s === 2)
                                                            return "Only A";
                                                        if (s === 3)
                                                            return "Only B";
                                                        if (s === 4)
                                                            return "Folder (A)";
                                                        if (s === 5)
                                                            return "Folder (B)";
                                                        return "";
                                                    }
                                                    elide: Text.ElideRight
                                                    verticalAlignment: Text.AlignVCenter
                                                    font.pixelSize: Theme.typography.caption
                                                    font.family: Theme.typography.mono
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: function (mouse) {
                                            treeView.currentIndex = index;
                                            treeView.forceActiveFocus();
                                            window.previewNode = node;
                                            if (node.isFolder && node.children.length > 0) {
                                                treeModel.toggleExpanded(node.relPath);
                                            }
                                            if (mouse.button === Qt.RightButton) {
                                                contextMenu.targetRelPath = node.relPath;
                                                contextMenu.targetIsFolder = node.isFolder;
                                                contextMenu.targetHasA = node.status === 0 || node.status === 1 || node.status === 2 || node.status === 4;
                                                contextMenu.targetHasB = node.status === 0 || node.status === 1 || node.status === 3 || node.status === 4;
                                                contextMenu.popup();
                                            }
                                        }
                                    }
                                }

                                ScrollBar.vertical: ScrollBar {}
                            }

                            GridView {
                                id: resultsGrid
                                anchors.fill: parent
                                visible: window.resultsView === "grid"
                                clip: true
                                model: treeModel.flatItems
                                cellWidth: 150
                                cellHeight: 150
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar {}

                                delegate: Item {
                                    id: cell
                                    required property int index
                                    required property var modelData
                                    readonly property var node: modelData
                                    readonly property bool isImg: !cell.node.isFolder && window.isImageName(cell.node.name)
                                    width: resultsGrid.cellWidth
                                    height: resultsGrid.cellHeight

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 5
                                        radius: Theme.radius.md
                                        color: cardHover.hovered ? Theme.panelAlt : Theme.panel
                                        border.color: cardHover.hovered ? Theme.accent : Theme.line
                                        border.width: 1
                                        Behavior on border.color {
                                            ColorAnimation {
                                                duration: Theme.motion.fast
                                            }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: Theme.space.sm
                                            spacing: Theme.space.xs

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                radius: Theme.radius.sm
                                                color: Theme.bg
                                                clip: true
                                                Image {
                                                    anchors.fill: parent
                                                    anchors.margins: 2
                                                    visible: cell.isImg
                                                    source: cell.isImg ? ("image://thumb/" + encodeURIComponent(window.rowThumbPath(cell.node))) : ""
                                                    sourceSize.width: 256
                                                    sourceSize.height: 256
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                    cache: true
                                                }
                                                Icon {
                                                    anchors.centerIn: parent
                                                    visible: !cell.isImg
                                                    size: 34
                                                    color: Theme.faint
                                                    name: cell.node.isFolder ? "folder" : (/\.(mp4|mov|mkv|avi|webm|m4v|mxf|wmv|ts)$/i.test(cell.node.name) ? "video" : (/\.(wav|mp3|flac|ogg|m4a|aiff?|wv|ape)$/i.test(cell.node.name) ? "audio" : "file"))
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.space.xs
                                                Rectangle {
                                                    width: 8
                                                    height: 8
                                                    radius: 4
                                                    Layout.alignment: Qt.AlignVCenter
                                                    color: Theme.statusColor(cell.node.aggregateStatus !== undefined ? cell.node.aggregateStatus : cell.node.status)
                                                }
                                                Label {
                                                    Layout.fillWidth: true
                                                    text: cell.node.name
                                                    color: Theme.text
                                                    elide: Text.ElideMiddle
                                                    font.pixelSize: Theme.typography.caption
                                                    font.family: Theme.typography.mono
                                                }
                                            }
                                        }

                                        HoverHandler {
                                            id: cardHover
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                window.previewNode = cell.node;
                                                if (cell.node.isFolder && cell.node.children.length > 0)
                                                    treeModel.toggleExpanded(cell.node.relPath);
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                id: emptyState
                                anchors.fill: parent
                                visible: treeModel.flatItems.length === 0
                                color: Theme.bg
                                border.color: Theme.line
                                border.width: 1

                                readonly property bool hasFolders: folderController.folderA.length > 0 && folderController.folderB.length > 0

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width - 80, 460)
                                    spacing: Theme.space.md

                                    Icon {
                                        Layout.alignment: Qt.AlignHCenter
                                        size: 56
                                        color: Theme.line
                                        name: folderController.busy ? "sync" : (folderController.hasReport ? "filter" : "folder-tree")

                                        RotationAnimator on rotation {
                                            from: 0
                                            to: 360
                                            duration: 1400
                                            loops: Animation.Infinite
                                            running: folderController.busy
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Theme.muted
                                        font.pixelSize: Theme.typography.title
                                        font.bold: true
                                        text: folderController.busy ? qsTr("Comparing folders…") : (folderController.hasReport ? qsTr("Nothing to show here") : (emptyState.hasFolders ? qsTr("Ready to compare") : qsTr("Compare two folders")))
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                        color: Theme.faint
                                        font.pixelSize: Theme.typography.label
                                        text: folderController.busy ? qsTr("Scanning and matching files between Folder A and Folder B.") : (folderController.hasReport ? qsTr("No items match the current filter.") : (emptyState.hasFolders ? qsTr("Press Start Comparison (%1) to scan both folders.").arg(window.hintText(window.startShortcut)) : qsTr("Choose Folder A and Folder B in the sidebar to begin.")))
                                    }
                                }
                            }
                        }
                    }
                }
            }

                DockPanel {
                    id: mediaPanel
                    title: qsTr("PREVIEW")
                    iconName: "eye"
                    floatable: true
                    SplitView.preferredWidth: 340
                    SplitView.minimumWidth: 220

                    MediaPreviewPanel {
                        anchors.fill: parent
                        node: window.previewNode
                    }
                }
            }

            DockPanel {
                id: consolePanel
                title: qsTr("CONSOLE")
                iconName: "info"
                collapsible: true
                floatable: true
                property real expandedHeight: Math.max(160, Math.round(window.height * 0.18))
                SplitView.minimumHeight: collapsed ? collapsedSize : 90
                SplitView.maximumHeight: collapsed ? collapsedSize : Infinity
                onCollapseToggled: {
                    SplitView.preferredHeight = collapsed ? collapsedSize : expandedHeight;
                    window.persistLayout();
                }

                ColumnLayout {
                    id: statusPanel
                    anchors.fill: parent
                    anchors.margins: Theme.space.md
                    spacing: Theme.space.sm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.sm
                        Label {
                            text: "STATUS"
                            color: Theme.muted
                            font.pixelSize: Theme.typography.body
                            font.family: Theme.typography.mono
                        }
                        Label {
                            Layout.fillWidth: true
                            text: folderController.statusText + "  /  " + folderController.progressText
                            color: Theme.text
                            elide: Text.ElideMiddle
                            font.pixelSize: Theme.typography.body
                            font.family: Theme.typography.mono
                            activeFocusOnTab: true

                            ToolTip.visible: (hoverArea.containsMouse || activeFocus) && truncated
                            ToolTip.text: text
                            ToolTip.delay: 300

                            HoverHandler {
                                id: hoverArea
                            }
                        }
                        AppButton {
                            iconName: "trash"
                            text: "Clear"
                            onClicked: folderController.clearLog()
                        }
                    }

                    ListView {
                        id: logView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: folderController.logEntries
                        spacing: Theme.space.xs
                        property bool autoScrollToLatest: true

                        onMovementStarted: {
                            if (!atYEnd) {
                                autoScrollToLatest = false;
                            }
                        }
                        onMovementEnded: {
                            if (atYEnd) {
                                autoScrollToLatest = true;
                            }
                        }
                        onCountChanged: {
                            if (autoScrollToLatest && count > 0) {
                                positionViewAtBeginning();
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AlwaysOn
                        }

                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool isError: modelData.indexOf("[ERROR]") >= 0
                            readonly property bool isWarn: modelData.indexOf("[WARN]") >= 0
                            width: ListView.view.width
                            radius: Theme.radius.sm
                            color: isError ? Theme.logErrorBg : (isWarn ? Theme.logWarnBg : "transparent")

                            implicitHeight: logText.implicitHeight + 6

                            // Severity stripe.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 3
                                radius: Theme.radius.sm
                                visible: parent.isError || parent.isWarn
                                color: parent.isError ? Theme.bad : Theme.warn
                            }

                            Text {
                                id: logText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: (parent.isError || parent.isWarn) ? 10 : 6
                                anchors.rightMargin: 6
                                text: modelData
                                color: parent.isError ? Theme.logErrorText : (parent.isWarn ? Theme.logWarnText : Theme.text)
                                elide: Text.ElideRight
                                font.pixelSize: Theme.typography.caption
                                font.family: Theme.typography.mono
                            }
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
            if (!targetRelPath || !folderController.folderA)
                return "";
            return folderController.folderA + "/" + targetRelPath;
        }
        function pathB() {
            if (!targetRelPath || !folderController.folderB)
                return "";
            return folderController.folderB + "/" + targetRelPath;
        }

        MenuItem {
            text: "◀ " + qsTr("Copy to A")
            enabled: folderController.canCopyToA
            onTriggered: folderController.copySelectedToA()
        }
        MenuItem {
            text: qsTr("Copy to B") + " ▶"
            enabled: folderController.canCopyToB
            onTriggered: folderController.copySelectedToB()
        }
        MenuSeparator {}
        MenuItem {
            text: "◀ " + qsTr("Move to A")
            enabled: folderController.canMoveToA
            onTriggered: folderController.moveSelectedToA()
        }
        MenuItem {
            text: qsTr("Move to B") + " ▶"
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
            spacing: Theme.space.sm
            Layout.fillWidth: true
            Label {
                text: qsTr("Profile name")
                color: Theme.text
            }
            AppTextField {
                id: profileNameField
                Layout.fillWidth: true
                placeholderText: qsTr("e.g. card-A vs backup")
            }
        }

        onAccepted: {
            if (profileNameField.text.length > 0) {
                folderController.saveProfile(profileNameField.text);
                profileCombo.model = folderController.listProfiles();
                profileCombo.currentIndex = profileCombo.find(profileNameField.text);
                profileNameField.text = "";
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
            planRows = folderController.buildSyncPlan(chosenMode, propagateDeletes, conflict);
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.space.md
                rowSpacing: 6

                Label {
                    text: qsTr("Mode:")
                    color: Theme.text
                }
                AppComboBox {
                    Layout.fillWidth: true
                    model: [qsTr("Mirror A → B"), qsTr("Mirror B → A"), qsTr("Two-way (newer wins)"), qsTr("Two-way (manual)")]
                    currentIndex: syncDialog.chosenMode
                    onActivated: {
                        syncDialog.chosenMode = currentIndex;
                        syncDialog.rebuild();
                    }
                }

                Label {
                    text: qsTr("Conflicts:")
                    color: Theme.text
                }
                AppComboBox {
                    Layout.fillWidth: true
                    model: [qsTr("Newer wins"), qsTr("Larger wins"), qsTr("Ask"), qsTr("Skip")]
                    currentIndex: syncDialog.conflict
                    onActivated: {
                        syncDialog.conflict = currentIndex;
                        syncDialog.rebuild();
                    }
                }

                AppCheckBox {
                    text: qsTr("Propagate deletes")
                    checked: syncDialog.propagateDeletes
                    onToggled: {
                        syncDialog.propagateDeletes = checked;
                        syncDialog.rebuild();
                    }
                }
                AppCheckBox {
                    text: qsTr("Dry run (preview only, no file changes)")
                    checked: syncDialog.dryRun
                    onToggled: syncDialog.dryRun = checked
                }
            }

            Label {
                text: qsTr("Planned actions: %1").arg(syncDialog.planRows.length)
                color: Theme.muted
                font.family: Theme.typography.mono
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: syncDialog.planRows
                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 30
                    color: index % 2 === 0 ? Theme.panel : Theme.panelAlt

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space.sm
                        anchors.rightMargin: Theme.space.sm
                        spacing: Theme.space.sm
                        Text {
                            width: 60
                            verticalAlignment: Text.AlignVCenter
                            height: parent.height
                            text: ["Copy", "Delete", "Rename", "Skip"][modelData.kind] || ""
                            color: modelData.kind === 1 ? Theme.bad : Theme.text
                            font.family: Theme.typography.mono
                            font.pixelSize: Theme.typography.caption
                        }
                        Text {
                            width: parent.width - 80
                            verticalAlignment: Text.AlignVCenter
                            height: parent.height
                            text: modelData.path + "  —  " + modelData.reason
                            color: Theme.text
                            elide: Text.ElideMiddle
                            font.family: Theme.typography.mono
                            font.pixelSize: Theme.typography.caption
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                AppButton {
                    text: qsTr("Refresh plan")
                    onClicked: syncDialog.rebuild()
                }
                Item {
                    Layout.fillWidth: true
                }
                AppButton {
                    variant: AppButton.Primary
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
            pathA = a;
            pathB = b;
            textMode = folderController.isTextFile(a) && folderController.isTextFile(b);
            if (textMode) {
                diffLines = folderController.loadTextDiff(a, b);
            } else {
                hexA = folderController.hexWindow(a, 0, 4096);
                hexB = folderController.hexWindow(b, 0, 4096);
            }
            open();
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.space.sm

            Label {
                text: contentDiffDialog.pathA + "  ⟷  " + contentDiffDialog.pathB
                color: Theme.muted
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.caption
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
                    color: modelData.kind === 1 ? Theme.diffInsertBg : modelData.kind === 2 ? Theme.diffDeleteBg : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        spacing: Theme.space.sm
                        Text {
                            width: 50
                            text: modelData.lineA > 0 ? modelData.lineA : ""
                            color: Theme.faint
                            font.family: Theme.typography.mono
                            font.pixelSize: Theme.typography.caption
                        }
                        Text {
                            width: 50
                            text: modelData.lineB > 0 ? modelData.lineB : ""
                            color: Theme.faint
                            font.family: Theme.typography.mono
                            font.pixelSize: Theme.typography.caption
                        }
                        Text {
                            width: parent.width - 130
                            text: (modelData.kind === 1 ? "+ " : modelData.kind === 2 ? "- " : "  ") + modelData.text
                            color: Theme.text
                            font.family: Theme.typography.mono
                            font.pixelSize: Theme.typography.caption
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            RowLayout {
                visible: !contentDiffDialog.textMode
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.space.sm
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    TextArea {
                        readOnly: true
                        text: contentDiffDialog.hexA
                        font.family: Theme.typography.mono
                        font.pixelSize: Theme.typography.caption
                        color: Theme.text
                        background: Rectangle {
                            color: Theme.panelAlt
                        }
                    }
                }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    TextArea {
                        readOnly: true
                        text: contentDiffDialog.hexB
                        font.family: Theme.typography.mono
                        font.pixelSize: Theme.typography.caption
                        color: Theme.text
                        background: Rectangle {
                            color: Theme.panelAlt
                        }
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
            spacing: Theme.space.md
            Layout.fillWidth: true

            Label {
                text: "The destination already contains:"
                font.bold: true
                color: Theme.text
            }
            Label {
                text: overwriteDialog.pendingInfo.relativePath ? overwriteDialog.pendingInfo.relativePath : ""
                color: Theme.accent
                font.family: Theme.typography.mono
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Rectangle {
                height: 1
                color: Theme.line
                Layout.fillWidth: true
            }

            GridLayout {
                columns: 2
                columnSpacing: Theme.space.lg
                rowSpacing: Theme.space.xs
                Layout.fillWidth: true

                Label {
                    text: "Source:"
                    color: Theme.muted
                }
                Label {
                    text: overwriteDialog.pendingInfo.sourceInfo ? overwriteDialog.pendingInfo.sourceInfo : ""
                    font.family: Theme.typography.mono
                    color: Theme.text
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Label {
                    text: "Destination:"
                    color: Theme.muted
                }
                Label {
                    text: overwriteDialog.pendingInfo.destInfo ? overwriteDialog.pendingInfo.destInfo : ""
                    font.family: Theme.typography.mono
                    color: Theme.text
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                height: 1
                color: Theme.line
                Layout.fillWidth: true
            }

            Label {
                text: "How do you want to proceed?"
                color: Theme.muted
                font.pixelSize: Theme.typography.body
            }

            RowLayout {
                spacing: Theme.space.sm
                Layout.fillWidth: true

                AppButton {
                    Layout.fillWidth: true
                    variant: AppButton.Primary
                    text: "Overwrite"
                    onClicked: {
                        folderController.confirmOverwrite("overwrite");
                        overwriteDialog.close();
                    }
                }
                AppButton {
                    Layout.fillWidth: true
                    text: "Overwrite All"
                    onClicked: {
                        folderController.confirmOverwrite("overwriteAll");
                        overwriteDialog.close();
                    }
                }
                AppButton {
                    Layout.fillWidth: true
                    text: "Skip"
                    onClicked: {
                        folderController.confirmOverwrite("skip");
                        overwriteDialog.close();
                    }
                }
                AppButton {
                    Layout.fillWidth: true
                    text: "Skip All"
                    onClicked: {
                        folderController.confirmOverwrite("skipAll");
                        overwriteDialog.close();
                    }
                }
                AppButton {
                    Layout.fillWidth: true
                    text: "Cancel"
                    onClicked: {
                        folderController.confirmOverwrite("cancel");
                        overwriteDialog.close();
                    }
                }
            }
        }
    }

    // ── Command palette (Ctrl/Cmd+K) ──────────────────────────────────────

    Shortcut {
        sequence: window.isMac ? "Meta+K" : "Ctrl+K"
        onActivated: {
            commandPalette.refresh();
            commandPalette.open();
        }
    }

    Popup {
        id: commandPalette
        modal: true
        focus: true
        width: Math.min(parent.width * 0.6, 560)
        x: Math.round((parent.width - width) / 2)
        y: Math.round(parent.height * 0.12)
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property var commands: []
        property string query: ""

        function refresh() {
            commands = [
                {
                    "title": qsTr("Start comparison"),
                    "icon": "play",
                    "run": function () {
                        folderController.startComparison();
                    }
                },
                {
                    "title": qsTr("Cancel comparison"),
                    "icon": "stop",
                    "run": function () {
                        folderController.cancelComparison();
                    }
                },
                {
                    "title": qsTr("Choose Folder A…"),
                    "icon": "folder",
                    "run": function () {
                        folderController.chooseFolderA();
                    }
                },
                {
                    "title": qsTr("Choose Folder B…"),
                    "icon": "folder",
                    "run": function () {
                        folderController.chooseFolderB();
                    }
                },
                {
                    "title": qsTr("Export report (TXT)"),
                    "icon": "file-text",
                    "run": function () {
                        folderController.exportTxt();
                    }
                },
                {
                    "title": qsTr("Export report (CSV)"),
                    "icon": "file-csv",
                    "run": function () {
                        folderController.exportCsv();
                    }
                },
                {
                    "title": qsTr("Open sync planner"),
                    "icon": "sync",
                    "run": function () {
                        syncDialog.rebuild();
                        syncDialog.open();
                    }
                },
                {
                    "title": qsTr("Clear log"),
                    "icon": "trash",
                    "run": function () {
                        folderController.clearLog();
                    }
                },
                {
                    "title": qsTr("Workspace: Compare"),
                    "icon": "split",
                    "run": function () {
                        window.applyWorkspace("Compare");
                    }
                },
                {
                    "title": qsTr("Workspace: Review"),
                    "icon": "split",
                    "run": function () {
                        window.applyWorkspace("Review");
                    }
                },
                {
                    "title": qsTr("Workspace: Triage"),
                    "icon": "split",
                    "run": function () {
                        window.applyWorkspace("Triage");
                    }
                },
                {
                    "title": qsTr("Theme: System"),
                    "icon": "theme-system",
                    "run": function () {
                        folderController.theme = "system";
                    }
                },
                {
                    "title": qsTr("Theme: Light"),
                    "icon": "theme-light",
                    "run": function () {
                        folderController.theme = "light";
                    }
                },
                {
                    "title": qsTr("Theme: Dark"),
                    "icon": "theme-dark",
                    "run": function () {
                        folderController.theme = "dark";
                    }
                }
            ];
        }

        function filtered() {
            if (query.length === 0)
                return commands;
            var q = query.toLowerCase();
            return commands.filter(function (c) {
                return c.title.toLowerCase().indexOf(q) >= 0;
            });
        }

        function runCurrent() {
            var items = filtered();
            if (commandList.currentIndex >= 0 && commandList.currentIndex < items.length) {
                var cmd = items[commandList.currentIndex];
                close();
                cmd.run();
            }
        }

        onOpened: {
            query = "";
            paletteSearch.text = "";
            commandList.currentIndex = 0;
            paletteSearch.forceActiveFocus();
        }

        background: Rectangle {
            color: Theme.panel
            border.color: Theme.line
            border.width: 1
            radius: Theme.radius.lg
        }

        contentItem: ColumnLayout {
            spacing: 0

            AppTextField {
                id: paletteSearch
                Layout.fillWidth: true
                Layout.margins: Theme.space.sm
                placeholderText: qsTr("Type a command…")
                onTextChanged: {
                    commandPalette.query = text;
                    commandList.currentIndex = 0;
                }
                Keys.onDownPressed: commandList.incrementCurrentIndex()
                Keys.onUpPressed: commandList.decrementCurrentIndex()
                Keys.onReturnPressed: commandPalette.runCurrent()
                Keys.onEnterPressed: commandPalette.runCurrent()
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.line
            }

            ListView {
                id: commandList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 320)
                clip: true
                model: commandPalette.filtered()
                currentIndex: 0
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    id: cmdRow
                    required property int index
                    required property var modelData
                    readonly property bool current: ListView.isCurrentItem
                    width: ListView.view.width
                    height: 36
                    color: current ? Theme.accent : (rowHover.hovered ? Theme.panelAlt : "transparent")

                    HoverHandler {
                        id: rowHover
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space.md
                        anchors.rightMargin: Theme.space.md
                        spacing: Theme.space.sm
                        Icon {
                            name: cmdRow.modelData.icon
                            size: 15
                            color: cmdRow.current ? Theme.accentText : Theme.muted
                        }
                        Label {
                            Layout.fillWidth: true
                            text: cmdRow.modelData.title
                            color: cmdRow.current ? Theme.accentText : Theme.text
                            font.pixelSize: Theme.typography.label
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            commandList.currentIndex = index;
                            commandPalette.runCurrent();
                        }
                    }
                }
            }
        }
    }

    // ── Controller signal connections ────────────────────────────────────

    Connections {
        target: folderController
        function onOverwriteNeeded(info) {
            overwriteDialog.pendingInfo = info;
            overwriteDialog.open();
        }
    }

    // ── Tree model for comparison results ─────────────────────────────────

    QtObject {
        id: treeModel

        property var fullTree: []
        property var expandedPaths: ({})
        property var flatItems: []

        function rebuild() {
            fullTree = folderController.buildComparisonTree();
            expandedPaths = {};
            flattenTree();
        }

        function toggleExpanded(relPath) {
            if (expandedPaths[relPath] !== undefined) {
                delete expandedPaths[relPath];
            } else {
                expandedPaths[relPath] = true;
            }
            flattenTree();
        }

        function flattenTree() {
            var items = [];
            function walk(nodes, depth) {
                for (var i = 0; i < nodes.length; i++) {
                    var node = nodes[i];
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
                    });
                    if (items[items.length - 1].isFolder && node.children.length > 0 && items[items.length - 1].expanded) {
                        walk(node.children, depth + 1);
                    }
                }
            }
            walk(fullTree, 0);
            flatItems = items;
        }
    }

    Connections {
        target: folderController
        function onHasReportChanged() {
            if (folderController.hasReport)
                treeModel.rebuild();
        }
    }
}
