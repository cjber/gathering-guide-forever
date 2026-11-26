local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()
local recorded = {}
ns.core = {
	SafeCall = function(label, fn, ...)
		local ok, err = pcall(fn, ...)
		recorded[#recorded + 1] = { label = label, ok = ok, err = err }
	end,
}
ns.Defer = function(fn)
	fn()
end
debugprofilestop = os.clock
H.Load(ns, "Locales/enUS.lua", "Core/GatherMate.lua", "Core/Planner.lua")

-- GatherMate2 keeps its own metadata under string keys next to the zones; only the numeric keys are zones.
GatherMate2 = {
	gmdbs = {
		Mining = {
			[1411] = {},
			[1412] = {},
			__gm2_prefix = "Mining",
			__gm2_storage_map = {},
			__gm2_base_storage = {},
		},
	},
	GetNodesForZone = function() end,
}
local zones = ns.GatherMate.Zones("Mining")
assert(#zones == 2 and zones[1] == 1411 and zones[2] == 1412, "the metadata keys are not zones")
assert(#ns.GatherMate.Zones("Herb Gathering") == 0, "a kind GatherMate2 has no table for has no zones")

-- A plan that raises is reported to the caller and the report, and is not started twice for one key.
local done, failed = 0, 0
ns.Planner.Async("a", function()
	error("bad argument #1 to 'next'")
end, function()
	done = done + 1
end, function()
	failed = failed + 1
end)
assert(done == 0 and failed == 1, "the failure reaches the caller")
assert(#recorded == 1 and recorded[1].label == "planner" and not recorded[1].ok, "the error is recorded")
assert(ns.Planner.LastError():find("bad argument #1 to 'next'", 1, true), "the report has the message")

-- A plan that finishes reports its result.
local value
ns.Planner.Async("b", function()
	return 42
end, function(result)
	value = result
end, function()
	failed = failed + 1
end)
assert(value == 42 and failed == 1, "a finished plan is delivered")

print("planner_spec ok")
