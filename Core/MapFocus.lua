---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- Clears other markers off the world map while the Gathering page is up or a tour runs, under the Only show Gathering
-- pins on the map setting: the suite addons' pins are set aside through their APIs (Core/MapHold.lua) and the game's
-- own quest pins are hidden, and all come back afterwards. GatherMate2's icons follow the setting alone
-- (Core/GatherMate.lua), and a tour's route is sent without numbered stop markers (Journey/Tour.lua).
local Focus = {}
ns.MapFocus = Focus

-- The data provider pins hidden. Each pass calls only Hide and Show on them and leaves the providers and the player's
-- own map settings alone.
local TEMPLATES = { "QuestPinTemplate" }
-- The events the quest pin provider redraws on; CVAR_UPDATE covers its questPOI switch. Combat holds a pass back.
local EVENTS = {
	"QUEST_LOG_UPDATE",
	"QUEST_WATCH_LIST_CHANGED",
	"QUEST_POI_UPDATE",
	"SUPER_TRACKING_CHANGED",
	"CVAR_UPDATE",
	"PLAYER_REGEN_ENABLED",
}

-- The pins hidden here, so only those are shown again.
---@type table<Frame, true>
local hidden = setmetatable({}, { __mode = "k" })
local panelShown = false
-- Frames left to run a pass on. Two, because Adventure Guide Forever shows the quest pins it had hidden on the frame
-- after it is set aside, which can fall after the first pass.
local passes = 0
local driver = CreateFrame("Frame")
driver:Hide()

local function Active()
	if not ns.DB or not ns.DB.onlyGatheringPins then
		return false
	end
	return panelShown or (ns.Tour ~= nil and ns.Tour.Active())
end

-- Hides the pins while active, else shows the ones hidden here that the map still holds.
local function Pass()
	local map = WorldMapFrame
	if not map or InCombatLockdown() then
		return
	end
	local active = Active()
	if not active and next(hidden) == nil then
		return
	end
	for _, template in ipairs(TEMPLATES) do
		for pin in map:EnumeratePinsByTemplate(template) do
			if active then
				if pin:IsShown() then
					hidden[pin] = true
					pin:Hide()
				end
			elseif hidden[pin] then
				pin:Show()
			end
		end
	end
	if not active then
		wipe(hidden)
	end
end

local function Queue()
	if not Active() and next(hidden) == nil then
		return
	end
	passes = 2
	driver:Show()
end

driver:SetScript("OnUpdate", function(self)
	ns.core.SafeCall("map focus", Pass)
	passes = passes - 1
	if passes <= 0 then
		self:Hide()
	end
end)

-- Applies the current state. Hidden quest pins come back before the other addons resume, so Adventure Guide Forever can
-- hide its own again.
function Focus.Sync()
	local active = Active()
	if not active then
		Pass()
	end
	ns.SetGuidePinsHidden(active)
	ns.Navigation.SetPinsHidden(active)
	Queue()
end

---@param shown boolean whether the Gathering page is on screen
function Focus.SetPanelShown(shown)
	panelShown = shown
	Focus.Sync()
end

for _, event in ipairs(EVENTS) do
	ns.On(event, Queue)
end

local watching = false
local function Watch()
	if watching or not WorldMapFrame or not (ns.core and ns.core.MapCanvas) then
		return
	end
	watching = true
	-- The providers redraw their pins as the map opens or turns.
	ns.core.MapCanvas.Watch(WorldMapFrame, function(_, what)
		if what == "show" or what == "map" then
			Queue()
		end
	end)
end
ns.OnLoaded(Watch)
ns.On("ADDON_LOADED", function(name)
	if name == "Blizzard_WorldMap" then
		Watch()
	end
end)
