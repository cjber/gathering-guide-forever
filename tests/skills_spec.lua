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

print("skills_spec ok")
