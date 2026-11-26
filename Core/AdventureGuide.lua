---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- Adventure Guide Forever's map pins, set aside while a tour shows only this addon's. The newer Adventure Guide
-- Forever publishes SuspendMapPins(owner) and ResumeMapPins(owner) on its API; an older one has neither, and then
-- nothing is called. Adventure Guide Forever forgets a suspension when the session ends.
local AG = {}
ns.AdventureGuide = AG

local OWNER = "GatheringGuideForever"
local suspended = false

---@return table?
local function API()
	local guide = rawget(_G, "AdventureGuideForever")
	local api = guide and guide.API
	if type(api) == "table" and type(api.SuspendMapPins) == "function" and type(api.ResumeMapPins) == "function" then
		return api
	end
	return nil
end

-- Sets its pins aside or brings them back, once per change.
---@param hidden boolean
function AG.SetHidden(hidden)
	if hidden == suspended then
		return
	end
	local api = API()
	if not api then
		return
	end
	if pcall(hidden and api.SuspendMapPins or api.ResumeMapPins, OWNER) then
		suspended = hidden
	end
end
