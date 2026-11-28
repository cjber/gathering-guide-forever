# Changelog

What changed in each release, in the terms a player would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists.

Each version's entry is also its release notes on GitHub and CurseForge.

## [0.2.2] - 2026-11-28

### Changed

- The starting zones' smaller nodes look different on the map. With this addon's own node icons (the default), Poor Copper Vein, Wilted Peacebloom and Stunted Silverleaf each wear their own picture, one nodule, petal or leaf short of the ordinary one, on the loop and on the minimap. Hovering a loop pin names them.

## [0.2.1] - 2026-11-27

### Fixed

- **The shopping list ranks its zones over several frames.** With Shortest Path Forever installed it could ask for a travel time to every zone in one frame, which could freeze the game.

## [0.2.0] - 2026-11-27

<!-- discord-image: docs/screenshots/gathering-tour.png -->

### Added

- **Hover a node pin.** It names its herbs and ores and, on a tour, where each comes in the loop.
- Choose the herb and ore icons under "Node icons" in the settings menu: this addon's pictures (the default), the game's item icons or GatherMate2's own. The choice covers the loop on the world map and GatherMate2's pins on the minimap and world map. On the minimap this addon's pictures and the item icons are see-through, and nodes close to you keep GatherMate2's hollow ring, so the game's tracking dot shows under them.

### Changed

- **Opening a zone starts its tour.** It starts when no tour or other journey is guiding you; a tour you stop stays stopped.
- **A calmer route line.** With Shortest Path Forever 1.49.0 or later, a tour draws a solid line with softly rounded corners over the leg you are on and the next four, the later ones faded.

### Fixed

- **A reload keeps your tour.** It carries on from the same node, with the same skill-up and loot counts.
- Tours no longer take long jumps across a zone or double back over it: the loop through the nodes is much shorter.
- A loop is ordered by walking distance, so it no longer detours round hills and walls to reach the next node. Shortest Path Forever measures the walks in the background once a zone's tour starts, which takes about half a minute for a couple of hundred nodes, longer in larger zones; the tour takes the new order at the next node you reach, and later tours in that zone start with it.

## [0.1.1] - 2026-11-27

### Added

- **Demonsage and Heavy Thorium Veins.** Both now show on the zone pages and in the farming list, at skill 300, with Demonsage and Heavy Thorium Ore as list items. They give no skill-up at the skill cap, so farming list tours visit them, and zone tours do with **Skip nodes with no skill-up** turned off.

### Changed

- **An empty GatherMate2 database says what to do.** With no nodes for your professions, the Gathering page explains how to import them with GatherMate2_Data, and the README lists the steps.

### Fixed

- **The tracker counts to the next colour change.** Each skill line shows your skill against the rank at which a node on the loop next changes colour, such as Mining 38 / 51 on a Copper loop, in place of your trained cap.
- **A closed Gathering page stays off the map.** A tour update no longer brings back the pins of the zone you were viewing after you close the page.
- **The last tracker line is drawn in full.** Letters such as g and y, and commas, keep their lower parts.

## [0.1.0] - 2026-11-26

<!-- discord-image: docs/screenshots/gathering-tour.png -->

### Added

- **A Gathering page in the world map's quest log.** It ranks the best zones for your mining and herbalism skills with their skill ranges, travel time and skill-ups per ten minutes (a lap counts at least a node's respawn time and the trip to the zone). With both professions, one loop takes in veins and herbs together. The top zones show first with the rest a click away, and Search zones finds a zone by name.
- **A page for each zone.** Picking a zone turns the world map to it and pins its loop. See how long it takes to reach your trained maximum, every node coloured by its chance to raise your skill, and the next zones to move on to.
- **Gathering tours.** Start a tour and Shortest Path Forever walks you through the zone's nodes in a loop, beginning at the node nearest you. Its journey line shows the way (at full strength through the whole batch from Shortest Path Forever 1.47.0), the world map draws a small pin on each of the loop's nodes, with its own picture for every herb and ore (nearby nodes share a pin until you zoom in, a visited node is dropped, the next one clearer), and a Gathering Tour section in the objective tracker shows the next node and its distance, your place in the loop, each skill, your skill-ups and the zone to move on to. "Skip nodes with no skill-up" leaves out nodes that can no longer raise your skill.
- **A calm world map.** "Only show Gathering pins on the map" is on by default: GatherMate2's world map icons are hidden, and while the Gathering page is up or a tour runs the game's quest markers and the map pins of Shortest Path Forever, Adventure Guide Forever and Legacy Forever are hidden too. A tour's route also leaves out numbered stop markers. Those addons need a version that allows it. Markers come back when you leave the page and no tour is running. GatherMate2's icons come back when you turn the option off, log out or disable the addon.
- **A live tally while you farm.** The Gathering Tour section counts what you loot on a tour, shows how many a list item still needs with a progress bar, and shows your gold per hour from Auctionator prices or the vendor price, once every item has one. The tally lasts as long as its tour and restarts with a new one.
- **Farm for a list.** Add herbs and ores to a shopping list with how many you need, see how many you carry, and start farming in the best zone for the missing items you can gather now: the one that gets you them soonest, the trip there included. Items above your skill show the skill they need.
