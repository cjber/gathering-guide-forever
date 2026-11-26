# Changelog

What changed in each release, in the terms a player would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists.

Each version's entry is also its release notes on GitHub and CurseForge.

## [0.1.0] - 2026-11-26

<!-- discord-image: docs/screenshots/gathering-tour.png -->

### Added

- **A Gathering page in the world map's quest log.** It lists the best mining and herbalism zones for your skill with their skill range, travel time and skill-ups per ten minutes (a lap counts at least a node's respawn time and the trip to the zone), and a zone view with every node coloured by its chance to raise your skill.
- **Gathering tours.** Start a tour and Shortest Path Forever walks you through the zone's nodes in a loop, beginning at the node nearest you. Its journey line shows the way, the world map draws a small mining or herbalism pin on each node of the loop (a visited node is dropped, the next one clearer), and a Gathering Tour section in the objective tracker shows the stop number and the size of the loop. "Skip nodes with no skill-up" leaves out nodes that can no longer raise your skill.
- **A calm world map.** "Only show Gathering pins on the map" is on by default: GatherMate2's world map icons are hidden, and during a tour Shortest Path Forever's numbered stop markers and Adventure Guide Forever's map pins are set aside too, on versions of those addons that allow it. Stopping the tour brings the markers and pins back. GatherMate2's icons come back when you turn the option off, log out or disable the addon.
- **A live tally while you farm.** The Gathering Tour section counts what you loot on a tour, shows how many a list item still needs with a progress bar, and shows your gold per hour from Auctionator prices or the vendor price, once every item has one. The tally lasts as long as its tour and restarts with a new one.
- **Farm for a list.** Add herbs and ores to a shopping list with how many you need, see how many you carry, and start farming in the best zone for everything on it: the one that gets you the missing items soonest, the trip there included.
