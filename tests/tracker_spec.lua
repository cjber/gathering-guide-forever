local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()
ns.On = function() end
ns.OnLoaded = function() end
ns.Tour = { Listen = function() end }
ns.Session = { Listen = function() end }
H.Load(ns, "Locales/enUS.lua", "UI/Tracker.lua")
GetCoinTextureString = function(copper)
	return copper .. "c"
end

assert(ns.Tracker.TallyLine({ item = "Copper Ore", gathered = 12 }) == "Copper Ore: 12 gathered")
assert(
	ns.Tracker.TallyLine({ item = "Copper Ore", gathered = 12, need = 20, left = 8 })
		== "Copper Ore: 12 gathered, 8 still needed"
)
assert(ns.Tracker.RateLine(nil) == "Gold per hour: price unknown")
assert(ns.Tracker.RateLine(1234.7) == "Gold per hour: 1234c", "whole copper")

print("tracker_spec ok")
