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

-- GatherMate2's real shape: gmdbs[kind] is a proxy with string metadata keys, and a zone's nodes come through __index
-- from the base storage or, once a storage addon registers the zone, from a storage-map table.
local storageMap = { Extra = { [1413] = { [3560355000] = 201 }, [1414] = {} } }
local zoneStorage = { [1413] = "Extra", [1414] = "Extra" }
local proxy = setmetatable({
	__gm2_prefix = "Mine",
	__gm2_storage_map = storageMap,
	__gm2_base_storage = { [1411] = { [3560355000] = 201 }, [1412] = {} },
}, {
	__index = function(t, zone)
		local store = zoneStorage[zone] and t.__gm2_storage_map[zoneStorage[zone]] or t.__gm2_base_storage
		return store[zone]
	end,
})
GatherMate2 = { gmdbs = { Mining = proxy }, GetNodesForZone = function() end }
local zones = ns.GatherMate.Zones("Mining")
assert(
	#zones == 2 and zones[1] == 1411 and zones[2] == 1413,
	"the zones with nodes, from base storage and storage maps"
)
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
