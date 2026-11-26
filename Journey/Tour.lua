---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end
local L = ns.L

-- A tour: the loop through a zone's nodes, started at the one nearest the player and handed to Shortest Path Forever in
-- batches of up to 64 stops. The tour advances when the journey reports a stop arrived and sends the next batch after
-- the last stop of this one, so the loop repeats until the player stops it.
-- Batching follows Shortest Path Forever's Journey/FarmingCursor.lua (GPL-3.0).
local Tour = {}
ns.Tour = Tour

---@type table?
local state
---@type fun()?
local unobserve
local listeners = {}

local function Notify()
	for _, fn in ipairs(listeners) do
		ns.core.SafeCall("tour listener", fn)
	end
	if ns.Loop then
		ns.Loop.Refresh()
	end
end

---@param fn fun()
function Tour.Listen(fn)
	listeners[#listeners + 1] = fn
end

-- The order indices of the next batch, walking the loop from pos, at most one lap and max stops. A node that can no
-- longer raise the skill is passed over when skip is set.
---@param order GGNode[]
---@param pos number
---@param skip boolean
---@param rank number
---@param max number
---@return number[]
function Tour.NextBatch(order, pos, skip, rank, max)
	local batch = {}
	for step = 0, #order - 1 do
		local index = (pos - 1 + step) % #order + 1
		local node = order[index]
		if not skip or ns.Skills.Chance(rank, node.required) > 0 then
			batch[#batch + 1] = index
			if #batch >= max then
				break
			end
		end
	end
	return batch
end

local function Rank()
	return (ns.Skills.Rank(assert(state).line))
end

-- Sends the next batch to the journey. Returns whether it started.
local function Submit()
	local tour, db = assert(state), assert(ns.DB)
	-- A shopping-list tour gathers every wanted node, whatever it does for the skill.
	local skip = db.skipNoSkillUp and not tour.list
	local batch = Tour.NextBatch(tour.order, tour.pos, skip, Rank(), ns.Navigation.MAX_STOPS)
	if #batch == 0 then
		tour.status = "nothing"
		return false
	end
	local stops = {}
	for i, index in ipairs(batch) do
		local node = tour.order[index]
		stops[i] = { map = node.uiMapID, x = node.x, y = node.y, title = node.name }
	end
	local ok, why = ns.Navigation.Route(stops)
	if not ok then
		tour.status = why or "refused"
		return false
	end
	tour.batch = batch
	tour.status = "running"
	return true
end

local function Observed(phase, index)
	if not state or not state.batch then
		return
	end
	local orderIndex = state.batch[index]
	if not orderIndex then
		return
	end
	if phase ~= "arrived" then
		return
	end
	state.visited = state.visited + 1
	state.pos = orderIndex % #state.order + 1
	if orderIndex == #state.order then
		state.laps = state.laps + 1
	end
	if index < #state.batch then
		Notify()
		return
	end
	-- The last stop of the batch was reached: send the next batch once the journey's own callback has returned.
	local tour = state
	ns.Defer(function()
		if state == tour then
			Submit()
			Notify()
		end
	end)
end

-- Starts a tour over a planned zone. Returns whether it started and why not: "navigation" when Shortest Path Forever
-- lacks the API, "blocked" when combat or a corpse holds guidance, "empty" when nothing is left to gather.
---@param plan table a Planner zone: kind, uiMapID, name, order
---@return boolean ok
---@return string? reason
function Tour.Start(plan)
	if not ns.Navigation.Available() then
		return false, "navigation"
	end
	local nav = ns.Navigation.State()
	if nav.blocked then
		return false, "blocked"
	end
	if #plan.order == 0 then
		return false, "empty"
	end
	local order = plan.order
	local player = ns.World.Player()
	if player then
		local nearest = ns.Order.Nearest(order, player)
		if nearest then
			order = ns.Order.Rotate(order, nearest)
		end
	end
	local k = ns.KindByName[plan.kind]
	local previous = state
	state = {
		kind = plan.kind,
		line = k and k.line or 0,
		name = plan.name,
		list = plan.list == true,
		uiMapID = plan.uiMapID,
		order = order,
		pos = 1,
		visited = 0,
		laps = 0,
		status = "starting",
	}
	if not Submit() then
		local why = state.status
		state = previous
		return false, why
	end
	-- The new journey replaced the old one; only now does the old tour let go of its observer and its session.
	if unobserve then
		unobserve()
	end
	unobserve = ns.Navigation.Observe(Observed)
	ns.Char.last = { kind = plan.kind, uiMapID = plan.uiMapID, name = plan.name }
	ns.Session.Begin(plan, GetServerTime())
	Notify()
	return true
end

-- Ends the tour, its journey and its session.
---@param quiet boolean?
function Tour.Stop(quiet)
	if unobserve then
		unobserve()
		unobserve = nil
	end
	if state then
		ns.Navigation.Cancel()
		state = nil
	end
	ns.Session.End()
	if not quiet then
		Notify()
	end
end

---@return boolean
function Tour.Active()
	return state ~= nil
end

-- The running tour for the tracker and panel, or nil.
---@return table?
function Tour.Progress()
	if not state then
		return nil
	end
	return {
		kind = state.kind,
		name = state.name,
		uiMapID = state.uiMapID,
		visited = state.visited,
		total = #state.order,
		laps = state.laps,
		status = state.status,
		next = state.order[state.pos],
		order = state.order,
		pos = state.pos,
	}
end

---@return string
function Tour.Describe()
	if not state then
		return "idle"
	end
	return ("%s, node %d of %d, status %s"):format(state.name, state.pos, #state.order, state.status)
end

-- A changed setting that affects the batch in flight sends it again from the current stop.
---@param key string
function Tour.OnSettingChanged(key)
	if state and key == "skipNoSkillUp" then
		if Submit() then
			Notify()
		end
	elseif key == "loopOnMap" or key == "showTracker" then
		Notify()
	end
end

-- Reasons a tour could not start, in the player's words.
---@param reason string?
---@return string
function Tour.Reason(reason)
	local text = {
		navigation = L["Shortest Path Forever needs an update to guide a tour."],
		blocked = L["Guidance is paused in combat or while dead."],
		empty = L["There is nothing to gather here at your skill."],
		nothing = L["No node here can raise your skill."],
	}
	return text[reason or ""] or L["The journey could not start."]
end

-- A new skill level or a leaving player can end a stale tour. A player who dies or enters combat keeps the tour; the
-- journey itself pauses.
ns.On("PLAYER_LOGOUT", function()
	Tour.Stop(true)
end)
