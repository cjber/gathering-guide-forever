---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end
local L = ns.L

-- The Gathering side page of the world map's quest log (ForeverCore.QuestLogTabs). Three views, each built as a plain
-- list of row specs and then drawn from a row pool per row type:
--   overview  Continue and the best zones for the player's gathering professions, or the zones matching a search
--   zone      one zone's card, its nodes by skill-up chance, the next zones and the tour
--   list      a shopping list of herbs and ores, the best zone for all of it and other places
local Panel = {}
ns.Panel = Panel

local PAD = 12
local HIDE_TIP = "Shows only this addon's pins on the world map. It hides GatherMate2's world map icons, and during a "
	.. "tour Shortest Path Forever's numbered stop markers and Adventure Guide Forever's map pins (these two need "
	.. "their newer versions). The tour's markers come back when it stops. GatherMate2's pins come back when you turn "
	.. "this off, log out or disable the addon."
local ICONS_TIP = "Draws GatherMate2's herb and ore pins with this addon's pictures, on the minimap and on its world "
	.. "map. On the minimap they are see-through, and close nodes keep GatherMate2's hollow ring, so the game's "
	.. "tracking dot shows under them."
local TIPS = { onlyGatheringPins = HIDE_TIP, gatheringIcons = ICONS_TIP }
-- Row heights, and the room before and after a row, by type. A heading with a back button and a zone's own card are
-- taller (Height).
local HEIGHTS = {
	heading = 47,
	header = 26,
	card = 66,
	node = 20,
	item = 32,
	place = 46,
	zone = 28,
	more = 26,
	check = 22,
	text = 34,
	search = 26,
}
local BEFORE = { header = 6, check = 6, search = 4 }
local AFTER = { header = 2, card = 4, place = 4, zone = 4, text = 2, search = 10 }
local TALL_HEADING, TALL_CARD = 58, 88
-- A large card holds three lines; each one more makes it this much taller.
local CARD_LINE = 14
local NODE_ICON, ITEM_ICON = 18, 26
-- A ringed icon: the art masked to a circle this share of the ring's width.
local RING_ICON = 0.64
local FOOTER = 40
-- The room above the list for the overview's search box and settings button.
local TOP_BAR = 29
local MIN_WIDTH = 240
local MUTED = { 0.6, 0.6, 0.6 }
local COLORS = { red = { 1, 0.3, 0.3 }, green = { 0.25, 0.75, 0.25 }, grey = MUTED }

---@type Frame?
local panel
---@type table
local view = { name = "overview" }
local specs = {}
---@type Frame?, ScrollFrame?, Texture?, Button?, (EditBox|{Instructions: FontString})?, FontString?, Button?
local content, scroll, background, footerButton, search, footerText, cog
local pickedZone
-- Whether the player can see the page, as the tab module last reported it.
local onScreen = false
-- Whether the player asked for every zone on the overview.
local expanded = false

-- What a view with no result yet says: that it is planning, or that the plan failed.
---@param failed boolean?
---@param planning string
---@return string
local function PlanText(failed, planning)
	return failed and L["The plan failed. The report window (/ggf report) shows why."] or planning
end

--[[ View specs ]]

