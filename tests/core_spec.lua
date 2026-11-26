-- The saved variables load with defaults, and a saved farming list keeps only items the data knows.
local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")

local onEvent
_G.CreateFrame = function()
	return {
		SetScript = function(_, _, fn)
			onEvent = fn
		end,
		RegisterEvent = function() end,
	}
end
_G.ForeverCore = {
	Register = function()
		return {
			SafeCall = function(_, fn, ...)
				fn(...)
			end,
		}
	end,
}
_G.GatheringGuideForeverCharDB = {
	list = { { item = "Obsidian Chunk", need = 20 }, { item = "Copper Ore", need = 5 } },
}

local ns = H.Namespace()
ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
H.Load(ns, "Data/Items.lua", "Core/Core.lua")
onEvent(nil, "ADDON_LOADED", "GatheringGuideForever")

assert(ns.DB.onlyGatheringPins == true, "defaults are filled in")
assert(#ns.Char.list == 1 and ns.Char.list[1].item == "Copper Ore", "an unknown saved item is dropped")
print("core_spec ok")
