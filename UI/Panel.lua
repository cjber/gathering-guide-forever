---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end
local L = ns.L

-- The Gathering side page of the world map's quest log (ForeverCore.QuestLogTabs). Three views, each built as a plain
-- list of row specs and then drawn by one row pool:
--   overview  Continue, and the best zones for the player's mining and herbalism
--   zone      one zone's nodes by skill-up chance, the next zones, and the tour
--   list      a shopping list of herbs and ores, the best zone for all of it and other places
local Panel = {}
ns.Panel = Panel

local PAD = 8
local HIDE_TIP = "Turns GatherMate2's world map icons off, so the map shows only this addon's pins for the zone "
	.. "you are viewing or touring. Your own GatherMate2 setting is put back when you turn this off, log out or "
	.. "disable the addon. Minimap icons are not changed."
local HEIGHTS = { title = 44, header = 22, card = 42, node = 30, toggle = 24, text = 34, item = 42, search = 28 }
local ICON = 32
local NODE_ICON = 22
local ROW_GAP = 2
local FOOTER = 40
local TOP_BAR = 29
local MIN_WIDTH = 240

---@type Frame?
local panel
---@type table
local view = { name = "overview" }
local rows = {}
local specs = {}
---@type Frame?, Button?, (EditBox|{Instructions: FontString})?, FontString?
local content, footerButton, search, footerText
local pickedZone

local function Rank(kind)
	return (ns.Skills.Rank(ns.KindByName[kind].line))
end

-- A herb's or ore's own item icon (a file id) when the client knows the item by name, else its profession's atlas.
---@param name string
---@param kind string?
---@return string|number?
local function NodeIcon(name, kind)
	local icon = C_Item.GetItemInfoInstant and select(5, C_Item.GetItemInfoInstant(name)) -- multi-value: the icon is fifth
	return icon or ns.KIND_ATLAS[kind or ""]
end

local function Minutes(seconds)
	return math.max(1, math.floor(seconds / 60 + 0.5))
end

local Result = ns.Planner.Result

-- What a view with no result yet says: that it is planning, or that the plan failed.
---@param failed boolean?
---@param planning string
---@return string
local function PlanText(failed, planning)
	return failed and L["The plan failed. The report window (/ggf report) shows why."] or planning
end

Panel.ClearResults = ns.Planner.ClearResults

--[[ View specs ]]

