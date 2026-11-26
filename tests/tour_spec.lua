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
local events = {}
ns.On = function(event, fn)
	events[event] = fn
end
ns.Defer = function(fn)
	fn()
end
local began, ended = 0, 0
ns.Session = {
	Begin = function()
		began = began + 1
	end,
	End = function()
		ended = ended + 1
	end,
}
local hidden = false
ns.MapFocus = {
	Sync = function()
		hidden = ns.Tour.Active() and ns.DB.onlyGatheringPins == true
	end,
}
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
ns.DB.onlyGatheringPins = true
local started, why = Tour.Start({ kind = "Mining", uiMapID = 1, name = "Zone", order = loop })
assert(started, why)
assert(routes[1][1].x == 0.3, "the tour starts at the node nearest the player")
assert(#routes[1] == 6, "every node in one batch")
assert(Tour.Active() and Tour.Progress().visited == 0)
assert(began == 1, "a started tour begins a session")
assert(hidden == true, "the guide's pins are set aside during a tour")
local progress = Tour.Progress()
assert(progress.stop == 1 and progress.stops == 6 and progress.total == 6, "the count is the batch SPF shows")

observer("arrived", 1, routes[1][1])
assert(Tour.Progress().visited == 1, "an arrival advances the tour")
assert(Tour.Progress().stop == 2, "the stop number follows the journey's own")
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

-- A start the journey refuses leaves the running tour and its session alone.
local navigate = ShortestPathForever.API.NavigateRoute
ShortestPathForever.API.NavigateRoute = function()
	return false
end
started, why = Tour.Start({ kind = "Mining", uiMapID = 1, name = "Other", order = loop })
assert(not started and why == "refused", why)
assert(Tour.Progress().name == "Zone" and observer and began == 1 and ended == 0, "the old tour and session stay")

-- A batch refused in combat goes again once combat ends.
ShortestPathForever.API.JourneyState = function()
	return { blocked = "combat" }
end
for i = 1, 6 do
	observer("arrived", i, routes[2][i])
end
assert(Tour.Progress().status == "blocked", "the tour waits out combat")
ShortestPathForever.API.NavigateRoute = navigate
ShortestPathForever.API.JourneyState = function()
	return {}
end
events.PLAYER_REGEN_ENABLED()
assert(Tour.Progress().status == "running" and #routes == 3, "the next lap is sent after combat")
events.PLAYER_REGEN_ENABLED()
assert(#routes == 3, "a running tour is not sent again")

Tour.Stop()
assert(hidden == false, "stopping brings the guide's pins back")
assert(not Tour.Active() and observer == nil, "stop ends the tour and unsubscribes")
assert(ended == 1, "stop ends the session")

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
