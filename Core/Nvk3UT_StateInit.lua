-- Core/Nvk3UT_StateInit.lua
-- Centralized SavedVariables bootstrap and first-login defaults for Nvk3UT.
-- This module does NOT register ESO events, does NOT create UI, and does NOT call ReloadUI.

Nvk3UT_StateInit = Nvk3UT_StateInit or {}

-- Internal helper: shallow-safe table ensure
local function EnsureTable(parent, key)
    if type(parent) ~= "table" then
        return {}
    end

    local value = parent[key]
    if type(value) ~= "table" then
        value = {}
        parent[key] = value
    end
    return value
end

-- SavedVariables defaults mirrored from the legacy core file.
-- TODO Model: split tracker/font defaults into dedicated settings modules.
local DEFAULT_FONT_FACE_BOLD = "$(BOLD_FONT)"
local DEFAULT_FONT_OUTLINE = "soft-shadow-thick"

local DEFAULT_QUEST_FONTS = {
    category = { face = DEFAULT_FONT_FACE_BOLD, size = 20, outline = DEFAULT_FONT_OUTLINE },
    title = { face = DEFAULT_FONT_FACE_BOLD, size = 16, outline = DEFAULT_FONT_OUTLINE },
    line = { face = DEFAULT_FONT_FACE_BOLD, size = 14, outline = DEFAULT_FONT_OUTLINE },
}

local DEFAULT_ACHIEVEMENT_FONTS = {
    category = { face = DEFAULT_FONT_FACE_BOLD, size = 20, outline = DEFAULT_FONT_OUTLINE },
    title = { face = DEFAULT_FONT_FACE_BOLD, size = 16, outline = DEFAULT_FONT_OUTLINE },
    line = { face = DEFAULT_FONT_FACE_BOLD, size = 14, outline = DEFAULT_FONT_OUTLINE },
}

local DEFAULT_TRACKER_APPEARANCE = {
    questTracker = {
        colors = {
            categoryTitle = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            objectiveText = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            entryTitle = { r = 1, g = 1, b = 0, a = 1 },
            activeTitle = { r = 1, g = 1, b = 1, a = 1 },
        },
    },
    achievementTracker = {
        colors = {
            categoryTitle = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            objectiveText = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            entryTitle = { r = 1, g = 1, b = 0, a = 1 },
            activeTitle = { r = 1, g = 1, b = 1, a = 1 },
        },
    },
}

local DEFAULT_HOST_SETTINGS = {
    HideInCombat = false,
}

local defaults = {
    version = 4,
    debug = false,
    General = {
        showStatus = true,
        favScope = "account",
        favoritesVisibleCap = 20,
        recentWindow = 0,
        recentMax = 100,
        showCategoryCounts = true,
        showQuestCategoryCounts = true,
        showAchievementCategoryCounts = true,
        window = {
            left = 200,
            top = 200,
            width = 360,
            height = 640,
            locked = false,
        },
        features = {
            completed = true,
            favorites = true,
            recent = true,
            todo = true,
            tooltips = true,
        },
    },
    QuestTracker = {
        active = true,
        hideDefault = false,
        hideInCombat = false,
        lock = false,
        autoGrowV = true,
        autoGrowH = false,
        autoExpand = true,
        autoTrack = true,
        background = {
            enabled = true,
            alpha = 0.35,
            edgeAlpha = 0.5,
            padding = 8,
        },
        fonts = DEFAULT_QUEST_FONTS,
    },
    AchievementTracker = {
        active = true,
        lock = false,
        autoGrowV = true,
        autoGrowH = false,
        background = {
            enabled = true,
            alpha = 0.35,
            edgeAlpha = 0.5,
            padding = 8,
        },
        fonts = DEFAULT_ACHIEVEMENT_FONTS,
        tooltips = true,
        sections = {
            favorites = true,
            recent = true,
            completed = true,
            todo = true,
        },
    },
    appearance = DEFAULT_TRACKER_APPEARANCE,
    Settings = {
        Host = DEFAULT_HOST_SETTINGS,
    },
}

local function MergeDefaults(target, source)
    if type(source) ~= "table" then
        return target
    end

    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(source) do
        if type(value) == "table" then
            target[key] = MergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end

    return target
end

