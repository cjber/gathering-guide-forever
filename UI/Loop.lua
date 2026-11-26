---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- Draws a loop on the world map: calm pins for the nodes still to visit, one atlas per GatherMate2 node kind, the next
-- one slightly clearer. Nodes whose pins would overlap at this zoom share one pin at their middle, in the first one's
-- art; the next node keeps its own pin, which also stands for the nodes under it. A visited node is not drawn: only the
-- pins that matter stay on the map.
-- The way between them is Shortest Path Forever's own journey line. GatherMate2's own world map pins are switched off
-- by the Only show Gathering pins on the map setting (Core/GatherMate.lua).
-- The frames are ForeverCore's private map canvas pins, never a Blizzard data provider.
local Loop = {}
ns.Loop = Loop

-- A calm size that still reads at map scale.
local PIN_SIZE = 12
local NEXT_SIZE = 16
local ALPHA = { ahead = 0.6, next = 0.95 }

local NodePin = {}
local pool
---@type table?
local plan
local nextIndex

local function Setup(self)
	self.Texture = self:CreateTexture(nil, "ARTWORK")
end

function NodePin:OnLoad()
	self:SetScalingLimits(1, 1, 1.2)
	-- Without a level type the pin sits under the map's explored-area art and shows only over unexplored ground.
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	Setup(self)
	self.Texture:SetPoint("CENTER")
end
function NodePin:OnAcquired(node, state)
	local size = state == "next" and NEXT_SIZE or PIN_SIZE
	self:SetSize(size, size)
	self:SetAlpha(ALPHA[state])
	ns.Fit(self.Texture, ns.KIND_ATLAS[node.kind], size, size)
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
	pool = canvas.Pool(Map(), mixinNode)
	canvas.Watch(Map(), function()
		Loop.Draw()
	end)
end

-- One pin for a group of nodes, at their middle.
---@param group table[]
---@return table node
local function Middle(group)
	local x, y = 0, 0
	for _, node in ipairs(group) do
		x, y = x + node.x, y + node.y
	end
	return { x = x / #group, y = y / #group, kind = group[1].kind }
end

-- Redraws the loop for the map now showing.
function Loop.Draw()
	Build()
	if not pool then
		return
	end
	pool:ReleaseAll()
	local shown = plan
	if not ns.DB or not ns.DB.loopOnMap or not shown then
		return
	end
	local map = Map()
	if not map or not map:IsVisible() or map:GetMapID() ~= shown.uiMapID then
		return
	end
	local order = shown.order
	-- The size a pin has on screen at this zoom, as its scaling limits set it.
	local size = PIN_SIZE * map:GetGlobalPinScale() * Lerp(1, 1.2, Saturate(map:GetCanvasZoomPercent()))
	local Group = ns.core.MapCanvas.OverlapGroups
	local nextNode = nextIndex and order[nextIndex]
	-- Nodes before the next one are visited and stay off the map; a preview has no next node and draws all of them.
	local ahead = {}
	for i = nextIndex or 1, #order do
		local node = order[i]
		if node ~= nextNode and not (nextNode and #Group(map, { nextNode, node }, size) == 1) then
			ahead[#ahead + 1] = node
		end
	end
	for _, group in ipairs(Group(map, ahead, size)) do
		pool:Acquire(Middle(group), "ahead")
	end
	if nextNode then
		pool:Acquire(nextNode, "next")
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
