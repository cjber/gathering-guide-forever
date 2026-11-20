---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

local World = {}
ns.World = World

local function Finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end
World.Finite = Finite

-- A map position as a world point {map = instance id, x, y} in yards, or nil when the client cannot place it.
---@param uiMapID number
---@param x number
---@param y number
---@return {map: number, x: number, y: number}?
function World.Point(uiMapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
		return nil
	end
	local instance, pos = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(x, y))
	if not pos or not Finite(pos.x) or not Finite(pos.y) then
		return nil
	end
	return { map = instance, x = pos.x, y = pos.y }
end

-- Where the player stands as a world point, or nil while the client withholds the position.
---@return {map: number, x: number, y: number}?
function World.Player()
	if not UnitPosition then
		return nil
	end
	local y, x, _, instance = UnitPosition("player")
	if y == nil or (canaccessvalue and not canaccessvalue(y)) then
		return nil
	end
	if not Finite(x) or not Finite(y) then
		return nil
	end
	return { map = instance, x = x, y = y }
end

---@param a {x: number, y: number}
---@param b {x: number, y: number}
---@return number
function World.Distance(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

-- The map the player stands on, for the zone views.
---@return number?
function World.PlayerMap()
	return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end
