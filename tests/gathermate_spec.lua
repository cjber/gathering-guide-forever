local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Namespace()
local events = {}
ns.On = function(event, fn)
	events[event] = fn
end
ns.OnLoaded = function() end
H.Load(ns, "Locales/enUS.lua", "Core/GatherMate.lua", "Core/Settings.lua")
ns.DB = { onlyGatheringPins = true }
ns.Tour = nil

-- GatherMate2's profile switches: the world map and the minimap each have their own.
local refreshes, profileName = 0, "Default"
local profile = { showWorldMap = true, showMinimap = true, show = {} }
GatherMate2 = {
	GetNodesForZone = function() end,
	db = {
		profile = profile,
		GetCurrentProfile = function()
			return profileName
		end,
	},
	SendMessage = function(_, message)
		assert(message == "GatherMate2ConfigChanged", "GatherMate2's own config message is the refresh")
		refreshes = refreshes + 1
	end,
}
local Settings = ns.SettingsModule

Settings.SyncGatherMate()
assert(
	profile.showWorldMap == false and refreshes == 1,
	"the world map icons are hidden through GatherMate2's own switch"
)
assert(profile.showMinimap == true, "the minimap keeps the player's setting")
assert(ns.DB.gm2WorldMap.Default == true, "the player's value is saved first")

Settings.SyncGatherMate()
assert(
	refreshes == 1 and ns.DB.gm2WorldMap.Default == true,
	"hiding twice neither refreshes again nor saves the hidden value"
)

Settings.Set("onlyGatheringPins", false)
assert(
	profile.showWorldMap == true and ns.DB.gm2WorldMap == nil and refreshes == 2,
	"turning it off restores the icons"
)

-- Logout puts the player's value back whatever the setting says; the next login hides again.
Settings.Set("onlyGatheringPins", true)
events.PLAYER_LOGOUT()
assert(profile.showWorldMap == true, "logout restores the value")
events.PLAYER_LOGIN()
assert(profile.showWorldMap == false, "login hides it again")

-- A crash: the switch was left off and the saved original survives in our SavedVariables.
profile.showWorldMap = false
ns.DB.gm2WorldMap = { Default = true }
Settings.Set("onlyGatheringPins", false)
assert(profile.showWorldMap == true and ns.DB.gm2WorldMap == nil, "the saved original is put back after a crash")

-- A player who keeps the icons off themselves stays off.
profile.showWorldMap = false
ns.DB.gm2WorldMap = nil
Settings.Set("onlyGatheringPins", true)
Settings.Set("onlyGatheringPins", false)
assert(profile.showWorldMap == false, "a value the player chose is the value restored")

-- Switching profiles while hidden: each profile gets its own original back, and an untouched one is left alone.
local other = { showWorldMap = true, show = {} }
GatherMate2.db.profiles = { Default = profile, Other = other }
profile.showWorldMap = true
Settings.Set("onlyGatheringPins", true)
profileName = "Other"
GatherMate2.db.profile = other
Settings.SyncGatherMate()
assert(profile.showWorldMap == false and other.showWorldMap == false, "both profiles were hidden")
Settings.Set("onlyGatheringPins", false)
assert(profile.showWorldMap == true and other.showWorldMap == true, "each profile gets its own value back")
assert(ns.DB.gm2WorldMap == nil, "nothing left saved")
profileName = "Default"
GatherMate2.db.profile = profile

-- Without GatherMate2 nothing happens.
GatherMate2 = nil
ns.DB.gm2WorldMap = nil
Settings.Set("onlyGatheringPins", true)
assert(ns.DB.gm2WorldMap == nil, "no GatherMate2, nothing saved")

-- Shaped like GatherMate2's Display: its profile upvalue is nil until OnEnable, a redraw before that raises inside
-- GatherMate2 (Display.lua:748/364), and it listens to the config message only while enabled.
do
	local listener, db, errors = nil, nil, 0
	local real = { showWorldMap = true, show = {} }
	local gm = {
		db = {
			profile = real,
			GetCurrentProfile = function()
				return "Default"
			end,
		},
		SendMessage = function(_, message)
			if message == "GatherMate2ConfigChanged" and listener then
				db = real
				if not db.showWorldMap then
					return
				end
				if db.show == nil then
					errors = errors + 1
				end
			end
		end,
	}
	GatherMate2 = gm
	ns.DB = { onlyGatheringPins = true }
	Settings.SyncGatherMate()
	assert(real.showWorldMap == false and errors == 0, "a hide before Display is enabled only writes the switch")
	listener = true -- Display:OnEnable
	db = real
	assert(db.showWorldMap == false, "Display reads the hidden switch when it enables")
	Settings.Set("onlyGatheringPins", false)
	assert(real.showWorldMap == true and errors == 0, "a restore after enable redraws through the message")
end

-- A profile in an older format has no show table: GatherMate2's redraw would raise on it, so we only write the switch.
do
	local sent = 0
	local old = { showWorldMap = true }
	GatherMate2 = {
		db = {
			profile = old,
			GetCurrentProfile = function()
				return "Default"
			end,
		},
		SendMessage = function()
			sent = sent + 1
		end,
	}
	ns.DB = { onlyGatheringPins = true }
	Settings.SyncGatherMate()
	assert(old.showWorldMap == false and sent == 0, "a profile without show is hidden without a redraw")
	Settings.Set("onlyGatheringPins", false)
	assert(old.showWorldMap == true and sent == 0, "and restored without one")
	old.show = {}
	Settings.Set("onlyGatheringPins", true)
	assert(sent == 1, "a complete profile is redrawn")
end

print("gathermate_spec ok")
