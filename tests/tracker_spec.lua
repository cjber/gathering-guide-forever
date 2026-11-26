local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()
local handlers, loaded = {}, {}
ns.On = function(event, fn)
	handlers[event] = fn
end
ns.OnLoaded = function(fn)
	loaded[#loaded + 1] = fn
end
ns.core = {
	SafeCall = function(_, fn, ...)
		return fn(...)
	end,
}
ns.Tour = {
	Listen = function() end,
	Progress = function()
		return {
			name = "Zone",
			pos = 2,
			stop = 2,
			stops = 4,
			total = 5,
			laps = 0,
			status = "running",
			next = { name = "Copper Vein" },
		}
	end,
}
ns.Planner = {
	Items = function()
		return { ["Copper Ore"] = { kind = "Mining", nodes = { "Copper Vein" } } }
	end,
}
ns.DB.showTracker = true
local bags = { ["Copper Ore"] = 5 }
C_Item = {
	GetItemCount = function(item)
		return bags[item]
	end,
	GetItemIDForItemInfo = function()
		return 2770
	end,
	GetItemInfo = function()
		return "n", "l", nil, nil, nil, nil, nil, nil, nil, nil, 100
	end,
}
C_Timer = {
	NewTicker = function()
		return { Cancel = function() end }
	end,
}
GetCoinTextureString = function(copper)
	return copper .. "c"
end
local now = 0
GetServerTime = function()
	return now
end

-- The section the addon builds from the tracker template, with a recording block in place of Blizzard's.
local dirty = 0
local module
ObjectiveTrackerFrame, ObjectiveTrackerManager = {}, {}
CreateFrame = function()
	module = {
		SetHeader = function() end,
		MarkDirty = function()
			dirty = dirty + 1
		end,
	}
	return module
end
Mixin = function(target, mixin)
	for key, value in pairs(mixin) do
		target[key] = value
	end
end
ForeverCore = { TrackerHost = { Attach = function() end } }
H.Load(ns, "Locales/enUS.lua", "Journey/Session.lua", "UI/Tracker.lua")
for _, fn in ipairs(loaded) do
	fn()
end

assert(ns.Tracker.TallyLine({ item = "Copper Ore", gathered = 12 }) == "Copper Ore: 12 gathered")
assert(
	ns.Tracker.TallyLine({ item = "Copper Ore", gathered = 12, need = 20, left = 8 })
		== "Copper Ore: 12 gathered, 8 still needed"
)
assert(ns.Tracker.RateLine(nil) == "Gold per hour: price unknown")
assert(ns.Tracker.RateLine(1234.7) == "Gold per hour: 1234c", "whole copper")

local objectives, percents = {}, {}
local block = {
	SetHeader = function() end,
	AddObjective = function(_, key, text)
		objectives[#objectives + 1] = { key = key, text = text }
	end,
	AddProgressBar = function(_, key)
		return {
			SetPercent = function(_, percent)
				percents[key] = percent
			end,
		}
	end,
}
module.GetBlock = function()
	return block
end
module.LayoutBlock = function() end
local function Draw()
	objectives, percents = {}, {}
	module:LayoutContents()
	return objectives
end

-- A list tour: loot through the real events, and the section shows the tally, its bar and the rate.
ns.Char.list = { { item = "Copper Ore", need = 20 } }
ns.Session.Begin({ list = true, name = "Zone", order = {} }, 0)
local before = dirty
handlers.LOOT_OPENED()
bags["Copper Ore"] = 10
handlers.BAG_UPDATE_DELAYED()
handlers.LOOT_CLOSED()
assert(dirty > before, "a loot marks the section dirty")
now = 1800
local lines = Draw()
assert(lines[#lines - 1].text == "Copper Ore: 5 gathered, 10 still needed", lines[#lines - 1].text)
assert(percents[#lines - 1] == 50, "the bar shows what is carried against the need")
assert(lines[#lines].text == "Gold per hour: 1000c", lines[#lines].text)
now = 3600
lines = Draw()
assert(lines[#lines].text == "Gold per hour: 500c", "the rate follows the clock")

-- A tour with no items to tally draws no rate line.
ns.Session.Begin({ kind = "Mining", name = "Zone", order = { { name = "Elsewhere" } } }, 0)
lines = Draw()
assert(not lines[#lines].text:find("Gold per hour"), "no rate without entries")
ns.Session.End()

print("tracker_spec ok")
