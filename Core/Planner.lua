---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- Plans loops and rates from the player's GatherMate2 nodes and skill. A zone's loop is built once and the skill-up
-- chances are read from it, so a new skill level changes the numbers and never the geometry.
local Planner = {}
ns.Planner = Planner

---@type table<string, {order: GGNode[], yards: number}>
local loops = {}

-- Items the list can hold, each with the nodes it comes from, by name.
---@return table<string, {kind: string, nodes: string[]}>
function Planner.Items()
	local items = {}
	for name, skill in pairs(ns.NodeSkills) do
		if skill[1] == 182 then
			items[name] = { kind = "Herb Gathering", nodes = { name } }
		end
	end
	for item, nodes in pairs(ns.OreNodes) do
		items[item] = { kind = "Mining", nodes = nodes }
	end
	return items
end

-- Adds world coordinates, dropping nodes the client cannot place.
---@param nodes GGNode[]
---@return GGNode[]
function Planner.Place(nodes)
	local placed = {}
	for _, node in ipairs(nodes) do
		local p = ns.World.Point(node.uiMapID, node.x, node.y)
		if p then
			node.wx, node.wy, node.world = p.x, p.y, p.map
			placed[#placed + 1] = node
		end
	end
	return placed
end

-- Seconds for one lap: walking the loop and gathering at every node, but never less than a node takes to respawn.
---@param yards number
---@param count number
---@return number
function Planner.Seconds(yards, count)
	return math.max(yards / ns.WALK_YARDS_PER_SECOND + count * ns.SECONDS_PER_NODE, ns.NODE_RESPAWN_SECONDS)
end

-- Gains per ten minutes for one lap, counting the trip to the zone.
---@param gain number
---@param seconds number the lap, from Planner.Seconds
---@param travel number? seconds to reach the zone, when known
---@return number
function Planner.Rate(gain, seconds, travel)
	return gain / (seconds + (travel or 0)) * 600
end

-- Seconds to reach a loop's first node, or nil when Shortest Path cannot say.
---@param uiMapID number
---@param order GGNode[]
---@return number?
local function Travel(uiMapID, order)
	return ns.Navigation.Estimate(uiMapID, order[1].x, order[1].y)
end

---@param nodes GGNode[]
---@return string
local function Signature(nodes)
	local ids = {}
	for i, n in ipairs(nodes) do
		ids[i] = ("%s:%s:%s:%s"):format(n.kind, n.uiMapID, n.nodeID, n.coord)
	end
	table.sort(ids)
	return table.concat(ids, "|")
end

-- The nodes of a zone the player can gather now. With skipNoSkillUp only those that can still raise the skill.
---@param nodes GGNode[]
---@param rank number
---@param skipNoSkillUp boolean
---@return GGNode[]
function Planner.Eligible(nodes, rank, skipNoSkillUp)
	local result = {}
	for _, node in ipairs(nodes) do
		local chance = ns.Skills.Chance(rank, node.required)
		if rank >= node.required and (chance > 0 or not skipNoSkillUp) then
			result[#result + 1] = node
		end
	end
	return result
end

-- The loop through these nodes, from the cache when the same set was solved before.
---@param nodes GGNode[]
---@param yield fun()? called between slices of work, so a pumped caller can spread the solve over frames
---@return GGNode[] order
---@return number yards
function Planner.Loop(nodes, yield)
	local key = Signature(nodes)
	local hit = loops[key]
	if not hit then
		local job = ns.Order.Begin(nodes)
		while job.Step() == "working" do
			if yield then
				yield()
			end
		end
		hit = { order = job.order, yards = job.yards }
		loops[key] = hit
	end
	return hit.order, hit.yards
end

---@param uiMapID number
---@return string
function Planner.ZoneName(uiMapID)
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapID)
	return info and info.name or tostring(uiMapID)
end

-- One zone's plan for a kind at a skill: the loop, its duration and the expected skill-ups per ten minutes.
---@param kind string
---@param uiMapID number
---@param rank number
---@param skipNoSkillUp boolean
---@param yield fun()?
---@return table?
function Planner.Zone(kind, uiMapID, rank, skipNoSkillUp, yield)
	local all = Planner.Place(ns.GatherMate.Nodes(uiMapID, kind))
	local nodes = Planner.Eligible(all, rank, skipNoSkillUp)
	if #nodes == 0 then
		return nil
	end
	local order, yards = Planner.Loop(nodes, yield)
	local seconds = Planner.Seconds(yards, #order)
	local travel = Travel(uiMapID, order)
	local expected = 0
	local lowest, highest = math.huge, 0
	for _, node in ipairs(order) do
		expected = expected + ns.Skills.Chance(rank, node.required)
		lowest = math.min(lowest, node.required)
		highest = math.max(highest, node.required)
	end
	return {
		kind = kind,
		uiMapID = uiMapID,
		name = Planner.ZoneName(uiMapID),
		nodes = all,
		order = order,
		count = #order,
		yards = yards,
		seconds = seconds,
		travel = travel,
		rate = Planner.Rate(expected, seconds, travel),
		lowest = lowest,
		highest = highest,
	}
end

-- The best zones for a kind at a skill, by skill-ups per ten minutes, best first.
---@param kind string
---@param rank number
---@param skipNoSkillUp boolean
---@param limit number
---@param yield fun()?
---@return table[]
function Planner.Best(kind, rank, skipNoSkillUp, limit, yield)
	local zones = {}
	for _, uiMapID in ipairs(ns.GatherMate.Zones(kind)) do
		local zone = Planner.Zone(kind, uiMapID, rank, skipNoSkillUp, yield)
		if yield then
			yield()
		end
		if zone and zone.rate > 0 then
			zones[#zones + 1] = zone
		end
	end
	table.sort(zones, function(a, b)
		if a.rate ~= b.rate then
			return a.rate > b.rate
		end
		return a.uiMapID < b.uiMapID
	end)
	while #zones > limit do
		zones[#zones] = nil
	end
	return zones
end

-- The zones after this one the player will move on to as the skill rises: the best zones at the skill that this zone's
-- highest requirement reaches, one for each step up.
---@param zone table
---@param rank number
---@param skipNoSkillUp boolean
---@param yield fun()?
---@return table[]
function Planner.Next(zone, rank, skipNoSkillUp, yield)
	local ahead = zone.highest + 100
	local list = {}
	for _, z in ipairs(Planner.Best(zone.kind, math.max(rank, ahead), skipNoSkillUp, 4, yield)) do
		if z.uiMapID ~= zone.uiMapID then
			list[#list + 1] = z
		end
	end
	return list
end

-- The shopping list's rows: each item with how many the player holds and still needs.
---@return {item: string, have: number, need: number}[]
function Planner.ListRows()
	local rows = {}
	for _, entry in ipairs(ns.Char.list) do
		rows[#rows + 1] = {
			item = entry.item,
			need = entry.need,
			have = C_Item.GetItemCount(entry.item) or 0,
		}
	end
	return rows
end

---@param item string
---@param need number
function Planner.AddItem(item, need)
	for _, entry in ipairs(ns.Char.list) do
		if entry.item == item then
			entry.need = need
			return
		end
	end
	table.insert(ns.Char.list, { item = item, need = need })
end

---@param item string
function Planner.RemoveItem(item)
	for i, entry in ipairs(ns.Char.list) do
		if entry.item == item then
			table.remove(ns.Char.list, i)
			return
		end
	end
end

-- Best places to farm everything still needed on the list, by wanted nodes per ten minutes, best first.
---@param limit number
---@param yield fun()?
---@return table[]
function Planner.ListZones(limit, yield)
	local items = Planner.Items()
	local wanted, kinds = {}, {}
	for _, row in ipairs(Planner.ListRows()) do
		local def = items[row.item]
		if def and row.have < row.need then
			kinds[def.kind] = true
			for _, node in ipairs(def.nodes) do
				wanted[node] = true
			end
		end
	end
	-- One loop per map across both professions, over the wanted nodes the player's skill can already gather.
	local byMap, maps = {}, {}
	for kind in pairs(kinds) do
		local rank = ns.Skills.Rank(ns.KindByName[kind].line)
		for _, uiMapID in ipairs(ns.GatherMate.Zones(kind)) do
			for _, node in ipairs(Planner.Place(ns.GatherMate.Nodes(uiMapID, kind))) do
				if wanted[node.name] and rank >= node.required then
					if not byMap[uiMapID] then
						byMap[uiMapID] = { kind = kind, nodes = {} }
						maps[#maps + 1] = uiMapID
					end
					table.insert(byMap[uiMapID].nodes, node)
				end
			end
		end
	end
	local zones = {}
	for _, uiMapID in ipairs(maps) do
		local entry = byMap[uiMapID]
		local order, yards = Planner.Loop(entry.nodes, yield)
		local seconds = Planner.Seconds(yards, #order)
		local travel = Travel(uiMapID, order)
		zones[#zones + 1] = {
			kind = entry.kind,
			list = true,
			uiMapID = uiMapID,
			name = Planner.ZoneName(uiMapID),
			order = order,
			count = #order,
			yards = yards,
			seconds = seconds,
			travel = travel,
			rate = Planner.Rate(#order, seconds, travel),
		}
	end
	table.sort(zones, function(a, b)
		if a.rate ~= b.rate then
			return a.rate > b.rate
		end
		return a.uiMapID < b.uiMapID
	end)
	while #zones > limit do
		zones[#zones] = nil
	end
	return zones
end

-- Runs work(yield) as a coroutine across frames, a few milliseconds at a time, then calls done with its results, or
-- failed when the work raises. Work already running for the same key is not started twice.
---@type table<string, boolean>
local running = {}
---@type string?
local lastError

-- The message of the last plan that failed, for the report window.
---@return string?
function Planner.LastError()
	return lastError
end

---@param key string
---@param work fun(yield: fun()): any
---@param done fun(result: any)
---@param failed fun()
function Planner.Async(key, work, done, failed)
	if running[key] then
		return
	end
	running[key] = true
	local started
	local function budget()
		started = debugprofilestop()
	end
	local co = coroutine.create(function()
		return work(function()
			if debugprofilestop() - started > 6 then
				coroutine.yield()
			end
		end)
	end)
	local function pump()
		budget()
		local ok, result = coroutine.resume(co)
		if not ok then
			running[key] = nil
			lastError = debug.traceback(co, tostring(result))
			ns.core.SafeCall("planner", error, lastError, 0)
			failed()
		elseif coroutine.status(co) == "dead" then
			running[key] = nil
			done(result)
		else
			ns.Defer(pump)
		end
	end
	pump()
end
