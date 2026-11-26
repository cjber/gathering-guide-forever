# AGENTS.md

Gathering Guide Forever is a WoW: Forever addon (Interface 16001) for Mining and Herbalism. It picks the best zones for
the player's skills, tours a zone's gathering nodes along a loop and farms for a shopping list. It runs on
ForeverCore and Shortest Path Forever (the pathing engine it drives through the public API), and reads GatherMate2's
node database when installed. Shortest Path Forever is the only addon this one asks for walking directions.

## Commands

```sh
stylua --check .
luacheck .
FOREVER_CORE=../forever-core python3 -m tools.forever_tools.specs   # every tests/*_spec.lua in parallel
bash tools/typecheck.sh                                            # LuaLS: CI runs it, about 5 GB locally
uv run --project tools --frozen --group dev ruff check tools && uv run --project tools --frozen --group dev ruff format --check tools
python3 tools/deadcode.py --check
python3 tools/repo_rules.py            # spf-through-adapter: only Core/Navigation.lua names Shortest Path Forever
python3 tools/changelog.py --check
python3 tools/forever_tools/credits.py --check
python3 tools/check_family.py && python3 tools/check_store_page.py && python3 tools/check_copy.py docs/curseforge.md README.md
```

CI jobs: `deadcode`, `check`, `python`, `typecheck`, `project-rules`, `workflows`, `secrets`, `package`; each is a
required check. `headless-smoke` is a commit status posted from the in-game agent, not a CI job. A release is a signed
`vX.Y.Z` tag after `python3 tools/changelog.py release X.Y.Z`; `release.yml` packages for GitHub and CurseForge.

## Layout and conventions

- `Core/` holds the namespace, GatherMate2 and skill data access, the planner and settings. `Journey/` holds the loop
  order and the tour. `UI/` holds the quest log panel, the tracker section and the map loop.
- Shortest Path Forever is reached only through `Core/Navigation.lua`, using its published `ShortestPathForever.API`
  (`NavigateRoute` with `{policy = "walking"}`, `ObserveStops`, `JourneyState`, `Cancel`, `Estimate`). Settings may read
  its saved farming options once, read-only. `tools/repo_rules.py` enforces this.
- Node skill requirements are `Data/NodeSkills.lua`, copied from SkillUp Forever's data; GatherMate2 does not hold them.
- Atlases from the client only, native aspect (`ns.Fit`), no minimap button, no chat messages. Vendored
  `tools/forever_tools` and `tools/forever_sim` refresh with
  `python3 tools/forever_tools/sync.py update --source ../forever-core`; never edit them here.
- `tools/forever-core.txt` pins the ForeverCore release and must equal the TOC's `X-Forever-Core`; the package
  carries that release under `Libs/ForeverCore`.

## Standards

- `wow-forever-addon`: https://github.com/cjber/forever-core/tree/main/.agents/skills/wow-forever-addon (the WFA-*
  requirements every WoW: Forever addon meets: UI look, assets, README and store page, CI and release)
- `repo-standards`: the RS-* requirements every cjber and agent-labs-dev repo meets; its `audit.py` checks this repo.
