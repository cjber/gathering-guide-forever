# Changelog

What changed in each release, in the terms a player would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists.

Each version's entry is also its release notes on GitHub and CurseForge.

## [0.1.0] - 2026-11-26

<!-- discord-image: docs/screenshots/gathering-tour.png -->

### Added

- **A Gathering page in the world map's quest log.** It ranks the best zones for your mining and herbalism skills with their skill ranges, travel time and skill-ups per ten minutes (a lap counts at least a node's respawn time and the trip to the zone). With both professions, one loop takes in veins and herbs together. The top zones show first with the rest a click away, and Search zones finds a zone by name.
- **A page for each zone.** Picking a zone turns the world map to it and pins its loop. See how long it takes to reach your trained maximum, every node coloured by its chance to raise your skill, and the next zones to move on to.
- **Gathering tours.** Start a tour and Shortest Path Forever walks you through the zone's nodes in a loop, beginning at the node nearest you. Its journey line shows the way (at full strength through the whole batch from Shortest Path Forever 1.47.0), the world map draws a small pin on each of the loop's nodes, with its own picture for every herb and ore (nearby nodes share a pin until you zoom in, a visited node is dropped, the next one clearer), and a Gathering Tour section in the objective tracker shows the next node and its distance, your place in the loop, each skill, your skill-ups and the zone to move on to. "Skip nodes with no skill-up" leaves out nodes that can no longer raise your skill.
- **A calm world map.** "Only show Gathering pins on the map" is on by default: GatherMate2's world map icons are hidden, and while the Gathering page is up or a tour runs the game's quest markers and the map pins of Shortest Path Forever, Adventure Guide Forever and Legacy Forever are hidden too. A tour's route also leaves out numbered stop markers. Those addons need a version that allows it. Markers come back when you leave the page and no tour is running. GatherMate2's icons come back when you turn the option off, log out or disable the addon.
- **A live tally while you farm.** The Gathering Tour section counts what you loot on a tour, shows how many a list item still needs with a progress bar, and shows your gold per hour from Auctionator prices or the vendor price, once every item has one. The tally lasts as long as its tour and restarts with a new one.
- **Farm for a list.** Add herbs and ores to a shopping list with how many you need, see how many you carry, and start farming in the best zone for the missing items you can gather now: the one that gets you them soonest, the trip there included. Items above your skill show the skill they need.
