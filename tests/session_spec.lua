local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Load(H.Namespace(), "Locales/enUS.lua", "Journey/Session.lua")

local bags = { ["Copper Ore"] = 5, ["Tin Ore"] = 0 }
C_Item = {
	GetItemCount = function(item)
		return bags[item]
	end,
}
local vendor, link = { ["Copper Ore"] = 100, ["Tin Ore"] = 0 }, "|Hitem|h"
GetItemInfo = function(item)
	return item, link, nil, nil, nil, nil, nil, nil, nil, nil, vendor[item]
end
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

-- A plain tour tracks the items its nodes give, from the bags as they are now.
local zone = { kind = "Mining", name = "Zone", order = { { name = "Copper Vein" }, { name = "Tin Vein" } } }
Session.Begin(zone, 1000)
local rows = Session.Rows()
assert(#rows == 2 and rows[1].item == "Copper Ore" and rows[2].item == "Tin Ore", "the zone's items, sorted")
assert(rows[1].gathered == 0 and rows[1].need == nil and rows[1].left == nil, "no need on a plain tour")

-- The tally counts gains; spending lowers the baseline and never the count.
bags["Copper Ore"] = 8
Session.Refresh()
assert(Session.Rows()[1].gathered == 3, "gains are counted")
bags["Copper Ore"] = 2
Session.Refresh()
assert(Session.Rows()[1].gathered == 3, "a sale does not lower the tally")
bags["Copper Ore"] = 4
Session.Refresh()
assert(Session.Rows()[1].gathered == 5, "gains after a sale count from the lower baseline")

-- A list tour tracks the list with what is still needed.
ns.Char.list = { { item = "Copper Ore", need = 10 } }
Session.Begin({ list = true, name = "List", order = {} }, 1000)
rows = Session.Rows()
assert(
	#rows == 1 and rows[1].need == 10 and rows[1].left == 6 and rows[1].have == 4,
	"the list's need less what is carried"
)
bags["Copper Ore"] = 30
Session.Refresh()
assert(Session.Rows()[1].left == 0 and Session.Rows()[1].gathered == 26, "left never goes below zero")

-- A new tour resets the tally; ending it clears the session.
Session.Begin(zone, 2000)
assert(Session.Rows()[1].gathered == 0 and ns.Char.session.startedAt == 2000, "a new tour resets")
Session.End()
assert(not Session.Active() and #Session.Rows() == 0, "ending clears the session")

-- The saved session is the whole state, so a reload that keeps it keeps the counts.
bags["Copper Ore"] = 1
Session.Begin(zone, 0)
bags["Copper Ore"] = 4
Session.Refresh()
local saved = ns.Char.session
ns.Char = { list = {}, session = saved }
assert(Session.Rows()[1].gathered == 3 and Session.Name() == "Zone", "the session survives from saved variables")

-- Prices: vendor sell price by default, Auctionator when loaded and priced, unknown when neither has one.
assert(Session.UnitPrice("Copper Ore") == 100, "vendor price fallback")
assert(Session.UnitPrice("Tin Ore") == nil, "a zero vendor price is unknown")
Auctionator = {
	API = {
		v1 = {
			GetAuctionPriceByItemLink = function(_, item)
				assert(item == link)
				return 250
			end,
		},
	},
}
assert(Session.UnitPrice("Copper Ore") == 250, "Auctionator wins when it has a price")
Auctionator.API.v1.GetAuctionPriceByItemLink = function() end
assert(Session.UnitPrice("Copper Ore") == 100, "Auctionator without a price falls back to the vendor")
Auctionator = nil

-- Per hour: copper gathered at the unit price over the elapsed hours; unknown without a price or elapsed time.
assert(Session.PerHour(1800) == 600, "3 ore at 100 copper in half an hour")
assert(Session.PerHour(0) == nil, "no time has passed")
vendor["Copper Ore"] = 0
assert(Session.PerHour(1800) == nil, "no price known")
Session.End()
assert(Session.PerHour(1800) == nil, "no session")

print("session_spec ok")
