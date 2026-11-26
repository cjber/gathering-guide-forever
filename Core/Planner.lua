---@type string, GGNamespace
local addonName, ns = ...
if ns.broken then
	return
end

-- Plans loops and rates from the player's GatherMate2 nodes and skills. A plan is made for `ranks`, the skill in each
-- profession the player has by GatherMate2's kind: one loop per zone through the nodes of all of them, each node's
-- chance read from its own profession's skill. A zone's loop is built once and the skill-up chances are read from it,
-- so a new skill level changes the numbers and never the geometry.
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

-- The herb or ore behind a name: itself for an item, which a herb node shares, else the ore a vein gives.
---@param name string
---@return string?
local function Item(name)
	if ns.ItemIDs[name] then
		return name
	end
	for ore, veins in pairs(ns.OreNodes) do
		for _, vein in ipairs(veins) do
			if vein == name then
				return ore
			end
		end
	end
end

-- The art for a node or item: the item's icon file, else the profession's tracking atlas.
---@param name string
---@param kind string
---@return number|string icon a file ID, or an atlas name
function Planner.Icon(name, kind)
	local item = Item(name)
	return item and C_Item.GetItemIconByID(ns.ItemIDs[item]) or ns.KIND_ATLAS[kind]
end

-- Each kind of node among a zone's nodes: how many there are and the skill it needs, the commonest first.
---@param nodes GGNode[]
---@return GGNodeType[]
function Planner.NodeTable(nodes)
	local byName, list = {}, {}
	for _, node in ipairs(nodes) do
		local entry = byName[node.name]
		if not entry then
			entry = { name = node.name, kind = node.kind, required = node.required, count = 0 }
			byName[node.name] = entry
			list[#list + 1] = entry
		end
		entry.count = entry.count + 1
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.name < b.name
	end)
	return list
end

-- How long a loop takes to give a profession its next point at a rank: a lap's length over the skill-ups a lap is
-- expected to give there. Nil at a rank the loop gives nothing.
---@param zone {order: GGNode[], seconds: number}
---@param kind string
---@return fun(rank: number): number?
local function Pace(zone, kind)
	---@type table<number, number>
	local counts = {}
	for _, node in ipairs(zone.order) do
		if node.kind == kind then
			counts[node.required] = (counts[node.required] or 0) + 1
		end
	end
	return function(rank)
		local expected = 0
		for required, count in pairs(counts) do
			expected = expected + count * ns.Skills.Chance(rank, required)
		end
		return expected > 0 and zone.seconds / expected or nil
	end
end

-- Seconds on a zone's loop to raise a profession's skill from one rank to another. Nil when there is nothing to raise
-- or the loop cannot give one of the points.
---@param zone {order: GGNode[], seconds: number}
---@param kind string
---@param from number
---@param to number
---@return number?
function Planner.TimeToSkill(zone, kind, from, to)
	if to <= from then
		return nil
	end
	local pace, total = Pace(zone, kind), 0
	for rank = from, to - 1 do
		local seconds = pace(rank)
		if not seconds then
			return nil
		end
		total = total + seconds
	end
	return total
end

-- The rank a profession's skill reaches after some seconds on a zone's loop, at most `to`.
---@param zone {order: GGNode[], seconds: number}
---@param kind string
---@param from number
---@param to number
---@param seconds number
---@return number
function Planner.SkillAfter(zone, kind, from, to, seconds)
	local pace, total, rank = Pace(zone, kind), 0, from
	while rank < to do
		local point = pace(rank)
		if not point or total + point > seconds then
			break
		end
		total, rank = total + point, rank + 1
	end
	return rank
end

