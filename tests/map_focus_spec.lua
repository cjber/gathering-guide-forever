local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()
local events = {}
ns.On = function(event, fn)
	events[event] = fn
end
ns.OnLoaded = function() end
ns.core = {
	SafeCall = function(_, fn, ...)
		fn(...)
	end,
}
local touring = false
ns.Tour = {
	Active = function()
		return touring
	end,
}
local guideHidden, journeyHidden = false, false
ns.SetGuidePinsHidden = function(value)
	guideHidden = value
end
ns.Navigation = {
	SetPinsHidden = function(value)
		journeyHidden = value
	end,
}

local driver = {
	shown = false,
	Hide = function(self)
		self.shown = false
	end,
	Show = function(self)
		self.shown = true
	end,
	SetScript = function(self, _, fn)
		self.update = fn
	end,
}
CreateFrame = function()
	return driver
end
local combat = false
InCombatLockdown = function()
	return combat
end
wipe = function(t)
	for key in pairs(t) do
		t[key] = nil
	end
end

local function Pin(shown)
	return {
		shown = shown,
		IsShown = function(self)
			return self.shown
		end,
		Hide = function(self)
			self.shown = false
		end,
		Show = function(self)
			self.shown = true
		end,
	}
end
local pins = { Pin(true), Pin(false) }
WorldMapFrame = {
	EnumeratePinsByTemplate = function(_, template)
		local i = 0
		return function()
			if template ~= "QuestPinTemplate" then
				return nil
			end
			i = i + 1
			return pins[i]
		end
	end,
}

-- Runs the queued frames.
local function Frames()
	while driver.shown do
		driver.update(driver)
	end
end

H.Load(ns, "Core/MapFocus.lua")
local Focus = ns.MapFocus
ns.DB.onlyGatheringPins = true

Focus.SetPanelShown(true)
Frames()
assert(guideHidden and journeyHidden, "the suite addons' marks are set aside while the Gathering page is up")
assert(not pins[1].shown, "the game's quest pins are hidden")

-- A pin shown again on the frame after, as Adventure Guide Forever does when set aside, is caught.
Focus.Sync()
driver.update(driver)
pins[2].shown = true
Frames()
assert(not pins[2].shown, "a pin shown a frame late is hidden too")

-- The provider adds a pin on a quest event.
pins[3] = Pin(true)
events.QUEST_LOG_UPDATE()
Frames()
assert(not pins[3].shown, "a new quest pin is hidden")

Focus.SetPanelShown(false)
Frames()
assert(not guideHidden and not journeyHidden, "leaving the page brings the suite addons' marks back")
assert(pins[1].shown and pins[2].shown and pins[3].shown, "and the quest pins")

-- Only pins hidden here come back.
pins[1].shown = false
touring = true
Focus.Sync()
Frames()
touring = false
Focus.Sync()
Frames()
assert(not pins[1].shown, "a pin hidden by something else stays hidden")
assert(pins[2].shown)

-- A tour that ends in combat restores once combat does.
touring = true
Focus.Sync()
Frames()
combat = true
touring = false
Focus.Sync()
Frames()
assert(not pins[2].shown, "no pin is touched in combat")
combat = false
events.PLAYER_REGEN_ENABLED()
Frames()
assert(pins[2].shown, "and comes back after it")

ns.DB.onlyGatheringPins = false
touring = true
Focus.SetPanelShown(true)
Frames()
assert(pins[2].shown and not guideHidden and not journeyHidden, "the setting off leaves the map alone")
print("map_focus_spec ok")
