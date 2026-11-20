#!/usr/bin/env python3
"""Concept mockup for the gathering addon (cjber/shortest-path-forever#1131), drawn with forever-core's wowmock.

A direction preview, not a capture: every number and node position on it is illustrative. The planner lives where
Adventure Guide lives, as a side tab of the world map's quest log, so the zone it recommends and the tour through it
sit on the map beside it. Art follows Adventure Guide's panel: QuestLog-main-background, options_listexpand section
headers, the ui-journeys-renown-button journey card and common-button-list-large rows. gathering_v1.py is the first,
standalone-window take.

    python3 gathering.py        # writes gathering.png
"""

import math
import os
import random
import sys
from pathlib import Path

FOREVER_CORE = Path(os.environ.get("FOREVER_CORE", Path(__file__).resolve().parents[1] / "forever-core"))
sys.path.insert(0, str(FOREVER_CORE / "tools" / "wowmock"))

import wowmock
from PIL import Image, ImageChops, ImageDraw
from wowmock import FONTS, FRIZQT, Font

OUT = Path(__file__).resolve().parent
ARATHI = 1417
QUEST_LOG_WIDTH = 333  # QuestLogOwnerMixin's side panel width

GOLD = wowmock.rgb("ffd200")
WHITE = (1.0, 1.0, 1.0)
MUTED = wowmock.rgb("a0a0a0")
# The client's skill-up colours, and red for a node the player cannot gather yet.
SKILL = {
    "orange": wowmock.rgb("ff8040"),
    "yellow": wowmock.rgb("ffff00"),
    "green": wowmock.rgb("40c040"),
    "red": wowmock.rgb("ff2020"),
}
TITLE = Font(FRIZQT, 16, GOLD, (1, -1))  # GameFontNormalLarge
MED = Font(FRIZQT, 14, GOLD, (1, -1))  # GameFontNormalMed2
ROW_TITLE = Font(FRIZQT, 13, GOLD, (1, -1))
RATE = Font(FRIZQT, 13, WHITE, (1, -1))
SMALL = FONTS["GameFontHighlightSmall"]
NORMAL = FONTS["GameFontHighlight"]

ICON = {
    "mining": "Interface\\Icons\\Trade_Mining.blp",
    "herbalism": "Interface\\Icons\\Trade_Herbalism.blp",
}
PIN = {"mining": "worldquest-icon-mining", "herbalism": "worldquest-icon-herbalism"}

NODES = [  # item icon, name, count on the loop, colour, need, what next
    ("INV_Ore_Iron_01", "Iron Deposit", 38, "orange", 125, "yellow at 150"),
    ("INV_Misc_Herb_03", "Kingsblood", 31, "orange", 125, "yellow at 150"),
    ("INV_Ore_Tin_01", "Tin Vein", 24, "green", 65, "1 in 4"),
    ("INV_Misc_Flower_02", "Wild Steelbloom", 9, "yellow", 115, "green at 165"),
    ("INV_Misc_Root_02", "Liferoot", 14, "red", 150, "not yet"),
    ("INV_Ore_Gold_01", "Gold Vein", 5, "red", 155, "not yet"),
]

NEXT = [  # zone, levels, nodes, rate, travel
    ("Hillsbrad Foothills", "20-30", [("Iron", "orange"), ("Steelbloom", "orange"), ("Tin", "green")], "6.8", "9 min"),
    ("Stranglethorn Vale", "30-45", [("Iron", "orange"), ("Kingsblood", "orange"), ("Tin", "green")], "6.1", "14 min"),
]


def explored(ui, map_id):
    art = wowmock.map_art(ui, map_id)
    for o in wowmock.map_overlays(ui, map_id):
        wowmock.draw_overlay(ui, art, o.offset_x, o.offset_y, o.width, o.height, o.tiles)
    return art


