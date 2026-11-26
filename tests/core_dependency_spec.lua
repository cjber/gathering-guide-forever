-- The addon never names ForeverCore as a hard dependency (the client would skip it when core is missing).
local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local toc = H.Read("GatheringGuideForever.toc")
local dependencies = toc:match("## Dependencies: ([^\n]*)") or ""
assert(not dependencies:find("ForeverCore"), "ForeverCore is an optional dependency")
assert(toc:match("## OptionalDeps: [^\n]*ForeverCore"), "ForeverCore is listed under OptionalDeps")
print("core_dependency_spec ok")
