# Third-party inputs

Everything Gathering Guide Forever is built from that it did not write itself: where each comes from, its licence, and
whether any of it reaches the zip players install. The addon itself is GPL-3.0-or-later ([LICENSE](LICENSE)).

## Ships in the zip

| Input | Used for | Pin | Licence |
|---|---|---|---|
| [Shortest Path Forever](https://github.com/cjber/shortest-path-forever) | The loop order (`Journey/Order.lua`) and the stop batching (`Journey/Tour.lua`) are ported from its farming tour, `Journey/FarmingOrder.lua` and `Journey/FarmingCursor.lua` | Its `main` branch when ported | GPL-3.0-or-later |
| [SkillUp Forever](https://github.com/cjber/skillup-forever) `Data/Sources.lua`, from [CMaNGOS classic-db](https://github.com/cmangos/classic-db) and wago.tools | The skill each herb and ore node needs, in `Data/NodeSkills.lua`, except Demonsage and Heavy Thorium Vein | classic-db `22b51464f1625f6ef6275771de1f5466c6f5d19e`; wago.tools Lock, `wow_classic_beta 1.60.1.70959` | GPL-3.0 |
| [GatherMate2](https://www.curseforge.com/wow/addons/gathermate2) by Kagaro, Xinhuan, Nevcairiel and Ammo | The node ID numbers and English names in `Data/NodeNames.lua`, from its `Constants.lua`. Node locations are read from the player's own database at runtime; `Core/GatherMate.lua` is a reader written for this addon | GatherMate2 1.52.7 | GPL-2.0-or-later |
| [wago.tools](https://wago.tools/db2/ItemSparse) ItemSparse | The item ID of each herb and ore, in `Data/Items.lua` | `1.60.1.71091`; Demonsage and Heavy Thorium Ore `1.60.1.71139` | Game data |
| Wowhead's Forever tooltips for objects [566786](https://nether.wowhead.com/forever/tooltip/object/566786) and [566779](https://nether.wowhead.com/forever/tooltip/object/566779) | The skill Demonsage and Heavy Thorium Vein need, in `Data/NodeSkills.lua` | Read 27 November 2026 | Game data |

The map pins in `media/Nodes/`, one per herb and ore, are original art made for this addon with AI assistance
(Google's `gemini-nano-banana-2.1`) and no Blizzard art. `tools/export_nodes.py` exports them from the originals in
`tools/pin_source/`.

## Read in game, never bundled

| Input | Used for | Licence |
|---|---|---|
| Shortest Path Forever | Walking the tour, through its public `ShortestPathForever.API` only | GPL-3.0-or-later |
| GatherMate2 | Node locations | GPL-2.0-or-later |

## Build and test only

| Input | Used for | Pin | Licence |
|---|---|---|---|
| [Ketho's WoW API annotations](https://github.com/Ketho/vscode-wow-api) | lua-language-server types in `tools/typecheck.sh` | `revision` in `tools/typecheck.sh` | MIT |
| [forever_tools](https://github.com/cjber/forever-core/tree/main/.agents/skills/wow-forever-addon/tooling/forever_tools) | Shared lints and release checks, vendored in `tools/forever_tools/` | `revision` in `tools/forever_tools/MANIFEST.json` | MIT |
| Ko-fi, GitHub Sponsors and Discord buttons | The support buttons in the README, in `docs/*-button.png` | None | Their brand assets, used to link to their pages |

## Players

| Who | What | Notes |
|---|---|---|
