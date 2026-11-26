---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- Other addons' map pins, set aside while Core/MapFocus.lua clears the map. The newer Adventure Guide Forever, Legacy
-- Forever and journey engine (Core/Navigation.lua) publish SuspendMapPins(owner) and ResumeMapPins(owner) on their
-- APIs; an older one has neither, and then nothing is called. Each forgets a suspension when the session ends.
local OWNER = "GatheringGuideForever"

-- A switch for one addon's pins, which calls it once per change.
---@param read fun(): table? the addon's published API, when it is loaded
---@return fun(hidden: boolean)
function ns.MapHold(read)
	local suspended = false
	return function(hidden)
		if hidden == suspended then
			return
		end
		local api = read()
		if type(api) ~= "table" or type(api.SuspendMapPins) ~= "function" or type(api.ResumeMapPins) ~= "function" then
			return
		end
		if pcall(hidden and api.SuspendMapPins or api.ResumeMapPins, OWNER) then
			suspended = hidden
		end
	end
end

local holds = {}
for _, name in ipairs({ "AdventureGuideForever", "LegacyForever" }) do
	holds[#holds + 1] = ns.MapHold(function()
		local addon = rawget(_G, name)
		return addon and addon.API
	end)
end

---@param hidden boolean
function ns.SetGuidePinsHidden(hidden)
	for _, hold in ipairs(holds) do
		hold(hidden)
	end
end
