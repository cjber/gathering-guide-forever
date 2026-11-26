std = "lua51"
max_line_length = 120
exclude_files = {
	"forever-core/**",
	"tools/.cache/**",
	".release/**",
	".types/**",
	"types/**",
	".claude/**",
	"reference/**",
	".bugpatrol/runs/**",
	".speedpatrol/runs/**",
	".sloppatrol/runs/**",
}
ignore = { "212/_.*" } -- unused arguments prefixed with _
globals = {
	"GatheringGuideForeverDB",
	"GatheringGuideForeverCharDB",
	"SLASH_GATHERINGGUIDEFOREVER1",
	"SLASH_GATHERINGGUIDEFOREVER2",
	"SlashCmdList",
}
files["tests/**"] = { globals = { "ShortestPathForever", "C_SkillInfo", "C_Item", "GetServerTime", "GetCoinTextureString", "Auctionator", "C_Timer", "ObjectiveTrackerFrame", "ObjectiveTrackerManager", "CreateFrame", "Mixin", "ForeverCore" } }
read_globals = {
	"ForeverCore",
	"GatherMate2",
	"ShortestPathForeverDB",
	"ShortestPathForever",
	-- The game's own objective tracker, which UI/Tracker.lua hangs its section on, and the world map's quest log.
	"ObjectiveTrackerFrame",
	"ObjectiveTrackerManager",
	"QuestMapFrame",
	"WorldMapFrame",
	"ToggleWorldMap",
	"Mixin",
	"CreateFromMixins",
	"CreateVector2D",
	"CreateFrame",
	"C_AddOns",
	"C_Item",
	"C_Map",
	"C_SkillInfo",
	"C_Texture",
	"C_Timer",
	"canaccessvalue",
	"debugprofilestop",
	"GameFontDisableSmall",
	"GameFontHighlight",
	"GameFontNormal",
	"GameFontNormalSmall",
	"GameTooltip",
	"GetServerTime",
	"GetCoinTextureString",
	"UIParent",
	"UnitPosition",
}
