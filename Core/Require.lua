local _, ns = ...
local ready = ForeverCore ~= nil
	and type(ForeverCore.APIKit) == "table"
	and type(ForeverCore.APIKit.Hub) == "function"
	and type(ForeverCore.APIKit.NotReady) == "function"
	and type(ForeverCore.ContextMenu) == "function"
	and type(ForeverCore.TrackerSection) == "table"
	and type(ForeverCore.TrackerSection.UpdateText) == "function"
ns.ForeverRequire(ready, { key = "GATHERINGGUIDEFOREVER", "/gathering", "/ggf" })
