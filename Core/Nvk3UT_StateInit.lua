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

local function isDebugEnabled(addonTable)
    local utils = (addonTable and addonTable.Utils) or (Nvk3UT and Nvk3UT.Utils) or Nvk3UT_Utils
    if utils and type(utils.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(utils.IsDebugEnabled)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local diagnostics = (addonTable and addonTable.Diagnostics) or (Nvk3UT and Nvk3UT.Diagnostics) or Nvk3UT_Diagnostics
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return diagnostics:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local root = addonTable or Nvk3UT
    if type(root) == "table" and type(root.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return root:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local sv = root and (root.sv or root.SV)
    if type(sv) == "table" and sv.debug ~= nil then
        return sv.debug == true
    end

    return false
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

local function CopyColor(color)
    if type(color) ~= "table" then
        return { r = 1, g = 1, b = 1, a = 1 }
    end

    return {
        r = color.r or 1,
        g = color.g or 1,
        b = color.b or 1,
        a = color.a or 1,
    }
end

local COLOR_CATEGORY = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 }
local COLOR_ENTRY = { r = 1, g = 1, b = 0, a = 1 }
local COLOR_ACTIVE = { r = 1, g = 1, b = 1, a = 1 }
local COLOR_COMPLETED = { r = 0.6, g = 0.6, b = 0.6, a = 1 }

local DEFAULT_TRACKER_APPEARANCE = {
    questTracker = {
        colors = {
            categoryTitle = CopyColor(COLOR_CATEGORY),
            objectiveText = CopyColor(COLOR_CATEGORY),
            entryTitle = CopyColor(COLOR_ENTRY),
            activeTitle = CopyColor(COLOR_ACTIVE),
        },
    },
    achievementTracker = {
        colors = {
            categoryTitle = CopyColor(COLOR_CATEGORY),
            objectiveText = CopyColor(COLOR_CATEGORY),
            entryTitle = CopyColor(COLOR_ENTRY),
            activeTitle = CopyColor(COLOR_ACTIVE),
        },
    },
    endeavorTracker = {
        colors = {
            categoryTitle = CopyColor(COLOR_CATEGORY),
            objectiveText = CopyColor(COLOR_CATEGORY),
            entryTitle = CopyColor(COLOR_ENTRY),
            activeTitle = CopyColor(COLOR_ACTIVE),
            completed = CopyColor(COLOR_COMPLETED),
        },
    },
}

local DEFAULT_ENDEAVOR_SETTINGS = {
    Enabled = true,
    ShowCountsInHeaders = true,
    CompletedHandling = "hide",
    Colors = {
        CategoryTitle = CopyColor(COLOR_CATEGORY),
        EntryName = CopyColor(COLOR_ENTRY),
        Objective = CopyColor(COLOR_CATEGORY),
        Active = CopyColor(COLOR_ACTIVE),
        Completed = CopyColor(COLOR_COMPLETED),
    },
    Font = {
        Family = DEFAULT_FONT_FACE_BOLD,
        Size = DEFAULT_ACHIEVEMENT_FONTS.title.size,
        Outline = DEFAULT_FONT_OUTLINE,
    },
}

local DEFAULT_ENDEAVOR_DATA = {
    expanded = true,
    position = { x = nil, y = nil },
    window = { locked = false },
    categories = {},
    lastRefresh = 0,
}

local DEFAULT_HOST_SETTINGS = {
    HideInCombat = false,
}

local DEFAULT_ACHIEVEMENT_CACHE = {
    buildHash = "",
    lastBuildAt = 0,
    categories = {
        Favorites = {},
        Recent = {},
        Completed = {},
        ToDo = {},
    },
}

local defaults = {
    version = 4,
    debug = false,
    General = {
        showStatus = true,
        favScope = "account",
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
    AchievementCache = DEFAULT_ACHIEVEMENT_CACHE,
    EndeavorData = DEFAULT_ENDEAVOR_DATA,
    Endeavor = DEFAULT_ENDEAVOR_SETTINGS,
}

local ENDEAVOR_COLOR_ROLE_MAPPING = {
    CategoryTitle = "categoryTitle",
    EntryName = "entryTitle",
    Objective = "objectiveText",
    Active = "activeTitle",
    Completed = "completed",
}

local function NormalizeColorComponent(value, fallback)
    local numeric = tonumber(value)
    if numeric == nil then
        numeric = fallback ~= nil and fallback or 1
    end
    if numeric < 0 then
        numeric = 0
    elseif numeric > 1 then
        numeric = 1
    end
    return numeric
end

local function EnsureEndeavorSettings(saved)
    if type(saved) ~= "table" then
        return nil
    end

    local endeavor = EnsureTable(saved, "Endeavor")
    MergeDefaults(endeavor, defaults.Endeavor)

    local legacyTracker = saved.EndeavorTracker

    if endeavor.Enabled == nil then
        if type(legacyTracker) == "table" and legacyTracker.active ~= nil then
            endeavor.Enabled = legacyTracker.active ~= false
        else
            local achievement = saved.AchievementTracker
            if type(achievement) == "table" and achievement.active ~= nil then
                endeavor.Enabled = achievement.active ~= false
            else
                endeavor.Enabled = defaults.Endeavor.Enabled
            end
        end
    else
        endeavor.Enabled = endeavor.Enabled ~= false
    end

    if endeavor.ShowCountsInHeaders == nil then
        local general = saved.General or {}
        local fallback = general.showAchievementCategoryCounts
        if fallback == nil then
            fallback = defaults.General.showAchievementCategoryCounts
        end
        endeavor.ShowCountsInHeaders = fallback ~= false
    else
        endeavor.ShowCountsInHeaders = endeavor.ShowCountsInHeaders ~= false
    end

    if type(endeavor.CompletedHandling) ~= "string" then
        endeavor.CompletedHandling = defaults.Endeavor.CompletedHandling
    else
        local normalized = string.lower(endeavor.CompletedHandling)
        if normalized ~= "recolor" then
            endeavor.CompletedHandling = "hide"
        else
            endeavor.CompletedHandling = "recolor"
        end
    end

    local colors = EnsureTable(endeavor, "Colors")
    local appearance = EnsureTable(saved, "appearance")
    local trackerAppearance = EnsureTable(appearance, "endeavorTracker")
    trackerAppearance.colors = trackerAppearance.colors or {}

    for configKey, role in pairs(ENDEAVOR_COLOR_ROLE_MAPPING) do
        local defaultColor = defaults.Endeavor.Colors[configKey]
        local color = EnsureTable(colors, configKey)
        local appearanceColor = trackerAppearance.colors[role]

        if type(appearanceColor) == "table" then
            color.r = NormalizeColorComponent(color.r or appearanceColor.r, defaultColor.r)
            color.g = NormalizeColorComponent(color.g or appearanceColor.g, defaultColor.g)
            color.b = NormalizeColorComponent(color.b or appearanceColor.b, defaultColor.b)
            color.a = NormalizeColorComponent(color.a or appearanceColor.a, defaultColor.a)
        else
            color.r = NormalizeColorComponent(color.r, defaultColor.r)
            color.g = NormalizeColorComponent(color.g, defaultColor.g)
            color.b = NormalizeColorComponent(color.b, defaultColor.b)
            color.a = NormalizeColorComponent(color.a, defaultColor.a)
        end

        trackerAppearance.colors[role] = {
            r = color.r,
            g = color.g,
            b = color.b,
            a = color.a,
        }
    end

    local font = EnsureTable(endeavor, "Font")
    if type(font.Family) ~= "string" or font.Family == "" then
        font.Family = defaults.Endeavor.Font.Family
    end

    local size = tonumber(font.Size)
    if size == nil then
        size = defaults.Endeavor.Font.Size
    end
    size = math.floor(size + 0.5)
    if size < 12 then
        size = 12
    elseif size > 36 then
        size = 36
    end
    font.Size = size

    if type(font.Outline) ~= "string" or font.Outline == "" then
        font.Outline = defaults.Endeavor.Font.Outline
    end

    return endeavor
end

local function EnsureAchievementCache(saved)
    local cache = EnsureTable(saved, "AchievementCache")
    if cache.buildHash == nil then
        cache.buildHash = ""
    end
    if cache.lastBuildAt == nil then
        cache.lastBuildAt = 0
    end

    local categories = EnsureTable(cache, "categories")
    local favorites = EnsureTable(categories, "Favorites")
    local recent = EnsureTable(categories, "Recent")
    local completed = EnsureTable(categories, "Completed")
    local todoPrimary = EnsureTable(categories, "Todo")
    local todoAlternate = EnsureTable(categories, "ToDo")

    -- Keep Favorites/Recent/Completed references alive even if unused to avoid
    -- accidental nil assignments by callers expecting tables.
    favorites = favorites
    recent = recent
    completed = completed

    if todoAlternate ~= todoPrimary then
        if next(todoAlternate) ~= nil and next(todoPrimary) == nil then
            todoPrimary = todoAlternate
        elseif next(todoAlternate) ~= nil and next(todoPrimary) ~= nil then
            for key, value in pairs(todoAlternate) do
                if todoPrimary[key] == nil then
                    todoPrimary[key] = value
                end
            end
        end
    end

    categories.Todo = todoPrimary
    categories.ToDo = todoPrimary

    return cache
end

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

local function EnsureEndeavorData(saved, safeCall)
    if type(saved) ~= "table" then
        return false
    end

    local endeavor = saved.EndeavorData
    local needsMerge = type(endeavor) ~= "table"

    if not needsMerge then
        if endeavor.expanded == nil then
            needsMerge = true
        end
        if type(endeavor.position) ~= "table" then
            needsMerge = true
        end
        if type(endeavor.window) ~= "table" then
            needsMerge = true
        end
        if type(endeavor.categories) ~= "table" then
            needsMerge = true
        end
        if endeavor.lastRefresh == nil then
            needsMerge = true
        end
    end

    local function applyDefaults()
        local target = EnsureTable(saved, "EndeavorData")
        MergeDefaults(target, DEFAULT_ENDEAVOR_DATA)
        EnsureTable(target, "position")
        local window = EnsureTable(target, "window")
        EnsureTable(target, "categories")

        if target.expanded == nil then
            target.expanded = DEFAULT_ENDEAVOR_DATA.expanded
        end

        if window.locked == nil then
            window.locked = DEFAULT_ENDEAVOR_DATA.window.locked
        end

        if target.lastRefresh == nil then
            target.lastRefresh = DEFAULT_ENDEAVOR_DATA.lastRefresh
        end

        return true
    end

    local initialized = false
    if needsMerge then
        if type(safeCall) == "function" then
            initialized = safeCall(applyDefaults) and true or false
        else
            initialized = applyDefaults()
        end
    else
        applyDefaults()
    end

    return initialized
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

    EnsureEndeavorSettings(saved)

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
    EnsureEndeavorSettings(saved)
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

    EnsureAchievementCache(saved)
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

    local safeCall = addonTable and addonTable.SafeCall
    if not safeCall and Nvk3UT and type(Nvk3UT.SafeCall) == "function" then
        safeCall = Nvk3UT.SafeCall
    end

    local endeavorInitialized = EnsureEndeavorData(sv, safeCall)

    addonTable.SV = sv
    addonTable.sv = sv

    if type(addonTable.SetDebugEnabled) == "function" then
        addonTable:SetDebugEnabled(sv.debug)
    end

    local debugActive = isDebugEnabled(addonTable)

    if endeavorInitialized and debugActive and type(addonTable.Debug) == "function" then
        addonTable.Debug("Initialized EndeavorData defaults")
    elseif endeavorInitialized and debugActive and d then
        d("[Nvk3UT DEBUG] Initialized EndeavorData defaults")
    end

    if Nvk3UT_Diagnostics and Nvk3UT_Diagnostics.SyncFromSavedVariables then
        Nvk3UT_Diagnostics.SyncFromSavedVariables(sv)
    end

    return sv
end

return Nvk3UT_StateInit
