---@type string, GGNamespace
local addonName, ns = ...
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
	for item in pairs(ns.ItemIDs) do
		local nodes = ns.OreNodes[item]
		items[item] = { kind = nodes and "Mining" or "Herb Gathering", nodes = nodes or { item } }
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

-- One zone's loop for a kind at a skill, before the trip there: its duration and the expected skill-ups per lap. The
-- rate is the one from where the player already stands (rate, no travel); Planner.Reach adds the trip.
---@param kind string
---@param uiMapID number
---@param rank number
---@param skipNoSkillUp boolean
---@param yield fun()?
---@return table?
function Planner.Plan(kind, uiMapID, rank, skipNoSkillUp, yield)
	local all = Planner.Place(ns.GatherMate.Nodes(uiMapID, kind))
	local nodes = Planner.Eligible(all, rank, skipNoSkillUp)
	if #nodes == 0 then
		return nil
	end
	local order, yards = Planner.Loop(nodes, yield)
	local seconds = Planner.Seconds(yards, #order)
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
		expected = expected,
		rate = Planner.Rate(expected, seconds, 0),
		lowest = lowest,
		highest = highest,
	}
end

-- Counts the trip from where the player stands to the zone's loop into its rate.
---@param zone table
---@return table zone
function Planner.Reach(zone)
	zone.travel = Travel(zone.uiMapID, zone.order)
	zone.rate = Planner.Rate(zone.expected, zone.seconds, zone.travel)
	return zone
end

---@param kind string
---@param uiMapID number
---@param rank number
---@param skipNoSkillUp boolean
---@param yield fun()?
---@return table?
function Planner.Zone(kind, uiMapID, rank, skipNoSkillUp, yield)
	local zone = Planner.Plan(kind, uiMapID, rank, skipNoSkillUp, yield)
	return zone and Planner.Reach(zone)
end

---@param a table
---@param b table
---@return boolean
local function Better(a, b)
	if a.rate ~= b.rate then
		return a.rate > b.rate
	end
	return a.uiMapID < b.uiMapID
end

