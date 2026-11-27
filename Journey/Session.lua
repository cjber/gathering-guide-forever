---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- The farming session of a tour: the skill gained since the tour began, what the player looted, counted from bag count
-- gains while a loot window is open (so mail, the bank, the auction house, trades and crafting never count), and the
-- gold per hour those items are worth. It lives exactly as long as its tour: a new tour replaces it, and stopping the
-- tour or logging out ends it, and a reload carries it on with its tour.
local Session = {}
ns.Session = Session

local SECONDS_PER_HOUR = 3600
-- How often the gold per hour is drawn again while the session runs, since it changes with the clock.
local RATE_REFRESH_SECONDS = 60
local CALLER = "GatheringGuideForever"

---@class GGSessionSkill
---@field kind string
---@field line number
---@field start number

---@class GGSession
---@field startedAt number
---@field list boolean
---@field entries {item: string, last: number, gathered: number}[]
---@field skills GGSessionSkill[]

---@type GGSession?
local session
local looting = false
---@type {Cancel: fun(self)}?
local ticker
---@type fun()[]
local listeners = {}

---@param fn fun()
function Session.Listen(fn)
	listeners[#listeners + 1] = fn
end

local function Notify()
	for _, fn in ipairs(listeners) do
		ns.core.SafeCall("session listener", fn)
	end
end

---@param item string
---@return number
local function Count(item)
	return C_Item.GetItemCount(ns.ItemIDs[item]) or 0
end

-- A tally that counts from what the bags hold now.
---@param item string
local function Entry(item)
	return { item = item, last = Count(item), gathered = 0 }
end

-- Counts and removals are read from the shopping list live; an item added during a list tour starts its tally here.
function Session.ListChanged()
	if session and session.list then
		local tracked = {}
		for _, entry in ipairs(session.entries) do
			tracked[entry.item] = true
		end
		for _, want in ipairs(ns.Char.list) do
			if not tracked[want.item] then
				session.entries[#session.entries + 1] = Entry(want.item)
			end
		end
	end
	Notify()
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
	for item, def in pairs(ns.Planner.Items()) do
		for _, node in ipairs(def.nodes) do
			if present[node] then
				wanted[#wanted + 1] = { item = item }
				break
			end
		end
	end
	table.sort(wanted, function(a, b)
		return a.item < b.item
	end)
	return wanted
end

-- The running session, for a reload to save.
---@return GGSession?
function Session.Current()
	return session
end

-- Runs a session, replacing any earlier one.
---@param running GGSession
function Session.Continue(running)
	session = running
	if ticker then
		ticker:Cancel()
	end
	ticker = C_Timer.NewTicker(RATE_REFRESH_SECONDS, Notify)
end

-- Starts a session for a tour, replacing any earlier one. Counts start from what the bags hold now.
---@param plan table a Planner zone
---@param now number seconds
function Session.Begin(plan, now)
	local entries = {}
	for i, want in ipairs(Session.Wanted(plan)) do
		entries[i] = Entry(want.item)
	end
	local present = {}
	for _, node in ipairs(plan.order) do
		present[node.kind] = true
	end
	local skills = {}
	for _, k in ipairs(ns.Kinds) do
		if present[k.kind] then
			skills[#skills + 1] = { kind = k.kind, line = k.line, start = (ns.Skills.Rank(k.line)) }
		end
	end
	Session.Continue({ startedAt = now, list = plan.list == true, entries = entries, skills = skills })
end

-- Ends the session and the loot window it was watching, so loot still open does not reach the next tour.
function Session.End()
	session = nil
	looting = false
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- The professions the tour's nodes belong to, with the skill each had when the session began.
---@return GGSessionSkill[]
function Session.Skills()
	return session and session.skills or {}
end

-- Skill points gained in those professions since the session began, and the rate per ten minutes once there is a gain
-- and time has passed. Nil without a session.
---@param now number seconds
---@return number? gained
---@return number? rate
function Session.SkillUps(now)
	if not session then
		return nil
	end
	local gained = 0
	for _, skill in ipairs(session.skills) do
		gained = gained + math.max((ns.Skills.Rank(skill.line)) - skill.start, 0)
	end
	local elapsed = now - session.startedAt
	return gained, gained > 0 and elapsed > 0 and gained / elapsed * 600 or nil
end

-- Moves each item's baseline to what the bags hold; a gain counts as gathered only when credit is set.
---@param credit boolean
local function Sync(credit)
	for _, entry in ipairs(session and session.entries or {}) do
		local count = Count(entry.item)
		if credit and count > entry.last then
			entry.gathered = entry.gathered + count - entry.last
		end
		entry.last = count
	end
end

-- Gains while the loot window is open are loot; at any other time the bags changed for another reason.
function Session.BagsChanged()
	Sync(looting)
	Notify()
end

function Session.LootOpened()
	Sync(false)
	looting = true
end

function Session.LootClosed()
	Sync(looting)
	looting = false
	Notify()
end

-- The listed need of an item, read from the live shopping list; nil when the item has left it.
---@param item string
---@return number?
local function ListedNeed(item)
	for _, entry in ipairs(ns.Char.list) do
		if entry.item == item then
			return entry.need
		end
	end
end

-- A tally row per item: gathered this session, carried now, and for a list tour how many the list still needs. An item
-- taken off the list during the tour has no row.
---@return {item: string, gathered: number, have: number, need: number?, left: number?}[]
function Session.Rows()
	local rows = {}
	local current = session
	if not current then
		return rows
	end
	for _, entry in ipairs(current.entries) do
		local need = current.list and ListedNeed(entry.item) or nil
		if need or not current.list then
			rows[#rows + 1] = {
				item = entry.item,
				gathered = entry.gathered,
				have = entry.last,
				need = need,
				left = need and math.max(need - entry.last, 0),
			}
		end
	end
	return rows
end

---@param item string
---@return number?
local function AuctionPrice(item)
	local auctionator = rawget(_G, "Auctionator")
	local api = type(auctionator) == "table" and auctionator.API and auctionator.API.v1
	if not api then
		return nil
	end
	local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, ns.ItemIDs[item])
	return ok and type(price) == "number" and price > 0 and price or nil
end

---@param item string
---@return number?
local function VendorPrice(item)
	local price = select(11, C_Item.GetItemInfo(ns.ItemIDs[item]))
	return type(price) == "number" and price > 0 and price or nil
end

-- Copper per hour of what was gathered, priced by one source for every item: Auctionator when it prices them all, else
-- the vendor price when it does. Nil when no source prices every item or no time has passed.
---@param now number seconds
---@return number?
function Session.PerHour(now)
	if not session or #session.entries == 0 or now <= session.startedAt then
		return nil
	end
	for _, price in ipairs({ AuctionPrice, VendorPrice }) do
		---@type number?
		local total = 0
		for _, entry in ipairs(session.entries) do
			local unit = price(entry.item)
			if not unit then
				total = nil
				break
			end
			total = total + unit * entry.gathered
		end
		if total then
			return total / ((now - session.startedAt) / SECONDS_PER_HOUR)
		end
	end
	return nil
end

ns.On("BAG_UPDATE_DELAYED", Session.BagsChanged)
ns.On("LOOT_OPENED", Session.LootOpened)
ns.On("LOOT_CLOSED", Session.LootClosed)
ns.On("SKILL_LINES_CHANGED", function()
	if session then
		Notify()
	end
end)
-- A price the client had not cached arrives as item data; the rate can be drawn then.
ns.On("GET_ITEM_INFO_RECEIVED", function()
	if session then
		Notify()
	end
end)
