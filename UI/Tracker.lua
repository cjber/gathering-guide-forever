---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end
local L = ns.L

-- The Gathering Tour section in ForeverCore's shared tracker column: the zone, how far round the loop the player is and
-- the next node. It draws only while a tour runs.
local Tracker = {}
ns.Tracker = Tracker

---@type table?
local module

function Tracker.Refresh()
	if module then
		module:MarkDirty()
	end
end

local ModuleMixin = { headerText = L["Gathering Tour"] }

-- The lines the section shows for a tour's progress.
---@param progress table
---@return string[]
function Tracker.Lines(progress)
	local lines = {
		string.format(L["Node %d of %d"], progress.pos, progress.total),
	}
	if progress.next then
		lines[#lines + 1] = string.format(L["Next: %s"], progress.next.name)
	end
	if progress.laps > 0 then
		lines[#lines + 1] = string.format(L["Loops finished: %d"], progress.laps)
	end
	if progress.status ~= "running" then
		lines[#lines + 1] = ns.Tour.Reason(progress.status)
	end
	return lines
end

function ModuleMixin:LayoutContents()
	local progress = ns.DB.showTracker and ns.Tour.Progress()
	if not progress then
		return
	end
	local block = self:GetBlock(1)
	block:SetHeader(progress.name)
	for index, text in ipairs(Tracker.Lines(progress)) do
		block:AddObjective(index, text)
	end
	self:LayoutBlock(block)
end

local function Create()
	if not (ObjectiveTrackerFrame and ObjectiveTrackerManager) then
		return
	end
	local section =
		CreateFrame("Frame", "GatheringGuideForeverObjectiveTracker", UIParent, "ObjectiveTrackerModuleTemplate")
	Mixin(section, ModuleMixin)
	section:SetHeader(ModuleMixin.headerText)
	section.uiOrder = 20
	module = section
end

Create()
ns.OnLoaded(function()
	if not module then
		return
	end
	module.safeCall = ns.core.SafeCall
	ForeverCore.TrackerHost.Attach(module)
	Tracker.Refresh()
end)
ns.Tour.Listen(Tracker.Refresh)
