local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Load(H.Namespace(), "Locales/enUS.lua", "Journey/Order.lua")
local Order = ns.Order

local function Grid(n)
	local nodes = {}
	for i = 1, n do
		nodes[i] = { uiMapID = 1, kind = "Mining", coord = i, nodeID = i, wx = (i * 37) % 101, wy = (i * 53) % 97 }
	end
	return nodes
end

-- The loop visits every node exactly once.
local nodes = Grid(40)
local order, yards = Order.Solve(nodes)
assert(#order == 40, "every node is in the loop")
local seen = {}
for _, node in ipairs(order) do
	assert(not seen[node.coord], "no node twice")
	seen[node.coord] = true
end
assert(math.abs(yards - Order.Length(order)) < 1e-6, "the reported length is the closed loop's")

-- The loop is deterministic and independent of the input order.
local reversed = {}
for i = #nodes, 1, -1 do
	reversed[#reversed + 1] = nodes[i]
end
local again = Order.Solve(reversed)
for i = 1, #order do
	assert(order[i].coord == again[i].coord, "same loop for the same nodes")
end

-- The step budget slices the work without changing the answer.
local job = Order.Begin(nodes)
local steps = 0
while job.Step() == "working" do
	steps = steps + 1
end
assert(steps > 0, "a large set takes more than one step")
for i = 1, #order do
	assert(job.order[i].coord == order[i].coord, "sliced work matches one call")
end

-- A line of nodes loops out and back.
local line = {}
for i = 1, 5 do
	line[i] = { uiMapID = 1, kind = "Mining", coord = i, nodeID = i, wx = i * 10, wy = 0 }
end
local _, lineYards = Order.Solve(line)
assert(math.abs(lineYards - 80) < 1e-6, "a line of five 10-yard steps closes at 80 yards")

-- Nearest picks the closest node, and Rotate starts the same loop there.
local nearest = Order.Nearest(order, { x = line[1].wx, y = 0 })
assert(nearest ~= nil)
local best, bestDistance
for i, node in ipairs(order) do
	local d = math.sqrt((node.wx - line[1].wx) ^ 2 + node.wy ^ 2)
	if not best or d < bestDistance then
		best, bestDistance = i, d
	end
end
assert(nearest == best, "Nearest returns the closest node")
local rotated = Order.Rotate(order, nearest)
assert(rotated[1] == order[nearest], "the tour starts at the nearest node")
assert(#rotated == #order, "rotation keeps every node")
for i = 1, #order do
	assert(rotated[i] == order[(nearest - 1 + i - 1) % #order + 1], "and follows the loop order")
end
assert(Order.Nearest({}, { x = 0, y = 0 }) == nil, "an empty loop has no nearest node")

print("order_spec ok")
