---@meta
---@class GGNode
---@field uiMapID number
---@field kind string
---@field coord number
---@field nodeID number
---@field x number
---@field y number
---@field name string
---@field wx number?
---@field wy number?
---@field world number?
---@field line number?
---@field required number?

---@class GGRange the lowest to highest skill a profession's nodes on a loop need
---@field lowest number
---@field highest number

---@class GGRanking the best zones at the player's skills
---@field zones table[]
---@field total number how many zones can raise a skill
---@field key string? what a saved ranking was planned for
---@field professions string? the professions a saved ranking was planned for

---@class GGNodeType a node name among a zone's nodes
---@field name string
---@field kind string
---@field required number
---@field count number

---@class GGNamespace
---@field [string] any
---@field L table<string, string>
---@field core table
---@field Credits table
---@field NodeNames table<number, string>
---@field ItemIDs table<string, number>
---@field NodeSkills table<string, number[]>
