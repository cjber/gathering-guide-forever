---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- Draws a loop on the world map as breadcrumb dots along each leg and a marker on the next node. The frames are
-- ForeverCore's private map canvas pins, never a Blizzard data provider.
local Loop = {}
ns.Loop = Loop

local DOT_SIZE = 8
local NODE_SIZE = 22
-- Breadcrumbs sit this far apart, as a fraction of the map.
local SPACING = 0.012
local MAX_DOTS = 400

local NodePin, DotPin = {}, {}
local pool, dots
---@type table?
local plan
local nextIndex

local function Setup(self)
	self.Texture = self:CreateTexture(nil, "ARTWORK")
end

function DotPin:OnLoad()
	self:SetSize(DOT_SIZE, DOT_SIZE)
	self:SetScalingLimits(1, 0.8, 1.2)
	Setup(self)
	self.Texture:SetAllPoints()
	ns.Fit(self.Texture, "Waypoint-MapPin-Untracked", DOT_SIZE, DOT_SIZE)
end
function DotPin:OnAcquired(x, y)
	self:SetPosition(x, y)
end

function NodePin:OnLoad()
	self:SetSize(NODE_SIZE, NODE_SIZE)
	self:SetScalingLimits(1, 1, 1.2)
	self.takesMouse = true
	Setup(self)
	self.Texture:SetPoint("CENTER")
	ns.Fit(self.Texture, "Waypoint-MapPin-Tracked", NODE_SIZE, NODE_SIZE)
end
function NodePin:OnAcquired(node)
	self.node = node
	self:SetPosition(node.x, node.y)
end

---@return table?
local function Map()
	return WorldMapFrame
end

local function Build()
	if pool or not (ns.core and ns.core.MapCanvas and Map()) then
		return
	end
	local canvas = ns.core.MapCanvas
	local mixinNode = Mixin({}, canvas.PinMixin, NodePin)
	local mixinDot = Mixin({}, canvas.PinMixin, DotPin)
	pool = canvas.Pool(Map(), mixinNode)
	dots = canvas.Pool(Map(), mixinDot)
	canvas.Watch(Map(), function()
		Loop.Draw()
	end)
end

-- The dots between two nodes of a loop on one map, nearest first, spaced by SPACING.
---@param a GGNode
---@param b GGNode
---@return number[][]
function Loop.Crumbs(a, b)
	local out = {}
	local dx, dy = b.x - a.x, b.y - a.y
	local length = math.sqrt(dx * dx + dy * dy)
	local count = math.floor(length / SPACING)
	for i = 1, count - 1 do
		local t = i / count
		out[#out + 1] = { a.x + dx * t, a.y + dy * t }
	end
	return out
end

-- Redraws the loop for the map now showing.
function Loop.Draw()
	Build()
	if not pool or not dots then
		return
	end
	pool:ReleaseAll()
	dots:ReleaseAll()
	local shown = plan
	if not ns.DB or not ns.DB.loopOnMap or not shown then
		return
	end
	local map = Map()
	if not map or not map:IsVisible() or map:GetMapID() ~= shown.uiMapID then
		return
	end
	local order, total = shown.order, 0
	for i, node in ipairs(order) do
		local following = order[i % #order + 1]
		if #order > 1 then
			for _, c in ipairs(Loop.Crumbs(node, following)) do
				total = total + 1
				if total > MAX_DOTS then
					break
				end
				dots:Acquire(c[1], c[2])
			end
		end
	end
	local node = order[nextIndex or 1]
	if node then
		pool:Acquire(node)
	end
end

-- Shows a plan's loop on its map: a running tour's, or the zone the panel is previewing. Nil clears it.
---@param shown table?
---@param index number? the next node
function Loop.Show(shown, index)
	plan, nextIndex = shown, index
	Loop.Draw()
end

-- Follows the running tour.
function Loop.Refresh()
	local progress = ns.Tour and ns.Tour.Progress()
	if progress then
		Loop.Show({ uiMapID = progress.uiMapID, order = progress.order }, progress.pos)
	else
		Loop.Show(nil)
	end
end

ns.OnLoaded(function()
	if C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") or WorldMapFrame then
		Build()
	end
end)
ns.On("ADDON_LOADED", function(name)
	if name == "Blizzard_WorldMap" then
		Build()
	end
end)
