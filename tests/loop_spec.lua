local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()

-- Frames and the map canvas the loop draws through, recording what each pin was given.
local fitted, acquired = {}, {}
ns.Fit = function(texture, atlas, w, h)
	fitted[#fitted + 1] = { atlas = atlas, w = w, h = h }
	texture.atlas = atlas
end
ns.KIND_ATLAS = { ["Mining"] = "ore", ["Herb Gathering"] = "herb" }
ns.OnLoaded = function() end
ns.On = function() end
local function Pin()
	local pin = { alpha = 1 }
	function pin.SetSize() end
	function pin:SetAlpha(a)
		self.alpha = a
	end
	function pin:SetPosition(x, y)
		self.x, self.y = x, y
	end
	function pin.SetScalingLimits() end
	function pin.CreateTexture()
		local t = {}
		function t.SetPoint() end
		function t.SetAllPoints() end
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
H.Load(ns, "UI/Loop.lua")
local Loop = ns.Loop

-- A pin per node still to visit, the right atlas per kind, the next one clearer; visited nodes are not drawn.
local order = {
	{ x = 0.1, y = 0.1, kind = "Mining" },
	{ x = 0.3, y = 0.1, kind = "Herb Gathering" },
	{ x = 0.5, y = 0.1, kind = "Mining" },
}
Loop.Show({ uiMapID = 7, order = order }, 2)
local pins = acquired
assert(#pins == 2, "visited nodes are not drawn, every later node gets a pin")
assert(
	pins[1].Texture.atlas == "ore" and pins[2].Texture.atlas == "herb",
	"ore wears the ore art and herbs the herb art"
)
assert(pins[1].Texture.desaturated ~= true and pins[2].Texture.desaturated ~= true, "no pin is grey")
assert(pins[1].alpha < pins[2].alpha, "the next pin is the clearest")
assert(pins[2].alpha < 1, "no pin is fully opaque")
for _, drawn in ipairs(fitted) do
	assert(drawn.w <= 16 and drawn.w == drawn.h, "pins stay calm in size and keep their aspect")
end

-- A preview with no next node draws every pin.
acquired = {}
Loop.Show({ uiMapID = 7, order = order }, nil)
assert(#acquired >= 3, "a preview draws the whole loop")

-- Overlapping nodes share a pin at their middle, in the first node's art, sized as the pins are at this zoom.
local crowd = {
	{ x = 0.1, y = 0.2, kind = "Herb Gathering" },
	{ x = 0.12, y = 0.4, kind = "Mining" },
	{ x = 0.8, y = 0.5, kind = "Mining" },
}
local function Draw(index)
	acquired = {}
	Loop.Show({ uiMapID = 7, order = crowd }, index)
	return acquired
end
reach, zoom = 0.05, 1
assert(#Draw(nil) == 2, "two overlapping nodes share one pin")
assert(math.abs(askedSize - 14.4) < 1e-9, "the grouping is asked at the pin's size at this zoom")
assert(acquired[1].Texture.atlas == "herb" and math.abs(acquired[1].x - 0.11) < 1e-9, "the shared pin is in the middle")
assert(math.abs(acquired[1].y - 0.3) < 1e-9, "the shared pin is in the middle both ways")
-- The next node keeps its own pin and covers the one under it; a node further along the same chain keeps a pin.
crowd[3] = { x = 0.16, y = 0.5, kind = "Mining" }
local grouped = Draw(1)
assert(#grouped == 2, "the node under the next stop has no pin of its own, the one beyond it does")
assert(grouped[1].x == 0.16 and grouped[2].x == 0.1 and grouped[2].y == 0.2, "the next stop keeps its place")
assert(grouped[2].alpha > grouped[1].alpha, "the next stop is the clearest")
reach = 0
assert(#Draw(nil) == 3, "nodes apart keep their own pins")

-- A zone on another map, or the setting off, draws nothing.
acquired = {}
Loop.Show({ uiMapID = 8, order = order }, 1)
assert(#acquired == 0, "a loop on another map is not drawn")
ns.DB.loopOnMap = false
Loop.Show({ uiMapID = 7, order = order }, 1)
assert(#acquired == 0, "the setting turns the loop off")

print("loop_spec ok")
