local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()
ns.WALK_YARDS_PER_SECOND, ns.SECONDS_PER_NODE = 7, 5
ns.core = {
	SafeCall = function(_, fn, ...)
		return fn(...)
	end,
}
ns.Kinds = { { kind = "Mining", line = 186, label = "Mining" } }
ns.KindByName = { Mining = ns.Kinds[1] }
C_SkillInfo = {
	GetSkillLineInfoByID = function()
		return { skillLevel = 60, maxSkillLevel = 75 }
	end,
}
H.Load(ns, "Locales/enUS.lua", "Core/Skills.lua", "Journey/Order.lua", "Core/Planner.lua")

-- Zones of different sizes and spreads, the way GatherMate2 holds a continent: a few hundred nodes each.
local zones = {}
for map = 1, 6 do
	local nodes = {}
	for i = 1, 50 * map do
		nodes[i] = {
			uiMapID = map,
			kind = "Mining",
			coord = i,
			nodeID = 1,
			x = ((i * 7919) % 1000) / 1000,
			y = ((i * 104729) % 1000) / 1000,
			wx = ((i * 7919) % 1000) * map,
			wy = (i * 104729) % 1000,
			required = 1,
			name = "Copper Vein",
		}
	end
	zones[map] = nodes
end
ns.GatherMate = {
	Zones = function()
		return { 1, 2, 3, 4, 5, 6 }
	end,
	Nodes = function(map)
		return zones[map]
	end,
}
ns.World = {
	Point = function() end,
}
-- The nodes already carry world coordinates; the planner places them through the world.
ns.Planner.Place = function(nodes)
	return nodes
end

-- Every zone is planned in slices, and the best zones so far are offered as each one finishes, so cards can appear
-- before the last zone is done.
local slices, offers = 0, {}
local best = ns.Planner.Best("Mining", 60, false, 3, function()
	slices = slices + 1
end, function(found)
	offers[#offers + 1] = found
end)
assert(#offers == 6, "an offer after each zone")
assert(#offers[1] == 1 and #offers[3] == 3 and #offers[6] == 3, "the list grows to its limit")
assert(#best == 3 and best[1] == offers[6][1], "the last offer is the result")
assert(slices >= 6, "the planner yields between zones")
local total = 0
for _, z in ipairs(zones) do
	total = total + #z
end
-- A bound on the yields a whole plan asks for: a few per node, never a few per pair of nodes.
assert(slices <= 4 * total, "yields grow with the nodes")

print("planner_spec ok")
