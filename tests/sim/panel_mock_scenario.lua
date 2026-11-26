-- luacheck: read globals scenario
local core = os.getenv("FOREVER_CORE") or "../forever-core"

scenario("Gathering shopping list mock", { addons = { { core, "ForeverCore" } } }, function(sim)
	local G = sim.G
	sim.world.maps[1417] = { name = "Arathi Highlands", parent = 1415, mapType = 3 }
	sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
	G.GatherMate2 = {
		GetNodesForZone = function()
			return next, {}
		end,
	}
	local items =
		{ { item = "Iron Ore", need = 20 }, { item = "Kingsblood", need = 10 }, { item = "Gold Ore", need = 4 } }
	sim:login({ savedVariables = { GatheringGuideForeverCharDB = { list = items } } })
	local counts = { ["Iron Ore"] = 6, Kingsblood = 10 }
	G.C_Item.GetItemCount = function(item)
		return counts[item] or 0
	end
	sim:openWorldMap(1417)
	sim:input(function()
		G.WorldMapFrame:SetQuestLogPanelShown(true)
	end)
	sim:slash("/gathering")
	sim:advance(0.2)
	local panel = assert(G.GatheringGuideForeverPanel, "missing Gathering panel")
	assert(panel:IsVisible(), "Gathering panel hidden")
	local tab = G.GatheringGuideForeverTab
	sim:input(function()
		tab:OnMouseDown("LeftButton")
		tab:OnMouseUp("LeftButton", true)
	end)
	local _, _, _, iconX, iconY = tab.Icon:GetPoint()
	assert(iconX == 0 and iconY == 0, "the native press cycle must keep the icon centred")
	local width = tonumber(os.getenv("GATHERING_MOCK_WIDTH"))
	if width then
		local height = panel:GetHeight()
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", G.QuestMapFrame.ContentsAnchor)
		panel:SetSize(width, height)
	end
	local viewport = panel:GetChildren()
	local content = viewport:GetScrollChild()
	local titled = false
	for _, row in ipairs({ content:GetChildren() }) do
		if row.Left and row.Left.GetText and row.Left:GetText() == "Gathering Guide" and row:IsShown() then
			titled = true
			assert(not row.Plate:IsShown() and not row.Band:IsShown(), "the title block wears no row art")
		elseif row.Left and row.Left.GetText and row.Left:GetText() == "Open my farming list" then
			assert(row.Plate:IsShown() and row.Icon:IsShown(), "the list action is a dark row with an icon")
		end
	end
	assert(titled, "the overview opens with the title block")
	local opened = false
	for _, row in ipairs({ content:GetChildren() }) do
		if row.Left and row.Left.GetText and row.Left:GetText() == "Open my farming list" then
			sim:input(function()
				row:GetScript("OnClick")(row, "LeftButton")
			end)
			opened = true
			break
		end
	end
	assert(opened, "the farming list action was missing")
	sim:advance(0.3)
	if os.getenv("GATHERING_MOCK_SCENE") ~= "1" then
		return
	end
	print("MOCK", "size", panel:GetSize())
	for _, row in ipairs({ content:GetChildren() }) do
		if row.Left and row.Left.GetText and row:IsShown() then
			local _, _, _, x, y = row:GetPoint()
			print(
				"MOCK",
				"row",
				x,
				y,
				row:GetHeight(),
				row:GetWidth(),
				row.Left:GetText() or "",
				row.Right:GetText() or "",
				row.Bar:IsShown() and row.Bar:GetValue() or "",
				row.Bar:IsShown() and select(2, row.Bar:GetMinMaxValues()) or ""
			)
		end
	end
end)
