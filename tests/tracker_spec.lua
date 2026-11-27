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
local order = {
	{ name = "Copper Vein", kind = "Mining", required = 1, world = 0, wx = 0, wy = 0 },
	{ name = "Iron Deposit", kind = "Mining", required = 125, world = 0, wx = 30, wy = 40 },
}
local progress = {
	uiMapID = 1417,
	name = "Zone",
	pos = 2,
	total = 5,
	laps = 0,
	status = "running",
	seconds = 60,
	order = order,
	next = order[2],
}
local touring = true
ns.Tour = {
	Listen = function() end,
	Active = function()
		return touring
	end,
	Progress = function()
		return touring and progress or nil
	end,
}
ns.Kinds = {
	{ kind = "Mining", line = 186, label = "Mining" },
	{ kind = "Herb Gathering", line = 182, label = "Herbalism" },
}
ns.KindByName = { Mining = ns.Kinds[1], ["Herb Gathering"] = ns.Kinds[2] }
ns.KIND_ATLAS = { Mining = "ore", ["Herb Gathering"] = "leaf" }
ns.Markup = function(icon, size)
	return ("<%s %d> "):format(icon, size)
end
local rank, max = 146, 150
-- Herbalism is learned only in the cases that set it.
local herbs
C_SkillInfo = {
	GetSkillLineInfoByID = function(line)
		if line == 186 then
			return { skillLevel = rank, maxSkillLevel = max }
		end
		return herbs
	end,
}
local player
ns.World = {
	Player = function()
		return player
	end,
	Distance = function(a, b)
		return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) + 0.4
	end,
}
local combat = false
InCombatLockdown = function()
	return combat
