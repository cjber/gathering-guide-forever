-- luacheck: read globals scenario ADDON
local core = os.getenv("FOREVER_CORE") or "../forever-core"

scenario("the farm list's search box and item counts", { addons = { { core, "ForeverCore" } } }, function(sim)
	sim:login()
	local G = sim.G
	-- GatherMate2 with no nodes: the page only needs it present to offer the list.
	G.GatherMate2 = {
		GetNodesForZone = function()
			return pairs({})
		end,
	}
	sim:slash("/gathering")
	sim:advance(0.1)
	local panel = G.GatheringGuideForeverPanel
	assert(panel and panel:IsVisible(), "the Gathering page shows")

	local function find(parent, match)
		for _, child in ipairs({ parent:GetChildren() }) do
			if child:IsShown() then
				if match(child) then
					return child
				end
				local found = find(child, match)
				if found then
					return found
				end
			end
		end
	end
	-- A row by the string in one of its named lines: a card's title, a result's name, a list item's text.
	local function row(field, text)
		return find(panel, function(frame)
			local line = frame[field]
			return type(line) == "table" and line.GetText and line:GetText() == text
		end)
	end
	local tab = G.GatheringGuideForeverTab
	sim:input(function()
		tab:OnMouseDown("LeftButton")
		tab:OnMouseUp("LeftButton", true)
	end)
	local _, _, _, iconX, iconY = tab.Icon:GetPoint()
	assert(iconX == 0 and iconY == 0, "the native press cycle must keep the icon centred")
	local function box()
		return find(panel, function(frame)
			return frame.Instructions ~= nil
		end)
	end
	assert(not box(), "with no profession there are no zones to search")
	sim:click(assert(row("Title", "Farm for a list"), "the home page offers the list"))
	sim:advance(0.1)
	local search = assert(box(), "the list's search box")
	assert(search:IsShown() and search.Instructions:GetText() == "Add an item", "the list's box finds items")

	sim:input(function()
		search:SetFocus()
		search:SetText("tin")
		-- As the client reports typing.
		search:GetScript("OnTextChanged")(search, true)
	end)
	sim:advance(0.1)
	assert(row("Name", "Tin Ore"), "typing shows the matching items")
	assert(search:IsShown() and search:HasFocus(), "the box keeps the cursor as the page is redrawn")
	-- The clear button empties the box from code.
	sim:input(function()
		search:SetText("")
	end)
	sim:advance(0.1)
	assert(not row("Name", "Tin Ore"), "the result goes with the text")

	sim:input(function()
		search:SetText("copper ore")
	end)
	sim:advance(0.1)
	sim:click(assert(row("Name", "Copper Ore"), "the result to add"))
	sim:advance(0.1)
	local list = G.GatheringGuideForeverCharDB.list
	assert(#list == 1 and list[1].need == 20, "added for 20")
	-- No profession here, so the list row also names the skill it needs.
	local count = assert(row("Name", "Copper Ore (needs 1)"), "the list row").Wanted
	assert(count:IsShown() and count:GetNumber() == 20, "its count is shown in a box")

	sim:input(function()
		count:SetFocus()
		count:SetText("45")
		count:ClearFocus()
	end)
	sim:advance(0.1)
	assert(list[1].need == 45, "the typed count is kept")

	sim:input(function()
		count:SetFocus()
		count:SetText("")
		count:ClearFocus()
	end)
	sim:advance(0.1)
	assert(list[1].need == 45 and count:GetNumber() == 45, "an empty count puts the old one back")

	sim:input(function()
		search:SetText("copper ore")
	end)
	sim:advance(0.1)
	assert(not row("Name", "Copper Ore"), "an item already listed is not offered again")

	-- Back on the home page the list shows as a card to continue.
	local back = assert(
		find(panel, function(frame)
			-- Scroll bars also name a button Back.
			return frame.Back ~= nil and frame.Ring ~= nil
		end),
		"the list's heading"
	).Back
	sim:click(back)
	sim:advance(0.1)
	local card = assert(row("Title", "Farm for a list"), "the list's card")
	assert(card.Corner:GetText() == "0 of 45", "how much of the list is carried")
	sim:expectNoErrors(ADDON)
end)
