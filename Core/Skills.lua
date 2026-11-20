---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

local Skills = {}
ns.Skills = Skills

-- Classic's gathering rule: a node gives a skill point for certain while the skill is under 25 above its requirement,
-- then 75%, 25% and finally never at 100 above it. A node above the skill cannot be gathered yet.
local BANDS = {
	{ below = 25, chance = 1.0, color = "orange" },
	{ below = 50, chance = 0.75, color = "yellow" },
	{ below = 100, chance = 0.25, color = "green" },
}

---@param rank number the player's skill
---@param required number the node's requirement
---@return number chance 0 to 1
---@return string color orange, yellow, green, grey or red
function Skills.Chance(rank, required)
	if rank < required then
		return 0, "red"
	end
	local over = rank - required
	for _, band in ipairs(BANDS) do
		if over < band.below then
			return band.chance, band.color
		end
	end
	return 0, "grey"
end

-- The player's current and maximum rank in a skill line.
---@param line number
---@return number rank
---@return number max
function Skills.Rank(line)
	---@diagnostic disable-next-line: undefined-global
	local api = C_SkillInfo
	local info = api and api.GetSkillLineInfoByID and api.GetSkillLineInfoByID(line)
	if not info then
		return 0, 0
	end
	return info.skillLevel or info.rank or 0, info.maxSkillLevel or info.maxRank or 0
end

-- Whether a node can still raise the player's skill now.
---@param node GGNode
---@param rank number
---@return boolean
function Skills.Gives(node, rank)
	local chance = Skills.Chance(rank, node.required)
	return chance > 0
end

local COLORS = {
	orange = { 1, 0.5, 0.25 },
	yellow = { 1, 1, 0 },
	green = { 0.25, 0.75, 0.25 },
	grey = { 0.5, 0.5, 0.5 },
	red = { 1, 0.15, 0.15 },
}
---@param color string
---@return number[]
function Skills.Color(color)
	return COLORS[color] or COLORS.grey
end
