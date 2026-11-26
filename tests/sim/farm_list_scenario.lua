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
	local function row(text)
		return find(panel, function(frame)
			-- Templates also name textures Left.
			return frame.Left and frame.Left.GetText and frame.Left:GetText() == text
		end)
	end
	sim:click(assert(row("Open my farming list"), "the way to the list"))
	local search = assert(
		find(panel, function(frame)
			return frame.Instructions ~= nil
		end),
		"the search box"
	)

	sim:input(function()
		search:SetFocus()
		search:SetText("tin")
		-- As the client reports typing.
		search:GetScript("OnTextChanged")(search, true)
	end)
	sim:advance(0.1)
	assert(row("Tin Ore"), "a result for what is typed")
	-- The clear button empties the box from code.
	sim:input(function()
		search:SetText("")
	end)
	sim:advance(0.1)
	assert(not row("Tin Ore"), "the result goes with the text")

	sim:input(function()
		search:SetText("copper ore")
	end)
	sim:advance(0.1)
	sim:click(assert(row("Copper Ore"), "the result to add"))
	sim:advance(0.1)
	local list = G.GatheringGuideForeverCharDB.list
	assert(#list == 1 and list[1].need == 20, "added for 20")
	-- No profession here, so the list row also names the skill it needs.
	local count = assert(row("Copper Ore (needs 1)"), "the list row").Count
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

	-- Adding it again leaves the count alone.
	sim:input(function()
		search:SetText("copper ore")
	end)
	sim:advance(0.1)
	sim:click(assert(row("Copper Ore"), "the result row comes first"))
	sim:advance(0.1)
	assert(#list == 1 and list[1].need == 45, "an item already listed keeps its count")
	sim:expectNoErrors(ADDON)
end)
