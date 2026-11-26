local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()

-- Frames and the map canvas the loop draws through, recording what each pin was given.
local fitted, acquired = {}, {}
ns.Fit = function(texture, atlas, w, h)
	fitted[#fitted + 1] = { atlas = atlas, w = w, h = h }
	texture.atlas = atlas
end
ns.KIND_ATLAS = { ["Mining"] = "Mobile-Mining", ["Herb Gathering"] = "Mobile-Herbalism" }
ns.OnLoaded = function() end
ns.On = function() end
local function Pin()
	local pin = { alpha = 1 }
	function pin.SetSize() end
	function pin:SetAlpha(a)
		self.alpha = a
	end
	function pin.SetPosition() end
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
ns.core = { MapCanvas = { PinMixin = {}, Pool = MakePool, Watch = function() end } }
_G.WorldMapFrame = {
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
local pins = {}
for _, pin in ipairs(acquired) do
	if pin.Texture.atlas and pin.Texture.atlas:find("^Mobile%-") then
		pins[#pins + 1] = pin
	end
end
assert(#pins == 2, "visited nodes are not drawn, every later node gets a pin")
assert(
	pins[2].Texture.atlas == "Mobile-Mining" and pins[1].Texture.atlas == "Mobile-Herbalism",
	"ore wears the mining atlas and herbs the herbalism atlas"
)
assert(pins[1].Texture.desaturated ~= true and pins[2].Texture.desaturated ~= true, "no pin is grey")
assert(pins[2].alpha < pins[1].alpha, "the next pin is the clearest")
assert(pins[1].alpha < 1, "no pin is fully opaque")
for _, drawn in ipairs(fitted) do
	assert(drawn.w <= 16 and drawn.w == drawn.h, "pins stay calm in size and keep their aspect")
end

-- A preview with no next node draws every pin.
acquired = {}
Loop.Show({ uiMapID = 7, order = order }, nil)
assert(#acquired >= 3, "a preview draws the whole loop")

-- A zone on another map, or the setting off, draws nothing.
acquired = {}
Loop.Show({ uiMapID = 8, order = order }, 1)
assert(#acquired == 0, "a loop on another map is not drawn")
ns.DB.loopOnMap = false
Loop.Show({ uiMapID = 7, order = order }, 1)
assert(#acquired == 0, "the setting turns the loop off")

print("loop_spec ok")
