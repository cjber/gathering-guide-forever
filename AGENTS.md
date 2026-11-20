# AGENTS.md

Gathering Guide Forever is a WoW: Forever addon (Interface 16001) for Mining and Herbalism. It picks the best zones for
the player's skills, tours a zone's gathering nodes along a loop and farms for a shopping list. It requires
ForeverCore and Shortest Path Forever (the pathing engine it drives through the public API), and reads GatherMate2's
node database when installed. Shortest Path Forever is the only addon this one asks for walking directions.

## Standards

- `wow-forever-addon`: https://github.com/cjber/forever-core/tree/main/.agents/skills/wow-forever-addon (the WFA-*
  requirements every WoW: Forever addon meets: UI look, assets, README and store page, CI and release)
- `repo-standards`: the RS-* requirements every cjber and agent-labs-dev repo meets; its `audit.py` checks this repo.
