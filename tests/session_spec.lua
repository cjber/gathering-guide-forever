local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()
local handlers = {}
ns.On = function(event, fn)
	handlers[event] = fn
end
local tickers = {}
C_Timer = {
	NewTicker = function(seconds, fn)
		local ticker = { seconds = seconds, fn = fn }
		function ticker:Cancel()
			self.cancelled = true
		end
		tickers[#tickers + 1] = ticker
		return ticker
	end,
}
ns.core = {
	SafeCall = function(_, fn, ...)
		return fn(...)
	end,
}
H.Load(ns, "Locales/enUS.lua", "Journey/Session.lua")

local bags = { ["Copper Ore"] = 5, ["Tin Ore"] = 0 }
ns.ItemIDs = { ["Copper Ore"] = 2770, ["Tin Ore"] = 2771, Peacebloom = 2447 }
local names = { [2770] = "Copper Ore", [2771] = "Tin Ore", [2447] = "Peacebloom" }
local vendor = { [2770] = 100, [2771] = 40 }
C_Item = {
	-- By item ID: a name finds only items the client has cached.
	GetItemCount = function(id)
		return bags[names[id]]
	end,
	GetItemInfo = function(id)
		return "name", "link", nil, nil, nil, nil, nil, nil, nil, nil, vendor[id]
	end,
}
ns.Planner = {
	Items = function()
		return {
			["Copper Ore"] = { kind = "Mining", nodes = { "Copper Vein" } },
			["Tin Ore"] = { kind = "Mining", nodes = { "Tin Vein" } },
			Peacebloom = { kind = "Herb Gathering", nodes = { "Peacebloom" } },
		}
	end,
}
local Session = ns.Session

local function loot(item, count)
	Session.LootOpened()
	bags[item] = bags[item] + count
	Session.BagsChanged()
	Session.LootClosed()
end

-- A plain tour tracks the items its nodes give, from the bags as they are now.
local zone = { kind = "Mining", name = "Zone", order = { { name = "Copper Vein" }, { name = "Tin Vein" } } }
Session.Begin(zone, 1000)
local rows = Session.Rows()
assert(#rows == 2 and rows[1].item == "Copper Ore" and rows[2].item == "Tin Ore", "the zone's items, sorted")
assert(rows[1].gathered == 0 and rows[1].need == nil and rows[1].left == nil, "no need on a plain tour")

-- A ticker redraws the rate as time passes while the session runs, and stops when it ends; item data redraws it too.
local notified = 0
Session.Listen(function()
	notified = notified + 1
end)
assert(#tickers == 1 and not tickers[1].cancelled and tickers[1].seconds > 0, "a ticker runs with the session")
tickers[1].fn()
assert(notified == 1, "the tick redraws")
handlers.GET_ITEM_INFO_RECEIVED()
assert(notified == 2, "arriving item data redraws")
Session.Begin(zone, 1000)
assert(tickers[1].cancelled and #tickers == 2, "a new session replaces the ticker")

-- Only gains while the loot window is open count; mail, bank or crafting gains and spending move the baseline.
loot("Copper Ore", 3)
assert(Session.Rows()[1].gathered == 3, "looted gains are counted")
bags["Copper Ore"] = bags["Copper Ore"] + 4
Session.BagsChanged()
assert(Session.Rows()[1].gathered == 3, "a gain outside the loot window is not loot")
bags["Copper Ore"] = 2
Session.BagsChanged()
assert(Session.Rows()[1].gathered == 3, "a sale does not lower the tally")
loot("Copper Ore", 2)
assert(Session.Rows()[1].gathered == 5, "loot after a sale counts from the lower baseline")
Session.LootOpened()
bags["Copper Ore"] = bags["Copper Ore"] + 1
Session.LootClosed()
assert(Session.Rows()[1].gathered == 6, "a gain still unseen at the close counts")
bags["Copper Ore"] = bags["Copper Ore"] + 5
Session.BagsChanged()
assert(Session.Rows()[1].gathered == 6, "gains after the window closes are not loot")

-- A list tour reads the live list: what is needed, and no row once an item leaves it.
bags["Copper Ore"], bags["Tin Ore"] = 4, 0
ns.Char.list = { { item = "Copper Ore", need = 10 }, { item = "Tin Ore", need = 5 } }
Session.Begin({ list = true, name = "List", order = {} }, 1000)
rows = Session.Rows()
assert(#rows == 2 and rows[1].need == 10 and rows[1].left == 6 and rows[1].have == 4, "need less what is carried")
ns.Char.list[1].need = 20
assert(Session.Rows()[1].need == 20 and Session.Rows()[1].left == 16, "the need follows the list")
loot("Copper Ore", 30)
assert(Session.Rows()[1].left == 0 and Session.Rows()[1].gathered == 30, "left never goes below zero")
table.remove(ns.Char.list, 1)
rows = Session.Rows()
assert(#rows == 1 and rows[1].item == "Tin Ore", "an item taken off the list has no row")

-- Ending the session ends the loot window it watched: the old window's loot never reaches the next tour.
Session.LootOpened()
Session.End()
assert(tickers[#tickers].cancelled, "ending cancels the ticker")
local before = notified
handlers.GET_ITEM_INFO_RECEIVED()
assert(notified == before, "no session, no redraw")
bags["Copper Ore"], bags["Tin Ore"] = 4, 0
Session.Begin(zone, 1000)
bags["Copper Ore"] = 9
handlers.BAG_UPDATE_DELAYED()
handlers.LOOT_CLOSED()
assert(Session.Rows()[1].gathered == 0, "loot from before the session is not credited to it")

-- A new tour resets the tally; ending it clears the session.
Session.Begin(zone, 2000)
assert(Session.Rows()[1].gathered == 0, "a new tour resets")
Session.End()
assert(#Session.Rows() == 0 and Session.PerHour(9999) == nil, "ending clears the session")

-- Per hour, vendor source: every item must be priced, and nothing is shown until then.
bags["Copper Ore"], bags["Tin Ore"] = 1, 0
Session.Begin(zone, 0)
loot("Copper Ore", 3)
loot("Tin Ore", 5)
assert(Session.PerHour(1800) == 2 * (3 * 100 + 5 * 40), "gathered value over the elapsed hours")
assert(Session.PerHour(0) == nil, "no time has passed")
vendor[2771] = 0
assert(Session.PerHour(1800) == nil, "an unpriced item hides the rate rather than showing a part")
vendor[2771] = 40

-- Auctionator is one source for all items: used when it prices them all, else the vendor prices all of them.
local auction = { [2770] = 250, [2771] = 90 }
Auctionator = {
	API = {
		v1 = {
			GetAuctionPriceByItemID = function(caller, id)
				assert(caller == "GatheringGuideForever")
				return auction[id]
			end,
		},
	},
}
assert(Session.PerHour(1800) == 2 * (3 * 250 + 5 * 90), "Auctionator prices every item")
auction[2771] = nil
assert(
	Session.PerHour(1800) == 2 * (3 * 100 + 5 * 40),
	"one unpriced item leaves Auctionator for the vendor, never a mix"
)
Auctionator.API.v1.GetAuctionPriceByItemID = function()
	error("boom")
end
assert(Session.PerHour(1800) == 2 * (3 * 100 + 5 * 40), "an erroring Auctionator falls back to the vendor")
Auctionator = nil
assert(Session.PerHour(1800) == 2 * (3 * 100 + 5 * 40), "no Auctionator")
Session.End()

print("session_spec ok")