def loop_points(rng, count):
    """Spawn-like points scattered over Arathi's land, ordered into a loop (nearest neighbour, then 2-opt)."""
    pts = []
    while len(pts) < count:
        x, y = rng.uniform(0.2, 0.78), rng.uniform(0.22, 0.8)
        if x < 0.26 and y > 0.55 or (x > 0.7 and y > 0.7):
            continue
        if all((x - a) ** 2 + (y - b) ** 2 > 0.0035 for a, b in pts):
            pts.append((x, y))
    order = [pts.pop(0)]
    while pts:
        last = order[-1]
        nxt = min(pts, key=lambda p: (p[0] - last[0]) ** 2 + (p[1] - last[1]) ** 2)
        pts.remove(nxt)
        order.append(nxt)

    def d(a, b):
        return math.hypot(a[0] - b[0], a[1] - b[1])

    improved = True
    while improved:
        improved = False
        for i in range(1, len(order) - 1):
            for j in range(i + 1, len(order)):
                a, b, c, e = order[i - 1], order[i], order[j], order[(j + 1) % len(order)]
                if d(a, c) + d(b, e) < d(a, b) + d(c, e) - 1e-9:
                    order[i : j + 1] = reversed(order[i : j + 1])
                    improved = True
    return order


def breadcrumbs(canvas, points, spacing=9, dot=4, rim=1):
    """Shortest Path's walked route: gold dots on a dark rim every `spacing` units."""
    k = canvas.ui.scale
    dots, walked = [], 0.0
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        length = math.hypot(bx - ax, by - ay)
        t = math.ceil(walked / spacing) * spacing - walked
        while length and t <= length:
            dots.append((ax + (bx - ax) * t / length, ay + (by - ay) * t / length))
            t += spacing
        walked += length
    for radius, colour in ((dot / 2 + rim, (0.04, 0.04, 0.04, 0.5)), (dot / 2, (*GOLD, 1))):
        layer = Image.new("RGBA", canvas.image.size)
        draw = ImageDraw.Draw(layer)
        for x, y in dots:
            box = ((x - radius) * k, (y - radius) * k, (x + radius) * k, (y + radius) * k)
            draw.ellipse(box, fill=wowmock.rgba255(colour))
        canvas.image.alpha_composite(layer)


def header(canvas, x, y, w, label, trailing=None):
    """Adventure Guide's section header: the options_listexpand bar with its label."""
    ui = canvas.ui
    left, right = ui.atlas("options_listexpand_left"), ui.atlas("options_listexpand_right")
    h = 23
    lw, rw = left.width * h / left.height, right.width * h / right.height
    canvas.draw(left, x, y, lw, h)
    canvas.draw(right, x + w - rw, y, rw, h)
    canvas.draw(ui.atlas("_options_listexpand_middle"), x + lw, y, w - lw - rw, h)
    canvas.text(x + 8, y, label, MED, box_height=h)
    if trailing:
        canvas.text(x, y, trailing, SMALL, MUTED, justify="RIGHT", width=w - 22, box_height=h)


def ring_icon(canvas, cx, cy, size, icon):
    """An icon in the journey ring, masked round as Adventure Guide's chapter card draws it."""
    ui = canvas.ui
    layer = ui.canvas(canvas.width, canvas.height)
    inner = size * 0.64
    layer.draw(ui.texture(icon), cx - inner / 2, cy - inner / 2, inner, inner)
    mask = ui.texture("interface/characterframe/tempportraitalphamask.blp")
    layer.mask(mask, cx - inner / 2, cy - inner / 2, inner, inner)
    canvas.paste(layer, 0, 0)
    canvas.draw(ui.atlas("ui-journeys-renown-radial-bar"), cx - size / 2, cy - size / 2, size, size)


