---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- Reads the player's GatherMate2 database. Its nodes are never written; the one setting touched is the profile's
-- world map switch, while the Hide GatherMate2 map icons setting is on (HideWorldMap), and the player's value is put
-- back after it. The minimap keeps its own switch (showMinimap) untouched: our pins are for the world map.
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

---@return table? profile GatherMate2's active profile
local function Profile()
	local gm = Addon()
	local profile = gm and type(gm.db) == "table" and gm.db.profile
	if type(profile) ~= "table" or type(gm.SendMessage) ~= "function" then
		return nil
	end
	return profile
end

-- GatherMate2's own way to apply a setting change (its minimap button sends it after toggling showWorldMap): modules
-- listening re-read the profile and redraw. Display listens only once enabled and takes its profile from this message,
-- so nothing is redrawn before it exists, and it reads the switch itself when it enables.
-- The redraw reads the profile's show table, which a profile in an older format lacks and which makes that redraw
-- raise inside GatherMate2: such a profile is not redrawn from here, and GatherMate2 applies the switch on its next
-- refresh.
---@param profile table
local function Refresh(profile)
	if type(profile.show) == "table" then
		Addon():SendMessage("GatherMate2ConfigChanged")
	end
end

---@return string?
local function ProfileName()
	local gm = Addon()
	return gm and gm.db and type(gm.db.GetCurrentProfile) == "function" and gm.db:GetCurrentProfile() or nil
end

-- Turns GatherMate2's world map pins off through its own profile switch. The player's value and profile are saved
-- first (ns.DB.gm2WorldMap) and kept across a crash, so a later restore still has the original.
function GM.HideWorldMap()
	local profile = Profile()
	if not profile or not ns.DB then
		return
	end
	if ns.DB.gm2WorldMap == nil then
		ns.DB.gm2WorldMap = { shown = profile.showWorldMap, profile = ProfileName() }
	end
	if profile.showWorldMap then
		profile.showWorldMap = false
		Refresh(profile)
	end
end

-- Puts back the world map switch HideWorldMap saved, unless the player has since moved to another profile.
function GM.RestoreWorldMap()
	local saved = ns.DB and ns.DB.gm2WorldMap
	if saved == nil then
		return
	end
	local profile = Profile()
	if not profile then
		return
	end
	ns.DB.gm2WorldMap = nil
	if saved.profile == ProfileName() and profile.showWorldMap ~= saved.shown then
		profile.showWorldMap = saved.shown
		Refresh(profile)
	end
end
