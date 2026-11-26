# Changelog

What changed in each release, in the terms a player would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists.

Each version's entry is also its release notes on GitHub and CurseForge.

## [Unreleased]

- Ships with the same shared code as your other Forever addons, so they keep working together.

### Added

- **A Gathering page in the world map's quest log.** It lists the best mining and herbalism zones for your skill with their skill range, travel time and skill-ups per ten minutes, and a zone view with every node coloured by its chance to raise your skill.
- **Gathering tours.** Start a tour and Shortest Path Forever walks you through the zone's nodes in a loop, beginning at the node nearest you. A breadcrumb trail on the world map and a Gathering Tour section in the objective tracker show where you are. "Skip nodes with no skill-up" leaves out nodes that can no longer raise your skill.
- **A live tally while you farm.** The Gathering Tour section in the objective tracker counts what you gather on a tour, shows how many a list item still needs with a progress bar, and shows your gold per hour from Auctionator prices or the vendor price. The tally starts with the tour, restarts on a new one and survives a /reload.
- **Farm for a list.** Add herbs and ores to a shopping list with how many you need, see how many you carry, and start farming in the best zone for everything on it.
