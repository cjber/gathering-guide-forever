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
local HEIGHTS =
	{ header = 24, card = 50, node = 18, toggle = 24, button = 28, text = 34, item = 30, back = 24, search = 28 }
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
---@type Frame?, Button?, EditBox?, FontString?
local content, footerButton, search, footerText
local pickedZone

local function Rank(kind)
	return (ns.Skills.Rank(ns.KindByName[kind].line))
end

local function Minutes(seconds)
	return math.max(1, math.floor(seconds / 60 + 0.5))
end

-- Planned numbers for each view, filled in over frames by the planner and kept until the skill or setting changes.
local results = {}
local function Result(key, work, done)
	if results[key] ~= nil then
		return results[key]
	end
	ns.Planner.Async(key, work, function(value)
		results[key] = value
		done()
	end)
	return results[key]
end

function Panel.ClearResults()
	results = {}
end

--[[ View specs ]]

---@param zone table
---@return string
local function ZoneSub(zone)
	local travel = ns.Navigation.Estimate(zone.uiMapID, zone.order[1].x, zone.order[1].y)
	local parts = {
		string.format(L["Skill %d to %d"], zone.lowest or 0, zone.highest or 0),
	}
	if travel then
		parts[#parts + 1] = string.format(L["travel %d min"], Minutes(travel))
	end
	parts[#parts + 1] = string.format(L["%.1f per 10 min"], zone.rate)
	return table.concat(parts, ", ")
end

---@param refresh fun()
---@return table[]
function Panel.OverviewSpecs(refresh)
	local out = {}
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
		out[#out + 1] = { type = "header", text = L["Continue"] }
		out[#out + 1] = {
			type = "card",
			text = string.format(
				L["%s: %s"],
				ns.KindByName[last.kind] and ns.KindByName[last.kind].label or last.kind,
				last.name
			),
			sub = L["Start again from the node nearest you"],
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
			out[#out + 1] = { type = "header", text = string.format(L["%s, skill %d"], k.label, rank) }
			local key = ("best:%s:%d:%s"):format(k.kind, rank, tostring(ns.DB.skipNoSkillUp))
			local zones = Result(key, function(yield)
				return ns.Planner.Best(k.kind, rank, ns.DB.skipNoSkillUp, 3, yield)
			end, refresh)
			if not zones then
				out[#out + 1] = { type = "text", text = L["Planning loops..."] }
			elseif #zones == 0 then
				out[#out + 1] =
					{ type = "text", text = L["No zone in your GatherMate2 data has nodes for this skill."] }
			end
			for _, zone in ipairs(zones or {}) do
				out[#out + 1] = {
					type = "card",
					text = zone.name,
					sub = ZoneSub(zone),
					onClick = function()
						view = { name = "zone", kind = k.kind, uiMapID = zone.uiMapID }
						refresh()
					end,
				}
			end
		end
	end
	if not learned then
		out[#out + 1] = { type = "text", text = L["Learn Mining or Herbalism to see the best zones for your skill."] }
	end
	out[#out + 1] = { type = "header", text = L["Farm for a list"] }
	out[#out + 1] = {
		type = "button",
		text = L["Open my farming list"],
		onClick = function()
			view = { name = "list" }
			refresh()
		end,
	}
	return out
end

---@param refresh fun()
---@return table[]
function Panel.ZoneSpecs(refresh)
	local out = {
		{
			type = "back",
			text = L["Back"],
			onClick = function()
				view = { name = "overview" }
				refresh()
			end,
		},
	}
	local k = ns.KindByName[view.kind]
	local rank = Rank(view.kind)
	local skip = ns.DB.skipNoSkillUp
	local key = ("zone:%s:%d:%d:%s"):format(view.kind, view.uiMapID, rank, tostring(skip))
	local zone = Result(key, function(yield)
		return ns.Planner.Zone(view.kind, view.uiMapID, rank, skip, yield) or false
	end, refresh)
	out[#out + 1] = { type = "header", text = ns.Planner.ZoneName(view.uiMapID) }
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
	out[#out + 1] = { type = "header", text = k and k.label or view.kind }
	for _, name in ipairs(nodeOrder) do
		local c = counts[name]
		local chance, color = ns.Skills.Chance(rank, c.required)
		out[#out + 1] = {
			type = "node",
			text = name,
			right = color == "red" and string.format(L["needs %d"], c.required)
				or string.format("%d%%", math.floor(chance * 100 + 0.5)),
			sub = string.format("x%d", c.count),
			color = color,
		}
	end
	if zone == nil then
		out[#out + 1] = { type = "text", text = L["Planning the loop..."] }
	elseif zone == false then
		out[#out + 1] = { type = "text", text = L["Nothing here can raise your skill yet."] }
	else
		pickedZone = zone
		out[#out + 1] = { type = "text", text = ZoneSub(zone), color = "grey" }
		local nextKey = key .. ":next"
		local later = Result(nextKey, function(yield)
			return ns.Planner.Next(zone, rank, skip, yield)
		end, refresh)
		out[#out + 1] = { type = "header", text = L["Next zones"] }
		if not later then
			out[#out + 1] = { type = "text", text = L["Planning loops..."] }
		end
		for _, z in ipairs(later or {}) do
			out[#out + 1] = {
				type = "card",
				text = z.name,
				sub = ZoneSub(z),
				onClick = function()
					view = { name = "zone", kind = z.kind, uiMapID = z.uiMapID }
					refresh()
				end,
			}
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
			type = "back",
			text = L["Back"],
			onClick = function()
				view = { name = "overview" }
				refresh()
			end,
		},
		{ type = "header", text = L["Farm for a list"] },
		{ type = "search", text = L["Add an item"] },
	}
	for _, item in ipairs(Panel.Matches(view.query)) do
		out[#out + 1] = {
			type = "node",
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
	local zones = Result(key, function(yield)
		return ns.Planner.ListZones(4, yield)
	end, refresh)
	out[#out + 1] = { type = "header", text = L["Best zone for the whole list"] }
	if not zones then
		out[#out + 1] = { type = "text", text = L["Planning loops..."] }
		return out
	end
	if #zones == 0 then
		out[#out + 1] = { type = "text", text = L["Nothing on your list is in your GatherMate2 data."] }
		return out
	end
	pickedZone = zones[view.pick or 1] or zones[1]
	for i, zone in ipairs(zones) do
		if i == 2 then
			out[#out + 1] = { type = "header", text = L["Other places"] }
		end
		out[#out + 1] = {
			type = "card",
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

local function NewRow(index)
	local row = CreateFrame("Button", nil, content)
	row.Left = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Left:SetJustifyH("LEFT")
	row.Right = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	row.Right:SetJustifyH("RIGHT")
	row.Sub = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Sub:SetJustifyH("LEFT")
	row.Back = row:CreateTexture(nil, "BACKGROUND")
	row.Back:SetAllPoints()
	row.Back:SetColorTexture(1, 1, 1, 0)
	row.Check = row:CreateTexture(nil, "ARTWORK")
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

local function Layout(row, spec, width, y)
	local h = HEIGHTS[spec.type] or 24
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -y)
	row:SetSize(width - 2 * PAD, h)
	row.Left:ClearAllPoints()
	row.Right:ClearAllPoints()
	row.Sub:ClearAllPoints()
	row.Check:Hide()
	row.Bar:Hide()
	row.Sub:SetText("")
	row.Right:SetText(spec.right or "")
	row.Back:SetColorTexture(1, 1, 1, spec.selected and 0.12 or 0)
	local font = spec.type == "header" and "GameFontNormal" or "GameFontHighlight"
	row.Left:SetFontObject(font)
	local rgb = ColorOf(spec.color)
	if rgb then
		row.Left:SetTextColor(rgb[1], rgb[2], rgb[3])
	else
		row.Left:SetTextColor(1, 1, 1)
	end
	row.Left:SetText(spec.text or "")
	local left = 4
	if spec.type == "toggle" then
		ns.Fit(row.Check, spec.checked and "common-icon-checkmark" or "common-icon-redx", 14, 14)
		row.Check:SetPoint("LEFT", 4, 0)
		row.Check:Show()
		left = 24
	elseif spec.type == "back" then
		ns.Fit(row.Check, "common-icon-backarrow", 14, 14)
		row.Check:SetPoint("LEFT", 4, 0)
		row.Check:Show()
		left = 24
	end
	row.Right:SetPoint("RIGHT", -4, 0)
	if spec.type == "card" or spec.type == "item" then
		row.Left:SetPoint("TOPLEFT", left, -6)
		row.Left:SetPoint("RIGHT", row.Right, "LEFT", -4, 0)
		row.Right:ClearAllPoints()
		row.Right:SetPoint("TOPRIGHT", -4, -6)
		row.Sub:SetPoint("TOPLEFT", row.Left, "BOTTOMLEFT", 0, -2)
		row.Sub:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.Sub:SetText(spec.sub or "")
		if spec.bar then
			row.Bar:ClearAllPoints()
			row.Bar:SetPoint("BOTTOMLEFT", 4, 3)
			row.Bar:SetPoint("BOTTOMRIGHT", -4, 3)
			row.Bar:SetMinMaxValues(0, math.max(spec.bar.need, 1))
			row.Bar:SetValue(math.min(spec.bar.have, spec.bar.need))
			local done = spec.bar.have >= spec.bar.need
			row.Bar:SetStatusBarColor(done and 0.25 or 1, done and 0.75 or 0.8, done and 0.25 or 0.1)
			row.Bar:Show()
		end
	else
		row.Left:SetPoint("LEFT", left, 0)
		row.Left:SetPoint("RIGHT", row.Right, "LEFT", -4, 0)
		if spec.type == "node" and spec.sub then
			row.Sub:SetPoint("RIGHT", row.Right, "LEFT", -6, 0)
			row.Sub:SetText(spec.sub)
			row.Left:SetPoint("RIGHT", row.Sub, "LEFT", -4, 0)
		end
	end
	if spec.type == "text" then
		row.Left:SetWordWrap(true)
		row.Left:SetPoint("TOPLEFT", left, -2)
		row.Left:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.Left:SetFontObject("GameFontDisableSmall")
		if not rgb then
			row.Left:SetTextColor(0.8, 0.8, 0.8)
		end
	else
		row.Left:SetWordWrap(false)
	end
	row:EnableMouse(spec.onClick ~= nil)
	row:SetScript("OnClick", spec.onClick)
	row:SetScript("OnEnter", function()
		if spec.onClick then
			row.Back:SetColorTexture(1, 1, 1, 0.15)
		end
		if spec.tooltip then
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetText(spec.tooltip)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function()
		row.Back:SetColorTexture(1, 1, 1, spec.selected and 0.12 or 0)
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
				if (view.query or "") == "" then
					rows[i].Left:SetText(spec.text)
					rows[i].Left:SetTextColor(0.5, 0.5, 0.5)
				else
					rows[i].Left:SetText("")
				end
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
	search = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
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
		icon:ClearAllPoints()
		icon:SetPoint("CENTER", tab, "CENTER")
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
