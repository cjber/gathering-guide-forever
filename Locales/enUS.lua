---@type string, GGNamespace
local _, ns = ...
-- Every player-visible string is its own English text; a missing key reads as itself.
ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
