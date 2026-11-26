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
local profile = { showWorldMap = true, showMinimap = true }
GatherMate2 = {
	GetNodesForZone = function() end,
	db = {
		profile = profile,
		GetCurrentProfile = function()
			return profileName
		end,
	},
	GetModule = function()
		return {
			UpdateWorldMap = function()
				refreshes = refreshes + 1
			end,
		}
	end,
}
local Settings = ns.SettingsModule

Settings.SyncGatherMate()
assert(
	profile.showWorldMap == false and refreshes == 1,
	"the world map icons are hidden through GatherMate2's own switch"
)
assert(profile.showMinimap == true, "the minimap keeps the player's setting")
assert(ns.DB.gm2WorldMap.shown == true, "the player's value is saved first")

Settings.SyncGatherMate()
assert(
	refreshes == 1 and ns.DB.gm2WorldMap.shown == true,
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
ns.DB.gm2WorldMap = { shown = true, profile = "Default" }
Settings.Set("onlyGatheringPins", false)
assert(profile.showWorldMap == true and ns.DB.gm2WorldMap == nil, "the saved original is put back after a crash")

-- A player who keeps the icons off themselves stays off.
profile.showWorldMap = false
ns.DB.gm2WorldMap = nil
Settings.Set("onlyGatheringPins", true)
Settings.Set("onlyGatheringPins", false)
assert(profile.showWorldMap == false, "a value the player chose is the value restored")

-- Another profile is left alone.
profile.showWorldMap = true
Settings.Set("onlyGatheringPins", true)
profileName = "Other"
profile.showWorldMap = true
Settings.Set("onlyGatheringPins", false)
assert(profile.showWorldMap == true and ns.DB.gm2WorldMap == nil, "a profile switched to meanwhile is not rewritten")

-- Without GatherMate2 nothing happens.
GatherMate2 = nil
ns.DB.gm2WorldMap = nil
Settings.Set("onlyGatheringPins", true)
assert(ns.DB.gm2WorldMap == nil, "no GatherMate2, nothing saved")

print("gathermate_spec ok")
