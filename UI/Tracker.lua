---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end
local L = ns.L

-- The Gathering Tour section in ForeverCore's shared tracker column: the zone, how far round the loop the player is and
-- the next node, then the session's tally of what was gathered and its gold per hour. It draws while a tour runs and
-- while a session survives a reload.
local Tracker = {}
ns.Tracker = Tracker

---@type ForeverTrackerModule?
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

-- The line for one item of the session: what was gathered and, for a list item, how many are still needed.
---@param row table a Session row
---@return string
function Tracker.TallyLine(row)
	if row.left then
		return string.format(L["%s: %d gathered, %d still needed"], row.item, row.gathered, row.left)
	end
	return string.format(L["%s: %d gathered"], row.item, row.gathered)
end

-- The gold per hour line, with the price shown as unknown until an item has one.
---@param perHour number? copper per hour
---@return string
function Tracker.RateLine(perHour)
	if not perHour then
		return L["Gold per hour: price unknown"]
	end
	return string.format(L["Gold per hour: %s"], GetCoinTextureString(math.floor(perHour)))
end

function ModuleMixin:LayoutContents()
	local progress = ns.DB.showTracker and ns.Tour.Progress()
	local session = ns.DB.showTracker and ns.Session.Active()
	if not (progress or session) then
		return
	end
	local block = self:GetBlock(1)
	block:SetHeader(progress and progress.name or ns.Session.Name())
	local key = 0
	for _, text in ipairs(progress and Tracker.Lines(progress) or {}) do
		key = key + 1
		block:AddObjective(key, text)
	end
	for _, row in ipairs(ns.Session.Rows()) do
		key = key + 1
		block:AddObjective(key, Tracker.TallyLine(row))
		if row.need then
			local bar = block:AddProgressBar(key)
			if bar then
				bar:SetPercent(math.floor(math.min(row.have, row.need) / math.max(row.need, 1) * 100))
			end
		end
	end
	if session then
		key = key + 1
		block:AddObjective(key, Tracker.RateLine(ns.Session.PerHour(GetServerTime())))
	end
	self:LayoutBlock(block)
end

local function Create()
	if not (ObjectiveTrackerFrame and ObjectiveTrackerManager) then
		return
	end
	local template = "ObjectiveTrackerModuleTemplate"
	local frame = CreateFrame("Frame", "GatheringGuideForeverObjectiveTracker", UIParent, template)
	local section = frame --[[@as ForeverTrackerModule]]
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
ns.On("BAG_UPDATE_DELAYED", function()
	ns.Session.Refresh()
	Tracker.Refresh()
end)
