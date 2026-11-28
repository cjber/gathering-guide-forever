---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- The only file that talks to Shortest Path Forever, and only through its published ShortestPathForever.API. Everything
-- else asks this module, so a change in that API lands here.
--   API.NavigateRoute(owner, stops, {policy = "walking"}) guides a walking journey through the stops in order. Its
--   tourLine = true option draws a calm solid line over the next few legs; fadeLaterLegs = false draws every leg at
--   full strength where that is missing; stopMarkers = false leaves out the numbered stops.
--   API.ObserveStops(owner, callback) calls callback(phase, index, stop) with phase "arrived" or "settled" and returns
--   a function that unsubscribes.
--   API.SuspendMapPins(owner) and API.ResumeMapPins(owner) set its other map marks aside (Core/MapHold.lua).
--   API.JourneyState() reads {busy, pending, failure, blocked}: another journey under way, a route still being worked
--   out, why the last one failed, and whether combat or a corpse holds guidance.
--   API.EstimateWalks(owner, from, targets, callback, opts) measures the walk in yards from one place to each of the
--   others, and API.NavVersion() names the walking data those yards come from.
local Nav = {}
ns.Navigation = Nav

Nav.OWNER = "GatheringGuideForever"
Nav.MAX_STOPS = 64
-- The most stops a closed loop takes.
Nav.MAX_LOOP_STOPS = 2048

---@return table?
local function API()
	local spf = rawget(_G, "ShortestPathForever")
	local api = spf and spf.API
	if type(api) ~= "table" or type(api.version) ~= "number" or api.version > 2 then
		return nil
	end
	return api
end

-- Sets the other map marks Shortest Path Forever draws aside or brings them back; the journey's line and stops stay.
Nav.SetPinsHidden = ns.MapHold(API)

-- Whether Shortest Path Forever offers everything a tour needs.
---@return boolean
function Nav.Available()
	local api = API()
	return api ~= nil
		and type(api.NavigateRoute) == "function"
		and type(api.ObserveStops) == "function"
		and type(api.JourneyState) == "function"
end

-- The NavigateRoute option that draws the route line without its numbered stop markers, as the newer Shortest Path
-- Forever publishes it (docs/api.md there). An older one answers any other option with "invalid" and changes nothing,
-- so a tour asks once with it and once without.
Nav.MARKERS_OPTION = "stopMarkers"

-- The option that draws a tour of many close stops: a solid line with soft corners over the leg under way and the next
-- few, the later ones faded. Shortest Path Forever publishes it from API minor 12.
Nav.TOUR_OPTION = "tourLine"
Nav.TOUR_MINOR = 12

-- The option that takes the stops as one closed loop: the world map draws all of it, and the journey carries on from
-- the last stop to the first. Shortest Path Forever publishes it from API minor 14.
Nav.LOOP_OPTION = "loop"
Nav.LOOP_MINOR = 14

-- Where that is missing, the option that draws the legs past the next stop at full strength, so a tour's dotted line
-- stays readable. Published from API minor 10. Either option makes an older Shortest Path Forever refuse the call.
Nav.FADE_OPTION = "fadeLaterLegs"
Nav.FADE_MINOR = 10

---@param api table
---@param bare boolean?
---@param loop boolean?
---@return table<string, string|boolean>
local function Options(api, bare, loop)
	---@type table<string, string|boolean>
	local options = { policy = "walking" }
	local minor = type(api.minor) == "number" and api.minor or 0
	if minor >= Nav.TOUR_MINOR then
		options[Nav.TOUR_OPTION] = true
	elseif minor >= Nav.FADE_MINOR then
		options[Nav.FADE_OPTION] = false
	end
	if bare then
		options[Nav.MARKERS_OPTION] = false
	end
	if loop and minor >= Nav.LOOP_MINOR then
		options[Nav.LOOP_OPTION] = true
	end
	return options
end

-- Whether a tour can hand over its whole loop at once.
---@return boolean
function Nav.CanLoop()
	local api = API()
	return api ~= nil and type(api.minor) == "number" and api.minor >= Nav.LOOP_MINOR
end

