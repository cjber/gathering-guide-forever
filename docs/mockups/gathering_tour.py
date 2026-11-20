#!/usr/bin/env python3
"""Concept mockup: the gathering tour while you follow it (cjber/shortest-path-forever#1131).

A direction preview, not a capture; numbers and positions are illustrative. The minimap carries the loop as Shortest
Path's dotted trail with the tour's node pins, and the objective tracker gains a Gathering Tour module under the
quest list: the next node, both skills, the session rate and when to move on.

    python3 gathering_tour.py   # writes gathering-tour.png
"""

import math
import random

import gathering  # noqa: F401  (puts wowmock on the path)
import wowmock
from gathering import OUT, PIN, breadcrumbs, loop_points
from wowmock import FONTS, TrackerBlock, TrackerModule

EASTERN_KINGDOMS = 0
HERE = (-1340.0, -2390.0)  # illustrative world position in Arathi Highlands
ICON = "|TInterface\\Icons\\{}.blp:13:13|t "


def centred(canvas, atlas, x, y, size=None):
    art = canvas.ui.atlas(atlas)
    w, h = (size, size) if size else (art.width, art.height)
    canvas.draw(art, x - w / 2, y - h / 2, w, h)


def minimap(ui):
    canvas = ui.canvas(230, 230)
    cx, cy, size, radius = 115, 120, 198, 233 + 1 / 3
    face = ui.canvas(size, size)
    face.draw(wowmock.minimap_art(ui, EASTERN_KINGDOMS, *HERE, radius), 0, 0, size, size)
    # A stretch of the loop around the player: the same deterministic tour, scaled up to minimap range.
    loop = loop_points(random.Random(1417), 30)
    ox, oy = loop[0]
    pts = [(size / 2 + (x - ox) * 520, size / 2 + (y - oy) * 520) for x, y in loop[-4:] + loop[:6]]
    breadcrumbs(face, pts, spacing=8, dot=3.5)
    for index, (x, y) in enumerate(pts):
        if index in (3,):  # the node just gathered is gone from the minimap
            continue
        if 6 < x < size - 6 and 6 < y < size - 6:
            pin = ui.atlas(PIN["herbalism" if index % 3 == 1 else "mining"])
            face.draw(pin, x - pin.width * 0.65, y - pin.height * 0.65, pin.width * 1.3, pin.height * 1.3)
    face.mask(ui.atlas("ui-hud-minimap-frame-generic-mask").image, 0, 0, size, size)
    canvas.paste(face, cx - size / 2, cy - size / 2)
    centred(canvas, "UI-HUD-Minimap-Frame", cx, cy)
    centred(canvas, "MinimapArrow", cx, cy, 16)
    canvas.text(0, 6, "Arathi Highlands", FONTS["GameFontNormal"], justify="CENTER", width=230)
    return canvas


def tracker(ui):
    quests = TrackerModule(
        "Quests",
        [TrackerBlock("Hints of a New Plague?", ["Forsaken Courier slain: 0/1"])],
    )
    tour = TrackerModule(
        "Gathering Tour",
        [
            TrackerBlock(
                "Arathi Highlands  ·  node 9 of 30",
                [
                    ("|cffff8040Iron Deposit|r  85 yd", ICON.format("INV_Ore_Iron_01")),
                    "Mining 146 / 150",
                    "Herbalism 141 / 150",
                    "11 skill-ups  ·  8.2 per 10 min",
                ],
            ),
            TrackerBlock(
                "Next: Hillsbrad Foothills",
                [("At Mining 150, in about 4 min", False)],
            ),
        ],
    )
    canvas, _ = wowmock.objective_tracker(ui, [quests, tour])
    return canvas


def main():
    ui = wowmock.Ui(scale=1.2)
    mm = minimap(ui)
    tr = tracker(ui)
    w = max(mm.width, tr.width) + 40
    page = wowmock.backdrop(ui, w, mm.height + tr.height + 30)
    page.paste(mm, w - mm.width - 10, 10)
    page.paste(tr, w - tr.width - 14, mm.height + 14)
    wowmock.scene(ui, [(page, 0, 0)], margin=20).save(OUT / "gathering-tour.png")
    print(OUT / "gathering-tour.png")


if __name__ == "__main__":
    main()