def panel(canvas, x, y, w, h):
    ui = canvas.ui
    canvas.draw(ui.atlas("QuestLog-main-background"), x, y, w, h)
    pad = 12
    cx, cw = x + pad, w - pad * 2

    # Title, as Adventure Guide's, with a back button to the zone picker in place of the icon.
    back_button(canvas, cx + 2, y + 12)
    canvas.text(cx + 40, y + 12, "Gathering Guide", TITLE, justify="CENTER", width=cw - 40)
    canvas.text(cx + 40, y + 32, "Mining 142  ·  Herbalism 138", SMALL, justify="CENTER", width=cw - 40)

    # The journey card: the recommended zone and its tour.
    cy = y + 58
    card_h = 88
    canvas.draw(ui.atlas("ui-journeys-renown-button"), cx, cy, cw, card_h)
    ring_icon(canvas, cx + 40, cy + card_h / 2, 58, ICON["herbalism"])
    tx = cx + 76
    canvas.text(tx, cy + 14, "Arathi Highlands", MED)
    canvas.text(tx, cy + 15, "6 min", SMALL, justify="RIGHT", width=cx + cw - 14 - tx)
    canvas.text(tx, cy + 34, "7.9 skill-ups per 10 min", SMALL)
    canvas.text(tx, cy + 50, "Both skills to 150 in about 24 min", SMALL, MUTED)
    canvas.text(tx, cy + 64, "102 nodes  ·  14 min loop", SMALL, MUTED)

    # The nodes on this loop, one 22-unit row each, coloured by skill-up chance.
    sy = cy + card_h + 10
    header(canvas, cx, sy, cw, "On this tour", "skill")
    ry = sy + 28
    for icon, name, count, colour, need, note in NODES:
        dim = colour == "red"
        tint = (1, 1, 1, 0.5) if dim else (1, 1, 1, 1)
        canvas.draw(ui.texture(f"Interface\\Icons\\{icon}.blp"), cx + 6, ry + 2, 18, 18, tint)
        canvas.text(cx + 30, ry, name, NORMAL, SKILL[colour], box_height=22)
        canvas.text(cx + 134, ry + 1, f"{count}", SMALL, MUTED if dim else WHITE, justify="RIGHT", width=40, box_height=22)
        canvas.text(cx + 186, ry + 1, note, SMALL, MUTED, box_height=22)
        canvas.text(cx, ry + 1, f"{need}", SMALL, MUTED, justify="RIGHT", width=cw - 10, box_height=22)
        ry += 20
    wowmock.minimal_checkbox(canvas, cx + 4, ry + 6, "Skip nodes with no skill-up", size=22, checked=True, font=SMALL)

    # Where to go next, as Adventure Guide's library rows.
    ny = ry + 34
    header(canvas, cx, ny, cw, "Next zones", "per 10 min")
    row_y = ny + 28
    row_h = 46
    for zone, levels, nodes, rate, travel in NEXT:
        canvas.draw(ui.atlas("common-button-list-large"), cx, row_y, cw, row_h)
        canvas.text(cx + 12, row_y + 7, zone, ROW_TITLE)
        canvas.text(cx + 18 + canvas.text_width(zone, ROW_TITLE), row_y + 10, levels, SMALL, MUTED)
        canvas.text(cx, row_y + 8, rate, RATE, justify="RIGHT", width=cw - 12)
        nx = cx + 12
        for name, colour in nodes:
            canvas.text(nx, row_y + 25, name, SMALL, SKILL[colour])
            nx += canvas.text_width(name, SMALL) + 10
        canvas.text(cx, row_y + 25, travel, SMALL, MUTED, justify="RIGHT", width=cw - 12)
        row_y += row_h + 4

    wowmock.three_slice_button(canvas, cx + (cw - 180) / 2, y + h - 32, 180, 24, "Start tour")


WANT = [  # item icon, name, have, need, source node, nodes on the loop
    ("INV_Ore_Iron_01", "Iron Ore", 6, 20, "Iron Deposit", 38),
    ("INV_Misc_Herb_03", "Kingsblood", 3, 10, "Kingsblood", 31),
    ("INV_Ore_Gold_01", "Gold Ore", 0, 4, "Gold Vein", 5),
]

ELSEWHERE = [  # zone, what it covers, time for the whole list, travel
    ("Badlands", [("Iron Ore", True), ("Gold Ore", True), ("Kingsblood", False)], "26 min", "18 min"),
    ("Stranglethorn Vale", [("Iron Ore", True), ("Kingsblood", True), ("Gold Ore", True)], "29 min", "14 min"),
]


