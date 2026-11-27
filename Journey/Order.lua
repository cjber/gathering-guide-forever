---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- The loop through a set of nodes over world distance: nearest neighbour from the lowest identity, then 2-opt and
-- Or-opt moves, each joining a node to one of its nearest neighbours, until none shortens the loop. The loop does not
-- depend on the player; a tour rotates it to start at the node nearest them.
local Order = {}
ns.Order = Order

-- Loop iterations between two yields. A yield and resume cost far more than an iteration, so a slice is large.
local WORK_PER_STEP = 2048
-- How many of its nearest neighbours a move may join a node to.
local NEIGHBOURS = 10
-- The longest run of nodes an Or-opt move carries elsewhere in the loop.
local SEGMENT = 3
-- A move must shorten the loop by more than this, so rounding never moves it back and forth.
local EPSILON = 1e-6

local IDENTITY = { "uiMapID", "kind", "coord", "nodeID" }

local function Identity(a, b)
	for _, key in ipairs(IDENTITY) do
		if a[key] ~= b[key] then
			return a[key] < b[key]
		end
	end
	return false
end

local function Distance(a, b)
	local dx, dy = a.wx - b.wx, a.wy - b.wy
	return math.sqrt(dx * dx + dy * dy)
end

-- The loop through points 1 to count under distance d, as the points in visiting order.
---@param count number
---@param d fun(a: number, b: number): number
---@param tick fun()
---@return number[]
local function Loop(count, d, tick)
	local near = {}
	for a = 1, count do
		local list, far = {}, {}
		for b = 1, count do
			if b ~= a then
				local distance, at = d(a, b), #list
				if at < NEIGHBOURS or distance < far[at] then
					while at > 0 and far[at] > distance do
						at = at - 1
					end
					table.insert(list, at + 1, b)
					table.insert(far, at + 1, distance)
					list[NEIGHBOURS + 1], far[NEIGHBOURS + 1] = nil, nil
				end
			end
			tick()
		end
		near[a] = list
	end

	local order, pos = { 1 }, { 1 }
	for i = 2, count do
		local pick, best = nil, math.huge
		for b = 1, count do
			if not pos[b] then
				local distance = d(order[i - 1], b)
				if distance < best then
					pick, best = b, distance
				end
			end
			tick()
		end
		---@cast pick -?
		order[i], pos[pick] = pick, i
	end

	-- The point steps places further round the loop from a, backwards when negative.
	local function along(a, steps)
		return order[(pos[a] - 1 + steps) % count + 1]
	end

	-- Points a move has touched, still to be tried again.
	local queue, queued = {}, {}
	local function wake(...)
		for i = 1, select("#", ...) do
			local a = select(i, ...)
			if not queued[a] then
				queued[a] = true
				queue[#queue + 1] = a
			end
		end
	end

	-- Reverses the loop from first forward to last, or all the rest when that is shorter: the same loop either way.
	local function reverse(first, last)
		local i, j = pos[first], pos[last]
		local length = (j - i) % count + 1
		if length * 2 > count then
			i, j, length = j % count + 1, (i - 2) % count + 1, count - length
		end
		for _ = 1, math.floor(length / 2) do
			local a, b = order[i], order[j]
			order[i], order[j] = b, a
			pos[b], pos[a] = i, j
			i, j = i % count + 1, (j - 2) % count + 1
			tick()
		end
	end

	-- 2-opt: swaps the edge on one side of a, and the same side of a neighbour c, for the edge a to c and the one
	-- between the two points left over.
	local function uncross(a)
		for _, step in ipairs({ 1, -1 }) do
			local b = along(a, step)
			for _, c in ipairs(near[a]) do
				local joined = d(a, c)
				if joined >= d(a, b) then
					break
				end
				local e = along(c, step)
				if c ~= b and e ~= a and d(a, b) + d(c, e) - joined - d(b, e) > EPSILON then
					if step == 1 then
						reverse(b, c)
					else
						reverse(a, e)
					end
					wake(a, b, c, e)
					return true
				end
				tick()
			end
		end
		return false
	end

	-- Takes the run of length points from first and puts it between u and the point after it, from its end head.
	local function move(first, length, u, head)
		local run, moved = {}, {}
		for i = 0, length - 1 do
			run[i + 1] = along(first, i)
			moved[run[i + 1]] = true
		end
		local result = {}
		local current = along(first, length)
		for _ = 1, count - length do
			result[#result + 1] = current
			if current == u then
				for i = 1, length do
					result[#result + 1] = run[head == first and i or length - i + 1]
				end
			end
			repeat
				current = along(current, 1)
				tick()
			until not moved[current]
		end
		order = result
		for i, a in ipairs(order) do
			pos[a] = i
		end
	end

	-- Or-opt: carries a short run starting at a to between two other points, either way round.
	local function carry(a)
		for length = 1, math.min(SEGMENT, count - 3) do
			local last = along(a, length - 1)
			local p, q = along(a, -1), along(last, 1)
			local saved = d(p, a) + d(last, q) - d(p, q)
			local function inside(b)
				return (pos[b] - pos[a]) % count < length
			end
			for _, ends in ipairs({ { a, last }, { last, a } }) do
				local x, y = ends[1], ends[2]
				for _, c in ipairs(near[x]) do
					if d(x, c) >= saved then
						break
					end
					for _, step in ipairs({ 1, -1 }) do
						local e = along(c, step)
						if not inside(c) and not inside(e) and saved - (d(c, x) + d(y, e) - d(c, e)) > EPSILON then
							-- The run goes after u, whose neighbour there takes its far end.
							local u, head = c, x
							if step == -1 then
								u, head = e, y
							end
							move(a, length, u, head)
							wake(p, q, a, last, c, e)
							return true
						end
					end
					tick()
				end
			end
		end
		return false
	end

	if count > 3 then
		for _, a in ipairs(order) do
			wake(a)
		end
		local index = 1
		while queue[index] do
			local a = queue[index]
			index = index + 1
			queued[a] = false
			if not uncross(a) then
				carry(a)
			end
		end
	end
	return order
end

-- Starts a loop job over nodes that carry world coordinates wx and wy. Call Step until it is no longer "working";
-- each call does a bounded slice, so the caller defers the next one a frame.
---@param nodes GGNode[]
---@return table job {status, order, yards, Step}
function Order.Begin(nodes)
	local job = { status = "working", order = {}, yards = 0 }
	local work = 0
	local function tick()
		work = work + 1
		if work == WORK_PER_STEP then
			work = 0
			coroutine.yield()
		end
	end
	local co = coroutine.create(function()
		-- Points are numbered by identity, so the loop does not depend on the order the nodes came in.
		local sorted = {}
		for i, node in ipairs(nodes) do
			sorted[i] = node
		end
		table.sort(sorted, Identity)
		local result = {}
		if #sorted > 0 then
			local order = Loop(#sorted, function(a, b)
				return Distance(sorted[a], sorted[b])
			end, tick)
			for i, a in ipairs(order) do
				result[i] = sorted[a]
			end
		end
		return "ready", result
	end)
	function job.Step()
		if job.status ~= "working" then
			return job.status
		end
		local ok, status, result = coroutine.resume(co)
		if not ok then
			job.status = "error"
		elseif coroutine.status(co) == "dead" then
			job.status = status
			job.order = result or {}
			job.yards = Order.Length(job.order)
		end
		return job.status
	end
	return job
end

-- Runs a job to completion in one call, for the planner's small zones and the specs.
---@param nodes GGNode[]
---@return GGNode[] order
---@return number yards
function Order.Solve(nodes)
	local job = Order.Begin(nodes)
	while job.Step() == "working" do
	end
	return job.order, job.yards
end

-- The closed loop's length in world yards.
---@param order GGNode[]
---@return number
function Order.Length(order)
	local total = 0
	for i = 1, #order do
		total = total + Distance(order[i], order[i % #order + 1])
	end
	return total
end

-- The index of the node nearest a world point, or nil for an empty loop. Ties go to the lower identity.
---@param order GGNode[]
---@param point {x: number, y: number}
---@return number?
function Order.Nearest(order, point)
	local best, bestDistance
	for i, node in ipairs(order) do
		local d = Distance(node, { wx = point.x, wy = point.y })
		if not best or d < bestDistance or (d == bestDistance and Identity(node, order[best])) then
			best, bestDistance = i, d
		end
	end
	return best
end

-- The same loop starting at index start.
---@param order GGNode[]
---@param start number
---@return GGNode[]
function Order.Rotate(order, start)
	local rotated = {}
	for i = 0, #order - 1 do
		rotated[#rotated + 1] = order[(start - 1 + i) % #order + 1]
	end
	return rotated
end
