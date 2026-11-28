---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- Draws a loop on the world map: calm pins for the nodes still to visit, each herb and ore in the chosen icon style
-- (GatherMate.Icon), the next one slightly clearer. Nodes whose pins would overlap at this zoom share one pin at their
-- middle, in the first one's picture; the next node keeps its own pin, which also stands for the nodes under it. A
-- visited node is not drawn: only the pins that matter stay on the map. Hovering a pin names its nodes and, on a tour,
-- where the first of each comes in the loop.
-- The way between them is Shortest Path Forever's own journey line. GatherMate2's own world map pins are switched off
-- by the Only show Gathering pins on the map setting (Core/GatherMate.lua).
-- The frames are ForeverCore's private map canvas pins, never a Blizzard data provider.
local Loop = {}
ns.Loop = Loop
local L = ns.L

-- A calm size at which the pictures still tell apart.
local PIN_SIZE = 14
local NEXT_SIZE = 16
local ALPHA = { ahead = 0.8, next = 0.95 }

-- Hover only: presses still reach the map under the pin.
local NodePin = { takesMouse = true }
local pool
---@type table?
local preview

function NodePin:OnLoad()
	self:SetScalingLimits(1, 1, 1.2)
	-- Without a level type the pin sits under the map's explored-area art and shows only over unexplored ground.
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self.Texture = self:CreateTexture(nil, "ARTWORK")
	self.Texture:SetAllPoints()
end
function NodePin:OnAcquired(node, state, steps, total)
	self.members, self.steps, self.total = node.members, steps, total
	local size = state == "next" and NEXT_SIZE or PIN_SIZE
	self:SetSize(size, size)
	self:SetAlpha(ALPHA[state])
	local first = node.members[1]
	local texture, inset = ns.GatherMate.Icon(ns.DB.iconStyle, first.name, first.kind, first.nodeID, first.variant)
	-- A node the style has no picture for wears this addon's.
	if not texture then
		texture, inset = ns.NodeArt[first.variant or first.name], 0
	end
	self.Texture:SetTexture(texture)
	self.Texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
	self:SetPosition(node.x, node.y)
end

-- A line for each herb or ore among the pin's nodes, with how many it stands for, and under it the loop step of the
-- first one when a tour is running.
function NodePin:OnMouseEnter()
	local names, count, first = {}, {}, {}
	for _, node in ipairs(self.members) do
		local name = node.variant or node.name
		if not count[name] then
			names[#names + 1] = name
			count[name], first[name] = 0, self.steps and self.steps[node]
		end
		count[name] = count[name] + 1
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	for i, name in ipairs(names) do
		local label = count[name] > 1 and string.format(L["%s x%d"], name, count[name]) or name
		if i == 1 then
			GameTooltip:SetText(label)
		else
			GameTooltip:AddLine(label)
		end
		if first[name] then
			GameTooltip:AddLine(string.format(L["Node %d of %d"], first[name], self.total), 1, 1, 1)
		end
	end
	GameTooltip:Show()
end
function NodePin:OnMouseLeave()
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
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
	return { x = x / #group, y = y / #group, members = group }
end

-- The loop for a map: the running tour's when the tour is there, else the zone the panel is previewing.
---@param uiMapID number
---@return table? shown
---@return number? index the tour's next node
local function For(uiMapID)
	local progress = ns.Tour and ns.Tour.Progress()
	if progress and progress.uiMapID == uiMapID then
		return progress, progress.pos
	end
	if preview and preview.uiMapID == uiMapID then
		return preview
	end
end

-- Redraws the loop for the map now showing.
function Loop.Draw()
	Build()
	if not pool then
		return
	end
	pool:ReleaseAll()
	local map = Map()
	if not ns.DB or not ns.DB.loopOnMap or not map or not map:IsVisible() then
		return
	end
	local shown, nextIndex = For(map:GetMapID())
	if not shown then
		return
	end
	local order = shown.order
	-- The size a pin has on screen at this zoom, as its scaling limits set it.
	local size = PIN_SIZE * map:GetGlobalPinScale() * Lerp(1, 1.2, Saturate(map:GetCanvasZoomPercent()))
	local Group = ns.core.MapCanvas.OverlapGroups
	local nextNode = nextIndex and order[nextIndex]
	-- Nodes before the next one are visited and stay off the map; a preview has no next node and draws all of them.
	local ahead, under, steps = {}, { nextNode }, nextNode and {}
	for i = nextIndex or 1, #order do
		local node = order[i]
		if steps then
			steps[node] = i
		end
		if node ~= nextNode then
			local covered = nextNode and #Group(map, { nextNode, node }, size) == 1
			table.insert(covered and under or ahead, node)
		end
	end
	for _, group in ipairs(Group(map, ahead, size)) do
		pool:Acquire(Middle(group), "ahead", steps, #order)
	end
	if nextNode then
		local pin = { x = nextNode.x, y = nextNode.y, members = under }
		pool:Acquire(pin, "next", steps, #order)
	end
end

-- The zone the panel is previewing. Nil clears it.
---@param zone table?
function Loop.Preview(zone)
	preview = zone
	Loop.Draw()
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
