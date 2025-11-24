local strings = {
    -- Sections
    SI_NVK3UT_LAM_SECTION_JOURNAL = "Journal extensions",
    SI_NVK3UT_LAM_SECTION_STATUS_TEXT = "Status text",
    SI_NVK3UT_LAM_SECTION_TRACKER_HOST = "Tracker host",
    SI_NVK3UT_LAM_SECTION_DEBUG = "Debug & Support",

    -- Journal section
    SI_NVK3UT_LAM_JOURNAL_HEADER_STORAGE = "Favorites & data",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FAVORITE_SCOPE = "Favorite storage:",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FAVORITE_SCOPE_DESC = "Choose whether favorites are stored account-wide or per character.",
    SI_NVK3UT_LAM_OPTION_JOURNAL_SCOPE_ACCOUNT = "Account-wide",
    SI_NVK3UT_LAM_OPTION_JOURNAL_SCOPE_CHARACTER = "Per-character",
    SI_NVK3UT_LAM_OPTION_JOURNAL_RECENT_LIMIT = "Recent history (max entries)",
    SI_NVK3UT_LAM_OPTION_JOURNAL_RECENT_LIMIT_DESC = "Sets the hard cap for the number of recent entries.",
    SI_NVK3UT_LAM_JOURNAL_HEADER_FEATURES = "Features",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FEATURE_COMPLETED = "Completed enabled",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FEATURE_FAVORITES = "Favorites enabled",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FEATURE_RECENT = "Recent enabled",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FEATURE_TODO = "To-do list enabled",

    -- Status Text
    SI_NVK3UT_LAM_STATUS_HEADER_DISPLAY = "Display",
    SI_NVK3UT_LAM_OPTION_STATUS_SHOW_COMPASS = "Show status above the compass",

    -- Tracker Host
    SI_NVK3UT_LAM_TRACKER_HOST_HEADER_WINDOW = "Window & appearance",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_SHOW = "Show window",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_LOCK = "Lock window",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_ON_TOP = "Always on top",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_WIDTH = "Window width",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HEIGHT = "Window height",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HEADER_HEIGHT = "Header height",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HEADER_HEIGHT_DESC = "0 px hides the header area.",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_FOOTER_HEIGHT = "Footer height",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_FOOTER_HEIGHT_DESC = "0 px hides the footer area.",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_RESET_POSITION = "Reset position",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_RESET_POSITION_DESC = "Resets size, position, and behavior of the tracker window.",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HIDE_DEFAULT = "Hide default quest tracker",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_BACKGROUND = "Show background",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_BACKGROUND_ALPHA = "Background opacity (%)",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_EDGE = "Show border",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_EDGE_ALPHA = "Border opacity (%)",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_EDGE_THICKNESS = "Border thickness",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_PADDING = "Padding",
    SI_NVK3UT_LAM_TRACKER_HOST_HEADER_LAYOUT = "Auto-resize & layout",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_AUTOGROW_V = "Auto-adjust height",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_AUTOGROW_H = "Auto-adjust width",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_MIN_WIDTH = "Minimum width",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_MAX_WIDTH = "Maximum width",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_MIN_HEIGHT = "Minimum height",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_MAX_HEIGHT = "Maximum height",
    SI_NVK3UT_LAM_TRACKER_HOST_HEADER_BEHAVIOR = "Behavior",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HIDE_IN_COMBAT = "Hide tracker during combat",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HIDE_IN_COMBAT_DESC = "When enabled, the entire tracker host hides while you are in combat. The tracker remains visible while the AddOn Settings (LAM) are open.",

    -- Debug
    SI_NVK3UT_LAM_OPTION_DEBUG_ENABLE = "Enable debug",
    SI_NVK3UT_LAM_OPTION_SELF_TEST = "Run self-test",
    SI_NVK3UT_LAM_OPTION_SELF_TEST_DESC = "Performs a compact integrity check. With debug enabled, detailed chat logs are shown.",
    SI_NVK3UT_LAM_OPTION_RELOAD_UI = "Reload UI",
}

for stringId, value in pairs(strings) do
    ZO_CreateStringId(stringId, value)
end
