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

-- Calls fn(uiMapID, nodes) for every zone GatherMate2 holds nodes of this kind for, nodes being its coord -> nodeID
-- table. GatherMate2 has no iterator over zones: gmdbs[kind] is a proxy whose only real keys are metadata, and a zone's
-- nodes come through its __index. The zones are keys of the base storage and of each storage-map table, the two places
-- GatherMate2's own UpgradeNodeIDs walks, so they are read from there.
---@param kind string
---@param fn fun(uiMapID: number, nodes: table<number, number>)
local function Walk(kind, fn)
	local gm = Addon()
	local proxy = gm and type(gm.gmdbs) == "table" and gm.gmdbs[kind]
	if type(proxy) ~= "table" then
		return
	end
	local stores, seen = { proxy.__gm2_base_storage }, {}
	for _, store in pairs(proxy.__gm2_storage_map or {}) do
		stores[#stores + 1] = store
	end
	for _, store in ipairs(stores) do
		for uiMapID, nodes in pairs(store) do
			if not seen[uiMapID] and type(nodes) == "table" and next(nodes) ~= nil then
				seen[uiMapID] = true
				fn(uiMapID, nodes)
			end
		end
	end
end

---@param kind string
---@return number[]
function GM.Zones(kind)
	local zones = {}
	Walk(kind, function(uiMapID)
		zones[#zones + 1] = uiMapID
	end)
	table.sort(zones)
	return zones
end

-- A number that changes when the player's nodes of this kind change, so a saved plan knows its data moved. The sum
-- does not depend on the order the tables are walked in.
---@param kind string
---@return string
function GM.Fingerprint(kind)
	local count, sum = 0, 0
	Walk(kind, function(uiMapID, nodes)
		sum = (sum + uiMapID * 7919) % 1000000007
		for coord, nodeID in pairs(nodes) do
			count = count + 1
			sum = (sum + coord % 1000003 * 31 + nodeID) % 1000000007
		end
	end)
	return count .. ":" .. sum
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
