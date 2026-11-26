local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()

-- Every node the addon knows a skill for has its own picture, and the file it names is there.
H.Load(ns, "Data/NodeSkills.lua")
H.Load(ns, "Data/NodeArt.lua")
for name in pairs(ns.NodeSkills) do
	local path = ns.NodeArt[name]
	assert(path, name .. " has no map pin art")
	local file = path:match("^Interface\\AddOns\\GatheringGuideForever\\(.+)$")
	assert(file, name .. " names art outside the addon: " .. path)
	local handle = io.open(H.root .. "/" .. file:gsub("\\", "/"), "rb")
	assert(handle, name .. " names a missing art file: " .. path)
	handle:close()
end

-- Frames and the map canvas the loop draws through, recording what each pin was given.
local acquired = {}
ns.OnLoaded = function() end
ns.On = function() end
local function Pin()
	local pin = { alpha = 1 }
	function pin:SetSize(w, h)
		self.width, self.height = w, h
	end
	function pin:SetAlpha(a)
		self.alpha = a
	end
	function pin:SetPosition(x, y)
		self.x, self.y = x, y
	end
	function pin.SetScalingLimits() end
	function pin:UseFrameLevelType(levelType)
		self.levelType = levelType
	end
	function pin.CreateTexture()
		local t = {}
		function t.SetAllPoints() end
		function t:SetTexture(path)
			self.path = path
		end
		function t:SetDesaturated(d)
			self.desaturated = d
		end
		return t
	end
	return pin
end
local function MakePool(_, mixin)
	local pool = { pins = {} }
	function pool:ReleaseAll()
		self.pins = {}
	end
	function pool:Acquire(...)
		local pin = Mixin(Pin(), mixin)
		pin:OnLoad()
		pin:OnAcquired(...)
		self.pins[#self.pins + 1] = pin
		acquired[#acquired + 1] = pin
		return pin
	end
	return pool
end
Mixin = function(target, ...)
	for _, source in ipairs({ ... }) do
		for k, v in pairs(source) do
			target[k] = v
		end
	end
	return target
end
-- ForeverCore's grouping has its own spec. This stand-in joins neighbours in the list that sit within the reach.
local reach = 0
local askedSize
local function OverlapGroups(_, points, size)
	askedSize = size
	local groups = {}
	for i, point in ipairs(points) do
		if i > 1 and math.abs(point.x - points[i - 1].x) < reach then
			table.insert(groups[#groups], point)
		else
			groups[#groups + 1] = { point }
		end
	end
	return groups
end
Saturate = function(value)
	return math.max(0, math.min(1, value))
end
Lerp = function(a, b, t)
	return a + (b - a) * t
end
local zoom = 0
ns.core = { MapCanvas = { PinMixin = {}, Pool = MakePool, Watch = function() end, OverlapGroups = OverlapGroups } }
_G.WorldMapFrame = {
	GetCanvasZoomPercent = function()
		return zoom
	end,
	GetGlobalPinScale = function()
		return 1
	end,
	IsVisible = function()
		return true
	end,
	GetMapID = function()
		return 7
	end,
}
ns.DB.loopOnMap = true
local tour
ns.Tour = {
	Progress = function()
		return tour
	end,
}
H.Load(ns, "UI/Loop.lua")
local Loop = ns.Loop

local function Art(pin, name)
	return pin.Texture.path == ns.NodeArt[name]
end

-- A pin per node still to visit, in that node's art, the next one clearer; visited nodes are not drawn.
local order = {
	{ x = 0.1, y = 0.1, name = "Copper Vein" },
	{ x = 0.3, y = 0.1, name = "Peacebloom" },
	{ x = 0.5, y = 0.1, name = "Tin Vein" },
}
tour = { uiMapID = 7, order = order, pos = 2 }
Loop.Draw()
local pins = acquired
assert(#pins == 2, "visited nodes are not drawn, every later node gets a pin")
assert(Art(pins[1], "Tin Vein") and Art(pins[2], "Peacebloom"), "each node wears its own art")
assert(pins[1].Texture.desaturated ~= true and pins[2].Texture.desaturated ~= true, "no pin is grey")
assert(pins[1].levelType == "PIN_FRAME_LEVEL_AREA_POI", "pins draw above the map's explored-area art")
assert(pins[1].alpha < pins[2].alpha, "the next pin is the clearest")
assert(pins[2].alpha < 1, "no pin is fully opaque")
for _, pin in ipairs(pins) do
	assert(pin.width <= 16 and pin.width == pin.height, "pins stay calm in size and keep their aspect")
end

-- A preview with no next node draws every pin.
acquired, tour = {}, nil
Loop.Preview({ uiMapID = 7, order = order })
assert(#acquired == 3, "a preview draws the whole loop")

-- A running tour keeps its pins on its own map, whatever zone is previewed.
tour = { uiMapID = 7, order = order, pos = 2 }
acquired = {}
Loop.Draw()
assert(#acquired == 2, "the tour's pins, not the preview of its zone")
acquired = {}
Loop.Preview({ uiMapID = 8, order = order })
assert(#acquired == 2, "previewing another zone leaves the tour's map its pins")
tour = { uiMapID = 9, order = order, pos = 2 }
Loop.Draw()
acquired = {}
Loop.Preview({ uiMapID = 7, order = order })
assert(#acquired == 3, "a preview shows on a map the tour is not on")
tour = nil

-- Overlapping nodes share a pin at their middle, in the first node's art, sized as the pins are at this zoom.
local crowd = {
	{ x = 0.1, y = 0.2, name = "Peacebloom" },
	{ x = 0.12, y = 0.4, name = "Copper Vein" },
	{ x = 0.8, y = 0.5, name = "Copper Vein" },
}
local function Draw(index)
	tour = index and { uiMapID = 7, order = crowd, pos = index }
	acquired = {}
	Loop.Preview({ uiMapID = 7, order = crowd })
	return acquired
end
reach, zoom = 0.05, 1
assert(#Draw(nil) == 2, "two overlapping nodes share one pin")
assert(math.abs(askedSize - 16.8) < 1e-9, "the grouping is asked at the pin's size at this zoom")
assert(Art(acquired[1], "Peacebloom"), "the shared pin wears the first node's art")
assert(math.abs(acquired[1].x - 0.11) < 1e-9, "the shared pin is in the middle")
assert(math.abs(acquired[1].y - 0.3) < 1e-9, "the shared pin is in the middle both ways")
-- The next node keeps its own pin and covers the one under it; a node further along the same chain keeps a pin.
crowd[3] = { x = 0.16, y = 0.5, name = "Copper Vein" }
local grouped = Draw(1)
assert(#grouped == 2, "the node under the next stop has no pin of its own, the one beyond it does")
assert(grouped[1].x == 0.16 and grouped[2].x == 0.1 and grouped[2].y == 0.2, "the next stop keeps its place")
assert(grouped[2].alpha > grouped[1].alpha, "the next stop is the clearest")
reach = 0
assert(#Draw(nil) == 3, "nodes apart keep their own pins")

-- A zone on another map, or the setting off, draws nothing.
acquired, tour = {}, nil
Loop.Preview({ uiMapID = 8, order = order })
assert(#acquired == 0, "a loop on another map is not drawn")
ns.DB.loopOnMap = false
Loop.Preview({ uiMapID = 7, order = order })
assert(#acquired == 0, "the setting turns the loop off")

print("loop_spec ok")