-- Starts a walking journey through the stops. Returns whether it started, and why not. With bare set, Shortest Path
-- Forever draws the route line without its numbered markers when this version can; an older one keeps them. With loop
-- set (and Nav.CanLoop true) the stops are one closed loop, up to Nav.MAX_LOOP_STOPS.
---@param stops {map: number, x: number, y: number, title: string?, tooltip: string?}[]
---@param bare boolean?
---@param loop boolean?
---@return boolean ok
---@return string? reason
function Nav.Route(stops, bare, loop)
	local api = API()
	if not Nav.Available() or not api then
		return false, "unavailable"
	end
	if #stops == 0 or #stops > (loop and Nav.CanLoop() and Nav.MAX_LOOP_STOPS or Nav.MAX_STOPS) then
		return false, "invalid"
	end
	local ok, result
	if bare then
		ok, result = pcall(api.NavigateRoute, Nav.OWNER, stops, Options(api, true, loop))
	end
	if not (ok and result == true) then
		ok, result = pcall(api.NavigateRoute, Nav.OWNER, stops, Options(api, false, loop))
	end
	if not ok or result ~= true then
		return false, ok and "refused" or "error"
	end
	return true
end

-- Calls callback(phase, index, stop) as the journey reaches and settles on each stop. Returns the unsubscribe function.
---@param callback fun(phase: string, index: number, stop: table)
---@return fun()
function Nav.Observe(callback)
	local api = API()
	if not Nav.Available() or not api then
		return function() end
	end
	local ok, off = pcall(api.ObserveStops, Nav.OWNER, callback)
	if ok and type(off) == "function" then
		return off
	end
	return function() end
end

-- The journey's state, with every field present.
---@return {busy: boolean, pending: boolean, failure: string?, blocked: string?}
function Nav.State()
	local api = API()
	local state = { busy = false, pending = false }
	if api and type(api.JourneyState) == "function" then
		local ok, read = pcall(api.JourneyState)
		if ok and type(read) == "table" then
			state.busy = read.busy == true
			state.pending = read.pending == true
			state.failure = read.failure
			state.blocked = read.blocked
		end
	end
	return state
end

---@return boolean
function Nav.Cancel()
	local api = API()
	if api and type(api.Cancel) == "function" then
		return api.Cancel(Nav.OWNER) == true
	end
	return false
end

-- The walking data walk costs are measured over, or nil when Shortest Path Forever cannot measure walks.
---@return string?
function Nav.NavVersion()
	local api = API()
	if not api or type(api.EstimateWalks) ~= "function" or type(api.NavVersion) ~= "function" then
		return nil
	end
	local ok, version = pcall(api.NavVersion)
	return ok and type(version) == "string" and version or nil
end

-- Measures the walk from one node to each of the others. callback(costs, reason) runs once, later: costs[i] is yards,
-- or false where there is no walk. Returns whether the search started; combat or loading data refuses it. A new call
-- drops the search before it.
---@param from GGNode
---@param targets GGNode[]
---@param callback fun(costs: (number|false)[], reason: string?)
---@return boolean started
function Nav.Walks(from, targets, callback)
	local api = API()
	if not api or not Nav.NavVersion() then
		return false
	end
	local places = {}
	for i, node in ipairs(targets) do
		places[i] = { map = node.uiMapID, x = node.x, y = node.y }
	end
	-- Water walking is left out, so a kept cost never depends on a buff.
	local ok, cancel = pcall(
		api.EstimateWalks,
		Nav.OWNER,
		{ map = from.uiMapID, x = from.x, y = from.y },
		places,
		callback,
		{ waterWalking = false }
	)
	return ok and cancel ~= nil
end

-- Travel seconds from the player's place to a map point, or nil when SPF cannot say.
---@param map number
---@param x number
---@param y number
---@return number?
function Nav.Estimate(map, x, y)
	local api = API()
	if not api or type(api.Estimate) ~= "function" then
		return nil
	end
	local here = ns.World.PlayerMap()
	local pos = here and C_Map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(here, "player")
	if not pos then
		return nil
	end
	local px, py = pos:GetXY()
	local ok, seconds = pcall(api.Estimate, here, px, py, map, x, y)
	return ok and type(seconds) == "number" and seconds or nil
end