end
OBJECTIVE_DASH_STYLE_HIDE, OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE = 2, 3
ns.DB.showTracker = true
ns.ItemIDs = { ["Copper Ore"] = 2770 }
ns.OreNodes = { ["Copper Ore"] = { "Copper Vein" } }
local bags = { [2770] = 5 }
C_Item = {
	GetItemCount = function(item)
		return bags[item]
	end,
	GetItemInfo = function()
		return "n", "l", nil, nil, nil, nil, nil, nil, nil, nil, 100
	end,
	GetItemIconByID = function(id)
		return id * 10
	end,
}
local tickers = {}
C_Timer = {
	NewTicker = function(seconds, fn)
		local ticker = { seconds = seconds, fn = fn }
		function ticker:Cancel()
			self.cancelled = true
		end
		tickers[#tickers + 1] = ticker
		return ticker
	end,
}
-- The client has only C_CurrencyInfo.GetCoinTextureString; the retail global of that name is nil here.
C_CurrencyInfo = {
	GetCoinTextureString = function(copper)
		return copper .. "c"
	end,
}
assert(rawget(_G, "GetCoinTextureString") == nil, "no legacy money global is stubbed")
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
local updated = {}
ForeverCore = {
	TrackerHost = { Attach = function() end },
	TrackerSection = {
		UpdateText = function(_, blocks)
			updated[#updated + 1] = blocks
		end,
	},
}
H.Load(ns, "Locales/enUS.lua", "Core/Skills.lua", "Core/Planner.lua", "Journey/Session.lua", "UI/Tracker.lua")
---@type table?, number?, fun()?
local best, askedAt, arrive
ns.Planner.BestAt = function(at, _, refresh)
	askedAt, arrive = at, refresh
	return best
end
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
bags[2770] = 10
handlers.BAG_UPDATE_DELAYED()
handlers.LOOT_CLOSED()
assert(dirty > before, "a loot marks the section dirty")
now = 1800
local lines = Draw()
assert(lines[#lines - 1].text == "Copper Ore: 5 gathered, 10 still needed", lines[#lines - 1].text)
assert(percents["item:Copper Ore"] == 50, "the bar shows what is carried against the need")
assert(lines[#lines].text == "Gold per hour: 1000c", lines[#lines].text)
now = 3600
lines = Draw()
assert(lines[#lines].text == "Gold per hour: 500c", "the rate follows the clock")

-- A change to the shopping list marks the section dirty at once, without waiting for loot or the ticker.
for _, change in ipairs({
	function()
		ns.Planner.SetNeed("Copper Ore", 45)
	end,
	function()
		ns.Planner.RemoveItem("Copper Ore")
	end,
	function()
		ns.Planner.AddItem("Copper Ore", 30)
	end,
}) do
	before = dirty
	change()
	assert(dirty > before, "a list change marks the section dirty")
end
lines = Draw()
assert(lines[#lines - 1].text == "Copper Ore: 5 gathered, 20 still needed", lines[#lines - 1].text)

-- A zone tour draws no item or rate line before anything is looted.
ns.Session.Begin({ name = "Zone", order = { { name = "Copper Vein", kind = "Mining" } } }, 0)
for _, line in ipairs(Draw()) do
	assert(not line.text:find("gathered") and not line.text:find("Gold per hour"), line.text)
end
handlers.LOOT_OPENED()
bags[2770] = bags[2770] + 2
handlers.BAG_UPDATE_DELAYED()
handlers.LOOT_CLOSED()
lines = Draw()
assert(lines[#lines - 1].text == "Copper Ore: 2 gathered", lines[#lines - 1].text)
assert(lines[#lines].text:find("Gold per hour"), "the rate follows the first loot")
ns.Session.End()

-- The title counts the whole loop; the rows are the next node, the skill and the session's skill-ups and rate.
local function Rows(blocks)
	local texts = {}
	for i, row in ipairs(blocks[1].rows) do
		texts[i] = row.text
	end
	return texts
end
now = 0
ns.Session.Begin({ name = "Zone", order = order }, 0)
rank, now = 146 + 3, 1200
player = { map = 0, x = 0, y = 0 }
local blocks = ns.Tracker.Blocks()
assert(blocks[1].title == "Zone · node 2 of 5", blocks[1].title)
local texts = Rows(blocks)
assert(texts[1] == "<ore 13> |cffff8040Iron Deposit|r  50 yd", texts[1])
assert(texts[2] == "Mining 149 / 150", texts[2])
assert(texts[3] == "3 skill-ups · 1.5 per 10 min", texts[3])
-- Another continent has no distance.
player = { map = 1, x = 0, y = 0 }
assert(not Rows(ns.Tracker.Blocks())[1]:find(" yd"), "no distance across continents")

-- The next zone: the best one at the trained maximum, with this loop's expected time to that skill.
local function Onward()
	ns.Tracker.Refresh()
	return ns.Tracker.Blocks()[2]
end
rank = 145
assert(not Onward(), "no next zone while it is being planned")
best = { uiMapID = 1424, name = "Next Zone" }
assert(arrive)()
local ahead = ns.Tracker.Blocks()[2]
assert(askedAt.Mining == 150 and not askedAt["Herb Gathering"], "the zone is ranked at the trained maximum")
assert(ahead.title == "Next: Next Zone", ahead and ahead.title)
local expected = ns.Planner.TimeToSkill(progress, "Mining", rank, 150)
assert(
	ahead.rows[1].text == ("At Mining 150, in about %d min"):format(ns.Planner.Minutes(expected)),
	ahead.rows[1].text
)
best = { uiMapID = 1417, name = "Zone" }
rank = 147
assert(not Onward(), "no next zone while this one is still the best")
best = { uiMapID = 1424, name = "Next Zone" }
max, rank = 300, 148
assert(not Onward(), "no time and no next zone past what this loop can raise")
max, rank = 150, 149
assert(Onward(), "the next zone returns")
progress.list = true
ns.Tracker.Refresh()
assert(not ns.Tracker.Blocks()[2], "a list tour names no next zone")
progress.list = nil

-- With two professions there is a line for each, and the next zone is for the one this loop raises to its maximum
-- first, with the other as far as the loop will have brought it by then.
order[#order + 1] = { name = "Kingsblood", kind = "Herb Gathering", required = 125, world = 0, wx = 0, wy = 0 }
rank, max = 140, 150
herbs = { skillLevel = 147, maxSkillLevel = 150 }
ns.Session.Begin({ name = "Zone", order = order }, 0)
best, askedAt = { uiMapID = 1424, name = "Next Zone" }, nil
texts = Rows(ns.Tracker.Blocks())
assert(texts[2] == "Mining 140 / 150" and texts[3] == "Herbalism 147 / 150", texts[3])
ahead = Onward()
local sooner = ns.Planner.TimeToSkill(progress, "Herb Gathering", 147, 150)
assert(sooner < ns.Planner.TimeToSkill(progress, "Mining", 140, 150))
assert(
	ahead.rows[1].text == ("At Herbalism 150, in about %d min"):format(ns.Planner.Minutes(sooner)),
	ahead.rows[1].text
)
local reachedBy = ns.Planner.SkillAfter(progress, "Mining", 140, 150, sooner)
assert(askedAt["Herb Gathering"] == 150 and askedAt.Mining == reachedBy and reachedBy > 140 and reachedBy < 150)
-- A skill at its maximum drops out and the other one leads.
herbs = { skillLevel = 150, maxSkillLevel = 150 }
ahead = Onward()
assert(ahead.rows[1].text:find("^At Mining 150, "), ahead.rows[1].text)
assert(askedAt.Mining == 150 and askedAt["Herb Gathering"] == 150)
-- The skill counts to the next colour change among the loop's nodes of its kind, whatever the trained cap, and stands
-- alone once none is left.
herbs, rank, max = nil, 38, 75
ns.Session.Begin({ name = "Zone", order = { order[1], order[2] } }, 0)
assert(Rows(ns.Tracker.Blocks())[2] == "Mining 38 / 51", Rows(ns.Tracker.Blocks())[2])
rank = 120
assert(Rows(ns.Tracker.Blocks())[2] == "Mining 120", "grey copper has no change left and iron is out of reach")
rank, max = 149, 150
ns.Tracker.Refresh()

-- One ticker rewrites the text while a tour is drawn, waits out combat and stops with the tour.
ns.Tracker.Refresh()
local ticker
for _, t in ipairs(tickers) do
	if t.seconds == 1 and not t.cancelled then
		assert(not ticker, "one ticker")
		ticker = t
	end
end
assert(ticker, "the tour has a ticker")
ticker.fn()
assert(#updated == 1 and updated[1][1].title == "Zone · node 2 of 5")
combat = true
ticker.fn()
assert(#updated == 1, "nothing is rewritten in combat")
combat = false
ns.DB.showTracker = false
ns.Tracker.Refresh()
assert(ticker.cancelled and #ns.Tracker.Blocks() == 0, "a hidden section does no work")
local made = #tickers
ns.DB.showTracker, touring = true, false
ns.Tracker.Refresh()
assert(#ns.Tracker.Blocks() == 0 and #tickers == made, "no tour, no ticker")
ns.Session.End()

print("tracker_spec ok")
