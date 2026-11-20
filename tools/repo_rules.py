"""Check the rules this repository holds that no linter covers. CI runs it in the `project-rules` job.

- `spf-through-adapter`: Shortest Path Forever is reached only through Core/Navigation.lua, which uses its published
  `ShortestPathForever.API`. The one other file that may name the addon is Core/Settings.lua, which reads its saved
  farming settings and never calls it.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {"Core/Navigation.lua", "Core/Settings.lua", "Core/Core.lua"}
PATTERN = re.compile(r"ShortestPathForever(?!\w*(?:\.toc))")


def findings(root: Path) -> list[str]:
    hits = []
    for folder in ("Core", "Journey", "UI", "Data"):
        for path in sorted((root / folder).glob("*.lua")):
            rel = path.relative_to(root).as_posix()
            if rel in ALLOWED:
                continue
            for number, line in enumerate(path.read_text().splitlines(), 1):
                code = line.split("--", 1)[0]
                if PATTERN.search(code):
                    hits.append(f"{rel}:{number}: spf-through-adapter: use ns.Navigation for Shortest Path Forever.")
    return hits


def main() -> int:
    hits = findings(ROOT)
    for hit in hits:
        print(hit)
    return int(bool(hits))


if __name__ == "__main__":
    sys.exit(main())
