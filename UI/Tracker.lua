---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end
local L = ns.L

-- The Gathering Tour section in ForeverCore's shared tracker column: the zone and how far round the loop the player is,
-- the next node and its distance, the skills the tour raises, the session's tally and gold per hour, and the zone to
-- move on to. It draws only while a tour runs.
local Tracker = {}
ns.Tracker = Tracker

-- How often the text is rewritten during a tour, so the distance to the next node follows the player.
local TICK_SECONDS = 1

---@type ForeverTrackerModule?
local module
---@type {Cancel: fun(self)}?
local ticker

---@class GGTrackerRow
---@field key string
---@field text string
---@field percent number? a progress bar under the row
---@field dash number? the stock dash style, for a row without a dash

---@class GGTrackerBlock
---@field key number
---@field title string
---@field rows GGTrackerRow[]

-- The zone to move on to, and the tour, skills and setting it was worked out for.
---@type string?, GGTrackerBlock?
local planned, onward

local function Planned()
	planned = nil
	Tracker.Refresh()
end

-- Which skill this loop raises to its trained maximum soonest, how long that takes, and the best zone at that point
-- (that skill at its maximum, the others as far as the loop has brought them) when it is another one. Worked out when
-- the tour, a skill or the setting changes, never while the section is drawn: ranking zones reads every node
-- GatherMate2 holds.
local function Forecast()
	local progress = ns.DB.showTracker and ns.Tour.Progress()
	if not progress or progress.list then
		planned, onward = nil, nil
		return
	end
	local skills = ns.Skills.Learned()
	local skip = ns.DB.skipNoSkillUp
	local now = { progress.uiMapID, tostring(skip) }
	for _, skill in ipairs(skills) do
		now[#now + 1] = ("%s:%d:%d"):format(skill.kind, skill.rank, skill.max)
	end
	local state = table.concat(now, ":")
	if state == planned then
		return
	end
	planned, onward = state, nil
	local soonest
	for _, goal in ipairs(ns.Planner.Goals(progress, skills)) do
		if not soonest or goal.seconds < soonest.seconds then
			soonest = goal
		end
	end
	if not soonest then
		return
	end
	local then_ = {}
	for _, skill in ipairs(skills) do
		then_[skill.kind] = ns.Planner.SkillAfter(progress, skill.kind, skill.rank, skill.max, soonest.seconds)
	end
	then_[soonest.skill.kind] = soonest.skill.max
	local zone = ns.Planner.BestAt(then_, skip, Planned)
	if zone and zone.uiMapID ~= progress.uiMapID then
		onward = {
			key = 2,
			title = string.format(L["Next: %s"], zone.name),
			rows = {
				{
					key = "onward",
					text = string.format(
						L["At %s %d, in about %d min"],
						soonest.skill.label,
						soonest.skill.max,
						ns.Planner.Minutes(soonest.seconds)
					),
					dash = OBJECTIVE_DASH_STYLE_HIDE,
				},
			},
		}
	end
end

-- The next node in the colour it has at the player's skill, with its distance while the client gives the position.
---@param node GGNode
---@return string
local function NodeLine(node)
	local rank = ns.Skills.Rank(ns.KindByName[node.kind].line)
	local text = ns.Markup(ns.Planner.Icon(node.name, node.kind), 13)
		.. ns.Skills.Colored(node.name, rank, node.required)
	local player = ns.World.Player()
	if player and player.map == node.world then
		local yards = ns.World.Distance(player, { x = node.wx, y = node.wy })
		text = text .. "  " .. string.format(L["%d yd"], math.floor(yards + 0.5))
	end
	return text
end

-- A skill against the next rank at which one of the loop's nodes of that kind changes colour, or the skill alone once
-- none will.
---@param kind string
---@param line number
---@param nodes GGNode[]
---@return string
local function SkillLine(kind, line, nodes)
	local rank = ns.Skills.Rank(line)
	local change
	for _, node in ipairs(nodes) do
		if node.kind == kind then
			local _, at = ns.Skills.NextBand(rank, node.required)
			if at and (not change or at < change) then
				change = at
			end
		end
	end
	local label = ns.KindByName[kind].label
	return change and string.format("%s %d / %d", label, rank, change) or string.format("%s %d", label, rank)
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
	return string.format(L["Gold per hour: %s"], C_CurrencyInfo.GetCoinTextureString(math.floor(perHour)))
end

-- The section's blocks and rows, none without a tour or with the section turned off.
---@return GGTrackerBlock[]
function Tracker.Blocks()
	local progress = ns.DB.showTracker and ns.Tour.Progress()
	if not progress then
		return {}
	end
	local lines = {}
	local function Add(key, text, percent, dash)
		lines[#lines + 1] = { key = key, text = text, percent = percent, dash = dash }
	end
	if progress.next then
		Add("next", NodeLine(progress.next), nil, OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE)
	end
	for _, skill in ipairs(ns.Session.Skills()) do
		Add("skill:" .. skill.kind, SkillLine(skill.kind, skill.line, progress.order))
	end
	local now = GetServerTime()
	local gained, rate = ns.Session.SkillUps(now)
	if gained then
		local text = gained == 1 and L["1 skill-up"] or string.format(L["%d skill-ups"], gained)
		if rate then
			text = text .. " · " .. string.format(L["%.1f per 10 min"], rate)
		end
		Add("gained", text)
	end
	-- A zone tour's items appear once looted, so the section lists only what happened; a list item always shows what it
	-- still needs.
	local looted = false
	for _, row in ipairs(ns.Session.Rows()) do
		looted = looted or row.gathered > 0
		if row.need or row.gathered > 0 then
			local percent = row.need and math.floor(math.min(row.have, row.need) / row.need * 100)
			Add("item:" .. row.item, Tracker.TallyLine(row), percent)
		end
	end
	if looted then
		Add("gold", Tracker.RateLine(ns.Session.PerHour(now)))
	end
	if progress.laps > 0 then
		Add("laps", string.format(L["Loops finished: %d"], progress.laps))
	end
	if progress.status ~= "running" then
		Add("status", ns.Tour.Reason(progress.status))
	end
	local blocks = {
		{
			key = 1,
			title = string.format(L["%s · node %d of %d"], progress.name, progress.pos, progress.total),
			rows = lines,
		},
	}
	blocks[2] = onward
	return blocks
end

-- Rewrites the drawn text in place. The column holds its layout in combat, so the text waits too.
local function Tick()
	if module and not InCombatLockdown() then
		ForeverCore.TrackerSection.UpdateText(module, Tracker.Blocks())
	end
end

function Tracker.Refresh()
	if not module then
		return
	end
	Forecast()
	local drawing = ns.DB.showTracker and ns.Tour.Active()
	if drawing and not ticker then
		ticker = C_Timer.NewTicker(TICK_SECONDS, Tick)
	elseif not drawing and ticker then
		ticker:Cancel()
		ticker = nil
	end
	module:MarkDirty()
end

local ModuleMixin = { headerText = L["Gathering Tour"] }

function ModuleMixin:LayoutContents()
	for _, entry in ipairs(Tracker.Blocks()) do
		local block = self:GetBlock(entry.key)
		block:SetHeader(entry.title)
		for _, row in ipairs(entry.rows) do
			block:AddObjective(row.key, row.text, nil, true, row.dash)
			if row.percent then
				local bar = block:AddProgressBar(row.key)
				if bar then
					bar:SetPercent(row.percent)
				end
			end
		end
		self:LayoutBlock(block)
	end
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
ns.Session.Listen(Tracker.Refresh)
