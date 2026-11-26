---@type string, GGNamespace
local _, ns = ...
if ns.broken then
	return
end

local Skills = {}
ns.Skills = Skills

-- The highest a gathering skill goes, whatever the player has trained so far.
Skills.MAX = 300

-- Classic's gathering rule: a node gives a skill point for certain while the skill is under 25 above its requirement,
-- then 75%, 25% and finally never at 100 above it. A node above the skill cannot be gathered yet, and a skill at its
-- highest gains nothing from any node.
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
			return rank < Skills.MAX and band.chance or 0, band.color
		end
	end
	return 0, "grey"
end

-- The next change in a gatherable node's colour as the skill rises: the colour it turns to and the skill it turns at.
-- Nil while the node is out of reach, once it is grey, and when the skill cannot rise that far.
---@param rank number the player's skill
---@param required number the node's requirement
---@return string? color
---@return number? at
function Skills.NextBand(rank, required)
	local over = rank - required
	if over < 0 then
		return nil
	end
	for i, band in ipairs(BANDS) do
		if over < band.below then
			local after, at = BANDS[i + 1], required + band.below
			if at > Skills.MAX then
				return nil
			end
			return after and after.color or "grey", at
		end
	end
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

---@class GGSkill
---@field kind string
---@field label string
---@field rank number
---@field max number

-- The gathering professions the player has learned, in ns.Kinds order.
---@return GGSkill[]
function Skills.Learned()
	local learned = {}
	for _, k in ipairs(ns.Kinds) do
		local rank, max = Skills.Rank(k.line)
		if rank > 0 then
			learned[#learned + 1] = { kind = k.kind, label = k.label, rank = rank, max = max }
		end
	end
	return learned
end

-- The learned professions' skills by kind, what a plan is made for.
---@return table<string, number>
function Skills.Ranks()
	local ranks = {}
	for _, skill in ipairs(Skills.Learned()) do
		ranks[skill.kind] = skill.rank
	end
	return ranks
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

-- Text in the colour a node of this requirement has at a skill.
---@param text string
---@param rank number
---@param required number
---@return string
function Skills.Colored(text, rank, required)
	local _, color = Skills.Chance(rank, required)
	local rgb = Skills.Color(color)
	return ("|cff%02x%02x%02x%s|r"):format(rgb[1] * 255 + 0.5, rgb[2] * 255 + 0.5, rgb[3] * 255 + 0.5, text)
end
