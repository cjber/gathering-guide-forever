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
ns.Session = { ListChanged = function() end }
H.Load(ns, "Locales/enUS.lua", "Core/GatherMate.lua", "Core/Planner.lua")

-- GatherMate2's real shape: gmdbs[kind] is a proxy with string metadata keys, and a zone's nodes come through __index
-- from the base storage or, once a storage addon registers the zone, from a storage-map table.
ns.NodeNames, ns.NodeSkills = { [201] = "Copper Vein" }, { ["Copper Vein"] = { 186, 1 } }
local storageMap = { Extra = { [1413] = { [3560355000] = 201 }, [1414] = {} } }
local zoneStorage = { [1413] = "Extra", [1414] = "Extra" }
local proxy = setmetatable({
	__gm2_prefix = "Mine",
	__gm2_storage_map = storageMap,
	__gm2_base_storage = { [1411] = { [3560355000] = 201 }, [1412] = {}, [1415] = { [3560355000] = 999 } },
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
	"the zones with nodes the addon knows, from base storage and storage maps"
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

-- One plan covers every profession the player has: a zone's loop runs through the nodes of both, each judged at its
-- own skill, and a profession not learned brings none.
H.Load(ns, "Core/Skills.lua")
ns.Kinds = {
	{ kind = "Mining", line = 186, label = "Mining" },
	{ kind = "Herb Gathering", line = 182, label = "Herbalism" },
}
local mate, world = ns.GatherMate, ns.World
local fingerprint = "nodes"
ns.GatherMate = {
	Zones = function(kind)
		return kind == "Mining" and { 1, 2 } or { 2, 3 }
	end,
	Nodes = function(uiMapID, kind)
		if kind == "Mining" then
			return uiMapID == 3 and {} or { { name = "Vein", kind = kind, required = 1, uiMapID = uiMapID } }
		end
		return uiMapID == 1 and {} or { { name = "Flower", kind = kind, required = 100, uiMapID = uiMapID } }
	end,
	Fingerprint = function()
		return fingerprint
	end,
}
local spot = 1426
ns.World = {
	PlayerMap = function()
		return spot
	end,
}
local real = {
	Place = ns.Planner.Place,
	Loop = ns.Planner.Loop,
	ZoneName = ns.Planner.ZoneName,
	Plan = ns.Planner.Plan,
	Reach = ns.Planner.Reach,
	Best = ns.Planner.Best,
}
ns.Planner.Place = function(nodes)
	return nodes
end
ns.Planner.Loop = function(nodes)
	return nodes, 70
end
local names = { "Westfall", "Arathi Highlands", "Hillsbrad Foothills" }
ns.Planner.ZoneName = function(uiMapID)
	return names[uiMapID]
end
local both = { Mining = 40, ["Herb Gathering"] = 100 }
assert(table.concat(ns.Planner.Zones(both), ",") == "1,2,3", "the zones of either profession, once each")
assert(table.concat(ns.Planner.Zones({ Mining = 40 }), ",") == "1,2")
assert(#ns.Planner.Nodes(2, both) == 2 and #ns.Planner.Nodes(2, { Mining = 40 }) == 1)
local mixed = ns.Planner.Plan(2, both, true)
assert(mixed.count == 2 and mixed.expected == 1.75, "a yellow vein and an orange flower")
assert(mixed.ranges.Mining.highest == 1 and mixed.ranges["Herb Gathering"].lowest == 100)
assert(math.abs(mixed.rate - 1.75) < 1e-9, "skill-ups of both over one lap of a respawn")
assert(ns.Planner.Plan(3, { Mining = 40 }, true) == nil, "a zone with only the other profession's nodes")
local low = ns.Planner.Plan(2, { Mining = 40, ["Herb Gathering"] = 99 }, true)
assert(low.count == 1 and not low.ranges["Herb Gathering"], "each node is judged at its own skill")
local later = ns.Planner.NextRanks(mixed, both)
assert(later.Mining == 101 and later["Herb Gathering"] == 200, "each skill at where its highest node here goes grey")
later = ns.Planner.NextRanks(low, { Mining = 300, ["Herb Gathering"] = 99 })
assert(later.Mining == 300 and later["Herb Gathering"] == 99, "never below the player, nor moved without a node")
later = ns.Planner.NextRanks({ ranges = { Mining = { lowest = 230, highest = 230 } } }, { Mining = 240 })
assert(later.Mining == 299, "rated at the last skill that can still rise, never past the highest")

-- A zone search matches names, whatever the case, among the zones of the player's professions.
local found = ns.Planner.SearchZones("H", both)
assert(#found == 2 and found[1].name == "Arathi Highlands" and found[2].uiMapID == 3, "by name")
assert(#ns.Planner.SearchZones("hillsbrad", { Mining = 40 }) == 0)
assert(#ns.Planner.SearchZones("(", both) == 0, "typed text is not a pattern")

-- Best asks for a route only to the zones that can still make the list, and the trip counts in the order. It also says
-- how many zones can raise a skill.
local rates, reached = { [1] = 30, [2] = 20, [3] = 10, [4] = 9, [5] = 8, [6] = 0 }, 0
ns.Planner.Plan = function(uiMapID)
	return { uiMapID = uiMapID, rate = rates[uiMapID], expected = rates[uiMapID] }
end
ns.Planner.Reach = function(zone)
	reached = reached + 1
	zone.rate = zone.uiMapID == 1 and 5 or zone.rate
	return zone
end
ns.GatherMate.Zones = function()
	return { 1, 2, 3, 4, 5, 6 }
end
local top, total = real.Best({ Mining = 38 }, true, 2)
assert(top[1].uiMapID == 2 and top[2].uiMapID == 3 and total == 5, "a far zone drops below the near ones")
assert(top[1].rate == 20 and reached == 3, "zones that cannot beat the list are never reached: " .. reached)
reached = 0
local every = real.Best({ Mining = 38 }, true)
assert(#every == 5 and reached == 5 and every[5].uiMapID == 1, "without a limit every zone is reached")

-- The ranking is planned once: reopening reads memory, a fresh session reads the character's saved variables, and a
-- changed skill, GatherMate2 data, map or addon version plans again while the saved ranking stands in.
local version = "1.0.0"
C_AddOns = {
	GetAddOnMetadata = function()
		return version
	end,
}
ns.TOP_ZONES = 2
local plans, planned, limit = 0, 0, nil
ns.Planner.Best = function(_, _, asked)
	plans, limit = plans + 1, asked
	local range = { Mining = { lowest = 1, highest = 2 } }
	return { { uiMapID = 1, ranges = range, travel = 60, rate = 9, seconds = 600, count = 3, order = {} } }, 7
end
local function Open(rank, herbs, all)
	return ns.Planner.Ranking({ Mining = rank, ["Herb Gathering"] = herbs }, true, function()
		planned = planned + 1
	end, all)
end
local ranked = Open(38)
assert(plans == 1 and limit == 2 and #ranked.zones == 1 and ranked.total == 7, "the first open plans the top zones")
assert(Open(38) and plans == 1, "reopening does no planning")
ns.Planner.ClearResults()
ranked = Open(38)
assert(plans == 1 and ranked.zones[1].rate == 9 and ranked.total == 7, "a fresh session loads the saved ranking")
assert(ranked.zones[1].name == "Westfall" and ranked.zones[1].ranges.Mining.highest == 2 and not ranked.zones[1].order)
assert(#Open(38, nil, true).zones == 1 and plans == 2 and limit == nil, "every zone is planned only when asked for")
local function Again(why, ...)
	local before = plans
	ns.Planner.ClearResults()
	Open(...)
	assert(plans == before + 1, why .. " plans again")
end
Again("a new skill", 39)
Again("a second profession", 39, 10)
Again("its new skill", 39, 11)
fingerprint = "more"
Again("changed GatherMate2 data", 39, 11)
spot = 1411
Again("another map", 39, 11)
version = "1.0.1"
Again("a new addon version", 39, 11)
ns.Char.ranking = nil
Again("no saved ranking", 39, 11)
local async = ns.Planner.Async
ns.Planner.Async = function() end
ns.Planner.ClearResults()
assert(Open(40, 11).total == 7, "the saved ranking stands in while a new skill is planned")
assert(not Open(40), "a ranking saved for other professions never stands in")
-- A plan overtaken by a newer one finishes later and leaves the newer ranking saved.
local pending = {}
ns.Planner.Async = function(_, work, finish)
	pending[#pending + 1] = function()
		finish(work(function() end))
	end
end
ns.Planner.ClearResults()
Open(41, 11)
Open(42, 11)
pending[2]()
local newest = ns.Char.ranking.key
pending[1]()
assert(ns.Char.ranking.key == newest and newest:find("=42=", 1, true), "the newer ranking stays saved")
ns.Planner.Async = async
for name, fn in pairs(real) do
	ns.Planner[name] = fn
end
ns.GatherMate, ns.World = mate, world

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
	C_SkillInfo = {
		GetSkillLineInfoByID = function(line)
			return line == 186 and { skillLevel = 100, maxSkillLevel = 150 } or nil
		end,
	}
	ns.GatherMate.Zones = function()
		return { 1426, 2521 }
	end
	ns.GatherMate.Nodes = function(uiMapID)
		local nodes = {}
		for i = 1, loops[uiMapID].count do
			nodes[i] = { uiMapID = uiMapID, kind = "Mining", name = "Vein", required = 1, x = 0, y = 0 }
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
	local whole = 26215 * 12 / 183 / 7 + 12 * 5 + 217
	assert(math.abs(list[1].whole - whole) < 1e-6 and #list[1].lacking == 0, "the whole list, trip included")
	assert(list[1].found.ore == 183, "every node of the item is counted")
	missing = 600
	list = ns.Planner.ListZones(4)
	assert(list[1].uiMapID == 2521, "more than a lap missing: the denser zone wins on its full-lap rate")
	assert(list[1].whole == nil and list[1].lacking[1] == "ore", "a zone short of the list has no time for all of it")
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
	assert(#list[1].lacking == 1 and list[1].lacking[1] == "herb" and list[1].found.herb == nil, "what it lacks")

	-- A zone with exactly the nodes still missing walks them once: no respawn wait there either.
	ns.Planner.ListRows = function()
		return { { item = "ore", need = 5, have = 0 } }
	end
	list = ns.Planner.ListZones(4)
	local once = 70 / 7 + 5 * 5
	assert(#list[1].lacking == 0 and math.abs(list[1].whole - once) < 1e-6, "one pass over just enough nodes")
	assert(math.abs(list[1].rate - 5 / once * 600) < 1e-6, "and ranked at that pace")
end

-- Setting changes only a listed item.
do
	ns.Char.list = {}
	ns.Planner.AddItem("Copper Ore", 20)
	ns.Planner.SetNeed("Copper Ore", 45)
	ns.Planner.SetNeed("Tin Ore", 3)
	assert(#ns.Char.list == 1 and ns.Char.list[1].need == 45)
end

-- A zone's node table counts each kind of node, the commonest first and then by name.
do
	local types = ns.Planner.NodeTable({
		{ name = "Tin Vein", kind = "Mining", required = 65 },
		{ name = "Silver Vein", kind = "Mining", required = 75 },
		{ name = "Copper Vein", kind = "Mining", required = 1 },
		{ name = "Tin Vein", kind = "Mining", required = 65 },
	})
	assert(#types == 3 and types[1].name == "Tin Vein" and types[1].count == 2 and types[1].required == 65)
	assert(types[2].name == "Copper Vein" and types[3].name == "Silver Vein" and types[3].kind == "Mining")
end

-- The time to a skill is each point's lap length over the skill-ups a lap is expected to give that profession at that
-- rank, and the other profession's nodes only lengthen the lap.
do
	local function Node(kind)
		return { kind = kind, required = 1 }
	end
	local zone = { order = { Node("Mining"), Node("Mining"), Node("Herb Gathering") }, seconds = 600 }
	assert(ns.Planner.TimeToSkill(zone, "Mining", 1, 3) == 600, "two certain points from two veins a lap")
	assert(ns.Planner.TimeToSkill(zone, "Herb Gathering", 1, 3) == 1200, "one a lap from one herb")
	assert(ns.Planner.TimeToSkill(zone, "Mining", 40, 42) == 800, "yellow nodes give one and a half a lap")
	assert(ns.Planner.TimeToSkill(zone, "Mining", 100, 101) == 1200, "green nodes give half a point a lap")
	assert(ns.Planner.TimeToSkill(zone, "Mining", 100, 102) == nil, "a point the loop cannot give leaves it unknown")
	assert(ns.Planner.TimeToSkill(zone, "Mining", 3, 3) == nil, "nothing left to raise")
	assert(ns.Planner.SkillAfter(zone, "Mining", 1, 10, 600) == 3, "the rank reached in a time")
	assert(ns.Planner.SkillAfter(zone, "Mining", 1, 10, 599) == 2, "only whole points")
	assert(ns.Planner.SkillAfter(zone, "Mining", 1, 2, 600) == 2, "never past the maximum")
	assert(ns.Planner.SkillAfter(zone, "Mining", 100, 150, 1e9) == 101, "nor past what the loop can give")
	local goals = ns.Planner.Goals(zone, {
		{ kind = "Mining", rank = 1, max = 3 },
		{ kind = "Herb Gathering", rank = 75, max = 75 },
	})
	assert(#goals == 1 and goals[1].skill.kind == "Mining" and goals[1].seconds == 600, "a skill at its maximum is out")
end

-- A node wears its item's icon, a vein its ore's, and an unknown name the profession's atlas.
do
	ns.ItemIDs = { ["Copper Ore"] = 2770 }
	ns.OreNodes = { ["Copper Ore"] = { "Copper Vein" } }
	ns.KIND_ATLAS = { Mining = "ore" }
	C_Item = {
		GetItemIconByID = function(id)
			return id * 10
		end,
	}
	assert(ns.Planner.Icon("Copper Vein", "Mining") == 27700 and ns.Planner.Icon("Copper Ore", "Mining") == 27700)
	assert(ns.Planner.Icon("Odd Vein", "Mining") == "ore")
end

-- The best zone at some skills is the first of a ranking of one at them, and nothing while it is being planned.
do
	local result, best, gather, at = ns.Planner.Result, ns.Planner.Best, ns.GatherMate, ns.World
	ns.GatherMate = {
		Fingerprint = function()
			return "nodes"
		end,
	}
	ns.World = {
		PlayerMap = function()
			return 1
		end,
	}
	ns.Planner.Best = function(ranks, _, asked)
		return { { uiMapID = ranks.Mining * 10 + asked } }, 1
	end
	ns.Planner.Result = function(_, work)
		return work()
	end
	assert(ns.Planner.BestAt({ Mining = 150 }, true, function() end).uiMapID == 1501)
	ns.Planner.Result = function()
		return nil
	end
	assert(ns.Planner.BestAt({ Mining = 150 }, true, function() end) == nil)
	ns.Planner.Result, ns.Planner.Best, ns.GatherMate, ns.World = result, best, gather, at
end

-- Two views waiting for one plan are both told when it arrives.
do
	local finish
	ns.Planner.Async = function(_, _, arrived)
		finish = finish or arrived
	end
	local first, second = 0, 0
	local function First()
		first = first + 1
	end
	local function Second()
		second = second + 1
	end
	ns.Planner.ClearResults()
	assert(ns.Planner.Result("shared", nil, First) == nil)
	ns.Planner.Result("shared", nil, Second)
	ns.Planner.Result("shared", nil, Second)
	finish(7)
	assert(first == 1 and second == 1, "each waiting view once")
	assert(ns.Planner.Result("shared", nil, First) == 7 and first == 1, "a kept result calls nobody")
end

print("planner_spec ok")
