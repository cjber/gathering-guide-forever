local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Load(H.Namespace(), "Core/AdventureGuide.lua")
local AG = ns.AdventureGuide

-- An older Adventure Guide Forever has neither call: nothing happens and nothing errors.
AdventureGuideForever = { API = {} }
AG.SetHidden(true)
AG.SetHidden(false)

local calls = {}
AdventureGuideForever.API.SuspendMapPins = function(owner)
	calls[#calls + 1] = "suspend " .. owner
end
AdventureGuideForever.API.ResumeMapPins = function(owner)
	calls[#calls + 1] = "resume " .. owner
end
AG.SetHidden(false)
assert(#calls == 0, "nothing to bring back when nothing was set aside")
AG.SetHidden(true)
AG.SetHidden(true)
assert(#calls == 1 and calls[1] == "suspend GatheringGuideForever", "pins are set aside once, under our name")
AG.SetHidden(false)
assert(#calls == 2 and calls[2] == "resume GatheringGuideForever", "and brought back")
print("adventure_guide_spec ok")
