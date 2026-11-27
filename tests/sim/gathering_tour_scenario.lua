-- luacheck: read globals scenario ADDON
local core = os.getenv("FOREVER_CORE") or "../forever-core"

scenario("zones, a tour in the tracker and the pages with planned zones", {
	addons = { { core, "ForeverCore" } },
}, function(sim)
	local G = sim.G
	sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
	sim.world.maps[1417] = { name = "Arathi Highlands", parent = 1415, mapType = 3 }
	sim.world.maps[1424] = { name = "Hillsbrad Foothills", parent = 1415, mapType = 3 }
	sim.world.maps[1425] = { name = "The Hinterlands", parent = 1415, mapType = 3 }
	sim:login()
	-- On the continent the zones below are placed on.
	sim.world.player.instance = 0

	-- Copper, tin, iron and dark iron, so the table shows grey, green, orange and out of reach at mining 146. A coord is
	-- x and y in ten thousandths.
	local nodes = { [1417] = {}, [1424] = {}, [1425] = {} }
	local kinds = { 201, 202, 203, 217, 217 }
	for i = 1, 20 do
		nodes[1417][(1000 + i * 300) * 10000 + 2000 + (i % 4) * 900] = kinds[(i - 1) % #kinds + 1]
	end
	for i = 1, 6 do
		-- Iron for the list, and gold so the zone still gives skill-ups once Arathi's iron no longer does.
		nodes[1424][(2000 + i * 500) * 10000 + 5000 + (i % 2) * 700] = i % 2 == 0 and 203 or 205
	end
	for i = 1, 3 do
		nodes[1425][(3000 + i * 400) * 10000 + 3000 + i * 500] = 203
	end
	-- Kingsblood and, out of reach at herbalism 141, goldthorn in the same loop. Hillsbrad's goldthorn pays off once the
	-- skills have moved on.
	local herbs = { [1417] = {}, [1424] = {} }
	for i = 1, 12 do
		herbs[1424][(1500 + i * 350) * 10000 + 3500 + (i % 3) * 500] = 414
	end
	for i = 1, 6 do
		herbs[1417][(1200 + i * 800) * 10000 + 6000 + (i % 3) * 600] = i <= 4 and 411 or 414
	end
	G.GatherMate2 = {
		GetNodesForZone = function(_, uiMapID, kind)
			return pairs((kind == "Mining" and nodes or herbs)[uiMapID] or {})
		end,
		DecodeLoc = function(_, coord)
			return math.floor(coord / 10000) / 10000, coord % 10000 / 10000
		end,
		gmdbs = { Mining = { __gm2_base_storage = nodes }, ["Herb Gathering"] = { __gm2_base_storage = herbs } },
	}
	local skills = { [186] = 146, [182] = 141 }
	G.C_SkillInfo.GetSkillLineInfoByID = function(line)
		return { skillLevel = skills[line] or 0, maxSkillLevel = skills[line] and 225 or 0 }
	end
	local levels = { [1417] = { 30, 40 }, [1424] = { 20, 30 }, [1425] = { 40, 50 } }
	G.C_Map.GetMapLevels = function(uiMapID)
		local range = levels[uiMapID]
		if range then
			return range[1], range[2]
		end
	end
	G.C_Map.GetWorldPosFromMapPos = function(_, pos)
		local x, y = pos:GetXY()
		return 0, G.CreateVector2D(x * 1000, y * 1000)
	end
	local observed
	G.ShortestPathForever = {
		API = {
			version = 2,
			NavigateRoute = function()
				return true
			end,
			ObserveStops = function(_, callback)
				observed = callback
				return function() end
			end,
			JourneyState = function()
				return {}
			end,
			Estimate = function()
				return 120
			end,
			Cancel = function()
				return true
			end,
		},
	}
	G.GatheringGuideForeverCharDB.list = { { item = "Iron Ore", need = 20 } }

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
	local function drawn(frame, text)
		for _, region in ipairs({ frame:GetRegions() }) do
			if region.GetText and (region:GetText() or ""):find(text, 1, true) then
				return true
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			if child:IsShown() and drawn(child, text) then
				return true
			end
		end
		return false
	end
	local panel
	local function row(field, text)
		return find(panel, function(frame)
			local line = frame[field]
			return type(line) == "table" and line.GetText and (line:GetText() or ""):find(text, 1, true) ~= nil
		end)
	end
	local function footer(text)
		return find(panel, function(frame)
			return frame.GetText and frame:GetText() == text
		end)
	end
	local function click(frame)
		sim:click(frame)
		sim:advance(1)
	end

	local function heading()
		return assert(
			find(panel, function(frame)
				-- Scroll bars also name a button Back.
				return frame.Back ~= nil and frame.Ring ~= nil
			end),
			"the page's heading"
		)
	end

	sim:slash("/gathering")
	sim:advance(3)
	panel = assert(G.GatheringGuideForeverPanel, "missing Gathering panel")
	assert(row("Sub", "Mining 146 · Herbalism 141"), "both skills in the heading")
	local more = assert(row("Text", "1 more: click to show"), "the zones past the top two")
	click(more)
	sim:advance(5)
	assert(row("Text", "Show fewer zones"), "every zone is shown")
	for _, name in ipairs({ "Arathi Highlands", "Hillsbrad Foothills", "The Hinterlands" }) do
		assert(row("Title", name), name)
	end
	click(assert(row("Text", "Show fewer zones")))
	assert(row("Text", "1 more: click to show"), "and folded again")

	local search = assert(
		find(panel, function(frame)
			return frame.Instructions ~= nil
		end),
		"the zone search"
	)
	assert(search.Instructions:GetText() == "Search zones", search.Instructions:GetText())
	sim:input(function()
		search:SetFocus()
		search:SetText("hinter")
		search:GetScript("OnTextChanged")(search, true)
	end)
	sim:advance(1)
	local match = assert(row("Title", "The Hinterlands"), "the matching zone")
	assert(match.Levels:GetText() == "40-50", match.Levels:GetText())
	assert(not row("Title", "Arathi Highlands"), "and no other")
	click(match)
	sim:advance(5)
	assert(row("Title", "The Hinterlands"), "the matched zone's page")
	click(heading().Back)
	sim:advance(3)

	click(assert(row("Title", "Arathi Highlands"), "a zone card on the home page"))
	assert(row("Note", "not yet"), "a node out of reach says so")
	assert(row("Name", "Iron Deposit") and row("Name", "Kingsblood"), "ore and herbs in one table")
	assert(drawn(panel, "Both skills to 225 in about"), "one time for both skills")
	sim:advance(5)
	local onward = assert(row("Title", "Hillsbrad Foothills"), "the next zone")
	assert(onward.Levels:GetText() == "20-30", "with the client's level range")

	click(assert(footer("Start tour"), "the start button"))
	local tracker = G.GatheringGuideForeverObjectiveTracker
	sim:advance(3)
	-- Eight of the twenty veins and four of the six herbs can still raise a skill; the loop skips the others.
	assert(drawn(tracker, "node 1 of 12"), "the tracker names the place in the loop")
	assert(drawn(tracker, "Mining 146 / 225") and drawn(tracker, "Herbalism 141 / 225"), "and both skills")
	assert(drawn(tracker, " yd"), "and how far the next node is")
	assert(drawn(tracker, "Next: Hillsbrad Foothills"), "and where to be at the trained maximum")
	assert(drawn(tracker, "225, in about"), "with the time to get there")

	click(heading().Back)
	local card = assert(row("Title", "Arathi Highlands tour"), "the tour to continue")
	assert(card.Corner:GetText() == "1 of 12", card.Corner:GetText())

	local function pins()
		local count = 0
		local function walk(frame)
			for _, child in ipairs({ frame:GetChildren() }) do
				local art = child:IsVisible() and child.Texture and tostring(child.Texture:GetTexture())
				if art and art:find("GatheringGuideForever", 1, true) then
					count = count + 1
				end
				walk(child)
			end
		end
		walk(G.WorldMapFrame)
		return count
	end
	click(assert(row("Title", "Hillsbrad Foothills"), "a zone the tour is not in"))
	sim:advance(5)
	assert(G.WorldMapFrame:GetMapID() == 1424 and pins() > 0, "the page previews the picked zone's loop")
	sim:input(function()
		G.ForeverCore.QuestLogTabs.ShowQuests()
	end)
	sim:advance(1)
	assert(pins() == 0, "closing the tab clears the preview")
	sim:input(function()
		observed("arrived", 1)
	end)
	sim:advance(1)
	assert(drawn(G.GatheringGuideForeverObjectiveTracker, "node 2 of 12"), "the tour moves on")
	assert(pins() == 0, "and a tour update leaves the closed page's preview off the map")
	sim:input(function()
		G.ForeverCore.QuestLogTabs.Select("gathering")
	end)
	sim:advance(1)
	assert(pins() > 0, "the preview returns with the tab")
	click(heading().Back)

	click(assert(
		find(panel, function(frame)
			return frame:GetWidth() == 16 and frame:GetHeight() == 16 and frame:GetScript("OnClick") ~= nil
		end),
		"the settings button"
	))
	assert(drawn(G.UIParent, "Show the Gathering Tour in the objective tracker"), "the settings menu")
	click(assert(row("Title", "Farm for a list"), "the list's card"))
	sim:advance(5)
	assert(row("Title", "Arathi Highlands") or row("Title", "Hillsbrad Foothills"), "a zone for the list")
	assert(drawn(panel, "Whole list in about") or drawn(panel, "Short of"), "and what it gives of the list")
	click(assert(footer("Stop tour"), "the stop button"))
	assert(not tracker:IsShown() or not drawn(tracker, "node 2 of 12"), "the section goes with the tour")
	sim:expectNoErrors(ADDON)
end)
