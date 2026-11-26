# Changelog

What changed in each release, in the terms a player would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists.

Each version's entry is also its release notes on GitHub and CurseForge.

## [Unreleased]

- Ships with the same shared code as your other Forever addons, so they keep working together.

### Added

- **A Gathering page in the world map's quest log.** It lists the best mining and herbalism zones for your skill with their skill range, travel time and skill-ups per ten minutes (a lap counts at least a node's respawn time and the trip to the zone), and a zone view with every node coloured by its chance to raise your skill.
- **Gathering tours.** Start a tour and Shortest Path Forever walks you through the zone's nodes in a loop, beginning at the node nearest you. Shortest Path Forever's journey line and our small pins on the world map, and a Gathering Tour section in the objective tracker show where you are: the stop number Shortest Path Forever shows, and the size of the loop. "Skip nodes with no skill-up" leaves out nodes that can no longer raise your skill.
- **A calm world map.** "Only show Gathering pins on the map" is on by default: GatherMate2's world map icons are hidden, and during a tour Shortest Path Forever's numbered stop markers and Adventure Guide Forever's map pins are set aside too, on versions of those addons that allow it. Your own settings come back when you turn it off, stop the tour, log out or disable the addon. The way between tour stops is Shortest Path Forever's journey line.
- **A live tally while you farm.** The Gathering Tour section in the objective tracker counts what you loot on a tour, shows how many a list item still needs with a progress bar, and shows your gold per hour from Auctionator prices or the vendor price, once every item has one. The tally lasts as long as its tour and restarts with a new one.
- **Farm for a list.** Add herbs and ores to a shopping list with how many you need, see how many you carry, and start farming in the best zone for everything on it. The best zone is the one that gets you the missing items soonest, the trip there included, so a small list is not sent across the world for a bigger loop.
