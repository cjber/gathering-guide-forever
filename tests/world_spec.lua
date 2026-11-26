local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Load(H.Namespace(), "Journey/Order.lua", "Core/World.lua")

-- The client answers UnitPosition and GetWorldPosFromMapPos in one frame: the first value is the vector's x.
local standing = { x = 1200, y = -340 }
UnitPosition = function()
	return standing.x, standing.y, 0, 1
end
CreateVector2D = function(x, y)
	return { x = x, y = y }
end
C_Map = {
	GetWorldPosFromMapPos = function(_, v)
		return 1, { x = v.x * 10000, y = v.y * 10000 }
	end,
}

local player = ns.World.Player()
assert(player.x == 1200 and player.y == -340 and player.map == 1, "the player is read in the node frame")

-- Nodes placed through World.Point: the one beside the player is the loop's first stop.
local order = {}
for i, spot in ipairs({ { 0.5, 0.5 }, { 0.12, -0.034 }, { -0.4, 0.2 } }) do
	local point = assert(ns.World.Point(1, spot[1], spot[2]))
	order[i] = { wx = point.x, wy = point.y, uiMapID = 1, coord = i, nodeID = i }
end
local start = ns.Order.Nearest(order, player)
assert(start == 2, "the node nearest the player starts the tour")
assert(ns.Order.Rotate(order, start)[1] == order[2])
