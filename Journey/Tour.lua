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

-- The tour last toured and how far it got, for the panel's Continue card.
local function Remember()
	local tour = assert(state)
	ns.Char.last = {
		kind = tour.kind,
		uiMapID = tour.uiMapID,
		name = tour.name,
		list = tour.list,
		pos = tour.pos,
		total = #tour.order,
		gained = (ns.Session.SkillUps(GetServerTime())),
	}
end

local function Notify()
	if state then
		Remember()
	end
	for _, fn in ipairs(listeners) do
		ns.core.SafeCall("tour listener", fn)
	end
	if ns.Loop then
		ns.Loop.Draw()
	end
end

---@param fn fun()
function Tour.Listen(fn)
	listeners[#listeners + 1] = fn
end

-- The order indices of the next batch, walking the loop from pos, at most one lap and max stops. A node that can no
-- longer raise its profession's skill is passed over when skip is set.
---@param order GGNode[]
---@param pos number
---@param skip boolean
---@param ranks table<string, number>
---@param max number
---@return number[]
function Tour.NextBatch(order, pos, skip, ranks, max)
	local batch = {}
	for step = 0, #order - 1 do
		local index = (pos - 1 + step) % #order + 1
		local node = order[index]
		if not skip or ns.Skills.Chance(ranks[node.kind] or 0, node.required) > 0 then
			batch[#batch + 1] = index
			if #batch >= max then
				break
			end
		end
	end
	return batch
end

-- The order indices the journey is given from pos.
---@param pos number
---@param max number
---@return number[]
local function Batch(pos, max)
	local tour = assert(state)
	-- A shopping-list tour gathers every wanted node, whatever it does for the skill.
	local skip = assert(ns.DB).skipNoSkillUp and not tour.list
	return Tour.NextBatch(tour.order, pos, skip, ns.Skills.Ranks(), max)
end

-- Sends the next batch to the journey. Returns whether it started.
local function Submit()
	local tour, db = assert(state), assert(ns.DB)
	local batch = Batch(tour.pos, ns.Navigation.MAX_STOPS)
	if #batch == 0 then
		tour.status = "nothing"
		return false
	end
	local stops = {}
	for i, index in ipairs(batch) do
		local node = tour.order[index]
		stops[i] = { map = node.uiMapID, x = node.x, y = node.y, title = node.name }
	end
	local ok, why = ns.Navigation.Route(stops, db.onlyGatheringPins)
	if not ok then
		tour.status = ns.Navigation.State().blocked and "blocked" or why or "refused"
		return false
	end
	tour.batch = batch
	tour.pos = batch[1]
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
	local after = orderIndex % #state.order + 1
	local upcoming = state.batch[index + 1] or Batch(after, 1)[1] or after
	-- The loop's next stop sits no further on than this one only after the walk came round.
	if upcoming <= orderIndex then
		state.laps = state.laps + 1
	end
	state.pos = upcoming
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

-- The first profession in ns.Kinds order a loop has nodes of: the art of its Continue card.
---@param order GGNode[]
---@return string
local function FirstKind(order)
	local present = {}
	for _, node in ipairs(order) do
		present[node.kind] = true
	end
	for _, k in ipairs(ns.Kinds) do
		if present[k.kind] then
			return k.kind
		end
	end
	error("a loop without a gathering profession")
end

-- Starts a tour over a planned zone. Returns whether it started and why not: "navigation" when Shortest Path Forever
-- lacks the API, "blocked" when combat or a corpse holds guidance, "empty" when nothing is left to gather.
---@param plan table a Planner zone: uiMapID, name, order
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
	local previous = state
	state = {
		kind = FirstKind(order),
		name = plan.name,
		list = plan.list == true,
		uiMapID = plan.uiMapID,
		seconds = plan.seconds,
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
	ns.Session.Begin(plan, GetServerTime())
	ns.MapFocus.Sync()
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
		Remember()
		ns.Navigation.Cancel()
		state = nil
	end
	ns.Session.End()
	ns.MapFocus.Sync()
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
		list = state.list,
		name = state.name,
		uiMapID = state.uiMapID,
		seconds = state.seconds,
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
	if state and (key == "skipNoSkillUp" or key == "onlyGatheringPins") then
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

-- A player who dies or enters combat keeps the tour; the journey itself pauses. A batch sent while it is paused is
-- refused, so it goes again once combat ends or the player is alive.
local function Retry()
	ns.Defer(function()
		if state and state.status ~= "running" then
			Submit()
			Notify()
		end
	end)
end
ns.On("PLAYER_REGEN_ENABLED", Retry)
ns.On("PLAYER_ALIVE", Retry)
ns.On("PLAYER_UNGHOST", Retry)

ns.On("PLAYER_LOGOUT", function()
	Tour.Stop(true)
end)
