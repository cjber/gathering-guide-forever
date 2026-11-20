-- A bare namespace the specs load the addon's pure modules into, the way the client passes (addonName, ns).
local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local root = here .. "/.."

local Harness = {}

---@return table ns
function Harness.Namespace()
	local ns = { DB = { skipNoSkillUp = true }, Char = { list = {} } }
	return ns
end

---@param ns table
---@param ... string files relative to the addon root
function Harness.Load(ns, ...)
	for _, file in ipairs({ ... }) do
		local chunk = assert(loadfile(root .. "/" .. file))
		chunk("GatheringGuideForever", ns)
	end
	return ns
end

---@param path string
---@return string
function Harness.Read(path)
	local handle = assert(io.open(root .. "/" .. path, "r"))
	local text = handle:read("*a")
	handle:close()
	return text
end

Harness.root = root
return Harness
