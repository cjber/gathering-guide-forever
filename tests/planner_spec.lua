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

-- A lap is never shorter than a respawn, so a one-node zone cannot beat a real loop, and the trip there counts.
ns.WALK_YARDS_PER_SECOND, ns.SECONDS_PER_NODE, ns.NODE_RESPAWN_SECONDS = 7, 5, 600
local R = ns.NODE_RESPAWN_SECONDS
assert(ns.Planner.Seconds(0, 1) == R, "one node still takes a respawn")
local single = ns.Planner.Rate(1, ns.Planner.Seconds(0, 1), 0)
local loop = ns.Planner.Rate(20, ns.Planner.Seconds(2800, 20), 0)
assert(loop > single * 10, "a real loop beats a one-node zone")
assert(ns.Planner.Rate(20, ns.Planner.Seconds(2800, 20), 1320) < loop, "travel lowers the rate")
assert(
	ns.Planner.Rate(20, ns.Planner.Seconds(2800, 20), 3000) < ns.Planner.Rate(10, ns.Planner.Seconds(1400, 10), 0),
	"a far zone loses to a near one of similar yield"
)

-- The ranking is planned once: reopening reads memory, a fresh session reads the saved variables, and a changed
-- skill or GatherMate2 data plans again while the saved ranking stands in.
-- Best asks for a route only to the zones that can still make the list, and the trip counts in the order.
local realBest = ns.Planner.Best
local rates, reached = { [1] = 30, [2] = 20, [3] = 10, [4] = 9, [5] = 8 }, 0
ns.Planner.Plan = function(kind, uiMapID)
	return { kind = kind, uiMapID = uiMapID, rate = rates[uiMapID], expected = rates[uiMapID] }
end
ns.Planner.Reach = function(zone)
	reached = reached + 1
	zone.rate = zone.uiMapID == 1 and 5 or zone.rate
	return zone
end
ns.GatherMate.Zones = function()
	return { 1, 2, 3, 4, 5 }
end
local top = realBest("Mining", 38, true, 2)
assert(top[1].uiMapID == 2 and top[2].uiMapID == 3, "a far zone drops below the near ones")
assert(top[1].rate == 20 and reached == 3, "zones that cannot beat the list are never reached: " .. reached)

GetRealmName = function()
	return "Realm"
end
local version = "1.0.0"
C_AddOns = {
	GetAddOnMetadata = function()
		return version
	end,
}
ns.DB = {}
ns.TOP_ZONES = 3
local spot = 1426
ns.World = {
	PlayerMap = function()
		return spot
	end,
}
local plans, planned = 0, 0
ns.Planner.Zone = function(kind, uiMapID)
	return { kind = kind, uiMapID = uiMapID, rate = 4 }
end
ns.Planner.Best = function(kind)
	plans = plans + 1
	return { { kind = kind, uiMapID = 1411, lowest = 1, highest = 2, travel = 60, rate = 9, seconds = 600, count = 3 } }
end
local function Open(rank)
	local ranked, _, stale = ns.Planner.Ranking("Mining", rank, true, function()
		planned = planned + 1
	end)
	return ranked, stale
end
local ranked = Open(38)
assert(plans == 1 and #ranked == 2, "the first open plans")
assert(Open(38) and plans == 1, "reopening does no planning")
ns.Planner.ClearResults()
ranked = Open(38)
assert(plans == 1 and ranked[1].rate == 9 and ranked[1].name, "a fresh session loads the saved ranking")
local cached, stale = Open(39)
assert(plans == 2 and cached[1].uiMapID == 1411 and stale == false, "a new skill plans again")
ns.Planner.ClearResults()
GatherMate2.gmdbs.Mining.__gm2_base_storage[1411][9999999] = 202
local before = plans
ns.Planner.ClearResults()
Open(39)
assert(plans == before + 1, "changed GatherMate2 data plans again")
ns.DB.plans = nil
ns.Planner.ClearResults()
Open(39)
assert(plans == before + 2, "no saved ranking plans")

-- The player's own zone is always offered, and a move to another zone plans again.
ranked = Open(39)
assert(#ranked == 2 and ranked[2].uiMapID == 1426, "the current zone joins the best zones")
spot = 1411
ranked = Open(39)
assert(plans == before + 3 and #ranked == 1, "the current zone is not offered twice")
version = "1.0.1"
ns.Planner.ClearResults()
Open(39)
assert(plans == before + 4, "a new addon version plans again")

-- A list needs a finite number of nodes, so a far zone's trip is weighed against what is needed, not against its whole
-- lap: with 12 ore missing the near, smaller zone wins; with a whole lap or more missing the bigger zone's rate does.
do
	local loops = {
		[1426] = { count = 183, yards = 26215, travel = 217 },
		[2521] = { count = 294, yards = 27594, travel = 1475 },
	}
	local missing
	ns.Planner.Items = function()
		return { ore = { kind = "Mining", nodes = { "Vein" } } }
	end
	ns.Planner.ListRows = function()
		return { { item = "ore", need = 20, have = 20 - missing } }
	end
	ns.KindByName = { Mining = { line = 186 } }
	ns.Skills = {
		Rank = function()
			return 100
		end,
	}
	ns.GatherMate.Zones = function()
		return { 1426, 2521 }
	end
	ns.GatherMate.Nodes = function(uiMapID)
		local nodes = {}
		for i = 1, loops[uiMapID].count do
			nodes[i] = { uiMapID = uiMapID, name = "Vein", required = 1, x = 0, y = 0 }
		end
		return nodes
	end
	ns.Planner.Place = function(nodes)
		return nodes
	end
	local planning
	ns.Planner.Loop = function(nodes)
		planning = nodes[1].uiMapID
		return nodes, loops[planning].yards
	end
	ns.Planner.ZoneName = tostring
	ns.Navigation = {
		Estimate = function()
			return loops[planning].travel
		end,
	}

	missing = 12
	local list = ns.Planner.ListZones(4)
	assert(list[1].uiMapID == 1426, "12 missing: the near zone finishes first")
	missing = 600
	list = ns.Planner.ListZones(4)
	assert(list[1].uiMapID == 2521, "more than a lap missing: the denser zone wins on its full-lap rate")
	assert(math.abs(list[1].rate - 294 / (5412 + 1475) * 600) < 1e-6, "a whole lap is the full-lap rate")

	-- A zone is credited only with what its own nodes give, and a part lap has no respawn wait.
	loops = { [1426] = { count = 5, yards = 70, travel = 0 } }
	ns.GatherMate.Zones = function()
		return { 1426 }
	end
	ns.Planner.Items = function()
		return {
			ore = { kind = "Mining", nodes = { "Vein" } },
			herb = { kind = "Mining", nodes = { "Flower" } },
		}
	end
	ns.Planner.ListRows = function()
		return { { item = "ore", need = 2, have = 0 }, { item = "herb", need = 50, have = 0 } }
	end
	list = ns.Planner.ListZones(4)
	local part = 70 * 2 / 5 / 7 + 2 * 5
	assert(math.abs(list[1].rate - 2 / part * 600) < 1e-6, "two wanted veins, walked without a respawn wait")
end

-- Adding keeps a listed item's count; setting changes only a listed item.
do
	ns.Char.list = {}
	ns.Planner.AddItem("Copper Ore", 20)
	ns.Planner.SetNeed("Copper Ore", 45)
	ns.Planner.AddItem("Copper Ore", 20)
	ns.Planner.SetNeed("Tin Ore", 3)
	assert(#ns.Char.list == 1 and ns.Char.list[1].need == 45)
end

print("planner_spec ok")