-- The best zones for a kind at a skill, by skill-ups per ten minutes including the trip there, best first. A trip only
-- lowers a rate, so zones are taken in order of their rate without it and the search stops once the next one cannot
-- beat the limit-th best with its trip: the answer is exact and most zones never ask Shortest Path for a route.
---@param kind string
---@param rank number
---@param skipNoSkillUp boolean
---@param limit number
---@param yield fun()?
---@return table[]
function Planner.Best(kind, rank, skipNoSkillUp, limit, yield)
	local plans = {}
	for _, uiMapID in ipairs(ns.GatherMate.Zones(kind)) do
		local zone = Planner.Plan(kind, uiMapID, rank, skipNoSkillUp, yield)
		if yield then
			yield()
		end
		if zone and zone.rate > 0 then
			plans[#plans + 1] = zone
		end
	end
	table.sort(plans, Better)
	local zones = {}
	for _, zone in ipairs(plans) do
		if #zones >= limit and zone.rate < zones[limit].rate then
			break
		end
		zones[#zones + 1] = Planner.Reach(zone)
		table.sort(zones, Better)
		if yield then
			yield()
		end
	end
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
			have = C_Item.GetItemCount(ns.ItemIDs[entry.item]) or 0,
		}
	end
	return rows
end

---@param item string
---@return {item: string, need: number}?
local function Listed(item)
	for _, entry in ipairs(ns.Char.list) do
		if entry.item == item then
			return entry
		end
	end
end

-- An item already on the list keeps its count.
---@param item string
---@param need number
function Planner.AddItem(item, need)
	if not Listed(item) then
		table.insert(ns.Char.list, { item = item, need = need })
	end
end

---@param item string
---@param need number
function Planner.SetNeed(item, need)
	local entry = Listed(item)
	if entry then
		entry.need = need
	end
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

-- Best places to farm everything still needed on the list, by wanted nodes per ten minutes, best first. The list is
-- finite: a zone is credited with at most the items still missing that its own nodes give (one item per node), and
-- only that many nodes are walked, so the trip there is weighed against them and not spread over a lap the player will
-- not finish. A first pass meets only fresh nodes, so the respawn floor applies to a full lap alone.
---@param limit number
---@param yield fun()?
---@return table[]
function Planner.ListZones(limit, yield)
	local items = Planner.Items()
	local wanted, kinds, missing = {}, {}, {}
	for _, row in ipairs(Planner.ListRows()) do
		local def = items[row.item]
		if def and row.have < row.need then
			missing[row.item] = row.need - row.have
			kinds[def.kind] = true
			for _, node in ipairs(def.nodes) do
				wanted[node] = row.item
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
		local found, walked = {}, 0
		for _, node in ipairs(order) do
			local item = wanted[node.name]
			found[item] = (found[item] or 0) + 1
			if found[item] <= missing[item] then
				walked = walked + 1
			end
		end
		local passing = walked < #order
				and yards * walked / #order / ns.WALK_YARDS_PER_SECOND + walked * ns.SECONDS_PER_NODE
			or seconds
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
			rate = Planner.Rate(walked, passing, travel),
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

-- Planned numbers, filled in over frames and kept until the skill or a setting changes. The second value is true once
-- the plan raised an error, so the view says so instead of planning for ever.
local results, failures = {}, {}

---@param key string
---@param work fun(yield: fun()): any
---@param done fun()
---@return any
---@return boolean? failed
function Planner.Result(key, work, done)
	if results[key] ~= nil then
		return results[key]
	end
	if failures[key] then
		return nil, true
	end
	Planner.Async(key, work, function(value)
		results[key] = value
		done()
	end, function()
		failures[key] = true
		done()
	end)
	return results[key]
end

function Planner.ClearResults()
	results, failures = {}, {}
end

-- The best zones are saved per realm and kind in the account's saved variables, so a new login shows them at
-- once. A saved ranking is current when its key (addon version, kind, skill, setting, GatherMate2 data fingerprint
-- and the map the player stands in, because the trip to a zone depends on it) matches; otherwise it is shown while
-- a new one is planned.
local SUMMARY = { "uiMapID", "lowest", "highest", "travel", "rate", "seconds", "count" }

---@param zones table[]
---@return table[]
local function Freeze(zones)
	local out = {}
	for i, zone in ipairs(zones) do
		out[i] = { kind = zone.kind }
		for _, field in ipairs(SUMMARY) do
			out[i][field] = zone[field]
		end
	end
	return out
end

---@param saved table[]
---@return table[]
local function Thaw(saved)
	local out = {}
	for i, zone in ipairs(saved) do
		out[i] = {}
		for key, value in pairs(zone) do
			out[i][key] = value
		end
		out[i].name = Planner.ZoneName(zone.uiMapID)
	end
	return out
end

---@param kind string
---@return table?
local function Saved(kind)
	local plans = ns.DB and ns.DB.plans
	local realm = plans and plans[GetRealmName()]
	return realm and realm[kind]
end

-- The best zones for a kind at a skill, from memory or the saved variables when they are current, else planned over
-- frames. While that runs the last saved ranking stands in, third value true.
---@param kind string
---@param rank number
---@param skip boolean
---@param refresh fun()
---@return table[]?
---@return boolean? failed
---@return boolean? stale
function Planner.Ranking(kind, rank, skip, refresh)
	local here = ns.World.PlayerMap()
	-- The key holds the player's map, not the spot on it: walking about a zone does not plan every zone again.
	local key = ("best:%s:%s:%d:%s:%s:%s"):format(
		C_AddOns.GetAddOnMetadata(addonName, "Version"),
		kind,
		rank,
		tostring(skip),
		ns.GatherMate.Fingerprint(kind),
		tostring(here)
	)
	local saved = Saved(kind)
	if results[key] == nil and saved and saved.key == key then
		results[key] = Thaw(saved.zones)
	end
	local zones, failed = Planner.Result(key, function(yield)
		local best = Planner.Best(kind, rank, skip, ns.TOP_ZONES, yield)
		-- The player's own zone is the commonest choice, so it is always offered.
		local inBest = false
		for _, zone in ipairs(best) do
			inBest = inBest or zone.uiMapID == here
		end
		local own = here and not inBest and Planner.Zone(kind, here, rank, skip, yield)
		if own then
			best[#best + 1] = own
		end
		ns.DB.plans = ns.DB.plans or {}
		local realm = GetRealmName()
		ns.DB.plans[realm] = ns.DB.plans[realm] or {}
		ns.DB.plans[realm][kind] = { key = key, zones = Freeze(best) }
		return best
	end, refresh)
	if not zones and saved then
		return Thaw(saved.zones), failed, true
	end
	return zones, failed, false
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
