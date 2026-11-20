---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- Reads the player's GatherMate2 database. Nothing is written back and the profile's display filters are kept.
-- GatherMate2 is by Kagaro, Xinhuan, Nevcairiel and Ammo (BSD-2-Clause; see THIRD_PARTY.md).
local GM = {}
ns.GatherMate = GM

---@return table?
local function Addon()
	return rawget(_G, "GatherMate2")
end

---@return boolean
function GM.Available()
	local gm = Addon()
	return gm ~= nil and type(gm.GetNodesForZone) == "function"
end

-- Every uiMapID GatherMate2 holds nodes of this kind for.
---@param kind string
---@return number[]
function GM.Zones(kind)
	local gm = Addon()
	local zones = {}
	if gm and type(gm.gmdbs) == "table" and type(gm.gmdbs[kind]) == "table" then
		for uiMapID in pairs(gm.gmdbs[kind]) do
			zones[#zones + 1] = uiMapID
		end
		table.sort(zones)
	end
	return zones
end

-- The nodes of one kind in one zone that this addon knows a skill requirement for.
---@param uiMapID number
---@param kind string
---@return GGNode[]
function GM.Nodes(uiMapID, kind)
	local gm = Addon()
	local nodes = {}
	if not gm or type(gm.GetNodesForZone) ~= "function" then
		return nodes
	end
	for coord, nodeID in gm:GetNodesForZone(uiMapID, kind, false) do
		local x, y = gm:DecodeLoc(coord)
		local name = gm:GetNameForNode(kind, nodeID)
		local skill = name and ns.NodeSkills[name]
		if skill and x and y then
			nodes[#nodes + 1] = {
				uiMapID = uiMapID,
				kind = kind,
				coord = coord,
				nodeID = nodeID,
				x = x,
				y = y,
				name = name,
				line = skill[1],
				required = skill[2],
			}
		end
	end
	return nodes
end

-- A node's distinct names in one zone, for the item search.
---@param kind string
---@return string[]
function GM.NodeNames(kind)
	local names, seen = {}, {}
	for name, skill in pairs(ns.NodeSkills) do
		local k = ns.Kinds[1].line == skill[1] and ns.Kinds[1].kind or ns.Kinds[2].kind
		if k == kind and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end
