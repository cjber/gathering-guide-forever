local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Load(H.Namespace(), "Locales/enUS.lua", "Journey/Order.lua", "Core/MapHold.lua", "Core/Navigation.lua")
local failures = 0
ns.core = {
	SafeCall = function()
		failures = failures + 1
	end,
}
-- Next-frame work and the fake search's answers both wait here, so nothing runs inside the call that asked.
local frames = {}
ns.Defer = function(fn)
	frames[#frames + 1] = fn
end
local function Run()
	while frames[1] do
		table.remove(frames, 1)()
	end
end
debugprofilestop = os.clock
H.Load(ns, "Core/Planner.lua")
local Planner = ns.Planner
ns.DB.walks = {}

local function Node(coord, wx, wy, uiMapID)
	return {
		uiMapID = uiMapID or 1,
		kind = "Mining",
		coord = coord,
		nodeID = 201,
		x = wx / 1000,
		y = wy / 1000,
		wx = wx,
		wy = wy,
	}
end

-- A wall runs between x = 0 and x = 100 along both the top and the bottom edge: those walks are far longer than the
-- straight line, the diagonals are not. Nothing walks to a node at x = 900.
local function Walk(a, b)
	if a.x == 0.9 or b.x == 0.9 then
		return false
	end
	local dx, dy = (a.x - b.x) * 1000, (a.y - b.y) * 1000
	local wall = a.y == b.y and math.abs(dx) > 1 and 1000 or 0
	return math.sqrt(dx * dx + dy * dy) + wall
end
local nodes = { Node(1, 0, 0), Node(2, 100, 0), Node(3, 100, 10), Node(4, 0, 10) }

-- Without a Shortest Path Forever that measures walks the loop stays as planned.
ShortestPathForever = { API = { version = 2 } }
assert(Planner.Walked(nodes) == nil and not frames[1] and next(ns.DB.walks) == nil)

local asked, version, refuse, fail = {}, "nav/1", false, false
ShortestPathForever.API.NavVersion = function()
	return version
end
ShortestPathForever.API.EstimateWalks = function(owner, from, targets, callback, opts)
	assert(owner == "GatheringGuideForever" and opts.waterWalking == false and #targets >= 1)
	if refuse then
		return nil, "combat"
	end
	asked[#asked + 1] = { from = from, targets = targets }
	frames[#frames + 1] = function()
		local costs = {}
		for i, target in ipairs(targets) do
			costs[i] = not fail and Walk(from, target)
		end
		callback(costs, fail and "error" or nil)
	end
	return function() end
end

local function Legs(order)
	local length, walls = 0, 0
	for i, a in ipairs(order) do
		local b = order[i % #order + 1]
		length = length + ns.Order.Distance(a, b)
		walls = walls + (a.wy == b.wy and a.wx ~= b.wx and 1 or 0)
	end
	return length, walls
end
local _, straight = Legs(ns.Order.Solve(nodes))
assert(straight == 2, "the straight loop goes through both walls")

-- A failed search keeps nothing, and the next call tries again.
fail = true
assert(Planner.Walked(nodes) == nil)
Run()
assert(#asked == 1 and next(ns.DB.walks[1].pairs) == nil and not ns.DB.walks[1].order, "a failure is not kept")
fail = false

-- A refused search ends the job without a loop; the next call takes it up.
refuse = true
assert(Planner.Walked(nodes) == nil and not frames[1])
refuse = false

asked = {}
assert(Planner.Walked(nodes) == nil, "never ready inside the call")
local searches = #asked
assert(searches == 1, "one search at a time")
assert(Planner.Walked(nodes) == nil and #asked == searches, "a loop under way is not started again")
Run()
local walked = assert(Planner.Walked(nodes))
local _, walls = Legs(walked)
assert(#walked == 4 and walls == 0, "the walking loop goes round the walls")
assert(#asked == 3, "each pair measured once, whichever end asks")
local count = #asked
Run()
assert(Planner.Walked({ nodes[3], nodes[1], nodes[4], nodes[2] }) and #asked == count, "the same nodes ask nothing")

-- A new node costs only its own pairs, and one nothing walks to still takes a place in the loop.
asked = {}
local more = { nodes[1], nodes[2], nodes[3], nodes[4], Node(5, 900, 5) }
assert(Planner.Walked(more) == nil)
Run()
local grown = assert(Planner.Walked(more))
assert(#grown == 5, "every node is in the loop")
for _, search in ipairs(asked) do
	for _, target in ipairs(search.targets) do
		assert(search.from.x == 0.9 or target.x == 0.9, "known pairs are not measured again")
	end
end

-- New walking data drops what was measured over the old.
asked, version = {}, "nav/2"
assert(Planner.Walked(more) == nil and #asked == 1)
assert(ns.DB.walks[1].nav == "nav/2" and not ns.DB.walks[1].order)

-- Another zone takes over; the answer still on its way for the first is dropped.
local other = { Node(1, 0, 0, 2), Node(2, 100, 0, 2), Node(3, 100, 10, 2), Node(4, 0, 10, 2) }
assert(Planner.Walked(other) == nil)
Run()
assert(Planner.Walked(other) and not ns.DB.walks[1].order and next(ns.DB.walks[1].pairs) == nil)
assert(failures == 0)

print("walk_spec ok")
