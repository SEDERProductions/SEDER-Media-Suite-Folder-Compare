// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick

// Central design-token system for the whole UI. Every color, spacing value,
// radius, type size, motion duration and elevation depth is resolved here so
// that components never hardcode style. `dark` is bound once in Main.qml to
// folderController.effectiveDark; all theme-dependent tokens react to it.
//
// Token groups use concrete inline-component types (SpacingTokens, etc.) rather
// than a bare QtObject so that accesses like Theme.space.md stay statically
// typed for qmllint and can be compiled by qmlcachegen.
QtObject {
    id: theme

    property bool dark: true

    // ── Color · surfaces ──────────────────────────────────────────────────
    readonly property color bg: dark ? "#12110f" : "#ece6d9"
    readonly property color panel: dark ? "#1f1d1a" : "#f8f4ea"
    readonly property color panelAlt: dark ? "#282521" : "#e3dccb"
    readonly property color rail: dark ? "#16140f" : "#2a261d"

    // ── Color · content ───────────────────────────────────────────────────
    readonly property color text: dark ? "#ece6d9" : "#16140f"
    readonly property color muted: dark ? "#c4bcad" : "#3f392e"
    readonly property color faint: dark ? "#948b7d" : "#5c5548"
    readonly property color line: dark ? "#3b362e" : "#d6cfbe"

    // ── Color · semantic ──────────────────────────────────────────────────
    readonly property color accent: "#c63b13"
    readonly property color accentDark: "#8a3a16"
    readonly property color accentText: "#fff7ee"
    readonly property color good: dark ? "#4cab7e" : "#1f7a4d"
    readonly property color warn: "#a47a3a"
    readonly property color bad: dark ? "#d25645" : "#c63b13"

    // ── Color · docking chrome / overlays (used from Phase C/D onward) ─────
    readonly property color gutter: dark ? "#0d0c0b" : "#cfc6b2"
    readonly property color overlayScrim: Qt.rgba(0, 0, 0, 0.5)
    readonly property color focusRing: Qt.rgba(0.776, 0.231, 0.075, 0.55)

    // ── Log severity tints (replaces the broken inline window.isDark logic) ─
    readonly property color logErrorBg: dark ? "#3b2323" : "#f9e8e8"
    readonly property color logErrorText: dark ? "#ff9e9e" : "#8a1c1c"
    readonly property color logWarnBg: dark ? "#3a321f" : "#fcf6df"
    readonly property color logWarnText: dark ? "#ffd88a" : "#7a5a0f"

    // ── Diff line tints ───────────────────────────────────────────────────
    readonly property color diffInsertBg: dark ? "#1e4a2a" : "#d7f0dd"
    readonly property color diffDeleteBg: dark ? "#4a1e1e" : "#f6dada"

    // ── Spacing scale (4 / 8 grid) ─────────────────────────────────────────
    component SpacingTokens: QtObject {
        readonly property int xs: 4
        readonly property int sm: 8
        readonly property int md: 12
        readonly property int lg: 16
        readonly property int xl: 24
        readonly property int xxl: 32
    }
    readonly property SpacingTokens space: SpacingTokens {}

    // ── Corner radii ───────────────────────────────────────────────────────
    component RadiusTokens: QtObject {
        readonly property int sm: 4
        readonly property int md: 6
        readonly property int lg: 10
        readonly property int pill: 999
    }
    readonly property RadiusTokens radius: RadiusTokens {}

    // ── Typography ────────────────────────────────────────────────────────
    component TypographyTokens: QtObject {
        readonly property string ui: "Manrope, Segoe UI, sans-serif"
        readonly property string mono: Qt.platform.os === "osx" ? "Menlo" : (Qt.platform.os === "windows" ? "Consolas" : "monospace")
        readonly property int caption: 11
        readonly property int body: 12
        readonly property int label: 13
        readonly property int title: 17
        readonly property int display: 22
    }
    readonly property TypographyTokens typography: TypographyTokens {}

    // ── Motion ────────────────────────────────────────────────────────────
    component MotionTokens: QtObject {
        readonly property int fast: 90
        readonly property int base: 160
        readonly property int slow: 240
        readonly property int easeStandard: Easing.OutCubic
        readonly property int easeEmphasized: Easing.OutBack
    }
    readonly property MotionTokens motion: MotionTokens {}

    // ── Elevation (shadow depths consumed via Elevation.qml from Phase D) ──
    component ElevationTokens: QtObject {
        readonly property real e1: 8
        readonly property real e2: 18
        readonly property real e3: 32
    }
    readonly property ElevationTokens elevation: ElevationTokens {}

    // ── Status helpers (moved out of Main.qml so panels can share them) ────
    function statusColor(statusCode) {
        if (statusCode === 0)
            return good;
        if (statusCode === 1)
            return bad;
        if (statusCode === 2 || statusCode === 3)
            return warn;
        return faint;
    }

    function statusText(statusCode) {
        if (statusCode === 0)
            return "✓ Matching";
        if (statusCode === 1)
            return "✗ Changed";
        if (statusCode === 2)
            return "▸ Only A";
        if (statusCode === 3)
            return "▸ Only B";
        if (statusCode === 4)
            return "Folder";
        return "Unknown";
    }

    function filterLabel(index) {
        return ["All", "Matching", "Changed", "Only A", "Only B", "Folders"][index];
    }
}
