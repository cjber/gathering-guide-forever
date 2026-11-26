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

-- Inline icons keep their own shape: an item's file icon is square without its border, an atlas takes its width from
-- its native size, and an atlas the client cannot describe draws nothing.
_G.C_Texture = {
	GetAtlasInfo = function(atlas)
		return atlas == "wide" and { width = 26, height = 13 } or nil
	end,
}
assert(ns.Markup(134566, 13) == "|T134566:13:13:0:0:64:64:5:59:5:59|t ", ns.Markup(134566, 13))
assert(ns.Markup("wide", 13) == "|A:wide:13:26|a ", ns.Markup("wide", 13))
assert(ns.Markup("missing", 13) == "")

print("core_spec ok")
