// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Shapes
import Seder.UI

// A theme-recolorable line icon rendered from flattened Lucide path data
// (see IconPaths.qml). Using QtQuick.Shapes rather than a rasterized image means
// the icon stays crisp at any size and recolors to any Theme token by binding,
// with no QtGraphicalEffects/MultiEffect dependency.
//
//   Icon { name: "folder"; color: Theme.text; size: 16 }
Item {
    id: root

    property string name: ""
    property color color: Theme.text
    property int size: 16
    // Stroke width expressed in 24-grid units (Lucide's native 2px stroke).
    property real strokeWidth: 2

    readonly property string pathData: (name.length > 0 && IconPaths.has(name)) ? IconPaths.paths[name] : ""

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Shape {
        anchors.fill: parent
        antialiasing: true
        visible: root.pathData.length > 0
        // Map the 24-unit grid onto the requested pixel size. The stroke scales
        // with the transform, so a 2-unit stroke renders ~size/12 px.
        transform: Scale {
            xScale: root.size / IconPaths.gridSize
            yScale: root.size / IconPaths.gridSize
        }

        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: root.pathData
            }
        }
    }
}
