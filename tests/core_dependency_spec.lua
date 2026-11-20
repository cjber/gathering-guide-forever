-- The TOC pin and tools/forever-core.txt name the same ForeverCore release, and the addon never names core as a
-- hard dependency (the client would skip the addon when core is missing).
local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local toc = H.Read("GatheringGuideForever.toc")
local pin = assert(toc:match("## X%-Forever%-Core: (%S+)"), "the TOC records the ForeverCore pin")
local pinned = H.Read("tools/forever-core.txt"):match("^%s*(.-)%s*$")
assert(pin == pinned, "TOC pin " .. pin .. " equals tools/forever-core.txt " .. pinned)
local dependencies = toc:match("## Dependencies: ([^\n]*)") or ""
assert(not dependencies:find("ForeverCore"), "ForeverCore is an optional dependency")
assert(toc:match("## OptionalDeps: [^\n]*ForeverCore"), "ForeverCore is listed under OptionalDeps")
print("core_dependency_spec ok")
