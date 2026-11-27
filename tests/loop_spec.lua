local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()

-- Every node the addon knows a skill for has its own picture, and the file it names is there.
H.Load(ns, "Locales/enUS.lua", "Data/NodeSkills.lua")
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
		function t:SetTexCoord(left)
			self.left = left
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
ns.DB.iconStyle = "gathering"
local tour
ns.Tour = {
	Progress = function()
		return tour
	end,
}
ns.Planner = {
	ItemIcon = function(name)
		return name == "Peacebloom" and 2447 or nil
	end,
}
H.Load(ns, "Core/GatherMate.lua", "UI/Loop.lua")
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

-- The chosen icon style dresses the pins; a node it has no picture for wears this addon's.
ns.DB.iconStyle = "blizzard"
acquired = {}
Loop.Draw()
assert(Art(acquired[1], "Tin Vein") and acquired[1].Texture.left == 0, "no item: our art, whole")
assert(acquired[2].Texture.path == 2447 and acquired[2].Texture.left > 0, "the item's icon without its border")
ns.DB.iconStyle = "gathermate"
GatherMate2 = { nodeTextures = { Mining = { [202] = "gm-tin" } } }
order[3].kind, order[3].nodeID, order[2].kind, order[2].nodeID = "Mining", 202, "Herb Gathering", 401
acquired = {}
Loop.Draw()
assert(acquired[1].Texture.path == "gm-tin", "GatherMate2's own picture")
assert(Art(acquired[2], "Peacebloom"), "and ours where it has none")
ns.DB.iconStyle, GatherMate2 = "gathering", nil

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
-- Hovering a pin names its nodes; on a tour each name gets the loop step of its first node.
local tip
GameTooltip = {
	SetOwner = function(self, owner)
		self.owner, tip = owner, {}
	end,
	SetText = function(_, text)
		tip[#tip + 1] = text
	end,
	AddLine = function(_, text)
		tip[#tip + 1] = text
	end,
	Show = function() end,
	Hide = function(self)
		self.owner, tip = nil, nil
	end,
	IsOwned = function(self, owner)
		return self.owner == owner
	end,
}
local function Tip(pin)
	assert(pin.takesMouse and not pin.clicks, "a pin takes hover and lets presses through")
	pin:OnMouseEnter()
	local text = table.concat(tip, "; ")
	pin:OnMouseLeave()
	assert(tip == nil, "leaving a pin hides its tooltip")
	return text
end
grouped = Draw(1)
assert(Tip(grouped[2]) == "Peacebloom; Node 1 of 3; Copper Vein; Node 2 of 3", "the next pin names the node under it")
assert(Tip(grouped[1]) == "Copper Vein; Node 3 of 3", Tip(grouped[1]))
assert(Tip(Draw(nil)[1]) == "Peacebloom; Copper Vein x2", "a preview counts each name and has no steps")
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
