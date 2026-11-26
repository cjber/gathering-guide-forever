local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()
ns.OnLoaded = function() end
ns.KIND_ATLAS = { Mining = "pickaxe", ["Herb Gathering"] = "leaf" }
ns.Kinds = {
	{ kind = "Mining", line = 186, label = "Mining" },
	{ kind = "Herb Gathering", line = 182, label = "Herbalism" },
}
ns.KindByName = { Mining = ns.Kinds[1], ["Herb Gathering"] = ns.Kinds[2] }
ns.Markup = function(icon)
	return "<" .. icon .. ">"
end
SlashCmdList = {}
C_Item = {
	-- Both lookups by item ID: a name finds only items the client has cached.
	GetItemCount = function(id)
		assert(type(id) == "number", "counted by item ID")
		return 0
	end,
	GetItemIconByID = function(id)
		return id * 10
	end,
}
H.Load(ns, "Locales/enUS.lua", "Data/NodeSkills.lua", "Data/Items.lua", "Core/Skills.lua", "Core/Planner.lua")
-- The player's rank and trained maximum by skill line; a profession not learned has none.
local skills = { [186] = { 38, 75 } }
ns.Skills.Rank = function(line)
	local skill = skills[line] or { 0, 0 }
	return skill[1], skill[2]
end
ns.GatherMate = {
	Fingerprint = function()
		return "0:0"
	end,
}
ns.World = {
	PlayerMap = function()
		return 1426
	end,
	Levels = function(uiMapID)
		return uiMapID == 1424 and "20-30" or nil
	end,
}
-- Planning runs across frames in game; here the list's zones stay pending.
ns.Planner.Result = function() end
-- The world map and the shared opener, recording the maps the panel turns to.
local turned, gamepad = {}, false
WorldMapFrame = {
	GetMapID = function()
		return 1426
	end,
}
ForeverCore = {
	OpenMap = function(uiMapID)
		turned[#turned + 1] = uiMapID
		return true
	end,
}
ns.core = {
	MapCanvas = {
		Gamepad = function()
			return gamepad
		end,
	},
}
H.Load(ns, "UI/Panel.lua")
ns.Char.list = { { item = "Copper Ore", need = 20 }, { item = "Silver Ore", need = 5 } }

local rows = {}
for _, spec in ipairs(ns.Panel.ListSpecs(function() end)) do
	if spec.type == "item" then
		rows[#rows + 1] = spec
	end
end
assert(#rows == 2, "a row per list item")
assert(rows[1].text == "Copper Ore" and not rows[1].color and rows[1].icon == 27700, "gatherable, with its own icon")
assert(rows[2].text == "Silver Ore (needs 75)" and rows[2].color == "red", "above the player's skill")
assert(rows[2].icon == 27750, "an item the client has not cached still has its icon")

-- Every number on the pages comes from the plan, the saved tour or the bags.
skills[186] = { 146, 150 }
ns.DB.skipNoSkillUp = false
ns.TOP_ZONES = 1
ns.GatherMate.Available = function()
	return true
end
ns.Navigation = {
	Available = function()
		return true
	end,
}
UnitLevel = function()
	return 24
end
local function Loop(nodes)
	local order = {}
	for _, node in ipairs(nodes) do
		order[#order + 1] = { name = node[1], required = node[2], kind = node[3] or "Mining" }
	end
	return order
end
local function Zone(uiMapID, name, order, ranges)
	return {
		uiMapID = uiMapID,
		name = name,
		types = ns.Planner.NodeTable(order),
		order = order,
		count = #order,
		seconds = 600,
		travel = 240,
		rate = 5,
		ranges = ranges,
	}
end
local mined = Loop({
	{ "Iron Deposit", 125 },
	{ "Gold Vein", 100 },
	{ "Tin Vein", 65 },
	{ "Mithril Deposit", 175 },
	{ "Copper Vein", 1 },
})
local zone = Zone(1417, "Arathi Highlands", mined, { Mining = { lowest = 1, highest = 175 } })
local further = Zone(1424, "Hillsbrad Foothills", mined, { Mining = { lowest = 65, highest = 65 } })
local asked = 0
ns.Planner.Ranking = function(_, _, _, all)
	if all then
		asked = asked + 1
		return { zones = { zone, further }, total = 2 }
	end
	return { zones = { zone }, total = 2 }
end
local function Find(specs, kind, title)
	for _, spec in ipairs(specs) do
		if spec.type == kind and (not title or spec.title == title or spec.name == title) then
			return spec
		end
	end
	error("no " .. kind .. " " .. tostring(title))
end
local function Has(specs, kind, title)
	return (pcall(Find, specs, kind, title))
end
local function Nothing() end

ns.Char.last =
	{ kind = "Mining", uiMapID = 1417, name = "Arathi Highlands", list = false, pos = 9, total = 30, gained = 11 }
local overview = ns.Panel.OverviewSpecs(Nothing)
assert(Find(overview, "heading").sub == "Level 24 · Mining 146", Find(overview, "heading").sub)
local tour = Find(overview, "card", "Arathi Highlands tour")
assert(tour.lines[1] == "Node 9 of 30 · 11 skill-ups so far", tour.lines[1])
assert(tour.corner == "9 of 30" and tour.bar.have == 9 and tour.bar.need == 30)
local shopping = Find(overview, "card", "Farm for a list")
assert(shopping.lines[1] == "Copper Ore 0 of 20, and 1 more", shopping.lines[1])
assert(shopping.corner == "0 of 25" and shopping.bar.need == 25)
local ranked = Find(overview, "card", "Arathi Highlands")
assert(#ranked.right == 1 and ranked.right[1] == "<pickaxe>1-175" and ranked.corner == "4 min", ranked.right[1])
assert(ranked.lines[1] == "5.0 skill-ups per 10 min", ranked.lines[1])
assert(ranked.icon == ns.ItemIDs["Iron Ore"] * 10, "the card wears the hardest node the player can gather")
assert(Find(overview, "header", "Best zones for you").count == "2", "the header counts every zone")

-- The rest of the zones, and the trips to them, wait for a click.
local more = Find(overview, "more")
assert(more.text == "1 more: click to show" and more.sign == "+" and asked == 0, more.text)
assert(not Has(overview, "card", "Hillsbrad Foothills"))
more.onClick()
local all = ns.Panel.OverviewSpecs(Nothing)
assert(asked == 1 and Find(all, "card", "Hillsbrad Foothills").right[1] == "<pickaxe>65")
more = Find(all, "more")
assert(more.text == "Show fewer zones" and more.sign == "-", more.text)
more.onClick()
assert(not Has(ns.Panel.OverviewSpecs(Nothing), "card", "Hillsbrad Foothills"))

-- A tour saved without its position is offered with no bar and no made-up numbers.
ns.Char.last = { kind = "Mining", uiMapID = 1417, name = "Arathi Highlands" }
tour = Find(ns.Panel.OverviewSpecs(Nothing), "card", "Arathi Highlands tour")
assert(tour.lines[1] == "Start again from the node nearest you" and not tour.bar and not tour.corner)

-- Typing on the overview lists the matching zones in its place, with the level range where the client has one.
local searched
ns.Planner.SearchZones = function(text)
	searched = text
	return text == "hill" and { { uiMapID = 1424, name = "Hillsbrad Foothills" } } or {}
end
local _, view = ns.Panel.State()
view.query = "hill"
local results = ns.Panel.OverviewSpecs(Nothing)
local match = Find(results, "zone", "Hillsbrad Foothills")
assert(searched == "hill" and match.levels == "20-30" and #results == 2, "only the heading and the match")
view.query = "zzz"
results = ns.Panel.OverviewSpecs(Nothing)
assert(Find(results, "text").text == "No zone with nodes for your skills matches.")
view.query = "hill"
match.onClick()
local opened
ns.Planner.Result = function(key)
	opened = key
	return zone
end
local later
ns.Planner.NextZones = function(of, ranks)
	later = ns.Planner.NextRanks(of, ranks)
	return { further }
end
assert(Find(ns.Panel.ZoneSpecs(Nothing), "card", "Arathi Highlands") and opened:find("zone:1424:", 1, true))
ns.Panel.ZoneSpecs(Nothing)
assert(#turned == 1 and turned[1] == 1424, "a picked zone turns the map to it once")
gamepad = true
match.onClick()
ns.Panel.ZoneSpecs(Nothing)
assert(#turned == 1, "the gamepad interface turns its own map")
gamepad = false

ranked.onClick()
local page = ns.Panel.ZoneSpecs(Nothing)
assert(opened:find("zone:1417:", 1, true), opened)
local top = Find(page, "card", "Arathi Highlands")
assert(top.lines[2] == "Mining to 150 in about 20 min", top.lines[2])
assert(top.lines[3] == "5 nodes · 10 min loop" and top.right[1] == "4 min", top.lines[3])
local notes = {}
for _, spec in ipairs(page) do
	if spec.type == "node" then
		notes[#notes + 1] = spec.trailing .. " " .. tostring(spec.note) .. (spec.dim and " dim" or "")
	end
end
table.sort(notes)
assert(
	table.concat(notes, "; ") == "1 nil; 100 green at 150; 125 yellow at 150; 175 not yet dim; 65 1 in 4",
	table.concat(notes, "; ")
)
local onward = page[#page]
assert(onward.type == "place" and onward.value == "5.0" and onward.levels == "20-30" and later.Mining == 275)
assert(Find(page, "header", "Next zones").trailing == "per 10 min at 275")
-- At the trained maximum there is no time to give, only where to go next with the skill.
skills[186] = { 150, 150 }
top = Find(ns.Panel.ZoneSpecs(Nothing), "card", "Arathi Highlands")
assert(top.lines[2] == "Train Mining to raise it past 150", top.lines[2])
assert(top.lines[3] == "5 nodes · 10 min loop" and not top.lines[4], top.lines[3])
-- At the highest skill there is nothing left to train.
skills[186] = { 300, 300 }
top = Find(ns.Panel.ZoneSpecs(Nothing), "card", "Arathi Highlands")
assert(top.lines[2] == "5 nodes · 10 min loop" and not top.lines[3], top.lines[2])

-- Two professions make one plan: both ranges on a card, one node table and one time for both skills.
skills = { [186] = { 142, 150 }, [182] = { 138, 150 } }
local herbs = { { "Kingsblood", 125, "Herb Gathering" }, { "Wild Steelbloom", 115, "Herb Gathering" } }
for _, node in ipairs(Loop(herbs)) do
	mined[#mined + 1] = node
end
zone = Zone(1417, "Arathi Highlands", mined, {
	Mining = { lowest = 1, highest = 175 },
	["Herb Gathering"] = { lowest = 115, highest = 125 },
})
Find(ns.Panel.ZoneSpecs(Nothing), "heading").onBack()
overview = ns.Panel.OverviewSpecs(Nothing)
assert(Find(overview, "heading").sub == "Level 24 · Mining 142 · Herbalism 138", Find(overview, "heading").sub)
ranked = Find(overview, "card", "Arathi Highlands")
assert(ranked.right[1] == "<pickaxe>1-175" and ranked.right[2] == "<leaf>115-125", ranked.right[2])
ranked.onClick()
page = ns.Panel.ZoneSpecs(Nothing)
top = Find(page, "card", "Arathi Highlands")
local function Minutes(kind, from, to)
	return ns.Planner.Minutes(ns.Planner.TimeToSkill(zone, kind, from, to))
end
local both = math.max(Minutes("Mining", 142, 150), Minutes("Herb Gathering", 138, 150))
assert(top.lines[2] == ("Both skills to 150 in about %d min"):format(both), top.lines[2])
assert(top.lines[3] == "7 nodes · 10 min loop" and not top.lines[4], top.lines[3])
assert(Find(page, "node", "|cffff8040Kingsblood|r").trailing == "125", "herbs share the table, at the herbalism skill")
assert(Find(page, "header", "Next zones").trailing == "per 10 min at 275 and 225")
-- Trained maximums that differ are two times, and a skill at its maximum drops out.
skills[182] = { 138, 200 }
top = Find(ns.Panel.ZoneSpecs(Nothing), "card", "Arathi Highlands")
assert(top.lines[2] == ("Mining to 150 in about %d min"):format(Minutes("Mining", 142, 150)), top.lines[2])
assert(top.lines[3] == ("Herbalism to 200 in about %d min"):format(Minutes("Herb Gathering", 138, 200)), top.lines[3])
assert(top.lines[4] == "7 nodes · 10 min loop", top.lines[4])
skills[186] = { 150, 150 }
top = Find(ns.Panel.ZoneSpecs(Nothing), "card", "Arathi Highlands")
assert(top.lines[2]:find("^Herbalism to 200 ") and top.lines[3] == "Train Mining to raise it past 150", top.lines[2])
assert(top.lines[4] == "7 nodes · 10 min loop", top.lines[4])

-- The list's zone card says how long all of it takes, or what the zone comes short of.
shopping.onClick()
local listed = {
	{ uiMapID = 1, name = "Short", found = { ["Copper Ore"] = 40 }, lacking = { "Silver Ore" }, travel = 120 },
	{ uiMapID = 2, name = "Full", found = { ["Copper Ore"] = 30, ["Silver Ore"] = 6 }, lacking = {}, whole = 900 },
}
ns.Planner.Result = function()
	return listed
end
local list = ns.Panel.ListSpecs(Nothing)
local best = Find(list, "card", "Short")
assert(best.lines[1] == "Short of Silver Ore here" and best.lines[2] == "Copper Ore 40", best.lines[1])
local other = Find(list, "place", "Full")
assert(other.value == "15 min" and not other.corner, "no trip time is made up")
other.onClick()
best = Find(ns.Panel.ListSpecs(Nothing), "card", "Full")
assert(best.lines[1] == "Whole list in about 15 min", best.lines[1])
assert(best.lines[2] == "Copper Ore 30 · Silver Ore 6", best.lines[2])

print("panel_spec ok")
