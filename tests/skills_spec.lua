local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local H = dofile(here .. "/harness.lua")
local ns = H.Load(H.Namespace(), "Locales/enUS.lua", "Core/Skills.lua")
local Skills = ns.Skills

local function Expect(rank, required, chance, color)
	local c, name = Skills.Chance(rank, required)
	assert(c == chance and name == color, ("rank %d vs %d: got %s %s"):format(rank, required, c, name))
end

Expect(1, 25, 0, "red")
Expect(25, 25, 1, "orange")
Expect(49, 25, 1, "orange")
Expect(50, 25, 0.75, "yellow")
Expect(74, 25, 0.75, "yellow")
Expect(75, 25, 0.25, "green")
Expect(124, 25, 0.25, "green")
Expect(125, 25, 0, "grey")

-- The next change in a node's colour: none while out of reach or once grey.
local function Next(rank, required, color, at)
	local c, n = Skills.NextBand(rank, required)
	assert(c == color and n == at, ("rank %d vs %d: got %s at %s"):format(rank, required, tostring(c), tostring(n)))
end

Next(24, 25, nil, nil)
Next(25, 25, "yellow", 50)
Next(49, 25, "yellow", 50)
Next(50, 25, "green", 75)
Next(75, 25, "grey", 125)
Next(125, 25, nil, nil)
assert(Skills.Colored("Iron", 25, 25) == "|cffff8040Iron|r", Skills.Colored("Iron", 25, 25))
assert(Skills.Colored("Iron", 1, 25) == "|cffff2626Iron|r", Skills.Colored("Iron", 1, 25))

print("skills_spec ok")