local function AdoptLegacySettings(saved)
    if type(saved) ~= "table" then
        return
    end

    saved.General = MergeDefaults(saved.General, defaults.General)

    if type(saved.ui) == "table" then
        saved.General.showStatus = (saved.ui.showStatus ~= false)
        saved.General.favScope = saved.ui.favScope or saved.General.favScope
        saved.General.recentWindow = saved.ui.recentWindow or saved.General.recentWindow
        saved.General.recentMax = saved.ui.recentMax or saved.General.recentMax
    end

    saved.General.features = MergeDefaults(saved.General.features, defaults.General.features)
    if type(saved.features) == "table" then
        for key, value in pairs(saved.features) do
            saved.General.features[key] = value
        end
    end

    saved.QuestTracker = MergeDefaults(saved.QuestTracker, defaults.QuestTracker)
    saved.AchievementTracker = MergeDefaults(saved.AchievementTracker, defaults.AchievementTracker)
    saved.appearance = MergeDefaults(saved.appearance, defaults.appearance)

    saved.ui = saved.General
    saved.features = saved.General.features
end

local function EnsureFirstLoginStructures(saved)
    local general = EnsureTable(saved, "General")
    MergeDefaults(general, defaults.General)
    MergeDefaults(EnsureTable(general, "features"), defaults.General.features)
    MergeDefaults(EnsureTable(general, "window"), defaults.General.window)
    EnsureTable(general, "Appearance")
    EnsureTable(general, "layout")
    EnsureTable(general, "WindowBars")

    local questTracker = EnsureTable(saved, "QuestTracker")
    MergeDefaults(questTracker, defaults.QuestTracker)
    MergeDefaults(EnsureTable(questTracker, "background"), defaults.QuestTracker.background)
    MergeDefaults(EnsureTable(questTracker, "fonts"), defaults.QuestTracker.fonts)

    local achievementTracker = EnsureTable(saved, "AchievementTracker")
    MergeDefaults(achievementTracker, defaults.AchievementTracker)
    MergeDefaults(EnsureTable(achievementTracker, "background"), defaults.AchievementTracker.background)
    MergeDefaults(EnsureTable(achievementTracker, "fonts"), defaults.AchievementTracker.fonts)
    MergeDefaults(EnsureTable(achievementTracker, "sections"), defaults.AchievementTracker.sections)

    local appearance = EnsureTable(saved, "appearance")
    MergeDefaults(appearance, defaults.appearance)
    EnsureTable(appearance, "questTracker")
    EnsureTable(appearance, "achievementTracker")

    local settings = EnsureTable(saved, "Settings")
    local hostSettings = EnsureTable(settings, "Host")
    if hostSettings.HideInCombat == nil then
        if saved.QuestTracker and saved.QuestTracker.hideInCombat ~= nil then
            hostSettings.HideInCombat = saved.QuestTracker.hideInCombat == true
        else
            hostSettings.HideInCombat = DEFAULT_HOST_SETTINGS.HideInCombat
        end
    else
        hostSettings.HideInCombat = hostSettings.HideInCombat == true
    end
    MergeDefaults(settings, defaults.Settings)
    MergeDefaults(hostSettings, defaults.Settings.Host)

    if saved.debug == nil then
        saved.debug = defaults.debug
    end
    if saved.version == nil then
        saved.version = defaults.version
    end
end

-- Create or load SavedVariables and ensure all required subtables/fields exist.
-- addonTable is expected to be the global addon table Nvk3UT.
-- Returns the SavedVariables table.
function Nvk3UT_StateInit.BootstrapSavedVariables(addonTable)
    if type(addonTable) ~= "table" then
        return nil
    end

    local sv = addonTable.SV
    if type(sv) ~= "table" then
        sv = ZO_SavedVars:NewAccountWide("Nvk3UT_SV", 2, nil, defaults)
        addonTable.SV = sv
    end

    AdoptLegacySettings(sv)
    EnsureFirstLoginStructures(sv)

    addonTable.SV = sv
    addonTable.sv = sv

    if type(addonTable.SetDebugEnabled) == "function" then
        addonTable:SetDebugEnabled(sv.debug)
    end

    if Nvk3UT_Diagnostics and Nvk3UT_Diagnostics.SyncFromSavedVariables then
        Nvk3UT_Diagnostics.SyncFromSavedVariables(sv)
    end

    return sv
end

return Nvk3UT_StateInit
