local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Load(H.Namespace(), "Locales/enUS.lua", "Core/MapHold.lua", "Core/Navigation.lua")

local calls = {}
local function Publish(name, api)
	api.SuspendMapPins = function(owner)
		calls[#calls + 1] = name .. " suspend " .. owner
	end
	api.ResumeMapPins = function(owner)
		calls[#calls + 1] = name .. " resume " .. owner
	end
end

local function SetAll(hidden)
	ns.SetGuidePinsHidden(hidden)
	ns.Navigation.SetPinsHidden(hidden)
end

-- Missing addons and older ones, which publish neither call: nothing happens and nothing errors.
SetAll(true)
AdventureGuideForever = { API = {} }
LegacyForever = { API = {} }
ShortestPathForever = { API = { version = 2 } }
SetAll(true)
SetAll(false)

Publish("guide", AdventureGuideForever.API)
Publish("legacy", LegacyForever.API)
Publish("journey", ShortestPathForever.API)
SetAll(false)
assert(#calls == 0, "nothing to bring back when nothing was set aside")
SetAll(true)
SetAll(true)
assert(
	table.concat(calls, ", ")
		== "guide suspend GatheringGuideForever, legacy suspend GatheringGuideForever, "
			.. "journey suspend GatheringGuideForever",
	"each addon's pins are set aside once, under our name"
)
calls = {}
SetAll(false)
assert(
	table.concat(calls, ", ")
		== "guide resume GatheringGuideForever, legacy resume GatheringGuideForever, "
			.. "journey resume GatheringGuideForever",
	"and brought back"
)
print("map_hold_spec ok")
