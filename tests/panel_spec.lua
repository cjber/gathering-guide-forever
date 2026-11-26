local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()
ns.OnLoaded = function() end
ns.KIND_ATLAS = { Mining = "pickaxe", ["Herb Gathering"] = "leaf" }
ns.KindByName = { Mining = { line = 186 }, ["Herb Gathering"] = { line = 182 } }
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
H.Load(ns, "Locales/enUS.lua", "Data/NodeSkills.lua", "Data/Items.lua", "Core/Planner.lua")
ns.Skills = {
	Rank = function()
		return 38
	end,
}
ns.GatherMate = {
	Fingerprint = function()
		return "0:0"
	end,
}
ns.World = {
	PlayerMap = function()
		return 1426
	end,
}
-- Planning runs across frames in game; here the list's zones stay pending.
ns.Planner.Result = function() end
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

print("panel_spec ok")
