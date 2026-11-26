---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- The only file that talks to Shortest Path Forever, and only through its published ShortestPathForever.API. Everything
-- else asks this module, so a change in that API lands here.
--   API.NavigateRoute(owner, stops, {policy = "walking"}) guides a walking journey through the stops in order.
--   API.ObserveStops(owner, callback) calls callback(phase, index, stop) with phase "arrived" or "settled" and returns
--   a function that unsubscribes.
--   API.SuspendMapPins(owner) and API.ResumeMapPins(owner) set its other map marks aside (Core/MapHold.lua).
--   API.JourneyState() reads {busy, pending, failure, blocked}: another journey under way, a route still being worked
--   out, why the last one failed, and whether combat or a corpse holds guidance.
local Nav = {}
ns.Navigation = Nav

Nav.OWNER = "GatheringGuideForever"
Nav.MAX_STOPS = 64

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

-- Starts a walking journey through the stops. Returns whether it started, and why not. With bare set, Shortest Path
-- Forever draws the route line without its numbered markers when this version can; an older one keeps them.
---@param stops {map: number, x: number, y: number, title: string?, tooltip: string?}[]
---@param bare boolean?
---@return boolean ok
---@return string? reason
function Nav.Route(stops, bare)
	local api = API()
	if not Nav.Available() or not api then
		return false, "unavailable"
	end
	if #stops == 0 or #stops > Nav.MAX_STOPS then
		return false, "invalid"
	end
	local ok, result
	if bare then
		ok, result = pcall(api.NavigateRoute, Nav.OWNER, stops, { policy = "walking", [Nav.MARKERS_OPTION] = false })
	end
	if not (ok and result == true) then
		ok, result = pcall(api.NavigateRoute, Nav.OWNER, stops, { policy = "walking" })
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