def bar(canvas, x, y, w, h, value):
    """A thin progress bar: dark trough, gold fill."""
    canvas.fill(x, y, w, h, (0, 0, 0, 0.6))
    canvas.fill(x + 1, y + 1, (w - 2) * value, h - 2, (*GOLD, 0.85))


def panel_list(canvas, x, y, w, h):
    """Farm for a list: the items you need, the best place to get them all, and the alternatives."""
    ui = canvas.ui
    canvas.draw(ui.atlas("QuestLog-main-background"), x, y, w, h)
    pad = 12
    cx, cw = x + pad, w - pad * 2

    ring_icon(canvas, cx + 20, y + 28, 40, ICON["mining"])
    canvas.text(cx + 40, y + 12, "Gathering Guide", TITLE, justify="CENTER", width=cw - 40)
    canvas.text(cx + 40, y + 32, "Farm for a list", SMALL, justify="CENTER", width=cw - 40)

    sy = y + 58
    header(canvas, cx, sy, cw, "Shopping list", "have / need")
    ry = sy + 28
    for icon, name, have, need, _, _ in WANT:
        canvas.draw(ui.texture(f"Interface\\Icons\\{icon}.blp"), cx + 6, ry + 2, 26, 26)
        canvas.text(cx + 40, ry + 1, name, NORMAL)
        canvas.text(cx, ry + 1, f"{have} / {need}", SMALL, WHITE, justify="RIGHT", width=cw - 10)
        bar(canvas, cx + 40, ry + 19, cw - 50, 7, have / need)
        ry += 32
    wowmock.search_box(canvas, cx + 6, ry + 4, cw - 12, instructions="Add an item")

    cy = ry + 36
    card_h = 88
    canvas.draw(ui.atlas("ui-journeys-renown-button"), cx, cy, cw, card_h)
    ring_icon(canvas, cx + 40, cy + card_h / 2, 58, ICON["herbalism"])
    tx = cx + 76
    canvas.text(tx, cy + 14, "Arathi Highlands", MED)
    canvas.text(tx, cy + 15, "6 min", SMALL, justify="RIGHT", width=cx + cw - 14 - tx)
    canvas.text(tx, cy + 34, "Whole list in about 21 min", SMALL)
    canvas.text(tx, cy + 50, "Iron 38  ·  Kingsblood 31  ·  Gold 5", SMALL, MUTED)
    canvas.text(tx, cy + 64, "Loop skips nodes you don't need", SMALL, MUTED)

    ny = cy + card_h + 10
    header(canvas, cx, ny, cw, "Other places", "whole list")
    row_y = ny + 28
    row_h = 46
    for zone, items, total, travel in ELSEWHERE:
        canvas.draw(ui.atlas("common-button-list-large"), cx, row_y, cw, row_h)
        canvas.text(cx + 12, row_y + 7, zone, ROW_TITLE)
        canvas.text(cx, row_y + 7, total, RATE, justify="RIGHT", width=cw - 12)
        nx = cx + 12
        for name, has in items:
            canvas.text(nx, row_y + 25, name, SMALL, WHITE if has else SKILL["red"])
            nx += canvas.text_width(name, SMALL) + 10
        canvas.text(cx, row_y + 25, travel, SMALL, MUTED, justify="RIGHT", width=cw - 12)
        row_y += row_h + 4

    wowmock.three_slice_button(canvas, cx + (cw - 180) / 2, y + h - 32, 180, 24, "Start farming")


