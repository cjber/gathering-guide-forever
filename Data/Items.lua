---@type string, GGNamespace
local _, ns = ...

-- The nodes each gatherable item comes from, for the farming list. A herb is the item of the node of the same name;
-- an ore is the yield of the veins and deposits below.
ns.OreNodes = {
	["Copper Ore"] = { "Copper Vein" },
	["Tin Ore"] = { "Tin Vein" },
	["Incendicite Ore"] = { "Incendicite Mineral Vein" },
	["Lesser Bloodstone Ore"] = { "Lesser Bloodstone Deposit" },
	["Silver Ore"] = { "Silver Vein", "Ooze Covered Silver Vein" },
	["Iron Ore"] = { "Iron Deposit", "Ooze Covered Iron Deposit" },
	["Gold Ore"] = { "Gold Vein", "Ooze Covered Gold Vein" },
	["Indurium Ore"] = { "Indurium Mineral Vein" },
	["Mithril Ore"] = { "Mithril Deposit", "Ooze Covered Mithril Deposit" },
	["Truesilver Ore"] = { "Truesilver Deposit", "Ooze Covered Truesilver Deposit" },
	["Dark Iron Ore"] = { "Dark Iron Deposit" },
	["Thorium Ore"] = {
		"Small Thorium Vein",
		"Ooze Covered Thorium Vein",
		"Rich Thorium Vein",
		"Ooze Covered Rich Thorium Vein",
		"Hakkari Thorium Vein",
	},
	["Obsidian Chunk"] = { "Small Obsidian Chunk", "Large Obsidian Chunk" },
}
