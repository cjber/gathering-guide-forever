local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Load(H.Namespace(), "Locales/enUS.lua", "Core/Skills.lua", "Journey/Order.lua", "Core/Navigation.lua")
ns.World = {
	player = { x = 0, y = 0 },
	Player = function()
		return ns.World.player
	end,
	PlayerMap = function() end,
}
ns.Kinds = { { kind = "Mining", line = 186, label = "Mining" } }
ns.KindByName = { Mining = ns.Kinds[1] }
C_SkillInfo = {
	GetSkillLineInfoByID = function()
		return { skillLevel = 60, maxSkillLevel = 75 }
	end,
}
ns.On = function() end
ns.Defer = function(fn)
	fn()
end
ns.Session = { Begin = function() end, End = function() end }
GetServerTime = function()
	return 0
end
H.Load(ns, "Journey/Tour.lua")
local Tour = ns.Tour

-- NextBatch wraps from the position and drops nodes that cannot raise the skill when asked to.
local order = {
	{ required = 1 },
	{ required = 300 },
	{ required = 50 },
	{ required = 200 },
}
local batch = Tour.NextBatch(order, 3, false, 60, 10)
assert(table.concat(batch, ",") == "3,4,1,2", "starts at the position and wraps")
batch = Tour.NextBatch(order, 3, true, 60, 10)
assert(table.concat(batch, ",") == "3,1", "skip leaves out the node above the skill and the one with no chance")
batch = Tour.NextBatch(order, 1, false, 60, 2)
assert(#batch == 2, "a batch is capped")

-- A stub journey records what the tour asks.
local routes, observer = {}, nil
ShortestPathForever = {
	API = {
		version = 2,
		NavigateRoute = function(_, stops)
			routes[#routes + 1] = stops
			return true
		end,
		ObserveStops = function(_, callback)
			observer = callback
			return function()
				observer = nil
			end
		end,
		JourneyState = function()
			return {}
		end,
		Cancel = function()
			return true
		end,
	},
}

-- Nodes on a line, with the player nearest the third one.
local nodes = {}
for i = 1, 6 do
	nodes[i] = {
		uiMapID = 1,
		kind = "Mining",
		coord = i,
		nodeID = i,
		wx = i * 100,
		wy = 0,
		x = i / 10,
		y = 0.5,
		required = 1,
		name = "Node" .. i,
	}
end
local loop = ns.Order.Solve(nodes)
ns.World.player = { x = 300, y = 0 }
local started, why = Tour.Start({ kind = "Mining", uiMapID = 1, name = "Zone", order = loop })
assert(started, why)
assert(routes[1][1].x == 0.3, "the tour starts at the node nearest the player")
assert(#routes[1] == 6, "every node in one batch")
assert(Tour.Active() and Tour.Progress().visited == 0)

observer("arrived", 1, routes[1][1])
assert(Tour.Progress().visited == 1, "an arrival advances the tour")
observer("settled", 6, routes[1][6])
assert(#routes == 1, "a settled plan for the last stop is not an arrival")
for i = 2, 5 do
	observer("arrived", i, routes[1][i])
end
assert(#routes == 1, "the batch is not resent before its last stop")
observer("arrived", 6, routes[1][6])
assert(Tour.Progress().laps == 1, "the last stop closes a lap")
assert(#routes == 2, "the loop repeats after the last arrival")
assert(routes[2][1].x == routes[1][1].x, "and begins again where it began")

Tour.Stop()
assert(not Tour.Active() and observer == nil, "stop ends the tour and unsubscribes")

-- A blocked journey and a missing API refuse the start with a reason.
ShortestPathForever.API.JourneyState = function()
	return { blocked = "combat" }
end
started, why = Tour.Start({ kind = "Mining", uiMapID = 1, name = "Zone", order = loop })
assert(not started and why == "blocked")
ShortestPathForever = nil
started, why = Tour.Start({ kind = "Mining", uiMapID = 1, name = "Zone", order = loop })
assert(not started and why == "navigation")

print("tour_spec ok")