EASTERN_KINGDOMS = 1415
PLAYER_LEVEL = 34
ZONES = [  # name, levels, rate per 10 min, travel, nodes, map position on Eastern Kingdoms
    ("Arathi Highlands", (30, 40), "7.9", "6 min", [("Iron", "orange"), ("Kingsblood", "orange"), ("Tin", "green")], (0.53, 0.335)),
    ("Hillsbrad Foothills", (20, 30), "6.8", "9 min", [("Iron", "orange"), ("Steelbloom", "orange"), ("Tin", "green")], (0.41, 0.335)),
    ("The Hinterlands", (40, 50), "6.4", "11 min", [("Gold", "red"), ("Iron", "orange"), ("Liferoot", "red")], (0.585, 0.245)),
    ("Stranglethorn Vale", (30, 45), "6.1", "14 min", [("Iron", "orange"), ("Kingsblood", "orange"), ("Tin", "green")], (0.48, 0.84)),
    ("Badlands", (35, 45), "5.9", "22 min", [("Iron", "orange"), ("Gold", "red"), ("Kingsblood", "orange")], (0.62, 0.56)),
    ("Alterac Mountains", (30, 40), "5.2", "8 min", [("Iron", "orange"), ("Tin", "green"), ("Steelbloom", "orange")], (0.45, 0.235)),
    ("Wetlands", (20, 30), "4.4", "12 min", [("Tin", "green"), ("Bruiseweed", "yellow")], (0.535, 0.44)),
]


def level_colour(levels):
    """The client's difficulty colours for a zone's range against the player's level."""
    gap = levels[0] - PLAYER_LEVEL
    if gap >= 5:
        return SKILL["red"]
    if gap >= 3:
        return SKILL["orange"]
    if levels[1] >= PLAYER_LEVEL:
        return SKILL["yellow"]
    return SKILL["green"]


def back_button(canvas, x, y):
    canvas.draw(canvas.ui.atlas("common-icon-backarrow"), x, y, 32, 32)


def zone_badges(show_levels):
    """Each zone's rate (and level range, when shown) on the continent map; the best zone carries the ring."""

    def draw(ui, art, at):
        for index, (name, levels, rate, _, _, pos) in enumerate(ZONES):
            px, py = at(*pos)
            w, h = 58, 34 if show_levels else 22
            left, top = px - w / 2, py - h / 2
            edge = (*GOLD, 0.9) if index == 0 else (0.5, 0.5, 0.5, 0.6)
            art.fill(left - 1, top - 1, w + 2, h + 2, edge)
            art.fill(left, top, w, h, (0, 0, 0, 0.78))
            art.text(left, top + 3, rate, RATE, GOLD if index == 0 else WHITE, justify="CENTER", width=w)
            if show_levels:
                art.text(left, top + 19, f"{levels[0]}-{levels[1]}", SMALL, level_colour(levels), justify="CENTER", width=w)
        arrow = ui.atlas("UI-WorldMapArrow")
        ax, ay = at(0.5, 0.39)
        art.draw(arrow, ax - 12, ay - 12, 24, 24)

    return draw


def panel_zones(show_levels):
    """No zone chosen: every zone ranked for the player's skills, with a toggle for level ranges."""

    def draw(canvas, x, y, w, h):
        ui = canvas.ui
        canvas.draw(ui.atlas("QuestLog-main-background"), x, y, w, h)
        pad = 12
        cx, cw = x + pad, w - pad * 2
        ring_icon(canvas, cx + 20, y + 28, 40, ICON["mining"])
        canvas.text(cx + 40, y + 12, "Gathering Guide", TITLE, justify="CENTER", width=cw - 40)
        canvas.text(cx + 40, y + 32, "Mining 142  ·  Herbalism 138", SMALL, justify="CENTER", width=cw - 40)

        wowmock.search_box(canvas, cx + 6, y + 60, cw - 12, instructions="Search zones")
        wowmock.minimal_checkbox(canvas, cx + 4, y + 86, "Show level ranges", size=22, checked=show_levels, font=SMALL)

        sy = y + 114
        header(canvas, cx, sy, cw, "Best for you", "per 10 min")
        row_y, row_h = sy + 28, 44
        for index, (name, levels, rate, travel, nodes, _) in enumerate(ZONES[:6]):
            atlas = "common-button-list-large-selected" if index == 0 else "common-button-list-large"
            canvas.draw(ui.atlas(atlas), cx, row_y, cw, row_h)
            canvas.text(cx + 12, row_y + 6, name, ROW_TITLE)
            if show_levels:
                lx = cx + 18 + canvas.text_width(name, ROW_TITLE)
                canvas.text(lx, row_y + 8, f"{levels[0]}-{levels[1]}", SMALL, level_colour(levels))
            canvas.text(cx, row_y + 6, rate, RATE, justify="RIGHT", width=cw - 12)
            nx = cx + 12
            for node, colour in nodes:
                canvas.text(nx, row_y + 24, node, SMALL, SKILL[colour])
                nx += canvas.text_width(node, SMALL) + 10
            canvas.text(cx, row_y + 24, travel, SMALL, MUTED, justify="RIGHT", width=cw - 12)
            row_y += row_h + 3

    return draw