-- The skills a zone's loop can raise to their trained maximum, and how long each takes, in the order given.
---@param zone {order: GGNode[], seconds: number}
---@param skills GGSkill[]
---@return {skill: GGSkill, seconds: number}[]
function Planner.Goals(zone, skills)
	local goals = {}
	for _, skill in ipairs(skills) do
		local seconds = Planner.TimeToSkill(zone, skill.kind, skill.rank, skill.max)
		if seconds then
			goals[#goals + 1] = { skill = skill, seconds = seconds }
		end
	end
	return goals
end

-- A duration as the whole minutes shown to the player, never none.
---@param seconds number
---@return number
function Planner.Minutes(seconds)
	return math.max(1, math.floor(seconds / 60 + 0.5))
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

-- The zones GatherMate2 holds nodes in for any of the professions.
---@param ranks table<string, number>
---@return number[]
function Planner.Zones(ranks)
	local zones, seen = {}, {}
	for _, k in ipairs(ns.Kinds) do
		if ranks[k.kind] then
			for _, uiMapID in ipairs(ns.GatherMate.Zones(k.kind)) do
				if not seen[uiMapID] then
					seen[uiMapID] = true
					zones[#zones + 1] = uiMapID
				end
			end
		end
	end
	table.sort(zones)
	return zones
end

-- A zone's nodes of every one of the professions.
---@param uiMapID number
---@param ranks table<string, number>
---@return GGNode[]
function Planner.Nodes(uiMapID, ranks)
	local nodes = {}
	for _, k in ipairs(ns.Kinds) do
		if ranks[k.kind] then
			for _, node in ipairs(ns.GatherMate.Nodes(uiMapID, k.kind)) do
				nodes[#nodes + 1] = node
			end
		end
	end
	return nodes
end

-- The nodes of a zone the player can gather now. With skipNoSkillUp only those that can still raise their skill.
---@param nodes GGNode[]
---@param ranks table<string, number>
---@param skipNoSkillUp boolean
---@return GGNode[]
function Planner.Eligible(nodes, ranks, skipNoSkillUp)
	local result = {}
	for _, node in ipairs(nodes) do
		local rank = ranks[node.kind]
		if rank and rank >= node.required and (ns.Skills.Chance(rank, node.required) > 0 or not skipNoSkillUp) then
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

-- One zone's loop at the player's skills, before the trip there: its duration, the expected skill-ups per lap and the
-- skill range of each profession's nodes on it. The rate is the one from where the player already stands (rate, no
-- travel); Planner.Reach adds the trip.
---@param uiMapID number
---@param ranks table<string, number>
---@param skipNoSkillUp boolean
---@param yield fun()?
---@return table?
function Planner.Plan(uiMapID, ranks, skipNoSkillUp, yield)
	local all = Planner.Place(Planner.Nodes(uiMapID, ranks))
	local nodes = Planner.Eligible(all, ranks, skipNoSkillUp)
	if #nodes == 0 then
		return nil
	end
	local order, yards = Planner.Loop(nodes, yield)
	local seconds = Planner.Seconds(yards, #order)
	local expected = 0
	---@type table<string, GGRange>
	local ranges = {}
	for _, node in ipairs(order) do
		expected = expected + ns.Skills.Chance(ranks[node.kind], node.required)
		local range = ranges[node.kind] or { lowest = node.required, highest = node.required }
		range.lowest = math.min(range.lowest, node.required)
		range.highest = math.max(range.highest, node.required)
		ranges[node.kind] = range
	end
	return {
		uiMapID = uiMapID,
		name = Planner.ZoneName(uiMapID),
		types = Planner.NodeTable(all),
		order = order,
		count = #order,
		yards = yards,
		seconds = seconds,
		expected = expected,
		rate = Planner.Rate(expected, seconds, 0),
		ranges = ranges,
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

---@param uiMapID number
---@param ranks table<string, number>
---@param skipNoSkillUp boolean
---@param yield fun()?
---@return table?
function Planner.Zone(uiMapID, ranks, skipNoSkillUp, yield)
	local zone = Planner.Plan(uiMapID, ranks, skipNoSkillUp, yield)
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

-- The best zones at these skills, by skill-ups per ten minutes including the trip there, best first, and how many
-- zones can raise a skill at all. A trip only lowers a rate, so zones are taken in order of their rate without it and
-- the search stops once the next one cannot beat the limit-th best with its trip: the answer is exact and most zones
-- never ask Shortest Path for a route. Without a limit every zone is reached.
---@param ranks table<string, number>
---@param skipNoSkillUp boolean
---@param limit number?
---@param yield fun()?
---@return table[] zones
---@return number total
function Planner.Best(ranks, skipNoSkillUp, limit, yield)
	local plans = {}
	for _, uiMapID in ipairs(Planner.Zones(ranks)) do
		local zone = Planner.Plan(uiMapID, ranks, skipNoSkillUp, yield)
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
		if limit and #zones >= limit and zone.rate < zones[limit].rate then
			break
		end
		zones[#zones + 1] = Planner.Reach(zone)
		table.sort(zones, Better)
		if yield then
			yield()
		end
	end
	while limit and #zones > limit do
		zones[#zones] = nil
	end
	return zones, #plans
end

-- The skills the zones after this one are planned at: each at the one where this loop's highest node of its profession
-- stops giving skill-ups, at most the last that can still rise, or the player's own once past that or when the loop has
-- none of its nodes.
---@param zone {ranges: table<string, GGRange>}
---@param ranks table<string, number>
---@return table<string, number>
function Planner.NextRanks(zone, ranks)
	local later = {}
	for kind, rank in pairs(ranks) do
		local range = zone.ranges[kind]
		later[kind] = range and math.max(rank, math.min(range.highest + 100, ns.Skills.MAX - 1)) or rank
	end
	return later
end

-- The zones after this one the player will move on to as the skills rise, best first at Planner.NextRanks.
---@param zone table
---@param ranks table<string, number>
---@param skipNoSkillUp boolean
---@param yield fun()?
---@return table[]
function Planner.Next(zone, ranks, skipNoSkillUp, yield)
	local list = {}
	-- One more than is shown, since this zone itself can be among the best.
	for _, z in ipairs((Planner.Best(Planner.NextRanks(zone, ranks), skipNoSkillUp, ns.TOP_ZONES + 1, yield))) do
		if z.uiMapID ~= zone.uiMapID and #list < ns.TOP_ZONES then
			list[#list + 1] = z
		end
	end
	return list
end

-- The zones with nodes for the professions whose name holds the typed text, by name.
---@param text string
---@param ranks table<string, number>
---@return {uiMapID: number, name: string}[]
function Planner.SearchZones(text, ranks)
	local found = {}
	text = text:lower()
	for _, uiMapID in ipairs(Planner.Zones(ranks)) do
		local name = Planner.ZoneName(uiMapID)
		if name:lower():find(text, 1, true) then
			found[#found + 1] = { uiMapID = uiMapID, name = name }
		end
	end
	table.sort(found, function(a, b)
		return a.name < b.name
	end)
	return found
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
		ns.Session.ListChanged()
	end
end

---@param item string
---@param need number
function Planner.SetNeed(item, need)
	local entry = Listed(item)
	if entry then
		entry.need = need
		ns.Session.ListChanged()
	end
end

---@param item string
function Planner.RemoveItem(item)
	for i, entry in ipairs(ns.Char.list) do
		if entry.item == item then
			table.remove(ns.Char.list, i)
			ns.Session.ListChanged()
			return
		end
	end
end

-- Best places to farm everything still needed on the list, by wanted nodes per ten minutes, best first. The list is
-- finite: a zone is credited with at most the items still missing that its own nodes give (one item per node), and
-- only that many nodes are walked, so the trip there is weighed against them and not spread over a lap the player will
-- not finish. A first pass meets only fresh nodes, so the respawn floor applies to a full lap alone. A zone that gives
-- everything missing carries the whole list's seconds, trip included; the others name the items they come short of.
---@param limit number
---@param yield fun()?
---@return table[]
function Planner.ListZones(limit, yield)
	local items = Planner.Items()
	local rows = Planner.ListRows()
	local wanted, kinds, missing = {}, {}, {}
	for _, row in ipairs(rows) do
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
	local ranks = {}
	for kind, rank in pairs(ns.Skills.Ranks()) do
		if kinds[kind] then
			ranks[kind] = rank
		end
	end
	local byMap, maps = {}, {}
	for _, uiMapID in ipairs(Planner.Zones(ranks)) do
		for _, node in ipairs(Planner.Eligible(Planner.Place(Planner.Nodes(uiMapID, ranks)), ranks, false)) do
			if wanted[node.name] then
				if not byMap[uiMapID] then
					byMap[uiMapID] = {}
					maps[#maps + 1] = uiMapID
				end
				table.insert(byMap[uiMapID], node)
			end
		end
	end
	local zones = {}
	for _, uiMapID in ipairs(maps) do
		local order, yards = Planner.Loop(byMap[uiMapID], yield)
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
		local lacking = {}
		for _, row in ipairs(rows) do
			if missing[row.item] and (found[row.item] or 0) < missing[row.item] then
				lacking[#lacking + 1] = row.item
			end
		end
		local passing = (walked < #order or #lacking == 0)
				and yards * walked / #order / ns.WALK_YARDS_PER_SECOND + walked * ns.SECONDS_PER_NODE
			or seconds
		zones[#zones + 1] = {
			list = true,
			uiMapID = uiMapID,
			name = Planner.ZoneName(uiMapID),
			order = order,
			count = #order,
			seconds = seconds,
			travel = travel,
			rate = Planner.Rate(walked, passing, travel),
			found = found,
			lacking = lacking,
			whole = #lacking == 0 and travel and passing + travel or nil,
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
-- Who asked for a result still being planned: the panel and the tracker can want the same one.
---@type table<string, table<fun(), boolean>>
local waiting = {}

---@param key string
local function Planned(key)
	local callbacks = waiting[key]
	waiting[key] = nil
	for done in pairs(callbacks or {}) do
		done()
	end
end

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
	waiting[key] = waiting[key] or {}
	waiting[key][done] = true
	Planner.Async(key, work, function(value)
		results[key] = value
		Planned(key)
	end, function()
		failures[key] = true
		Planned(key)
	end)
	return results[key]
end

function Planner.ClearResults()
	results, failures = {}, {}
end

-- What a plan depends on besides its zone: each profession's skill and node data, the setting and the map the player
-- stands in. The map, not the spot on it, so walking about a zone does not plan every zone again.
---@param ranks table<string, number>
---@param skip boolean
---@return string
function Planner.Key(ranks, skip)
	local parts = {}
	for _, k in ipairs(ns.Kinds) do
		local rank = ranks[k.kind]
		if rank then
			parts[#parts + 1] = ("%s=%d=%s"):format(k.kind, rank, ns.GatherMate.Fingerprint(k.kind))
		end
	end
	parts[#parts + 1] = tostring(skip)
	parts[#parts + 1] = tostring(ns.World.PlayerMap())
	return table.concat(parts, ":")
end

-- The character's best zones are saved, so a new login shows them at once. A saved ranking is current when its key
-- (addon version and Planner.Key, because the trip to a zone depends on where the player stands) matches; otherwise it
-- is shown while a new one is planned, if it was planned for the same professions.
local SUMMARY = { "uiMapID", "ranges", "travel", "rate", "types" }

---@param ranks table<string, number>
---@return string
local function Professions(ranks)
	local kinds = {}
	for _, k in ipairs(ns.Kinds) do
		if ranks[k.kind] then
			kinds[#kinds + 1] = k.kind
		end
	end
	return table.concat(kinds, ":")
end

---@param ranking GGRanking
---@param key string
---@param professions string
---@return GGRanking
local function Freeze(ranking, key, professions)
	local zones = {}
	for i, zone in ipairs(ranking.zones) do
		zones[i] = {}
		for _, field in ipairs(SUMMARY) do
			zones[i][field] = zone[field]
		end
	end
	return { key = key, professions = professions, zones = zones, total = ranking.total }
end

---@param saved GGRanking
---@return GGRanking
local function Thaw(saved)
	local zones = {}
	for i, zone in ipairs(saved.zones) do
		zones[i] = {}
		for key, value in pairs(zone) do
			zones[i][key] = value
		end
		zones[i].name = Planner.ZoneName(zone.uiMapID)
	end
	return { zones = zones, total = saved.total }
end

-- The key last asked for, the only one whose ranking is saved: an older plan can finish after a newer one.
---@type string?
local asked

-- The best zones at these skills, from memory or the saved variables when they are current, else planned over frames.
-- While that runs the last saved ranking stands in. With all set it is every zone, each with its trip, planned only
-- when asked for and kept in memory.
---@param ranks table<string, number>
---@param skip boolean
---@param refresh fun()
---@param all boolean?
---@return GGRanking?
---@return boolean? failed
function Planner.Ranking(ranks, skip, refresh, all)
	local key = ("zones:%s:%s"):format(C_AddOns.GetAddOnMetadata(addonName, "Version"), Planner.Key(ranks, skip))
	local function Rank(yield)
		local zones, total = Planner.Best(ranks, skip, not all and ns.TOP_ZONES or nil, yield)
		return { zones = zones, total = total }
	end
	if all then
		return Planner.Result("all:" .. key, Rank, refresh)
	end
	asked = key
	local professions = Professions(ranks)
	local saved = ns.Char.ranking
	if saved and saved.professions ~= professions then
		saved = nil
	end
	if results[key] == nil and saved and saved.key == key then
		results[key] = Thaw(saved)
	end
	local ranking, failed = Planner.Result(key, function(yield)
		local planned = Rank(yield)
		if key == asked then
			ns.Char.ranking = Freeze(planned, key, professions)
		end
		return planned
	end, refresh)
	if not ranking and saved then
		return Thaw(saved), failed
	end
	return ranking, failed
end

-- Planner.Next over frames, kept until the skills it is planned at, the setting, the node data or the player's map
-- changes.
---@param zone table a Planner zone
---@param ranks table<string, number>
---@param skip boolean
---@param refresh fun()
---@return table[]?
---@return boolean? failed
function Planner.NextZones(zone, ranks, skip, refresh)
	local key = ("next:%d:%s"):format(zone.uiMapID, Planner.Key(Planner.NextRanks(zone, ranks), skip))
	return Planner.Result(key, function(yield)
		return Planner.Next(zone, ranks, skip, yield)
	end, refresh)
end

-- The best zone at these skills, the trip there counted, found over frames and kept like NextZones. Nil while it is
-- being planned, when planning fails and when no zone gives a skill-up.
---@param ranks table<string, number>
---@param skip boolean
---@param refresh fun()
---@return table?
function Planner.BestAt(ranks, skip, refresh)
	local zones = Planner.Result("best:" .. Planner.Key(ranks, skip), function(yield)
		return (Planner.Best(ranks, skip, 1, yield))
	end, refresh)
	return zones and zones[1]
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