-- The skills the player has learned, after the level when asked.
---@param withLevel boolean?
---@return string
local function SkillLine(withLevel)
	local parts = {}
	if withLevel then
		parts[1] = string.format(L["Level %d"], UnitLevel("player"))
	end
	for _, skill in ipairs(ns.Skills.Learned()) do
		parts[#parts + 1] = string.format("%s %d", skill.label, skill.rank)
	end
	return table.concat(parts, " · ")
end

---@param seconds number?
---@return string?
local function MinutesText(seconds)
	return seconds and string.format(L["%d min"], ns.Planner.Minutes(seconds)) or nil
end

-- The lowest to highest skill a profession's nodes on a loop ask for.
---@param range GGRange
---@return string
local function Range(range)
	if range.lowest == range.highest then
		return tostring(range.lowest)
	end
	return string.format("%d-%d", range.lowest, range.highest)
end

-- A zone card's skill ranges: one line for each profession the loop has nodes of, behind its tracking icon, so a lone
-- number reads as a skill.
---@param zone table
---@param learned GGSkill[]
---@return string[]
local function Ranges(zone, learned)
	local lines = {}
	for _, skill in ipairs(learned) do
		local range = zone.ranges[skill.kind]
		if range then
			lines[#lines + 1] = ns.Markup(ns.KIND_ATLAS[skill.kind], 12) .. Range(range)
		end
	end
	return lines
end

-- A zone's node names, each in its difficulty colour at its profession's skill.
---@param types GGNodeType[]
---@param ranks table<string, number>
---@return string
local function NodeNames(types, ranks)
	local names = {}
	for i, node in ipairs(types) do
		names[i] = ns.Skills.Colored(node.name, ranks[node.kind], node.required)
	end
	return table.concat(names, "  ")
end

-- A zone's art: the node needing the most skill among those the player can gather, else among all of them.
---@param types GGNodeType[]
---@param ranks table<string, number>
---@return number|string
local function ZoneIcon(types, ranks)
	local hardest, open = types[1], nil
	for _, node in ipairs(types) do
		if node.required > hardest.required then
			hardest = node
		end
		if node.required <= (ranks[node.kind] or 0) and (not open or node.required > open.required) then
			open = node
		end
	end
	local best = open or hardest
	return ns.Planner.Icon(best.name, best.kind)
end

-- Set by a click that asks for a zone: the map turns to it once the page knows which one.
local turnMap = false
-- Set by a click that opens a zone's page, and spent once the page knows its zone (Panel.AutoStart).
local autoStart = false

-- The shared opener refuses in combat, and under the gamepad interface the map is left to the player
-- (cjber/shortest-path-forever#158).
---@param uiMapID number
local function TurnMap(uiMapID)
	if not turnMap then
		return
	end
	turnMap = false
	if WorldMapFrame:GetMapID() ~= uiMapID and not ns.core.MapCanvas.Gamepad() then
		ForeverCore.OpenMap(uiMapID)
	end
end

---@param next table the view to open
---@param refresh fun()
---@return fun()
local function Open(next, refresh)
	return function()
		view, turnMap, autoStart = next, true, next.name == "zone"
		refresh()
	end
end

-- Starts the tour of a zone the player has just opened, unless a tour or another journey is under way. Redraws of the
-- same page start nothing, so a stopped tour stays stopped.
---@param zone table
---@return string? failure why it could not start, in the player's words
function Panel.AutoStart(zone)
	if not autoStart then
		return
	end
	autoStart = false
	if ns.Tour.Active() or ns.Navigation.State().busy then
		return
	end
	local ok, why = ns.Tour.Start(zone)
	return not ok and ns.Tour.Reason(why) or nil
end

-- The tour last toured and how far it got. A save without a position offers the tour alone.
---@param last table
---@param refresh fun()
---@return table
local function TourCard(last, refresh)
	local line = L["Start again from the node nearest you"]
	local card = {
		type = "card",
		icon = ns.KIND_ATLAS[last.kind],
		title = string.format(L["%s tour"], last.name),
		onClick = Open(
			last.list and { name = "list", pick = last.uiMapID } or { name = "zone", uiMapID = last.uiMapID },
			refresh
		),
	}
	if last.pos and last.total then
		line = string.format(L["Node %d of %d"], last.pos, last.total)
		if last.gained then
			local gained = last.gained == 1 and L["1 skill-up so far"]
				or string.format(L["%d skill-ups so far"], last.gained)
			line = line .. " · " .. gained
		end
		card.bar = { have = last.pos, need = last.total }
		card.corner = string.format(L["%d of %d"], last.pos, last.total)
	end
	card.lines = { line }
	return card
end

-- The shopping list at a glance: its first item, and how much of the whole list the player holds.
---@param listRows {item: string, have: number, need: number}[]
---@param refresh fun()
---@return table
local function ListCard(listRows, refresh)
	local card = {
		type = "card",
		icon = ns.KIND_ATLAS["Herb Gathering"],
		title = L["Farm for a list"],
		lines = { L["Search for an herb or ore to add it."] },
		onClick = Open({ name = "list" }, refresh),
	}
	local first = listRows[1]
	if not first then
		return card
	end
	local have, need = 0, 0
	for _, row in ipairs(listRows) do
		have = have + math.min(row.have, row.need)
		need = need + row.need
	end
	card.icon = ns.Planner.Icon(first.item, ns.Planner.Items()[first.item].kind)
	card.lines = {
		#listRows == 1 and string.format(L["%s %d of %d"], first.item, first.have, first.need)
			or string.format(L["%s %d of %d, and %d more"], first.item, first.have, first.need, #listRows - 1),
	}
	card.bar = { have = have, need = need }
	card.corner = string.format(L["%d of %d"], have, need)
	return card
end

-- Says why no zone is listed: `reason`, unless GatherMate2 holds no node of the player's professions, when it says
-- how to import them.
---@param out table[]
---@param ranks table<string, number>
---@param reason string
local function NoZones(out, ranks, reason)
	if next(ranks) and #ns.Planner.Zones(ranks) == 0 then
		out[#out + 1] = {
			type = "text",
			text = L["GatherMate2 has no nodes for your skills yet. With GatherMate2_Data installed, type /gathermate."],
		}
		reason = L["Open Import, tick Herbalism and Mining, then click Import GatherMate2Data."]
	end
	out[#out + 1] = { type = "text", text = reason }
end

-- The zones whose name holds the typed text. A match opens the zone; its trip and rate are planned there.
---@param out table[]
---@param ranks table<string, number>
---@param refresh fun()
local function SearchResults(out, ranks, refresh)
	local found = ns.Planner.SearchZones(view.query, ranks)
	for _, zone in ipairs(found) do
		out[#out + 1] = {
			type = "zone",
			title = zone.name,
			levels = ns.World.Levels(zone.uiMapID),
			onClick = Open({ name = "zone", uiMapID = zone.uiMapID }, refresh),
		}
	end
	if #found == 0 then
		NoZones(out, ranks, L["No zone with nodes for your skills matches."])
	end
end

-- The best zones section: the top few, and the rest behind a row that asks for them. The trips to those are only
-- estimated once asked for.
---@param out table[]
---@param ranks table<string, number>
---@param refresh fun()
local function BestZones(out, ranks, refresh)
	local header = { type = "header", key = "best", title = L["Best zones for you"] }
	out[#out + 1] = header
	local skip = ns.DB.skipNoSkillUp
	local ranking, failed = ns.Planner.Ranking(ranks, skip, refresh)
	if failed or not ranking then
		out[#out + 1] = { type = "text", text = PlanText(failed, L["Planning loops..."]) }
		return
	end
	header.count = tostring(ranking.total)
	if ranking.total == 0 then
		NoZones(out, ranks, L["No zone in your GatherMate2 data can raise your skill."])
		return
	end
	local zones, pending = ranking.zones, nil
	if expanded then
		local all, allFailed = ns.Planner.Ranking(ranks, skip, refresh, true)
		if all then
			zones = all.zones
		else
			pending = PlanText(allFailed, L["Planning loops..."])
		end
	end
	local learned = ns.Skills.Learned()
	for _, zone in ipairs(zones) do
		out[#out + 1] = {
			type = "card",
			icon = ZoneIcon(zone.types, ranks),
			title = zone.name,
			right = Ranges(zone, learned),
			lines = {
				string.format(L["%.1f skill-ups per 10 min"], zone.rate),
				NodeNames(zone.types, ranks),
			},
			corner = MinutesText(zone.travel),
			onClick = Open({ name = "zone", uiMapID = zone.uiMapID }, refresh),
		}
	end
	if pending then
		out[#out + 1] = { type = "text", text = pending }
	end
	local more = ranking.total - #ranking.zones
	if more > 0 then
		out[#out + 1] = {
			type = "more",
			text = expanded and L["Show fewer zones"] or string.format(L["%d more: click to show"], more),
			sign = expanded and "-" or "+",
			onClick = function()
				expanded = not expanded
				refresh()
			end,
		}
	end
end

---@param refresh fun()
---@return table[]
function Panel.OverviewSpecs(refresh)
	local out = {
		{ type = "heading", icon = ns.KIND_ATLAS["Mining"], title = L["Gathering Guide"], sub = SkillLine(true) },
	}
	if not ns.GatherMate.Available() then
		out[#out + 1] =
			{ type = "text", text = L["GatherMate2 supplies the node locations. Install it to plan a tour."] }
		return out
	end
	if not ns.Navigation.Available() then
		out[#out + 1] = {
			type = "text",
			text = L["Update Shortest Path Forever to start a tour. You can still plan one here."],
			color = "red",
		}
	end
	local ranks = ns.Skills.Ranks()
	local learned = next(ranks) ~= nil
	if learned and view.query and view.query ~= "" then
		SearchResults(out, ranks, refresh)
		return out
	end
	local last, listRows = ns.Char.last, ns.Planner.ListRows()
	if last or #listRows > 0 then
		out[#out + 1] = { type = "header", key = "continue", title = L["Continue"] }
		if last then
			out[#out + 1] = TourCard(last, refresh)
		end
		if #listRows > 0 then
			out[#out + 1] = ListCard(listRows, refresh)
		end
	end
	if learned then
		BestZones(out, ranks, refresh)
	else
		out[#out + 1] = {
			type = "text",
			text = L["Learn Mining or Herbalism to see the best zones for your skill."],
			ends = true,
		}
	end
	if #listRows == 0 then
		local card = ListCard(listRows, refresh)
		card.ends = true
		out[#out + 1] = card
	end
	return out
end

-- A node's row in a zone's table: how many there are, what changes next for it, and the skill it needs. A node out of
-- reach is dimmed.
---@param node GGNodeType
---@param rank number
---@return table
local function NodeRow(node, rank)
	local chance, color = ns.Skills.Chance(rank, node.required)
	local note
	if color == "red" then
		note = L["not yet"]
	elseif color == "green" and chance > 0 then
		note = string.format(L["1 in %d"], math.floor(1 / chance + 0.5))
	elseif color == "orange" or color == "yellow" then
		local after, at = ns.Skills.NextBand(rank, node.required)
		if after then
			note = string.format(after == "yellow" and L["yellow at %d"] or L["green at %d"], at)
		end
	end
	return {
		type = "node",
		icon = ns.Planner.Icon(node.name, node.kind),
		name = ns.Skills.Colored(node.name, rank, node.required),
		count = node.count,
		note = note,
		trailing = tostring(node.required),
		dim = color == "red",
	}
end

-- A zone card's lines on the skills the loop raises: one for each still short of its trained maximum, or a single one
-- when both are and share that maximum, taking the longer of the two times; then one for each at a trained maximum the
-- player can still train past.
---@param zone {order: GGNode[], seconds: number, ranges: table<string, GGRange>}
---@param skills GGSkill[]
---@return string[]
local function GoalLines(zone, skills)
	local goals, lines = ns.Planner.Goals(zone, skills), {}
	local first, second = goals[1], goals[2]
	if second and first.skill.max == second.skill.max then
		local minutes = ns.Planner.Minutes(math.max(first.seconds, second.seconds))
		lines[1] = string.format(L["Both skills to %d in about %d min"], first.skill.max, minutes)
	else
		for i, goal in ipairs(goals) do
			local minutes = ns.Planner.Minutes(goal.seconds)
			lines[i] = string.format(L["%s to %d in about %d min"], goal.skill.label, goal.skill.max, minutes)
		end
	end
	for _, skill in ipairs(skills) do
		if zone.ranges[skill.kind] and skill.rank >= skill.max and skill.max < ns.Skills.MAX then
			lines[#lines + 1] = string.format(L["Train %s to raise it past %d"], skill.label, skill.max)
		end
	end
	return lines
end

-- What the next zones are rated at: one skill, or one per profession when they differ.
---@param ranks table<string, number>
---@return string
local function RatedAt(ranks)
	local values = {}
	for _, k in ipairs(ns.Kinds) do
		values[#values + 1] = ranks[k.kind]
	end
	if values[2] and values[2] ~= values[1] then
		return string.format(L["per 10 min at %d and %d"], values[1], values[2])
	end
	return string.format(L["per 10 min at %d"], values[1])
end

---@param refresh fun()
---@return table[]
function Panel.ZoneSpecs(refresh)
	local out = {
		{
			type = "heading",
			title = L["Gathering Guide"],
			sub = SkillLine(),
			onBack = Open({ name = "overview" }, refresh),
		},
	}
	local ranks, uiMapID = ns.Skills.Ranks(), view.uiMapID
	TurnMap(uiMapID)
	local skip = ns.DB.skipNoSkillUp
	local key = ("zone:%d:%s"):format(uiMapID, ns.Planner.Key(ranks, skip))
	local zone, zoneFailed = ns.Planner.Result(key, function(yield)
		return ns.Planner.Zone(uiMapID, ranks, skip, yield) or false
	end, refresh)
	local types = zone and zone.types or ns.Planner.NodeTable(ns.Planner.Nodes(uiMapID, ranks))
	if zone then
		pickedZone = zone
		local lines = { string.format(L["%.1f skill-ups per 10 min"], zone.rate) }
		for _, line in ipairs(GoalLines(zone, ns.Skills.Learned())) do
			lines[#lines + 1] = line
		end
		lines[#lines + 1] = string.format(L["%d nodes · %d min loop"], zone.count, ns.Planner.Minutes(zone.seconds))
		out[#out + 1] = {
			type = "card",
			large = true,
			icon = ZoneIcon(types, ranks),
			title = zone.name,
			right = { MinutesText(zone.travel) },
			lines = lines,
		}
	else
		out[#out + 1] = {
			type = "text",
			text = zone == false and L["Nothing here can raise your skill yet."]
				or PlanText(zoneFailed, L["Planning the loop..."]),
		}
	end
	out[#out + 1] = {
		type = "header",
		key = "nodes",
		title = zone and L["On this tour"] or ns.Planner.ZoneName(uiMapID),
		trailing = L["skill"],
	}
	-- The commonest first, with the nodes out of reach last.
	for _, outOfReach in ipairs({ false, true }) do
		for _, node in ipairs(types) do
			if (ranks[node.kind] < node.required) == outOfReach then
				out[#out + 1] = NodeRow(node, ranks[node.kind])
			end
		end
	end
	out[#out + 1] = {
		type = "check",
		text = L["Skip nodes with no skill-up"],
		checked = skip,
		ends = true,
		onClick = function()
			ns.SettingsModule.Set("skipNoSkillUp", not ns.DB.skipNoSkillUp)
			ns.Planner.ClearResults()
			refresh()
		end,
	}
	if not zone then
		return out
	end
	local later = ns.Planner.NextRanks(zone, ranks)
	out[#out + 1] = { type = "header", key = "next", title = L["Next zones"], trailing = RatedAt(later) }
	local zones, failed = ns.Planner.NextZones(zone, ranks, skip, refresh)
	if not zones then
		out[#out + 1] = { type = "text", text = PlanText(failed, L["Planning loops..."]) }
	end
	for _, z in ipairs(zones or {}) do
		out[#out + 1] = {
			type = "place",
			title = z.name,
			levels = ns.World.Levels(z.uiMapID),
			value = string.format("%.1f", z.rate),
			names = NodeNames(z.types, later),
			corner = MinutesText(z.travel),
			onClick = Open({ name = "zone", uiMapID = z.uiMapID }, refresh),
		}
	end
	return out
end

-- The lowest skill at which any of an item's nodes can be gathered.
---@param nodes string[]
---@return number
local function LowestSkill(nodes)
	local lowest = math.huge
	for _, node in ipairs(nodes) do
		lowest = math.min(lowest, ns.NodeSkills[node][2])
	end
	return lowest
end

-- The item names matching what the player typed and not yet on the list, at most six.
---@param text string
---@return string[]
function Panel.Matches(text)
	local found = {}
	text = (text or ""):lower()
	if text == "" then
		return found
	end
	for name in pairs(ns.Planner.Items()) do
		if not ns.Planner.Listed(name) and name:lower():find(text, 1, true) then
			found[#found + 1] = name
		end
	end
	table.sort(found)
	while #found > 6 do
		found[#found] = nil
	end
	return found
end

-- The card of the list's chosen zone: the trip, the time for the whole list or what the zone comes short of, and how
-- many nodes it has for each item.
---@param zone table a Planner.ListZones zone
---@param listRows {item: string, have: number, need: number}[]
---@return table
local function ListZoneCard(zone, listRows)
	local items = ns.Planner.Items()
	local icon
	local found, lines = {}, {}
	for _, row in ipairs(listRows) do
		local count = zone.found[row.item]
		if count then
			icon = icon or ns.Planner.Icon(row.item, items[row.item].kind)
			found[#found + 1] = string.format("%s %d", row.item, count)
		end
	end
	if zone.whole then
		lines[1] = string.format(L["Whole list in about %d min"], ns.Planner.Minutes(zone.whole))
	elseif #zone.lacking > 0 then
		lines[1] = string.format(L["Short of %s here"], table.concat(zone.lacking, ", "))
	end
	lines[#lines + 1] = table.concat(found, " · ")
	lines[#lines + 1] = L["The loop takes only your list's nodes"]
	return {
		type = "card",
		large = true,
		icon = icon,
		title = zone.name,
		right = { MinutesText(zone.travel) },
		lines = lines,
		ends = true,
	}
end

-- The items still missing, those the zone comes short of in red.
---@param zone table
---@param listRows {item: string, have: number, need: number}[]
---@return string
local function MissingNames(zone, listRows)
	local lacking = {}
	for _, item in ipairs(zone.lacking) do
		lacking[item] = true
	end
	local names = {}
	for _, row in ipairs(listRows) do
		if row.have < row.need then
			names[#names + 1] = lacking[row.item] and "|cffff4d4d" .. row.item .. "|r" or row.item
		end
	end
	return table.concat(names, "  ")
end

---@param refresh fun()
---@return table[]
function Panel.ListSpecs(refresh)
	local out = {
		{
			type = "heading",
			title = L["Gathering Guide"],
			sub = L["Farm for a list"],
			onBack = Open({ name = "overview" }, refresh),
		},
		{ type = "header", key = "items", title = L["Shopping list"], trailing = L["have / need"] },
	}
	local listRows = ns.Planner.ListRows()
	local items = ns.Planner.Items()
	local ranks = ns.Skills.Ranks()
	local missing = {}
	for _, row in ipairs(listRows) do
		local def = items[row.item]
		local required = LowestSkill(def.nodes)
		local locked = (ranks[def.kind] or 0) < required
		if row.have < row.need then
			missing[#missing + 1] = row.item .. (row.need - row.have)
		end
		out[#out + 1] = {
			type = "item",
			icon = ns.Planner.Icon(row.item, def.kind),
			text = locked and string.format(L["%s (needs %d)"], row.item, required) or row.item,
			color = locked and "red" or nil,
			right = string.format("%d /", row.have),
			bar = { have = row.have, need = row.need },
			wanted = {
				item = row.item,
				need = row.need,
				set = function(need)
					ns.Planner.SetNeed(row.item, need)
					-- Next frame: losing focus can happen while the page is being laid out.
					ns.Defer(refresh)
				end,
			},
			tooltip = L["Click to remove from the list"],
			onClick = function()
				ns.Planner.RemoveItem(row.item)
				ns.Planner.ClearResults()
				refresh()
			end,
		}
	end
	out[#out + 1] = { type = "search", ends = true }
	for _, item in ipairs(Panel.Matches(view.query)) do
		out[#out + 1] = {
			type = "node",
			icon = ns.Planner.Icon(item, items[item].kind),
			name = item,
			trailing = L["Add"],
			trailingColor = "green",
			onClick = function()
				ns.Planner.AddItem(item, 20)
				view.query = nil
				ns.Planner.ClearResults()
				refresh()
			end,
		}
	end
	if #listRows == 0 then
		out[#out + 1] = { type = "text", text = L["Search for an herb or ore to add it."] }
		return out
	end
	if #missing == 0 then
		out[#out + 1] = { type = "text", text = L["You have everything on your list."] }
		return out
	end
	local key = ("list:%s:%s"):format(ns.Planner.Key(ranks, ns.DB.skipNoSkillUp), table.concat(missing, ","))
	local zones, failed = ns.Planner.Result(key, function(yield)
		return ns.Planner.ListZones(ns.TOP_ZONES + 1, yield)
	end, refresh)
	if not zones then
		out[#out + 1] = { type = "text", text = PlanText(failed, L["Planning loops..."]) }
		return out
	end
	if #zones == 0 then
		NoZones(out, ranks, L["No zone in your GatherMate2 data has anything on your list that your skill can gather."])
		return out
	end
	local picked = zones[1]
	for _, zone in ipairs(zones) do
		if zone.uiMapID == view.pick then
			picked = zone
		end
	end
	pickedZone = picked
	TurnMap(picked.uiMapID)
	out[#out + 1] = ListZoneCard(picked, listRows)
	if #zones == 1 then
		return out
	end
	out[#out + 1] = { type = "header", key = "others", title = L["Other places"], trailing = L["whole list"] }
	for _, zone in ipairs(zones) do
		if zone ~= picked then
			out[#out + 1] = {
				type = "place",
				title = zone.name,
				value = MinutesText(zone.whole),
				names = MissingNames(zone, listRows),
				corner = MinutesText(zone.travel),
				onClick = function()
					view.pick, turnMap = zone.uiMapID, true
					refresh()
				end,
			}
		end
	end
	return out
end

--[[ Drawing ]]

-- A spec's icon: an atlas name at its own aspect, or a file id whole.
---@param texture Texture
---@param icon string|number
---@param size number
local function SetIcon(texture, icon, size)
	if type(icon) == "number" then
		texture:SetTexCoord(0, 1, 0, 1)
		texture:SetTexture(icon) -- art-ok: a square file icon, whole, in a square box
		texture:SetSize(size, size)
	else
		ns.Fit(texture, icon, size, size)
	end
end

-- One line of text, cut short where its width ends.
---@param row Button
---@param font string
---@param justify JustifyHorizontal?
---@return FontString
local function Line(row, font, justify)
	local line = row:CreateFontString(nil, "ARTWORK", font)
	line:SetJustifyH(justify or "LEFT")
	line:SetWordWrap(false)
	return line
end

---@param line FontString
---@param color number[]
local function Tint(line, color)
	line:SetTextColor(color[1], color[2], color[3])
end

-- The Who list's row art at its native 69 height, scaled evenly to the row, as Shortest Path Forever's Nearby panel
-- draws it (UI/Art.lua).
local ROW_ART = 69

---@param row Button
---@param atlas string
---@param layer DrawLayer
---@return Texture
local function RowTexture(row, atlas, layer)
	local texture = row:CreateTexture(nil, layer)
	texture:SetAtlas(atlas) -- art-ok: at the atlas's native height, scaled uniformly to the row below
	row:HookScript("OnSizeChanged", function(_, width, height)
		if height <= 0 then
			return
		end
		local scale = height / ROW_ART
		texture:SetScale(scale)
		texture:SetSize(width / scale, ROW_ART)
		texture:ClearAllPoints()
		texture:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	end)
	return texture
end

-- The thin atlas progress bar, gold until full and then green.
---@param row Button
---@return StatusBar
local function NewBar(row)
	local bar = CreateFrame("StatusBar", nil, row)
	bar:SetStatusBarTexture("common-stat-bar-white")
	local trough = bar:CreateTexture(nil, "BACKGROUND")
	trough:SetPoint("TOPLEFT", -2, 1)
	trough:SetPoint("BOTTOMRIGHT", 2, -1)
	trough:SetAtlas("common-stat-bar-BG") -- art-ok: bar rim follows the size of its fill
	return bar
end

---@param bar StatusBar
---@param value {have: number, need: number}
local function SetBar(bar, value)
	bar:SetMinMaxValues(0, math.max(value.need, 1))
	bar:SetValue(math.min(value.have, value.need))
	local done = value.have >= value.need
	bar:SetStatusBarColor(done and 0.25 or 1, done and 0.75 or 0.8, done and 0.25 or 0.1)
end

-- An icon in the Adventure Guide's journey ring, masked round as its cards draw it.
---@param row Button
local function NewRing(row)
	local ring = { Icon = row:CreateTexture(nil, "ARTWORK"), Border = row:CreateTexture(nil, "OVERLAY") }
	ring.Mask = row:CreateMaskTexture()
	ring.Mask:SetAtlas("CircleMaskScalable")
	ring.Mask:SetPoint("CENTER", ring.Icon)
	ring.Icon:AddMaskTexture(ring.Mask)
	return ring
end

-- Draws the ring `size` wide with its centre `x` from the row's left, halfway down.
local function SetRing(ring, icon, size, x)
	ns.Fit(ring.Border, "ui-journeys-renown-radial-bar", size, size)
	ring.Border:ClearAllPoints()
	ring.Border:SetPoint("CENTER", ring.Border:GetParent(), "LEFT", x, 0)
	SetIcon(ring.Icon, icon, size * RING_ICON)
	ring.Icon:ClearAllPoints()
	ring.Icon:SetPoint("CENTER", ring.Border)
	ring.Mask:SetSize(size * RING_ICON, size * RING_ICON)
end

-- The box a list item's wanted count is typed into. Enter or clicking away keeps it, Escape puts the old one back.
local function NewCount(row)
	local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(4)
	box:SetJustifyH("CENTER")
	box:SetSize(38, 18)
	box:SetPoint("TOPRIGHT", -4, -3)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", function(self)
		self:SetNumber(self.wanted.need)
		self:ClearFocus()
	end)
	box:HookScript("OnEditFocusLost", function(self)
		local need = self:GetNumber()
		if need > 0 and need ~= self.wanted.need then
			self.wanted.set(need)
		else
			self:SetNumber(self.wanted.need)
		end
	end)
	return box
end

-- A pooled row's box keeps what is being typed only while it still shows the same item.
local function SetCount(box, wanted)
	local typing = box:HasFocus() and box.wanted.item == wanted.item
	box.wanted = wanted
	if not typing then
		box:SetNumber(wanted.need)
		box:ClearFocus()
	end
end

--[[ Rows: each type builds its regions once and fills them from a spec. ]]

local RowTypes = {}

RowTypes.heading = {
	Build = function(row)
		row.Ring = NewRing(row)
		row.Title = Line(row, "GameFontNormalLarge2", "CENTER")
		row.Sub = Line(row, "GameFontHighlightSmall", "CENTER")
		row.Back = CreateFrame("Button", nil, row)
		row.Back:SetSize(32, 32)
		row.Back:SetPoint("TOPLEFT", 2, -12)
		local arrow = row.Back:CreateTexture(nil, "ARTWORK")
		arrow:SetPoint("CENTER")
		ns.Fit(arrow, "common-icon-backarrow", 32, 32)
	end,
	Fill = function(row, spec, width)
		local top = spec.onBack and 12 or 7
		row.Title:SetPoint("TOPLEFT", 40, -top)
		row.Title:SetWidth(width - 40)
		row.Title:SetText(spec.title)
		row.Sub:SetPoint("TOPLEFT", 40, -top - (spec.onBack and 20 or 19))
		row.Sub:SetWidth(width - 40)
		row.Sub:SetText(spec.sub)
		row.Back:SetShown(spec.onBack ~= nil)
		row.Back:SetScript("OnClick", spec.onBack)
		row.Ring.Icon:SetShown(spec.icon ~= nil)
		row.Ring.Border:SetShown(spec.icon ~= nil)
		if spec.icon then
			SetRing(row.Ring, spec.icon, 30, 17)
		end
	end,
}

-- The Adventure Guide's section header, three-sliced from the options list's expander bar, whose right end shows
-- whether the section is folded.
local collapsed = {}

RowTypes.header = {
	Build = function(row)
		local left = row:CreateTexture(nil, "BACKGROUND")
		left:SetAtlas("options_listexpand_left") -- art-ok: a three-slice cap at its own shape
		left:SetSize(12, HEIGHTS.header)
		left:SetPoint("LEFT")
		row.Cap = row:CreateTexture(nil, "BACKGROUND")
		row.Cap:SetSize(28, HEIGHTS.header)
		row.Cap:SetPoint("RIGHT")
		for _, layer in ipairs({ "BACKGROUND", "HIGHLIGHT" }) do
			local middle = row:CreateTexture(nil, layer)
			middle:SetAtlas("_options_listexpand_middle") -- art-ok: the three-slice's tiling middle
			middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
			middle:SetPoint("BOTTOMRIGHT", row.Cap, "BOTTOMLEFT")
			if layer == "HIGHLIGHT" then
				middle:SetBlendMode("ADD")
				middle:SetAlpha(0.4)
			end
		end
		row.Title = Line(row, "GameFontNormalMed3")
		row.Title:SetPoint("LEFT", 8, 0)
		row.Trailing = Line(row, "GameFontHighlightSmall", "RIGHT")
		row.Trailing:SetPoint("RIGHT", -26, 0)
		Tint(row.Trailing, MUTED)
		row.Title:SetPoint("RIGHT", row.Trailing, "LEFT", -6, 0)
		row.Count = Line(row, "GameFontNormalMed3", "RIGHT")
		row.Count:SetPoint("RIGHT", -26, 0)
	end,
	Fill = function(row, spec)
		-- art-ok: a three-slice cap at its own shape
		row.Cap:SetAtlas(collapsed[spec.key] and "options_listexpand_right" or "options_listexpand_right_expanded")
		row.Title:SetText(spec.title)
		row.Trailing:SetText(spec.trailing or "")
		row.Count:SetText(spec.count or "")
		return function()
			collapsed[spec.key] = not collapsed[spec.key]
			Panel.Refresh()
		end
	end,
}

-- The Adventure Guide's journey card: a ringed icon, a title with up to two notes at its right, its lines, and either a
-- progress bar or a corner note. A large card is a view's own zone.
RowTypes.card = {
	Build = function(row)
		for _, layer in ipairs({ "BACKGROUND", "HIGHLIGHT" }) do
			local art = row:CreateTexture(nil, layer)
			art:SetAtlas("ui-journeys-renown-button") -- art-ok: nine-slice, margins set on the next line
			art:SetTextureSliceMargins(12, 12, 12, 12)
			-- The atlas has a 6 pixel empty margin.
			art:SetPoint("TOPLEFT", -6, 6)
			art:SetPoint("BOTTOMRIGHT", 6, -6)
			if layer == "HIGHLIGHT" then
				art:SetBlendMode("ADD")
				art:SetAlpha(0.4)
				row.Hover = art
			end
		end
		row.Ring = NewRing(row)
		row.Title = Line(row, "GameFontNormalMed3")
		row.Right = { Line(row, "GameFontHighlightSmall", "RIGHT"), Line(row, "GameFontHighlightSmall", "RIGHT") }
		row.Lines = {}
		-- A large card's most: the rate, a line for each profession and the loop.
		for i = 1, 4 do
			row.Lines[i] = Line(row, "GameFontHighlightSmall")
		end
		row.Corner = Line(row, "GameFontHighlightSmall", "RIGHT")
		Tint(row.Corner, MUTED)
		row.Bar = NewBar(row)
		row.Bar:SetSize(70, 6)
	end,
	Fill = function(row, spec, width)
		local large = spec.large
		local x = large and 76 or 58
		local tops = large and { 34, 50, 64, 78 } or { 27, 42 }
		row.Hover:SetShown(spec.onClick ~= nil)
		SetRing(row.Ring, spec.icon, large and 58 or 44, large and 40 or 30)
		local right = spec.right or {}
		for i, note in ipairs(row.Right) do
			note:SetText(right[i] or "")
			note:SetPoint("TOPRIGHT", -10, (large and -15 or -11) - (i - 1) * 15)
		end
		row.Title:SetPoint("TOPLEFT", x, large and -14 or -9)
		row.Title:SetWidth(width - x - 14 - row.Right[1]:GetStringWidth())
		row.Title:SetText(spec.title)
		row.Corner:SetText(spec.corner or "")
		row.Corner:SetPoint("BOTTOMRIGHT", -10, 8)
		for i, line in ipairs(row.Lines) do
			local text = spec.lines[i]
			line:SetShown(text ~= nil)
			if text then
				line:SetPoint("TOPLEFT", x, -tops[i])
				-- A small card's first line shares its height with the second right note, its second with the corner.
				local beside = not large and (i == 1 and row.Right[2] or row.Corner):GetStringWidth() or 0
				line:SetWidth(width - x - 14 - beside)
				line:SetText(text)
				Tint(line, i == 1 and { 1, 1, 1 } or MUTED)
			end
		end
		row.Bar:SetShown(spec.bar ~= nil)
		if spec.bar then
			row.Bar:SetPoint("TOPLEFT", x, -45)
			SetBar(row.Bar, spec.bar)
		end
	end,
}

-- A node in a zone's table, or a search result: icon, name, count, what changes next and a trailing word.
RowTypes.node = {
	Build = function(row)
		row.Hover = RowTexture(row, "common-button-list-large-hover", "HIGHLIGHT")
		row.Hover:SetBlendMode("ADD")
		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetPoint("LEFT", 6, 0)
		row.Name = Line(row, "GameFontHighlight")
		row.Name:SetPoint("LEFT", 30, 0)
		row.Count = Line(row, "GameFontHighlightSmall", "RIGHT")
		row.Count:SetPoint("RIGHT", -113, 0)
		row.Note = Line(row, "GameFontHighlightSmall")
		row.Note:SetPoint("LEFT", row, "RIGHT", -101, 0)
		row.Note:SetWidth(68)
		Tint(row.Note, MUTED)
		row.Trailing = Line(row, "GameFontHighlightSmall", "RIGHT")
		row.Trailing:SetPoint("RIGHT", -10, 0)
	end,
	Fill = function(row, spec, width)
		row.Hover:SetShown(spec.onClick ~= nil)
		SetIcon(row.Icon, spec.icon, NODE_ICON)
		row.Icon:SetAlpha(spec.dim and 0.5 or 1)
		row.Name:SetWidth(width - (spec.count and 171 or 80))
		row.Name:SetText(spec.name)
		row.Count:SetText(spec.count and tostring(spec.count) or "")
		Tint(row.Count, spec.dim and MUTED or { 1, 1, 1 })
		row.Note:SetText(spec.note or "")
		row.Trailing:SetText(spec.trailing)
		Tint(row.Trailing, COLORS[spec.trailingColor] or MUTED)
	end,
}

-- A list item: icon, name, how many are held of how many wanted, and its bar.
RowTypes.item = {
	Build = function(row)
		row.Hover = RowTexture(row, "common-button-list-large-hover", "HIGHLIGHT")
		row.Hover:SetBlendMode("ADD")
		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetPoint("TOPLEFT", 6, 1)
		row.Name = Line(row, "GameFontHighlight")
		row.Name:SetPoint("TOPLEFT", 40, -5)
		row.Held = Line(row, "GameFontHighlightSmall", "RIGHT")
		row.Wanted = NewCount(row)
		row.Held:SetPoint("RIGHT", row.Wanted, "LEFT", -8, 0)
		row.Name:SetPoint("RIGHT", row.Held, "LEFT", -6, 0)
		row.Bar = NewBar(row)
		row.Bar:SetPoint("TOPLEFT", 40, -25)
		row.Bar:SetPoint("TOPRIGHT", -4, -25)
		row.Bar:SetHeight(4)
	end,
	Fill = function(row, spec)
		SetIcon(row.Icon, spec.icon, ITEM_ICON)
		row.Name:SetText(spec.text)
		Tint(row.Name, COLORS[spec.color] or { 1, 1, 1 })
		row.Held:SetText(spec.right)
		SetCount(row.Wanted, spec.wanted)
		SetBar(row.Bar, spec.bar)
	end,
}

-- A row on the stock list art that lights under the pointer.
---@param row Button
local function ListArt(row)
	RowTexture(row, "common-button-list-large", "BACKGROUND")
	local hover = RowTexture(row, "common-button-list-large-hover", "HIGHLIGHT")
	hover:SetBlendMode("ADD")
end

-- A zone's name with its level range after it, the name cut short where the room ends.
---@param row table a zone row button
local function NewZoneTitle(row)
	row.Title = Line(row, "GameFontNormalMed3")
	row.Title:SetPoint("TOPLEFT", 12, -7)
	row.Levels = Line(row, "GameFontHighlightSmall")
	row.Levels:SetPoint("BOTTOMLEFT", row.Title, "BOTTOMRIGHT", 6, 0)
	Tint(row.Levels, MUTED)
end

---@param row table a zone row button
---@param spec table
---@param width number the room for both
local function SetZoneTitle(row, spec, width)
	row.Levels:SetText(spec.levels or "")
	row.Title:SetWidth(0)
	row.Title:SetText(spec.title)
	row.Title:SetWidth(math.min(row.Title:GetStringWidth(), width - row.Levels:GetStringWidth()))
end

-- Another zone: its name and level range, a figure, its nodes and the trip there.
RowTypes.place = {
	Build = function(row)
		ListArt(row)
		NewZoneTitle(row)
		row.Value = Line(row, "GameFontHighlightLarge", "RIGHT")
		row.Value:SetPoint("TOPRIGHT", -12, -8)
		row.Names = Line(row, "GameFontHighlightSmall")
		row.Names:SetPoint("TOPLEFT", 12, -26)
		row.Corner = Line(row, "GameFontHighlightSmall", "RIGHT")
		row.Corner:SetPoint("TOPRIGHT", -12, -27)
		Tint(row.Corner, MUTED)
	end,
	Fill = function(row, spec, width)
		row.Value:SetText(spec.value or "")
		row.Corner:SetText(spec.corner or "")
		SetZoneTitle(row, spec, width - 36 - row.Value:GetStringWidth())
		row.Names:SetWidth(width - 30 - row.Corner:GetStringWidth())
		row.Names:SetText(spec.names)
	end,
}

-- A zone a search found: its name and level range.
RowTypes.zone = {
	Build = function(row)
		ListArt(row)
		NewZoneTitle(row)
	end,
	Fill = function(row, spec, width)
		SetZoneTitle(row, spec, width - 30)
	end,
}

-- The options list's expander bar offering the rest of a section.
RowTypes.more = {
	Build = function(row)
		for _, layer in ipairs({ "BACKGROUND", "HIGHLIGHT" }) do
			local middle = row:CreateTexture(nil, layer)
			middle:SetAtlas("_options_listexpand_middle") -- art-ok: the three-slice's tiling middle
			middle:SetAllPoints()
			middle:SetAlpha(layer == "HIGHLIGHT" and 0.4 or 0.6)
			if layer == "HIGHLIGHT" then
				middle:SetBlendMode("ADD")
			end
		end
		row.Text = Line(row, "GameFontNormalSmall")
		row.Text:SetPoint("LEFT", 8, 0)
		row.Sign = Line(row, "GameFontHighlightMedium", "RIGHT")
		row.Sign:SetPoint("RIGHT", -10, 0)
	end,
	Fill = function(row, spec)
		row.Text:SetText(spec.text)
		row.Sign:SetText(spec.sign)
	end,
}

RowTypes.check = {
	Build = function(row)
		row.Box = CreateFrame("CheckButton", nil, row, "MinimalCheckboxTemplate")
		row.Box:SetSize(22, 22)
		row.Box:SetPoint("LEFT", 4, 0)
		-- The whole row takes the click.
		row.Box:EnableMouse(false)
		row.Text = Line(row, "GameFontHighlightSmall")
		row.Text:SetPoint("LEFT", row.Box, "RIGHT", 4, 0)
		row.Text:SetPoint("RIGHT")
	end,
	Fill = function(row, spec)
		row.Box:SetChecked(spec.checked)
		row.Text:SetText(spec.text)
	end,
}

RowTypes.text = {
	Build = function(row)
		row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.Text:SetJustifyH("LEFT")
		row.Text:SetPoint("TOPLEFT", 4, -2)
		row.Text:SetPoint("RIGHT", -4, 0)
	end,
	Fill = function(row, spec)
		row.Text:SetText(spec.text)
		Tint(row.Text, COLORS[spec.color] or { 0.8, 0.8, 0.8 })
	end,
}

-- The room the list's search box sits over, so typing needs no extra frame in the list.
RowTypes.search = { Build = function() end, Fill = function() end }

-- Rows by type, reused from one drawing to the next.
---@type table<string, Button[]>
local pools = {}

---@param kind string
---@param index number
---@return Button
local function Row(kind, index)
	pools[kind] = pools[kind] or {}
	local row = pools[kind][index]
	if not row then
		row = CreateFrame("Button", nil, content)
		RowTypes[kind].Build(row)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		pools[kind][index] = row
	end
	return row
end

---@param spec table
---@return number
local function Height(spec)
	if spec.type == "heading" and spec.onBack then
		return TALL_HEADING
	elseif spec.large then
		return TALL_CARD + math.max(#spec.lines - 3, 0) * CARD_LINE
	end
	return HEIGHTS[spec.type]
end

---@param row Button
---@param spec table
---@param width number
---@param y number
local function Draw(row, spec, width, y)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -y)
	row:SetSize(width, Height(spec))
	local action = RowTypes[spec.type].Fill(row, spec, width) or spec.onClick
	row:EnableMouse(action ~= nil)
	row:SetScript("OnClick", action)
	row:SetScript("OnEnter", function()
		if spec.tooltip then
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetText(spec.tooltip, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	row:Show()
end

local function Footer()
	local active = ns.Tour.Active()
	if not footerButton or not footerText then
		return
	end
	local text, onClick
	if active then
		text = L["Stop tour"]
		onClick = function()
			ns.Tour.Stop()
		end
	elseif view.name == "zone" and pickedZone then
		text = L["Start tour"]
	elseif view.name == "list" and pickedZone then
		text = L["Start farming"]
	end
	footerButton:SetShown(text ~= nil)
	if not text then
		footerText:SetText("")
		return
	end
	footerButton:SetText(text)
	footerButton:SetScript("OnClick", onClick or function()
		local ok, why = ns.Tour.Start(pickedZone)
		footerText:SetText(ok and "" or ns.Tour.Reason(why))
	end)
end

-- Centre-crop the native quest list artwork as Adventure Guide does on the same host.
---@param width number
---@param height number
local function LayoutBackground(width, height)
	local info = C_Texture.GetAtlasInfo("QuestLog-main-background")
	if not info or width <= 0 or height <= 0 then
		return
	end
	local left, right, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local aspect = width / height
	local native = info.width / info.height
	if native > aspect then
		local cut = (right - left) * (1 - aspect / native) / 2
		left, right = left + cut, right - cut
	else
		local cut = (bottom - top) * (1 - native / aspect) / 2
		top, bottom = top + cut, bottom - cut
	end
	assert(background):SetTexCoord(left, right, top, bottom)
end

-- The overview's search box finds zones and sits above the page, once there are zones to find; the list's finds items
-- and sits under them.
---@param searchRow Button?
local function PlaceSearch(searchRow)
	local box, page = assert(search), assert(panel)
	local home = view.name == "overview"
	local zones = home and ns.GatherMate.Available() and next(ns.Skills.Ranks()) ~= nil
	local typing = box:HasFocus()
	box:SetShown(zones or searchRow ~= nil)
	box.Instructions:SetText(home and L["Search zones"] or L["Add an item"])
	assert(cog):SetShown(home)
	if searchRow then
		box:SetParent(content)
		box:SetFrameLevel(searchRow:GetFrameLevel() + 1)
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", searchRow, "TOPLEFT", 6, -1)
		box:SetPoint("BOTTOMRIGHT", searchRow, "BOTTOMRIGHT", -6, 1)
	elseif zones then
		box:SetParent(page)
		box:SetFrameLevel(page:GetFrameLevel() + 2)
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -3)
		box:SetPoint("TOPRIGHT", page, "TOPRIGHT", -24, -3)
		box:SetHeight(22)
	end
	if box:IsShown() then
		if box:GetText() ~= (view.query or "") then
			box:SetText(view.query or "")
		end
		-- Parenting the box again while it is typed in must not take the cursor from it.
		if typing then
			box:SetFocus()
		end
	end
end

-- Draws the current view. A hidden page is left alone, so it cannot put its zone's loop back on the world map.
function Panel.Refresh()
	if not onScreen or not panel or not content or not scroll or not background then
		return
	end
	pickedZone = nil
	if view.name == "zone" then
		specs = Panel.ZoneSpecs(Panel.Refresh)
	elseif view.name == "list" then
		specs = Panel.ListSpecs(Panel.Refresh)
	else
		specs = Panel.OverviewSpecs(Panel.Refresh)
	end
	-- A folded header hides the rows under it, up to the next header or a row that ends its section.
	local shown, hidden = {}, false
	for _, spec in ipairs(specs) do
		if spec.type == "header" then
			shown[#shown + 1] = spec
			hidden = collapsed[spec.key] == true
		else
			hidden = hidden and not spec.ends
			if not hidden then
				shown[#shown + 1] = spec
			end
		end
	end
	specs = shown
	local top = view.name == "overview" and TOP_BAR or 0
	scroll:SetPoint("TOPLEFT", 0, -top)
	background:SetPoint("TOPLEFT", 0, -top)
	LayoutBackground(panel:GetWidth(), panel:GetHeight() - top)
	local width = math.max(MIN_WIDTH, panel:GetWidth() - 4)
	local y = 0
	local used, searchRow = {}, nil
	for i, spec in ipairs(specs) do
		if i > 2 then
			y = y + (BEFORE[spec.type] or 0)
		end
		used[spec.type] = (used[spec.type] or 0) + 1
		local row = Row(spec.type, used[spec.type])
		Draw(row, spec, width - 2 * PAD, y)
		if spec.type == "search" then
			searchRow = row
		end
		y = y + Height(spec) + (AFTER[spec.type] or 0)
	end
	for kind, pool in pairs(pools) do
		for i = (used[kind] or 0) + 1, #pool do
			pool[i]:Hide()
		end
	end
	content:SetSize(width, y + PAD)
	PlaceSearch(searchRow)
	ns.Loop.Preview(pickedZone)
	Footer()
	if pickedZone then
		local failure = Panel.AutoStart(pickedZone)
		if failure then
			assert(footerText):SetText(failure)
		end
	end
end

-- Specs the layout tests and the screenshots read.
---@return table[] specs
---@return table view
function Panel.State()
	return specs, view
end

-- The settings, as a menu on the overview's cog.
---@param owner Button
local function OpenSettings(owner)
	ForeverCore.ContextMenu(owner, function(_, root)
		root:CreateTitle(L["Gathering Guide"])
		-- menu-scroll-ok: the addon's few fixed settings
		for _, option in ipairs(ns.SettingsModule.options) do
			local entry = root:CreateCheckbox(option.label, function()
				return ns.DB[option.key]
			end, function()
				ns.SettingsModule.Set(option.key, not ns.DB[option.key])
				if option.key == "skipNoSkillUp" then
					ns.Planner.ClearResults()
				end
				Panel.Refresh()
			end)
			local tip = TIPS[option.key]
			if tip then
				entry:SetTooltip(function(tooltip)
					tooltip:SetText(L[tip], nil, nil, nil, nil, true)
				end)
			end
		end
	end)
end

local function Build()
	local map = QuestMapFrame
	panel = CreateFrame("Frame", "GatheringGuideForeverPanel", map)
	panel:SetPoint("TOPLEFT", map.ContentsAnchor)
	panel:SetPoint("BOTTOMRIGHT", map.ContentsAnchor, -22, 0)
	background = panel:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("TOPLEFT")
	background:SetPoint("BOTTOMRIGHT")
	background:SetAtlas("QuestLog-main-background") -- art-ok: centre-cropped to the panel's shape (LayoutBackground)
	panel:SetFrameLevel(map:GetFrameLevel() + 20)
	panel:EnableMouse(true)
	panel:Hide()
	scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", -4, FOOTER)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(MIN_WIDTH, 10)
	scroll:SetScrollChild(content)
	search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetAutoFocus(false)
	-- Hooked: the template's own handler hides the hint over typed text.
	-- Compared, not filtered by user input: the box's clear button empties it from code.
	search:HookScript("OnTextChanged", function(self)
		local text = self:GetText()
		if text ~= (view.query or "") then
			view.query = text
			Panel.Refresh()
		end
	end)
	search:SetScript("OnEscapePressed", search.ClearFocus)
	search:Hide()
	cog = CreateFrame("Button", nil, panel)
	cog:SetSize(16, 16)
	cog:SetPoint("TOPRIGHT", -4, -6)
	for _, layer in ipairs({ "ARTWORK", "HIGHLIGHT" }) do
		local art = cog:CreateTexture(nil, layer)
		art:SetPoint("CENTER")
		ns.Fit(art, "questlog-icon-setting", 16, 16)
		if layer == "HIGHLIGHT" then
			art:SetBlendMode("ADD")
		end
	end
	cog:SetScript("OnClick", OpenSettings)
	cog:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Settings"])
		GameTooltip:Show()
	end)
	cog:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	footerButton = CreateFrame("Button", nil, panel, "SharedButtonSmallTemplate")
	footerButton:SetSize(180, 24)
	footerButton:SetPoint("BOTTOM", 0, 8)
	footerText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	footerText:SetPoint("BOTTOM", footerButton, "TOP", 0, 2)
	panel:SetScript("OnSizeChanged", function()
		Panel.Refresh()
	end)
	-- The panel sets no OnShow or OnHide script because it lives under the world map; the tab module reports changes.
	local tab = ForeverCore.QuestLogTabs.Register("gathering", {
		name = "GatheringGuideForeverTab",
		tooltip = L["Gathering Guide"],
		panel = panel,
		order = 30,
		safeCall = ns.core.SafeCall,
		shown = function(visible)
			onScreen = visible
			ns.MapFocus.SetPanelShown(visible)
			if visible then
				Panel.Refresh()
			else
				autoStart = false
				ns.Loop.Preview(nil)
			end
		end,
	})
	if tab then
		---@diagnostic disable-next-line: undefined-field
		local icon = tab.Icon
		ns.Fit(icon, ns.KIND_ATLAS["Mining"], 30, 30)
		-- The stock icon's left offset is for full-bleed art. Keep the smaller glyph clear of the mask bevel.
		---@diagnostic disable-next-line: inject-field
		tab.GetFinalIconAnchorOffsets = function()
			return 0, 0
		end
		icon:ClearAllPoints()
		icon:SetPoint("CENTER", 0, 0)
	end
	ns.Tour.Listen(Panel.Refresh)
end

-- Opens the world map on the Gathering page. ForeverCore opens the map through the client's secure boundary, which is
-- the only way an addon opens it without tainting it; in combat the player opens it themselves.
function Panel.Open()
	if not WorldMapFrame:IsShown() and not (ForeverCore.OpenMap and ForeverCore.OpenMap()) then
		return
	end
	C_Timer.After(0.1, function()
		ForeverCore.QuestLogTabs.Select("gathering")
	end)
end

ns.OnLoaded(function()
	if QuestMapFrame and ForeverCore.QuestLogTabs then
		Build()
	end
end)

SLASH_GATHERINGGUIDEFOREVER1 = "/gathering"
SLASH_GATHERINGGUIDEFOREVER2 = "/ggf"
SlashCmdList["GATHERINGGUIDEFOREVER"] = function(message)
	local command = type(message) == "string" and message:lower():match("^%s*(.-)%s*$") or ""
	if ns.core.Report.Command(command) then
		return
	end
	Panel.Open()
end
