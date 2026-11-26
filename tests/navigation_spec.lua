local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Load(H.Namespace(), "Locales/enUS.lua", "Core/MapHold.lua", "Core/Navigation.lua")
local Nav = ns.Navigation

-- Without Shortest Path Forever the adapter is unavailable and every call is harmless.
ShortestPathForever = nil
assert(Nav.Available() == false)
local ok, why = Nav.Route({ { map = 1, x = 0.5, y = 0.5 } })
assert(ok == false and why == "unavailable")
assert(Nav.State().busy == false)
Nav.Observe(function() end)()
assert(Nav.Cancel() == false)

-- A stub of the public API.
local calls = {}
local observers = {}
ShortestPathForever = {
	API = {
		version = 2,
		NavigateRoute = function(owner, stops, options)
			calls[#calls + 1] = { owner = owner, stops = stops, options = options }
			return true
		end,
		ObserveStops = function(owner, callback)
			observers[owner] = callback
			return function()
				observers[owner] = nil
			end
		end,
		JourneyState = function()
			return { busy = true, blocked = "combat" }
		end,
		Cancel = function(owner)
			calls[#calls + 1] = { cancel = owner }
			return true
		end,
	},
}
assert(Nav.Available())

local stops = { { map = 1, x = 0.1, y = 0.2, title = "Copper Vein" } }
assert(Nav.Route(stops) == true)
assert(calls[1].owner == "GatheringGuideForever" and calls[1].stops == stops)
assert(calls[1].options.policy == "walking", "tours ask for walking guidance")

-- A bare route asks Shortest Path Forever to leave out its numbered markers; one that refuses the option is asked again
-- without it, and a plain route never sends it.
calls = {}
assert(Nav.Route(stops, true) == true)
assert(calls[1].options[Nav.MARKERS_OPTION] == false and #calls == 1, "a newer Shortest Path draws the line bare")
Nav.Route(stops)
assert(calls[2].options[Nav.MARKERS_OPTION] == nil, "a plain route sends no marker option")
local accept = ShortestPathForever.API.NavigateRoute
ShortestPathForever.API.NavigateRoute = function(owner, list, options)
	calls[#calls + 1] = { options = options }
	if options[Nav.MARKERS_OPTION] ~= nil then
		return nil, "invalid"
	end
	return accept(owner, list, options)
end
calls = {}
assert(Nav.Route(stops, true) == true, "an older Shortest Path still starts the tour")
assert(calls[1].options[Nav.MARKERS_OPTION] == false and calls[2].options[Nav.MARKERS_OPTION] == nil)
ShortestPathForever.API.NavigateRoute = accept

-- The full-strength loop is asked only of a Shortest Path that publishes it: an older one refuses the whole call.
calls = {}
ShortestPathForever.API.minor = 9
assert(Nav.Route(stops, true) == true)
assert(calls[1].options[Nav.FADE_OPTION] == nil and calls[1].options[Nav.MARKERS_OPTION] == false)
ShortestPathForever.API.minor = 10
calls = {}
assert(Nav.Route(stops, true) == true)
assert(calls[1].options[Nav.FADE_OPTION] == false and calls[1].options[Nav.MARKERS_OPTION] == false)
Nav.Route(stops)
assert(calls[2].options[Nav.FADE_OPTION] == false and calls[2].options[Nav.MARKERS_OPTION] == nil)
ShortestPathForever.API.minor = nil

ok, why = Nav.Route({})
assert(ok == false and why == "invalid", "no stops")
local many = {}
for i = 1, Nav.MAX_STOPS + 1 do
	many[i] = { map = 1, x = 0, y = 0 }
end
ok, why = Nav.Route(many)
assert(ok == false and why == "invalid", "more than one batch")

local seen = {}
local off = Nav.Observe(function(phase, index)
	seen[#seen + 1] = phase .. index
end)
observers.GatheringGuideForever("arrived", 1, stops[1])
assert(seen[1] == "arrived1")
off()
assert(observers.GatheringGuideForever == nil, "unsubscribe removes the observer")

local state = Nav.State()
assert(state.busy == true and state.pending == false and state.blocked == "combat")
assert(Nav.Cancel() == true)

-- A newer API major is not trusted.
ShortestPathForever.API.version = 3
assert(Nav.Available() == false)

-- A refusal and an error are reported, not thrown.
ShortestPathForever.API.version = 2
ShortestPathForever.API.NavigateRoute = function()
	return false
end
ok, why = Nav.Route(stops)
assert(ok == false and why == "refused")
ShortestPathForever.API.NavigateRoute = function()
	error("boom")
end
ok, why = Nav.Route(stops)
assert(ok == false and why == "error")

print("navigation_spec ok")
