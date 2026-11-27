---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end
local L = ns.L

-- The options, and the one-time read of the farming settings saved by Shortest Path Forever. The import only reads
-- ShortestPathForeverDB; nothing is written back to it.
local Settings = {}
ns.SettingsModule = Settings

Settings.options = {
	{ key = "skipNoSkillUp", label = L["Skip nodes with no skill-up"] },
	{ key = "loopOnMap", label = L["Draw the loop on the world map"] },
	{ key = "onlyGatheringPins", label = L["Only show Gathering pins on the map"] },
	{ key = "showTracker", label = L["Show the Gathering Tour in the objective tracker"] },
}

-- The pictures herb and ore nodes can wear on the loop and on GatherMate2's pins (GatherMate.Icon).
---@type {style: GGIconStyle, label: string}[]
Settings.iconStyles = {
	{ style = "gathering", label = L["Gathering"] },
	{ style = "blizzard", label = L["Game item icons"] },
	{ style = "gathermate", label = L["GatherMate2"] },
}

---@return boolean imported whether saved settings were found and copied
function Settings.ImportFromSPF()
	if ns.DB.importedFromSPF then
		return false
	end
	ns.DB.importedFromSPF = true
	local spf = rawget(_G, "ShortestPathForeverDB")
	local saved = type(spf) == "table" and spf.farming
	if type(saved) ~= "table" then
		return false
	end
	if type(saved.skipNoSkillUp) == "boolean" then
		ns.DB.skipNoSkillUp = saved.skipNoSkillUp
	end
	return true
end

-- GatherMate2's icons and its world map switch follow their settings.
function Settings.SyncGatherMate()
	if ns.DB.onlyGatheringPins then
		ns.GatherMate.HideWorldMap()
	else
		ns.GatherMate.RestoreWorldMap()
	end
	ns.GatherMate.SetIcons(ns.DB.iconStyle)
end

---@param style GGIconStyle
function Settings.SetIconStyle(style)
	ns.DB.iconStyle = style
	ns.GatherMate.SetIcons(style)
	ns.Loop.Draw()
end

---@param key string
---@param value boolean
function Settings.Set(key, value)
	ns.DB[key] = value and true or false
	if key == "onlyGatheringPins" then
		Settings.SyncGatherMate()
		ns.MapFocus.Sync()
	end
	if ns.Tour then
		ns.Tour.OnSettingChanged(key)
	end
end

ns.OnLoaded(function()
	Settings.ImportFromSPF()
end)
-- GatherMate2 sets its profile up before PLAYER_LOGIN. Its switch is put back at logout, so a disabled addon leaves
-- it as the player had it; a crash leaves the saved original for the next restore.
ns.On("PLAYER_LOGIN", Settings.SyncGatherMate)
ns.On("PLAYER_LOGOUT", ns.GatherMate.RestoreWorldMap)
