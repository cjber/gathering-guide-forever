---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

-- The loop through a set of nodes: an exact Euclidean minimum spanning tree walked in preorder and closed, a
-- 2-approximation of the shortest tour over world distance (the method Shortest Path Forever's farming order used).
-- The loop does not depend on the player; a tour rotates it to start at the node nearest them.
-- Ported from Shortest Path Forever's Journey/FarmingOrder.lua (GPL-3.0).
local Order = {}
ns.Order = Order

local function Identity(a, b)
	for _, key in ipairs({ "uiMapID", "kind", "coord", "nodeID" }) do
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

-- Starts a loop job over nodes that carry world coordinates wx and wy. Call Step until it is no longer "working"; each
-- call does one bounded slice, a single pass over the nodes, so a solve is as many slices as there are nodes and the
-- caller defers the next one to spread the work over frames.
---@param nodes GGNode[]
---@return table job {status, order, yards, Step}
function Order.Begin(nodes)
	local job = { status = "working", order = {}, yards = 0 }
	local count = #nodes
	local co = coroutine.create(function()
		if count == 0 then
			return "ready", {}
		end
		local root = 1
		for i = 2, count do
			if Identity(nodes[i], nodes[root]) then
				root = i
			end
		end
		local best, parent, used = {}, {}, {}
		for i = 1, count do
			best[i] = math.huge
		end
		best[root] = 0
		for _ = 1, count do
			local pick
			for i = 1, count do
				if
					not used[i]
					and (
						not pick
						or best[i] < best[pick]
						or (best[i] == best[pick] and Identity(nodes[i], nodes[pick]))
					)
				then
					pick = i
				end
			end
			used[pick] = true
			for i = 1, count do
				if not used[i] then
					local d = Distance(nodes[pick], nodes[i])
					if d < best[i] or (d == best[i] and parent[i] and Identity(nodes[pick], nodes[parent[i]])) then
						best[i], parent[i] = d, pick
					end
				end
			end
			coroutine.yield()
		end
		-- Preorder over the tree, each node's children taken in identity order.
		local children = {}
		for i = 1, count do
			if parent[i] then
				children[parent[i]] = children[parent[i]] or {}
				table.insert(children[parent[i]], i)
			end
		end
		for _, list in pairs(children) do
			table.sort(list, function(a, b)
				return Identity(nodes[a], nodes[b])
			end)
		end
		local result, stack, nextChild = {}, { root }, {}
		result[1] = nodes[root]
		while #stack > 0 do
			local current = stack[#stack]
			nextChild[current] = (nextChild[current] or 0) + 1
			local child = children[current] and children[current][nextChild[current]]
			if child then
				result[#result + 1] = nodes[child]
				stack[#stack + 1] = child
			else
				stack[#stack] = nil
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