MINE = "|A:worldquest-icon-mining:12:11|a"
HERB = "|A:worldquest-icon-herbalism:12:12|a"
OVERVIEW_ZONES = [  # name, levels, mining range, herbalism range, rate, nodes, travel
    ("Arathi Highlands", "30-40", "125-175", "115-160", "7.9 skill-ups per 10 min", "Iron, Kingsblood and Tin", "6 min"),
    ("Hillsbrad Foothills", "20-30", "65-155", "70-150", "6.8 skill-ups per 10 min", "Iron, Steelbloom and Tin", "9 min"),
]


def card(canvas, x, y, w, h, icon, title, right, subline, reason, corner, progress=None):
    """Adventure Guide's journey card: ringed icon, title with its ranges on the right, two lines, a corner note."""
    ui = canvas.ui
    canvas.draw(ui.atlas("ui-journeys-renown-button"), x, y, w, h)
    ring_icon(canvas, x + 30, y + h / 2, 44, icon)
    tx = x + 58
    canvas.text(tx, y + 9, title, ROW_TITLE)
    canvas.text(tx, y + 27, subline, SMALL, WHITE)
    for row, line in enumerate(right):
        canvas.text(tx, y + 11 + row * 16, line, SMALL, WHITE, justify="RIGHT", width=x + w - 10 - tx)
    if progress is not None:
        canvas.fill(tx, y + 45, 70, 6, (0, 0, 0, 0.7))
        canvas.fill(tx + 1, y + 46, 68 * progress, 4, (0.1, 0.75, 0.1, 1))
    elif reason:
        canvas.text(tx, y + 42, reason, SMALL, MUTED)
    canvas.text(tx, y + h - 19, corner, SMALL, MUTED, justify="RIGHT", width=x + w - 10 - tx)


def section(canvas, x, y, w, label, count=None):
    header(canvas, x, y, w, label)
    if count:
        canvas.text(x, y, count, MED, justify="RIGHT", width=w - 30, box_height=23)


def panel_overview():
    """No zone chosen, as Adventure Guide's overview: what to continue, then the best zones as journey cards."""

    def draw(canvas, x, y, w, h):
        ui = canvas.ui
        wowmock.search_box(canvas, x + 6, y + 2, w - 26, instructions="Search zones")
        canvas.draw(ui.atlas("questlog-icon-setting"), x + w - 18, y + 4, 15, 16)
        canvas.draw(ui.atlas("QuestLog-main-background"), x, y + 29, w, h - 29)
        cx, cw = x + 6, w - 12
        ring_icon(canvas, cx + 22, y + 52, 30, ICON["mining"])
        canvas.text(cx + 40, y + 36, "Gathering Guide", TITLE, justify="CENTER", width=cw - 40)
        canvas.text(cx + 40, y + 55, "Level 34  ·  Mining 142  ·  Herbalism 138", SMALL, WHITE, justify="CENTER", width=cw - 40)

        def ranges(mining, herb):
            return (f"{MINE} {mining}", f"{HERB} {herb}")

        sy = y + 76
        section(canvas, cx, sy, cw, "Continue")
        cy = sy + 27
        card(canvas, cx, cy, cw, 66, ICON["mining"], "Arathi Highlands tour", (),
             "Node 9 of 30  ·  11 skill-ups so far", None, "9 of 30", progress=9 / 30)
        cy += 70
        card(canvas, cx, cy, cw, 66, "Interface\\Icons\\INV_Ore_Iron_01.blp", "Farm for a list", (),
             "Iron Ore 6 of 20, and 2 more", None, "9 of 34", progress=9 / 34)
        cy += 76
        section(canvas, cx, cy, cw, "Best zones for you", "7")
        cy += 27
        for name, levels, mining, herb, rate, nodes, travel in OVERVIEW_ZONES:
            card(canvas, cx, cy, cw, 66, ICON["herbalism"] if "Hills" in name else ICON["mining"], name,
                 ranges(mining, herb), rate, nodes, travel)
            cy += 70
        canvas.draw(ui.atlas("_options_listexpand_middle"), cx, cy + 2, cw, 22, (1, 1, 1, 0.6))
        canvas.text(cx + 12, cy + 2, "5 more: click to show", SMALL, GOLD, box_height=22)
        canvas.text(cx, cy + 2, "+", MED, WHITE, justify="RIGHT", width=cw - 10, box_height=22)

    draw.search_row = 29
    return draw