---@param zone table
---@return string
local function ZoneSub(zone)
	local parts = {
		string.format(L["Skill %d to %d"], zone.lowest or 0, zone.highest or 0),
	}
	if zone.travel then
		parts[#parts + 1] = string.format(L["travel %d min"], Minutes(zone.travel))
	end
	return table.concat(parts, ", ")
end

---@param zone table
---@return string
local function RateText(zone)
	return string.format(L["%.1f per 10 min"], zone.rate)
end

-- A card for a zone: its kind's art, the zone's name and skill range, and the rate at the right.
---@param zone table
---@param onClick fun()
---@return table
local function ZoneCard(zone, onClick)
	return {
		type = "card",
		icon = ns.KIND_ATLAS[zone.kind],
		text = zone.name,
		sub = ZoneSub(zone),
		right = RateText(zone),
		onClick = onClick,
	}
end

---@param refresh fun()
---@return table[]
function Panel.OverviewSpecs(refresh)
	local out = {}
	local here = ns.World.PlayerMap()
	out[#out + 1] = {
		type = "title",
		icon = ns.KIND_ATLAS["Mining"],
		text = L["Gathering Guide"],
		sub = here and ns.Planner.ZoneName(here) or L["Best zones for your skill"],
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
	local last = ns.Char.last
	if last then
		out[#out + 1] = { type = "header", key = "continue", text = L["Continue"] }
		out[#out + 1] = {
			type = "card",
			icon = ns.KIND_ATLAS[last.kind],
			text = last.name,
			sub = L["Start again from the node nearest you"],
			right = ns.KindByName[last.kind] and ns.KindByName[last.kind].label or last.kind,
			onClick = function()
				view = { name = "zone", kind = last.kind, uiMapID = last.uiMapID }
				refresh()
			end,
		}
	end
	local learned = false
	for _, k in ipairs(ns.Kinds) do
		local rank = Rank(k.kind)
		if rank > 0 then
			learned = true
			local header = { type = "header", key = k.kind, text = string.format(L["%s, skill %d"], k.label, rank) }
			out[#out + 1] = header
			local zones, failed = ns.Planner.Ranking(k.kind, rank, ns.DB.skipNoSkillUp, refresh)
			header.count = zones and #zones or nil
			if failed or not zones then
				out[#out + 1] = { type = "text", text = PlanText(failed, L["Planning loops..."]) }
			elseif #zones == 0 then
				out[#out + 1] =
					{ type = "text", text = L["No zone in your GatherMate2 data has nodes for this skill."] }
			end
			for _, zone in ipairs(zones or {}) do
				out[#out + 1] = ZoneCard(zone, function()
					view = { name = "zone", kind = k.kind, uiMapID = zone.uiMapID }
					refresh()
				end)
			end
		end
	end
	if not learned then
		out[#out + 1] = { type = "text", text = L["Learn Mining or Herbalism to see the best zones for your skill."] }
	end
	out[#out + 1] = { type = "header", key = "list", text = L["Farm for a list"] }
	out[#out + 1] = {
		type = "card",
		icon = ns.KIND_ATLAS["Herb Gathering"],
		text = L["Open my farming list"],
		onClick = function()
			view = { name = "list" }
			refresh()
		end,
	}
	out[#out + 1] = {
		type = "toggle",
		text = L["Hide GatherMate2 map icons"],
		checked = ns.DB.hideGatherMate,
		tooltip = L[HIDE_TIP],
		onClick = function()
			ns.SettingsModule.Set("hideGatherMate", not ns.DB.hideGatherMate)
			refresh()
		end,
	}
	return out
end

---@param refresh fun()
---@return table[]
function Panel.ZoneSpecs(refresh)
	local k = ns.KindByName[view.kind]
	local out = {}
	local rank = Rank(view.kind)
	local skip = ns.DB.skipNoSkillUp
	local key = ("zone:%s:%d:%d:%s:%s"):format(
		view.kind,
		view.uiMapID,
		rank,
		tostring(skip),
		tostring(ns.World.PlayerMap())
	)
	local zone, zoneFailed = Result(key, function(yield)
		return ns.Planner.Zone(view.kind, view.uiMapID, rank, skip, yield) or false
	end, refresh)
	out[#out + 1] = {
		type = "title",
		icon = ns.KIND_ATLAS[view.kind],
		text = ns.Planner.ZoneName(view.uiMapID),
		sub = string.format(L["%s, skill %d"], k and k.label or view.kind, rank),
		onBack = function()
			view = { name = "overview" }
			refresh()
		end,
	}
	out[#out + 1] = {
		type = "toggle",
		text = L["Skip nodes with no skill-up"],
		checked = skip,
		onClick = function()
			ns.SettingsModule.Set("skipNoSkillUp", not ns.DB.skipNoSkillUp)
			Panel.ClearResults()
			refresh()
		end,
	}
	-- Every node the zone has by name, coloured by what it gives at this skill.
	local counts, nodeOrder = {}, {}
	for _, node in ipairs(ns.GatherMate.Nodes(view.uiMapID, view.kind)) do
		if not counts[node.name] then
			counts[node.name] = { count = 0, required = node.required }
			nodeOrder[#nodeOrder + 1] = node.name
		end
		counts[node.name].count = counts[node.name].count + 1
	end
	table.sort(nodeOrder, function(a, b)
		if counts[a].required ~= counts[b].required then
			return counts[a].required < counts[b].required
		end
		return a < b
	end)
	out[#out + 1] = { type = "header", key = "nodes", text = L["Nodes here"], count = #nodeOrder }
	for _, name in ipairs(nodeOrder) do
		local c = counts[name]
		local chance, color = ns.Skills.Chance(rank, c.required)
		out[#out + 1] = {
			type = "node",
			text = name,
			right = color == "red" and string.format(L["needs %d"], c.required)
				or string.format("%d%%", math.floor(chance * 100 + 0.5)),
			sub = string.format("x%d", c.count),
			icon = NodeIcon(name, view.kind),
			color = color,
		}
	end
	if zone == nil then
		out[#out + 1] = { type = "text", text = PlanText(zoneFailed, L["Planning the loop..."]) }
	elseif zone == false then
		out[#out + 1] = { type = "text", text = L["Nothing here can raise your skill yet."] }
	else
		pickedZone = zone
		out[#out + 1] = { type = "text", text = ZoneSub(zone) .. ", " .. RateText(zone), color = "grey" }
		local nextKey = key .. ":next"
		local later, laterFailed = Result(nextKey, function(yield)
			return ns.Planner.Next(zone, rank, skip, yield)
		end, refresh)
		local nextHeader = { type = "header", key = "next", text = L["Next zones"] }
		out[#out + 1] = nextHeader
		nextHeader.count = later and #later or nil
		if not later then
			out[#out + 1] = { type = "text", text = PlanText(laterFailed, L["Planning loops..."]) }
		end
		for _, z in ipairs(later or {}) do
			out[#out + 1] = ZoneCard(z, function()
				view = { name = "zone", kind = z.kind, uiMapID = z.uiMapID }
				refresh()
			end)
		end
	end
	return out
end

-- The item names matching what the player typed, at most six.
---@param text string
---@return string[]
function Panel.Matches(text)
	local found = {}
	text = (text or ""):lower()
	if text == "" then
		return found
	end
	for name in pairs(ns.Planner.Items()) do
		if name:lower():find(text, 1, true) then
			found[#found + 1] = name
		end
	end
	table.sort(found)
	while #found > 6 do
		found[#found] = nil
	end
	return found
end

---@param refresh fun()
---@return table[]
function Panel.ListSpecs(refresh)
	local out = {
		{
			type = "title",
			icon = ns.KIND_ATLAS["Herb Gathering"],
			text = L["Farm for a list"],
			sub = string.format(L["%d on your list"], #ns.Char.list),
			onBack = function()
				view = { name = "overview" }
				refresh()
			end,
		},
		{ type = "search", text = L["Add an item"] },
	}
	for _, item in ipairs(Panel.Matches(view.query)) do
		out[#out + 1] = {
			type = "node",
			icon = NodeIcon(item, ns.Planner.Items()[item].kind),
			text = item,
			right = L["Add"],
			color = "green",
			onClick = function()
				ns.Planner.AddItem(item, 20)
				view.query = nil
				Panel.ClearResults()
				refresh()
			end,
		}
	end
	local listRows = ns.Planner.ListRows()
	for _, row in ipairs(listRows) do
		out[#out + 1] = {
			type = "item",
			icon = NodeIcon(row.item, (ns.Planner.Items()[row.item] or {}).kind),
			text = row.item,
			right = string.format("%d / %d", row.have, row.need),
			bar = { have = row.have, need = row.need },
			tooltip = L["Click to remove from the list"],
			onClick = function()
				ns.Planner.RemoveItem(row.item)
				Panel.ClearResults()
				refresh()
			end,
		}
	end
	if #listRows == 0 then
		out[#out + 1] = { type = "text", text = L["Search for an herb or ore to add it."] }
		return out
	end
	local key = "list:"
		.. #listRows
		.. ":"
		.. table.concat(
			(function()
				local parts = {}
				for _, row in ipairs(listRows) do
					parts[#parts + 1] = row.item .. row.need .. (row.have < row.need and "o" or "d")
				end
				return parts
			end)(),
			","
		)
	local zones, listFailed = Result(key, function(yield)
		return ns.Planner.ListZones(4, yield)
	end, refresh)
	local best = { type = "header", key = "best", text = L["Best zone for the whole list"] }
	out[#out + 1] = best
	if not zones then
		out[#out + 1] = { type = "text", text = PlanText(listFailed, L["Planning loops..."]) }
		return out
	end
	if #zones == 0 then
		out[#out + 1] = { type = "text", text = L["Nothing on your list is in your GatherMate2 data."] }
		return out
	end
	pickedZone = zones[view.pick or 1] or zones[1]
	best.count = 1
	for i, zone in ipairs(zones) do
		if i == 2 then
			out[#out + 1] = { type = "header", key = "others", text = L["Other places"], count = #zones - 1 }
		end
		out[#out + 1] = {
			type = "card",
			icon = ns.KIND_ATLAS[zone.kind],
			text = zone.name,
			sub = string.format(L["%d nodes, %d min a loop"], zone.count, Minutes(zone.seconds)),
			selected = zone == pickedZone,
			onClick = function()
				view.pick = i
				refresh()
			end,
		}
	end
	return out
end

--[[ Drawing ]]

local COLORS = { red = { 1, 0.3, 0.3 }, grey = { 0.6, 0.6, 0.6 } }

local function ColorOf(color)
	if not color then
		return nil
	end
	return COLORS[color] or ns.Skills.Color(color)
end

-- The quest log's own art, drawn as Shortest Path Forever's Nearby panel draws it (UI/ServicesPanel.lua, UI/Art.lua):
-- the Who list's row at its native 69 height scaled evenly to the row, and the list header's band stretched across.
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

local function NewRow(index)
	local row = CreateFrame("Button", nil, content)
	row.Plate = RowTexture(row, "common-button-list-large", "BACKGROUND")
	row.Hover = RowTexture(row, "common-button-list-large-hover", "HIGHLIGHT")
	row.Hover:SetBlendMode("ADD")
	row.Band = row:CreateTexture(nil, "BACKGROUND")
	-- art-ok: the stock list header, stretched across its row as the client does
	row.Band:SetAtlas("common-button-list-collapseExpand")
	row.Band:SetAllPoints()
	row.Fold = CreateFrame("Button", nil, row, "CollapseButtonTemplate")
	row.Fold:SetPoint("RIGHT", -6, 0)
	row.Fold:EnableMouse(false)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Left = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Left:SetJustifyH("LEFT")
	row.Right = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Right:SetJustifyH("RIGHT")
	row.Sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Sub:SetJustifyH("LEFT")
	row.Check = row:CreateTexture(nil, "ARTWORK")
	row.BackButton = CreateFrame("Button", nil, row)
	row.BackButton:SetSize(24, 24)
	row.BackButton:SetPoint("LEFT", 0, 0)
	row.BackArt = row.BackButton:CreateTexture(nil, "ARTWORK")
	row.BackArt:SetPoint("CENTER")
	ns.Fit(row.BackArt, "common-icon-backarrow", 16, 16)
	row.Bar = CreateFrame("StatusBar", nil, row)
	row.Bar:SetStatusBarTexture("common-stat-bar-white")
	row.Bar:SetHeight(4)
	local trough = row.Bar:CreateTexture(nil, "BACKGROUND")
	trough:SetPoint("TOPLEFT", -2, 1)
	trough:SetPoint("BOTTOMRIGHT", 2, -1)
	trough:SetAtlas("common-stat-bar-BG") -- art-ok: bar rim follows the size of its fill
	rows[index] = row
	return row
end

-- Header sections folded away, per session as the stock quest log's group folds are.
---@type table<string, boolean>
local collapsed = {}

-- A spec's icon: an atlas name at its own aspect, or a file id whole.
---@param row table
---@param icon string|number
---@param size number
local function SetIcon(row, icon, size)
	if type(icon) == "number" then
		row.Icon:SetTexCoord(0, 1, 0, 1)
		row.Icon:SetTexture(icon)
		row.Icon:SetSize(size, size)
	else
		ns.Fit(row.Icon, icon, size, size)
	end
end

local function Layout(row, spec, width, y)
	local h = HEIGHTS[spec.type] or 24
	local kind = spec.type
	local plated = kind == "card" or kind == "item" or kind == "node"
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -y)
	row:SetSize(width - 2 * PAD, h)
	for _, part in ipairs({ row.Left, row.Right, row.Sub, row.Icon }) do
		part:ClearAllPoints()
	end
	row.Plate:SetShown(plated)
	row.Hover:SetShown(plated and spec.onClick ~= nil)
	row.Band:SetShown(kind == "header")
	row.Fold:SetShown(kind == "header" and spec.key ~= nil)
	row.Icon:SetShown(spec.icon ~= nil)
	row.BackButton:SetShown(spec.onBack ~= nil)
	row.BackButton:SetScript("OnClick", spec.onBack)
	row.Check:Hide()
	row.Bar:Hide()
	row.Sub:SetText("")
	row.Right:SetText(spec.right or "")
	row.Left:SetText(spec.text or "")
	local rgb = ColorOf(spec.color)
	local gold = NORMAL_FONT_COLOR
	local function Tint(r, g, b)
		row.Left:SetTextColor(r, g, b)
	end
	row.Left:SetWordWrap(false)
	row.Left:SetJustifyH("LEFT")
	row.Right:SetTextColor(1, 1, 1)
	if kind == "title" then
		local left = 2
		if spec.onBack then
			left = 26
		end
		if spec.icon then
			SetIcon(row, spec.icon, 30)
			row.Icon:SetPoint("LEFT", left, 0)
		end
		row.Left:SetFontObject("GameFontNormalLarge2")
		Tint(gold.r, gold.g, gold.b)
		row.Left:SetJustifyH("CENTER")
		row.Left:SetPoint("TOPLEFT", left + 34, -2)
		row.Left:SetPoint("TOPRIGHT", -left - 34, -2)
		row.Sub:SetFontObject("GameFontHighlight")
		row.Sub:SetJustifyH("CENTER")
		row.Sub:SetPoint("TOPLEFT", row.Left, "BOTTOMLEFT", 0, -2)
		row.Sub:SetPoint("TOPRIGHT", row.Left, "BOTTOMRIGHT", 0, -2)
		row.Sub:SetText(spec.sub or "")
	elseif kind == "header" then
		row.Left:SetFontObject("Game15Font_Shadow")
		Tint(gold.r, gold.g, gold.b)
		row.Right:SetFontObject("Game15Font_Shadow")
		row.Right:SetTextColor(gold.r, gold.g, gold.b)
		local right = spec.key and -28 or -8
		row.Right:SetText(spec.count and tostring(spec.count) or "")
		row.Right:SetPoint("RIGHT", right, 0)
		row.Left:SetPoint("LEFT", 8, 0)
		row.Left:SetPoint("RIGHT", row.Right, "LEFT", -4, 0)
		if spec.key then
			row.Fold:UpdateCollapsedState(collapsed[spec.key] == true)
		end
	elseif plated then
		local size = kind == "node" and NODE_ICON or ICON
		local left = 8
		if spec.icon then
			SetIcon(row, spec.icon, size)
			row.Icon:SetPoint("LEFT", 8, 0)
			left = 8 + size + 8
		end
		row.Right:SetFontObject("GameFontHighlight")
		row.Left:SetFontObject(kind == "node" and "GameFontHighlight" or "GameFontNormalMed3")
		if rgb then
			Tint(rgb[1], rgb[2], rgb[3])
		elseif kind == "node" then
			Tint(1, 1, 1)
		else
			Tint(gold.r, gold.g, gold.b)
		end
		if kind == "node" then
			row.Right:SetPoint("RIGHT", -8, 0)
			row.Left:SetPoint("LEFT", left, 0)
			row.Sub:SetFontObject("GameFontHighlightSmall")
			row.Sub:SetPoint("RIGHT", row.Right, "LEFT", -8, 0)
			row.Sub:SetText(spec.sub or "")
			row.Left:SetPoint("RIGHT", row.Sub, "LEFT", -4, 0)
		else
			row.Right:SetPoint("TOPRIGHT", -8, -9)
			row.Left:SetPoint("TOPLEFT", left, -6)
			row.Left:SetPoint("RIGHT", row.Right, "LEFT", -6, 0)
			row.Sub:SetFontObject("GameFontHighlightSmall")
			row.Sub:SetTextColor(0.75, 0.75, 0.75)
			row.Sub:SetPoint("TOPLEFT", row.Left, "BOTTOMLEFT", 0, -3)
			row.Sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
			row.Sub:SetText(spec.sub or "")
		end
		if spec.bar then
			row.Bar:ClearAllPoints()
			row.Bar:SetPoint("BOTTOMLEFT", left, 5)
			row.Bar:SetPoint("BOTTOMRIGHT", -8, 5)
			row.Bar:SetMinMaxValues(0, math.max(spec.bar.need, 1))
			row.Bar:SetValue(math.min(spec.bar.have, spec.bar.need))
			local done = spec.bar.have >= spec.bar.need
			row.Bar:SetStatusBarColor(done and 0.25 or 1, done and 0.75 or 0.8, done and 0.25 or 0.1)
			row.Bar:Show()
		end
	else
		row.Left:SetFontObject("GameFontHighlight")
		Tint(rgb and rgb[1] or 1, rgb and rgb[2] or 1, rgb and rgb[3] or 1)
		local left = 4
		if kind == "toggle" then
			ns.Fit(row.Check, spec.checked and "common-icon-checkmark" or "common-icon-redx", 14, 14)
			row.Check:ClearAllPoints()
			row.Check:SetPoint("LEFT", 4, 0)
			row.Check:Show()
			left = 24
		end
		row.Right:SetFontObject("GameFontNormalSmall")
		row.Right:SetPoint("RIGHT", -4, 0)
		row.Left:SetPoint("LEFT", left, 0)
		row.Left:SetPoint("RIGHT", row.Right, "LEFT", -4, 0)
		if kind == "text" then
			row.Left:SetWordWrap(true)
			row.Left:SetPoint("TOPLEFT", left, -2)
			row.Left:SetPoint("RIGHT", row, "RIGHT", -4, 0)
			row.Left:SetFontObject("GameFontHighlightSmall")
			if not rgb then
				Tint(0.8, 0.8, 0.8)
			end
		end
	end
	local action = spec.onClick
	if kind == "header" and spec.key then
		action = function()
			collapsed[spec.key] = not collapsed[spec.key]
			Panel.Refresh()
		end
	end
	row:EnableMouse(action ~= nil)
	row:SetScript("OnClick", action)
	row.Plate:SetAlpha(spec.selected and 1 or 0.85)
	row:SetScript("OnEnter", function()
		if spec.tooltip then
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetText(spec.tooltip, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:Show()
	return h
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

-- Draws the current view.
function Panel.Refresh()
	if not panel or not content or not search then
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
	-- A folded header hides the rows under it, up to the next header or title.
	local shown, hidden = {}, false
	for _, spec in ipairs(specs) do
		if spec.type == "header" or spec.type == "title" then
			hidden = spec.key ~= nil and collapsed[spec.key] == true
			shown[#shown + 1] = spec
		elseif not hidden then
			shown[#shown + 1] = spec
		end
	end
	specs = shown
	local width = math.max(2 * PAD + 1, panel:GetWidth() - 4)
	local y = PAD
	local searchSpec
	for i, spec in ipairs(specs) do
		if spec.type == "search" then
			searchSpec = spec
		end
		local row = rows[i] or NewRow(i)
		y = y + Layout(row, spec, width, y) + ROW_GAP
	end
	for i = #specs + 1, #rows do
		rows[i]:Hide()
	end
	content:SetSize(width, y + PAD)
	search:SetShown(searchSpec ~= nil)
	if searchSpec then
		-- The edit box sits over its row so typing needs no extra frame in the list.
		for i, spec in ipairs(specs) do
			if spec == searchSpec then
				search:ClearAllPoints()
				search:SetPoint("TOPLEFT", rows[i], "TOPLEFT", 6, -2)
				search:SetPoint("BOTTOMRIGHT", rows[i], "BOTTOMRIGHT", -6, 2)
				rows[i].Left:SetText("")
				search.Instructions:SetText(spec.text)
				if search:GetText() ~= (view.query or "") then
					search:SetText(view.query or "")
				end
			end
		end
	end
	if view.name == "zone" and pickedZone then
		ns.Loop.Show(pickedZone)
	else
		ns.Loop.Refresh()
	end
	Footer()
end

-- Specs the layout tests and the screenshots read.
---@return table[] specs
---@return table view
function Panel.State()
	return specs, view
end

---@param name string
---@param kind string?
---@param uiMapID number?
function Panel.Go(name, kind, uiMapID)
	view = { name = name, kind = kind, uiMapID = uiMapID }
	Panel.Refresh()
end

-- Centre-crop the native quest list artwork as Adventure Guide does on the same host.
---@param background Texture
---@param width number
---@param height number
local function LayoutBackground(background, width, height)
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
	background:SetTexCoord(left, right, top, bottom)
end

local function Build()
	local map = QuestMapFrame
	panel = CreateFrame("Frame", "GatheringGuideForeverPanel", map)
	panel:SetPoint("TOPLEFT", map.ContentsAnchor)
	panel:SetPoint("BOTTOMRIGHT", map.ContentsAnchor, -22, 0)
	local background = panel:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("TOPLEFT", 0, -TOP_BAR)
	background:SetPoint("BOTTOMRIGHT")
	background:SetAtlas("QuestLog-main-background")
	panel:SetFrameLevel(map:GetFrameLevel() + 20)
	panel:EnableMouse(true)
	panel:Hide()
	local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -TOP_BAR)
	scroll:SetPoint("BOTTOMRIGHT", -4, FOOTER)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(MIN_WIDTH, 10)
	scroll:SetScrollChild(content)
	search = CreateFrame("EditBox", nil, content, "SearchBoxTemplate")
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function(self, user)
		if user then
			view.query = self:GetText()
			Panel.Refresh()
		end
	end)
	search:SetScript("OnEscapePressed", search.ClearFocus)
	search:Hide()
	footerButton = CreateFrame("Button", nil, panel, "SharedButtonSmallTemplate")
	footerButton:SetSize(140, 24)
	footerButton:SetPoint("BOTTOM", 0, 8)
	footerText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	footerText:SetPoint("BOTTOM", footerButton, "TOP", 0, 2)
	local function Resize(_, width, height)
		LayoutBackground(background, width, height - TOP_BAR)
		Panel.Refresh()
	end
	panel:SetScript("OnSizeChanged", Resize)
	LayoutBackground(background, panel:GetWidth(), panel:GetHeight() - TOP_BAR)
	-- The panel sets no OnShow or OnHide script because it lives under the world map; the tab module reports changes.
	local tab = ForeverCore.QuestLogTabs.Register("gathering", {
		name = "GatheringGuideForeverTab",
		tooltip = L["Gathering Guide"],
		panel = panel,
		order = 30,
		safeCall = ns.core.SafeCall,
		shown = function(visible)
			if visible then
				Panel.Refresh()
			end
		end,
	})
	if tab then
		---@diagnostic disable-next-line: undefined-field
		local icon = tab.Icon
		ns.Fit(icon, "Mobile-Mining", 30, 30)
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
