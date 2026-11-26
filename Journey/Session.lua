---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- The farming session of a tour: what the player gathered since the tour began, counted from changes in the bag counts
-- of the items the tour is after, and the gold per hour those items are worth. It lives in the character's saved
-- variables, so a /reload keeps it; a new tour replaces it and stopping the tour ends it.
local Session = {}
ns.Session = Session

local SECONDS_PER_HOUR = 3600
local CALLER = "GatheringGuideForever"

---@return table?
local function Saved()
	return ns.Char and ns.Char.session
end

---@param item string
---@return number
local function Count(item)
	return C_Item.GetItemCount(item) or 0
end

-- The items a tour is after: the shopping list for a list tour, otherwise every item the zone's nodes give.
---@param plan table a Planner zone
---@return {item: string, need: number?}[]
function Session.Wanted(plan)
	local wanted = {}
	if plan.list then
		for _, entry in ipairs(ns.Char.list) do
			wanted[#wanted + 1] = { item = entry.item, need = entry.need }
		end
		return wanted
	end
	local present = {}
	for _, node in ipairs(plan.order) do
		present[node.name] = true
	end
	local items = ns.Planner.Items()
	for item, def in pairs(items) do
		if def.kind == plan.kind then
			for _, node in ipairs(def.nodes) do
				if present[node] then
					wanted[#wanted + 1] = { item = item }
					break
				end
			end
		end
	end
	table.sort(wanted, function(a, b)
		return a.item < b.item
	end)
	return wanted
end

-- Starts a session for a tour, replacing any earlier one. Counts start from what the bags hold now.
---@param plan table a Planner zone
---@param now number seconds
function Session.Begin(plan, now)
	local entries = {}
	for i, want in ipairs(Session.Wanted(plan)) do
		entries[i] = { item = want.item, need = want.need, last = Count(want.item), gathered = 0 }
	end
	ns.Char.session = { name = plan.name, startedAt = now, entries = entries }
end

function Session.End()
	if ns.Char then
		ns.Char.session = nil
	end
end

---@return boolean
function Session.Active()
	return Saved() ~= nil
end

---@return string?
function Session.Name()
	local session = Saved()
	return session and session.name
end

-- Adds what the bags gained since the last look to each item's gathered count; items spent or sold lower the baseline
-- and never the count.
function Session.Refresh()
	local session = Saved()
	if not session then
		return
	end
	for _, entry in ipairs(session.entries) do
		local count = Count(entry.item)
		if count > entry.last then
			entry.gathered = entry.gathered + count - entry.last
		end
		entry.last = count
	end
end

-- A tally row per item: gathered this session, carried now, and how many the list still needs, when it has a need.
---@return {item: string, gathered: number, have: number, need: number?, left: number?}[]
function Session.Rows()
	local rows = {}
	local session = Saved()
	for _, entry in ipairs(session and session.entries or {}) do
		rows[#rows + 1] = {
			item = entry.item,
			gathered = entry.gathered,
			have = entry.last,
			need = entry.need,
			left = entry.need and math.max(entry.need - entry.last, 0),
		}
	end
	return rows
end

-- What one of an item sells for in copper: Auctionator's price when it is loaded and has one, else the vendor price.
-- Nil when neither knows.
---@param item string
---@return number?
function Session.UnitPrice(item)
	local _, link, _, _, _, _, _, _, _, _, vendor = GetItemInfo(item)
	local auctionator = rawget(_G, "Auctionator")
	local api = type(auctionator) == "table" and auctionator.API and auctionator.API.v1
	if api and link then
		local price = api.GetAuctionPriceByItemLink(CALLER, link)
		if price and price > 0 then
			return price
		end
	end
	if vendor and vendor > 0 then
		return vendor
	end
	return nil
end

-- Copper per hour of the items gathered so far, nil while no tracked item has a price or no time has passed.
---@param now number seconds
---@return number?
function Session.PerHour(now)
	local session = Saved()
	if not session or now <= session.startedAt then
		return nil
	end
	local total, priced = 0, false
	for _, entry in ipairs(session.entries) do
		local price = Session.UnitPrice(entry.item)
		if price then
			priced = true
			total = total + price * entry.gathered
		end
	end
	if not priced then
		return nil
	end
	return total / ((now - session.startedAt) / SECONDS_PER_HOUR)
end