def arathi_pins(ui, art, at):
    """The overview's map: the zone you are in with its known nodes, no tour yet."""
    loop = loop_points(random.Random(1417), 30)
    for index, p in enumerate(loop):
        pin = ui.atlas(PIN["herbalism" if index % 3 == 1 else "mining"])
        pw, ph = pin.width * 1.6, pin.height * 1.6
        px, py = at(*p)
        art.draw(pin, px - pw / 2, py - ph / 2, pw, ph)
    arrow = ui.atlas("UI-WorldMapArrow")
    ax, ay = at(*loop[0])
    art.draw(arrow, ax - 14, ay - 14, 28, 28)


def arathi_loop(ui, art, at):
    rng = random.Random(1417)
    loop = loop_points(rng, 30)
    breadcrumbs(art, [at(*p) for p in loop] + [at(*loop[0])])
    for index, p in enumerate(loop):
        pin = ui.atlas(PIN["herbalism" if index % 3 == 1 else "mining"])
        pw, ph = pin.width * 1.6, pin.height * 1.6
        px, py = at(*p)
        art.draw(pin, px - pw / 2, py - ph / 2, pw, ph)
    # Nodes the player cannot gather yet stay on the map, dimmed and off the loop.
    for p in [(0.62, 0.33), (0.31, 0.27), (0.55, 0.74), (0.44, 0.48)]:
        pin = ui.atlas(PIN["herbalism"])
        pw, ph = pin.width * 1.6, pin.height * 1.6
        px, py = at(*p)
        art.draw(pin, px - pw / 2, py - ph / 2, pw, ph, (1, 1, 1, 0.35))
    arrow = ui.atlas("UI-WorldMapArrow")
    ax, ay = at(*loop[0])
    art.draw(arrow, ax - 14, ay - 14, 28, 28)


