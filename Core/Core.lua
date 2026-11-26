---@type string, GGNamespace
local addonName, ns = ...
local L = ns.L

if ns.broken then
	return
end

ns.ReportTitle = L["Gathering Guide Forever report"]
ns.core = ForeverCore.Register(addonName, {
	title = ns.ReportTitle,
	lines = function()
		return ns.ReportLines()
	end,
})
if type(ForeverCore.Credits) == "table" then
	ns.core.SafeCall("credits", ForeverCore.Credits.Register, "Gathering Guide Forever", ns.Credits)
end

-- The two gathering professions, keyed by the GatherMate2 database name and the client's skill line id.
ns.Kinds = {
	{ kind = "Mining", line = 186, label = L["Mining"] },
	{ kind = "Herb Gathering", line = 182, label = L["Herbalism"] },
}
-- The minimap tracking art (UiTextureAtlasElement: an ore chunk and a herb leaf) by GatherMate2's kind.
ns.KIND_ATLAS = { ["Mining"] = "Professions_Tracking_Ore", ["Herb Gathering"] = "Professions_Tracking_Herb" }
ns.KindByName = {}
for _, k in ipairs(ns.Kinds) do
	ns.KindByName[k.kind] = k
end

-- Walking pace and the time spent at each node, the two numbers a loop's duration and skill-up rate come from.
ns.WALK_YARDS_PER_SECOND = 7
ns.SECONDS_PER_NODE = 5
-- A node cannot be gathered again until it respawns, so no lap is shorter than this. Assumed, not measured: Blizzard
-- publishes no respawn time for Classic or Forever gathering nodes and players report anything from 5 to 30 minutes,
-- so ten minutes stands in until a source says otherwise (listed under Known limitations).
ns.NODE_RESPAWN_SECONDS = 600
-- The overview shows this many of the best zones; the rest are a click away.
ns.TOP_ZONES = 2

---@type table<string, fun(...)[]>
local handlers = {}
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		ns.core.SafeCall("event " .. event, fn, ...)
	end
end)

---@param event string
---@param fn fun(...)
function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		frame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

ns.defaults = { skipNoSkillUp = true, loopOnMap = true, showTracker = true, onlyGatheringPins = true }

ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then
		return
	end
	GatheringGuideForeverDB = GatheringGuideForeverDB or {}
	GatheringGuideForeverCharDB = GatheringGuideForeverCharDB or {}
	ns.DB = GatheringGuideForeverDB
	ns.Char = GatheringGuideForeverCharDB
	for key, value in pairs(ns.defaults) do
		if ns.DB[key] == nil then
			ns.DB[key] = value
		end
	end
	ns.Char.list = ns.Char.list or {}
	-- A saved item the data does not know has no ID or nodes to show or count.
	for i = #ns.Char.list, 1, -1 do
		if not ns.ItemIDs[ns.Char.list[i].item] then
			table.remove(ns.Char.list, i)
		end
	end
	ns.ready = true
	for _, fn in ipairs(ns.loadedHooks or {}) do
		ns.core.SafeCall("loaded", fn)
	end
end)

-- Modules that need the saved variables run after they load.
---@param fn fun()
function ns.OnLoaded(fn)
	if ns.ready then
		ns.core.SafeCall("loaded", fn)
	else
		ns.loadedHooks = ns.loadedHooks or {}
		table.insert(ns.loadedHooks, fn)
	end
end

function ns.ReportLines()
	local nav = ns.Navigation.State()
	return {
		"GatherMate2: " .. (ns.GatherMate.Available() and "loaded" or "missing"),
		"Shortest Path Forever: " .. (ns.Navigation.Available() and "ready" or "missing or too old"),
		"Tour: " .. (ns.Tour and ns.Tour.Describe() or "idle"),
		"Last plan error: " .. (ns.Planner and ns.Planner.LastError() or "none"),
		"Journey busy: " .. tostring(nav.busy) .. ", blocked: " .. tostring(nav.blocked),
	}
end

-- Runs fn on the next frame, so a long job never holds one frame.
---@param fn fun()
function ns.Defer(fn)
	C_Timer.After(0, fn)
end

-- An icon at its own shape, inline in a line of text with a space after it: an item's square file icon without its
-- border, or an atlas sized to its own aspect. Nothing for an atlas the client cannot describe.
---@param icon number|string
---@param size number the height in the text
---@return string
function ns.Markup(icon, size)
	if type(icon) == "number" then
		return ("|T%d:%d:%d:0:0:64:64:5:59:5:59|t "):format(icon, size, size)
	end
	local info = C_Texture.GetAtlasInfo(icon)
	if not info or info.height <= 0 then
		return ""
	end
	return ("|A:%s:%d:%d|a "):format(icon, size, math.floor(size * info.width / info.height + 0.5))
end

-- An atlas at its own aspect inside a box, never stretched. The caller anchors it by one point.
---@param texture Texture
---@param atlas string
---@param width number
---@param height number
function ns.Fit(texture, atlas, width, height)
	texture:SetAtlas(atlas)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	local aspect = info and info.width > 0 and info.height > 0 and info.width / info.height or 1
	local w, h = width, width / aspect
	if h > height then
		w, h = height * aspect, height
	end
	texture:SetSize(w, h)
end
