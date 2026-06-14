#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Generate qt/qml/components/IconPaths.qml from Lucide icon SVGs.

Lucide (https://lucide.dev) is MIT licensed. We do not ship the raw SVG files;
instead each icon's drawing is flattened into a single SVG path "d" string so it
can be rendered by a QtQuick.Shapes ShapePath and recolored at runtime against
the Theme. Run from the repo root:

    python3 scripts/generate-icon-paths.py

Requires network access to raw.githubusercontent.com. The generated file is
committed so normal builds need no network.
"""

from __future__ import annotations

import math
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

RAW = "https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/{}.svg"

# Curated set mapped to the app's needs. Key = name used in QML (Icon { name }),
# value = Lucide icon slug.
ICONS = {
    "folder": "folder",
    "folder-open": "folder-open",
    "folder-tree": "folder-tree",
    "chevron-right": "chevron-right",
    "chevron-down": "chevron-down",
    "chevron-up": "chevron-up",
    "chevron-left": "chevron-left",
    "close": "x",
    "more": "ellipsis",
    "search": "search",
    "play": "play",
    "stop": "square",
    "sync": "refresh-cw",
    "arrow-left": "arrow-left",
    "arrow-right": "arrow-right",
    "two-way": "arrow-right-left",
    "move-left": "arrow-left-to-line",
    "move-right": "arrow-right-to-line",
    "undo": "undo-2",
    "file-text": "file-text",
    "file-csv": "sheet",
    "save": "save",
    "trash": "trash-2",
    "reveal": "folder-symlink",
    "external": "external-link",
    "clipboard": "clipboard",
    "copy": "copy",
    "check": "check",
    "filter": "list-filter",
    "image": "image",
    "video": "film",
    "audio": "music",
    "file": "file",
    "waveform": "audio-waveform",
    "settings": "settings",
    "theme-light": "sun",
    "theme-dark": "moon",
    "theme-system": "monitor",
    "info": "info",
    "warning": "triangle-alert",
    "error": "circle-alert",
    "profile": "user",
    "split": "columns-2",
    "panel-left": "panel-left",
    "panel-bottom": "panel-bottom",
    "eye": "eye",
    "drive": "hard-drive",
    "diff": "git-compare",
    "open-file": "file-symlink",
    "zoom-fit": "scan",
    "rename": "pencil",
}


def fmt(n: float) -> str:
    s = f"{n:.3f}".rstrip("0").rstrip(".")
    return s if s != "-0" else "0"


def rounded_rect(x, y, w, h, rx, ry) -> str:
    rx = min(rx, w / 2)
    ry = min(ry, h / 2)
    if rx <= 0 and ry <= 0:
        return f"M{fmt(x)} {fmt(y)} h{fmt(w)} v{fmt(h)} h{fmt(-w)} Z"
    return (
        f"M{fmt(x+rx)} {fmt(y)} "
        f"h{fmt(w-2*rx)} a{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(rx)} {fmt(ry)} "
        f"v{fmt(h-2*ry)} a{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(-rx)} {fmt(ry)} "
        f"h{fmt(-(w-2*rx))} a{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(-rx)} {fmt(-ry)} "
        f"v{fmt(-(h-2*ry))} a{fmt(rx)} {fmt(ry)} 0 0 1 {fmt(rx)} {fmt(-ry)} Z"
    )


def circle(cx, cy, r) -> str:
    return (
        f"M{fmt(cx-r)} {fmt(cy)} "
        f"a{fmt(r)} {fmt(r)} 0 1 0 {fmt(2*r)} 0 "
        f"a{fmt(r)} {fmt(r)} 0 1 0 {fmt(-2*r)} 0"
    )


def ellipse(cx, cy, rx, ry) -> str:
    return (
        f"M{fmt(cx-rx)} {fmt(cy)} "
        f"a{fmt(rx)} {fmt(ry)} 0 1 0 {fmt(2*rx)} 0 "
        f"a{fmt(rx)} {fmt(ry)} 0 1 0 {fmt(-2*rx)} 0"
    )


def points_to_path(points: str, close: bool) -> str:
    nums = [float(v) for v in re.split(r"[ ,]+", points.strip()) if v]
    pts = list(zip(nums[0::2], nums[1::2]))
    if not pts:
        return ""
    d = "M" + " L".join(f"{fmt(x)} {fmt(y)}" for x, y in pts)
    return d + (" Z" if close else "")


def f(el, attr, default=0.0) -> float:
    v = el.get(attr)
    return float(v) if v is not None else default


def abs_leading_moveto(d: str) -> str:
    """Make a path's leading moveto absolute.

    SVG treats a leading relative `m` as absolute, but only when it is the first
    command of the path. Once several element paths are concatenated, a later
    sub-path starting with `m` would be taken relative to the previous sub-path's
    end. Rewriting the leading `m x y` to `M x y` (and re-tagging the following
    implicit linetos as relative `l`) makes each element self-positioning so
    concatenation is safe.
    """
    d = d.strip()
    if not d or d[0] != "m":
        return d
    m = re.match(r"m\s*(-?\d*\.?\d+)\s*,?\s*(-?\d*\.?\d+)(.*)$", d, re.S)
    if not m:
        return d
    x, y, rest = m.group(1), m.group(2), m.group(3)
    rest_stripped = rest.lstrip(" ,\t\n")
    if rest_stripped and rest_stripped[0] in "-.0123456789":
        return f"M{x} {y} l{rest_stripped}"
    return f"M{x} {y}{rest}"


def svg_to_path(svg: str) -> str:
    root = ET.fromstring(svg)
    parts: list[str] = []
    for el in root.iter():
        tag = el.tag.split("}")[-1]
        if tag == "path":
            d = el.get("d")
            if d:
                parts.append(abs_leading_moveto(d.strip()))
        elif tag == "line":
            parts.append(
                f"M{fmt(f(el,'x1'))} {fmt(f(el,'y1'))} L{fmt(f(el,'x2'))} {fmt(f(el,'y2'))}"
            )
        elif tag == "polyline":
            parts.append(points_to_path(el.get("points", ""), close=False))
        elif tag == "polygon":
            parts.append(points_to_path(el.get("points", ""), close=True))
        elif tag == "rect":
            rx = f(el, "rx", 0.0)
            ry = f(el, "ry", rx)
            parts.append(
                rounded_rect(f(el, "x"), f(el, "y"), f(el, "width"), f(el, "height"), rx, ry)
            )
        elif tag == "circle":
            parts.append(circle(f(el, "cx"), f(el, "cy"), f(el, "r")))
        elif tag == "ellipse":
            parts.append(ellipse(f(el, "cx"), f(el, "cy"), f(el, "rx"), f(el, "ry")))
    return " ".join(p for p in parts if p)


def main() -> int:
    out_lines = []
    ok = 0
    for name, slug in sorted(ICONS.items()):
        url = RAW.format(slug)
        try:
            with urllib.request.urlopen(url, timeout=20) as resp:
                svg = resp.read().decode("utf-8")
        except Exception as exc:  # noqa: BLE001
            print(f"  SKIP {name} ({slug}): {exc}", file=sys.stderr)
            continue
        d = svg_to_path(svg)
        if not d:
            print(f"  SKIP {name} ({slug}): no drawable elements", file=sys.stderr)
            continue
        out_lines.append(f'        "{name}": "{d}"')
        ok += 1
        print(f"  ok   {name} <- {slug}")

    body = ",\n".join(out_lines)
    qml = f"""// SPDX-License-Identifier: GPL-3.0-only
//
// Icon path data derived from Lucide (https://lucide.dev), MIT License,
// Copyright (c) for Lucide are held by the Lucide contributors. Each entry is a
// single flattened SVG path "d" string on a 24x24 grid, drawn with a round 2px
// stroke. GENERATED by scripts/generate-icon-paths.py — do not edit by hand.

pragma Singleton

import QtQuick

QtObject {{
    readonly property int gridSize: 24

    readonly property var paths: ({{
{body}
    }})

    function has(name) {{
        return paths[name] !== undefined;
    }}
}}
"""
    dest = Path("qt/qml/components/IconPaths.qml")
    dest.write_text(qml, encoding="utf-8")
    print(f"\nWrote {dest} with {ok} icons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