def window(draw_panel=None, map_id=ARATHI, nav=("World", "Eastern Kingdoms", "Arathi Highlands"), map_extras=None):
    ui = wowmock.Ui(scale=1.2)
    m = wowmock.WORLD_MAP_MARGIN
    w, h = wowmock.WORLD_MAP_WIDTH + QUEST_LOG_WIDTH, wowmock.WORLD_MAP_HEIGHT
    canvas = ui.canvas(w + 2 * m + 64, h + 2 * m)
    rock = ui.texture("interface/framegeneral/ui-background-rock.blp")
    wowmock.tiled(canvas, rock, m + 2, m + 21, w - 4, h - 23, rock.width / ui.scale, rock.height / ui.scale)
    container = (m + 2, m + wowmock.WORLD_MAP_SPACER, wowmock.WORLD_MAP_WIDTH - 5, h - 2 - wowmock.WORLD_MAP_SPACER)
    cx, cy, cw, ch = container
    art_image = explored(ui, map_id)
    scale = min(cw / art_image.width, ch / art_image.height)
    mw, mh = art_image.width * scale, art_image.height * scale
    mx, my = cx + (cw - mw) / 2, cy + (ch - mh) / 2

    def at(nx, ny):
        return mx + nx * mw, my + ny * mh

    art = ui.canvas(canvas.width, canvas.height)
    art.draw(art_image, mx, my, mw, mh)

    (map_extras or arathi_loop)(ui, art, at)

    keep = Image.new("L", art.image.size, 0)
    keep.paste(255, tuple(canvas.px(v) for v in (cx, cy, cx + cw, cy + ch)))
    art.image.putalpha(ImageChops.multiply(art.image.getchannel("A"), keep))
    canvas.paste(art, 0, 0)

    canvas.draw(ui.atlas("_UI-Frame-InnerTopTile"), m + 2, m + 63, cw, 3)
    nav_x, nav_y = m + 2 + 64, m + 25
    nav_w = (m + wowmock.WORLD_MAP_WIDTH - 3 + wowmock.WORLD_MAP_NAVBAR_X_OFFSET) - nav_x
    nav_h = (m + wowmock.WORLD_MAP_SPACER - 9) - nav_y
    nav = list(nav)
    wowmock.nav_bar(canvas, nav_x, nav_y, nav_w, nav_h, nav, nav[1:])
    canvas.draw(ui.atlas("common-dropdown-a-button"), nav_x + nav_w + 14, nav_y + nav_h / 2 - 8)
    toggle_x, toggle_y = cx + cw - 2 - 32, cy + ch - 1 - 32
    corner = ui.atlas("MapCornerShadow-Right")
    canvas.draw(corner, toggle_x + 34 - corner.width, toggle_y + 33 - corner.height)
    canvas.draw(ui.atlas("QuestCollapse-Hide-Up"), toggle_x, toggle_y, 32, 32)

    # The quest log's pane, its border, and the planner in it.
    qx, qy, qw, qh = m + w - 3 - 330, m + 25, 330, h - 25 - 3
    draw_panel = draw_panel or panel
    draw_panel(canvas, qx, qy, qw, qh)
    top = getattr(draw_panel, "search_row", 0)
    canvas.draw(ui.atlas("questlog-frame"), qx - 3, qy + top - 7, qw + 6, qh - top + 13)
    filigree = ui.atlas("questlog-frame-filigree")
    canvas.draw(filigree, qx + (qw - filigree.width) / 2, qy + top - 8)

    canvas.nine_slice(wowmock.camelot_layout(wowmock.PORTRAIT_FRAME_LAYOUT), m, m, w, h)
    portrait = ui.canvas(canvas.width, canvas.height)
    portrait.draw(ui.texture("interface/questframe/ui-questlog-bookicon.blp"), m - 5, m - 7, 62, 62)
    portrait.mask(ui.texture("interface/characterframe/tempportraitalphamask.blp"), m - 3, m - 7, 58, 58)
    canvas.paste(portrait, 0, 0)
    canvas.text(m + 58, m + 6, "Map & Quest Log", FONTS["GameFontNormal"], justify="CENTER", width=w - 82)
    canvas.draw(ui.atlas("RedButton-Exit"), m + w - 23, m, 24, 24)
    canvas.draw(ui.atlas("RedButton-Expand"), m + w - 48, m, 24, 24)

    # Side tabs: the quest log's own, then the planner's, selected.
    tab_x = m + w + 2
    quest = ui.atlas("questlog-questtypeicon-quest").image
    tab_h = wowmock.side_tab(canvas, tab_x, qy + 40, quest)
    wowmock.side_tab(canvas, tab_x, qy + 40 + tab_h + 2, ICON["mining"], selected=True)
    return wowmock.scene(ui, [(canvas, 0, 0)], margin=20)


if __name__ == "__main__":
    window().save(OUT / "gathering.png")
    window(panel_list).save(OUT / "gathering-list.png")
    window(panel_overview(), map_extras=arathi_pins).save(OUT / "gathering-overview.png")
    print("done")
