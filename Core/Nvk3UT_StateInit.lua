Nvk3UT_StateInit = Nvk3UT_StateInit or {}

local SCHEMA_VERSION = 3

local DEFAULT_FONT_FACE_BOLD = "$(BOLD_FONT)"
local DEFAULT_FONT_OUTLINE = "soft-shadow-thick"

local COLOR_PALETTE = {
    parchment = "#C5C29EFF",
    highlight = "#FFFF00FF",
    bright = "#FFFFFFFF",
}

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

local DEFAULT_UI = {
    showStatus = true,
    favScope = "account",
    recentWindow = 0,
    recentMax = 100,
    showCategoryCounts = true,
    showQuestCategoryCounts = true,
    showAchievementCategoryCounts = true,
    features = {
        completed = true,
        favorites = true,
        recent = true,
        todo = true,
        tooltips = true,
    },
    window = {
        left = 200,
        top = 200,
        width = 360,
        height = 640,
        locked = false,
    },
    layout = {},
    windowBars = {},
    questTracker = {
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
    achievementTracker = {
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
    appearance = {
        questTracker = {
            colors = {
                categoryTitle = "parchment",
                objectiveText = "parchment",
                entryTitle = "highlight",
                activeTitle = "bright",
            },
        },
        achievementTracker = {
            colors = {
                categoryTitle = "parchment",
                objectiveText = "parchment",
                entryTitle = "highlight",
                activeTitle = "bright",
            },
        },
    },
    host = {
        HideInCombat = false,
    },
}

local QUEST_CONFIG_KEYS = {
    active = true,
    hideDefault = true,
    hideInCombat = true,
    lock = true,
    autoGrowV = true,
    autoGrowH = true,
    autoExpand = true,
    autoTrack = true,
    background = true,
    fonts = true,
}

local ACHIEVEMENT_CONFIG_KEYS = {
    active = true,
    lock = true,
    autoGrowV = true,
    autoGrowH = true,
    background = true,
    fonts = true,
    tooltips = true,
    sections = true,
}

local ROOT_DEFAULTS = {
    schema = SCHEMA_VERSION,
    debug = false,
    ui = DEFAULT_UI,
}

local function copyTable(value)
    if type(value) ~= "table" then
        return value
    end

    local clone = {}
    for key, entry in pairs(value) do
        clone[key] = copyTable(entry)
    end
    return clone
end

local function round(value, places)
    if type(value) ~= "number" then
        return value
    end

    local multiplier = 10 ^ (places or 0)
    return math.floor(value * multiplier + 0.5) / multiplier
end

local function ensureTable(parent, key)
    if type(parent) ~= "table" then
        return {}
    end

    local child = parent[key]
    if type(child) ~= "table" then
        child = {}
        parent[key] = child
    end

    return child
end

local function encodeColor(r, g, b, a)
    local function clamp(component)
        component = tonumber(component) or 1
        if component < 0 then
            component = 0
        elseif component > 1 then
            component = 1
        end
        return component
    end

    local red = clamp(r)
    local green = clamp(g)
    local blue = clamp(b)
    local alpha = clamp(a)

    local function toHex(component)
        local channel = math.floor(component * 255 + 0.5)
        if channel < 0 then
            channel = 0
        elseif channel > 255 then
            channel = 255
        end
        return string.format("%02X", channel)
    end

    return string.format("#%s%s%s%s", toHex(red), toHex(green), toHex(blue), toHex(alpha))
end

local function normalizeColorEntry(entry, defaultKey)
    if type(entry) == "string" and entry ~= "" then
        return entry
    end

    if type(entry) == "table" then
        return encodeColor(entry.r, entry.g, entry.b, entry.a)
    end

    return defaultKey
end

local function normalizeBackground(target)
    if type(target) ~= "table" then
        target = {}
    end

    target.enabled = target.enabled ~= false
    target.alpha = round(tonumber(target.alpha) or DEFAULT_UI.questTracker.background.alpha, 2)
    target.edgeAlpha = round(tonumber(target.edgeAlpha) or DEFAULT_UI.questTracker.background.edgeAlpha, 2)
    target.padding = math.max(0, math.floor(tonumber(target.padding) or DEFAULT_UI.questTracker.background.padding))

    return target
end

local function normalizeFonts(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, fallback in pairs(defaults or {}) do
        local slot = target[key]
        if type(slot) ~= "table" then
            slot = {}
            target[key] = slot
        end

        slot.face = slot.face or fallback.face
        slot.size = tonumber(slot.size) or fallback.size
        slot.outline = slot.outline or fallback.outline
    end

    return target
end

local function mergeFlags(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(defaults or {}) do
        if target[key] == nil then
            target[key] = value and true or false
        else
            target[key] = target[key] and true or false
        end
    end

    return target
end

local function adoptLegacyAppearance(legacy)
    if type(legacy) ~= "table" then
        return nil
    end

    local appearance = {}
    for trackerType, defaults in pairs(DEFAULT_UI.appearance) do
        local tracker = {}
        appearance[trackerType] = tracker

        tracker.colors = {}
        local sourceTracker = legacy[trackerType]
        local sourceColors = sourceTracker and sourceTracker.colors

        for role, defaultKey in pairs(defaults.colors or {}) do
            local legacyColor = sourceColors and sourceColors[role]
            tracker.colors[role] = normalizeColorEntry(legacyColor, defaultKey)
        end
    end

    return appearance
end

local function normalizeAppearance(target)
    if type(target) ~= "table" then
        target = {}
    end

    for trackerType, defaults in pairs(DEFAULT_UI.appearance) do
        local tracker = ensureTable(target, trackerType)
        tracker.colors = tracker.colors or {}

        for role, defaultKey in pairs(defaults.colors or {}) do
            tracker.colors[role] = normalizeColorEntry(tracker.colors[role], defaultKey)
        end
    end

    return target
end

local function normalizeTrackerConfig(source, defaults, defaultFonts)
    source = type(source) == "table" and copyTable(source) or {}
    local normalized = {}

    normalized.active = source.active ~= false
    normalized.hideDefault = source.hideDefault == true
    normalized.hideInCombat = source.hideInCombat == true
    normalized.lock = source.lock == true
    normalized.autoGrowV = source.autoGrowV ~= false
    normalized.autoGrowH = source.autoGrowH == true
    normalized.autoExpand = source.autoExpand ~= false
    normalized.autoTrack = source.autoTrack ~= false

    normalized.background = normalizeBackground(source.background or {})
    normalized.fonts = normalizeFonts(source.fonts, defaultFonts)

    for key, defaultValue in pairs(defaults or {}) do
        if normalized[key] == nil then
            local value = source[key]
            if type(defaultValue) == "boolean" then
                normalized[key] = value ~= false
            elseif type(defaultValue) == "number" then
                normalized[key] = value ~= nil and value or defaultValue
            elseif normalized[key] == nil then
                normalized[key] = copyTable(defaultValue)
            end
        end
    end

    return normalized
end

local function normalizeUI(source)
    local ui = copyTable(DEFAULT_UI)

    if type(source) == "table" then
        for key, value in pairs(source) do
            if key ~= "features" and key ~= "questTracker" and key ~= "achievementTracker" and key ~= "appearance" and key ~= "host" then
                ui[key] = value
            end
        end

        if type(source.features) == "table" then
            ui.features = mergeFlags(source.features, DEFAULT_UI.features)
        end

        ui.questTracker = normalizeTrackerConfig(source.questTracker, DEFAULT_UI.questTracker, DEFAULT_QUEST_FONTS)
        ui.achievementTracker = normalizeTrackerConfig(source.achievementTracker, DEFAULT_UI.achievementTracker, DEFAULT_ACHIEVEMENT_FONTS)
        ui.appearance = normalizeAppearance(source.appearance)

        if type(source.host) == "table" then
            ui.host = {
                HideInCombat = source.host.HideInCombat == true,
            }
        end
    end

    ui.features = mergeFlags(ui.features, DEFAULT_UI.features)
    ui.appearance = normalizeAppearance(ui.appearance)
    ui.host = ui.host or copyTable(DEFAULT_UI.host)

    if ui.window then
        ui.window.locked = ui.window.locked == true
        ui.window.width = math.max(120, math.floor(tonumber(ui.window.width) or DEFAULT_UI.window.width))
        ui.window.height = math.max(120, math.floor(tonumber(ui.window.height) or DEFAULT_UI.window.height))
        ui.window.left = math.floor(tonumber(ui.window.left) or DEFAULT_UI.window.left)
        ui.window.top = math.floor(tonumber(ui.window.top) or DEFAULT_UI.window.top)
    end

    if ui.windowBars then
        for key, value in pairs(ui.windowBars) do
            local numeric = tonumber(value)
            if numeric then
                ui.windowBars[key] = math.max(0, math.floor(numeric))
            else
                ui.windowBars[key] = nil
            end
        end
    end

    return ui
end

local function migrateLegacy(saved)
    if type(saved) ~= "table" then
        return copyTable(ROOT_DEFAULTS)
    end

    local ui = saved.ui or saved.General or {}
    local questTracker = saved.QuestTracker or {}
    local achievementTracker = saved.AchievementTracker or {}

    if type(saved.questState) ~= "table" then
        local questState = copyTable(questTracker)
        for key in pairs(QUEST_CONFIG_KEYS) do
            questState[key] = nil
        end
        saved.questState = questState
    end

    local appearance = saved.appearance or {}
    if not ui.appearance then
        ui.appearance = adoptLegacyAppearance(appearance) or copyTable(DEFAULT_UI.appearance)
    end

    ui.questTracker = ui.questTracker or questTracker
    ui.achievementTracker = ui.achievementTracker or achievementTracker
    ui.host = ui.host or ((saved.Settings and saved.Settings.Host) or {})

    local normalized = normalizeUI(ui)

    saved.schema = SCHEMA_VERSION
    saved.version = nil
    saved.General = nil
    saved.features = nil
    saved.QuestTracker = nil
    saved.AchievementTracker = nil
    saved.appearance = nil
    saved.Settings = nil
    saved.ui = normalized

    return saved
end

local function ensureSchema(saved)
    if type(saved) ~= "table" then
        saved = copyTable(ROOT_DEFAULTS)
    end

    local schema = tonumber(saved.schema)
    if schema ~= SCHEMA_VERSION then
        saved = migrateLegacy(saved)
    end

    saved.ui = normalizeUI(saved.ui)
    if type(saved.questState) ~= "table" then
        saved.questState = {}
    end
    saved.schema = SCHEMA_VERSION

    return saved
end

local function buildLegacyBridge(saved)
    local function getUi()
        return saved.ui
    end

    local function getAchievementTrackerConfig()
        return saved.ui and saved.ui.achievementTracker
    end

    local function getAppearance()
        return saved.ui and saved.ui.appearance
    end

    local function getFeatures()
        local ui = getUi()
        return ui and ui.features
    end

    local function getQuestState()
        if type(saved.questState) ~= "table" then
            saved.questState = {}
        end
        return saved.questState
    end

    local questTrackerProxy = nil

    local function getQuestTrackerProxy()
        if not questTrackerProxy then
            questTrackerProxy = setmetatable({}, {
                __index = function(_, key)
                    local questState = getQuestState()
                    if questState[key] ~= nil then
                        return questState[key]
                    end
                    local currentUi = getUi()
                    local configTable = currentUi and currentUi.questTracker or {}
                    return configTable[key]
                end,
                __newindex = function(_, key, value)
                    if QUEST_CONFIG_KEYS[key] then
                        local currentUi = getUi()
                        if currentUi and currentUi.questTracker then
                            currentUi.questTracker[key] = value
                            saved.ui = normalizeUI(currentUi)
                        end
                    else
                        local questState = getQuestState()
                        questState[key] = value
                    end
                end,
                __pairs = function()
                    local combined = {}
                    local questState = getQuestState()
                    for key, value in pairs(questState) do
                        combined[key] = value
                    end
                    local currentUi = getUi()
                    local configTable = currentUi and currentUi.questTracker or {}
                    for key, value in pairs(configTable) do
                        if combined[key] == nil then
                            combined[key] = value
                        end
                    end
                    return next, combined, nil
                end,
            })
        end

        return questTrackerProxy
    end

    local legacySettingsProxy = nil

    local function getSettings()
        local ui = getUi()
        local host = ui and ui.host or {}
        if not legacySettingsProxy then
            legacySettingsProxy = {}
        end
        legacySettingsProxy.Host = host
        return legacySettingsProxy
    end

    local legacy = {
        General = {
            getter = getUi,
            setter = function(value)
                saved.ui = normalizeUI(value)
            end,
        },
        features = {
            getter = getFeatures,
            setter = function(value)
                local ui = saved.ui or {}
                ui.features = mergeFlags(value, DEFAULT_UI.features)
                saved.ui = normalizeUI(ui)
            end,
        },
        QuestTracker = {
            getter = getQuestTrackerProxy,
            setter = function(value)
                if type(value) ~= "table" then
                    return
                end

                local ui = saved.ui or {}
                ui.questTracker = normalizeTrackerConfig(value, DEFAULT_UI.questTracker, DEFAULT_QUEST_FONTS)
                saved.ui = normalizeUI(ui)

                local state = getQuestState()
                for key in pairs(state) do
                    state[key] = nil
                end
                for key, entry in pairs(value) do
                    if not QUEST_CONFIG_KEYS[key] then
                        state[key] = copyTable(entry)
                    end
                end
            end,
        },
        AchievementTracker = {
            getter = getAchievementTrackerConfig,
            setter = function(value)
                local ui = saved.ui or {}
                ui.achievementTracker = normalizeTrackerConfig(value, DEFAULT_UI.achievementTracker, DEFAULT_ACHIEVEMENT_FONTS)
                saved.ui = normalizeUI(ui)
            end,
        },
        appearance = {
            getter = getAppearance,
            setter = function(value)
                local ui = saved.ui or {}
                ui.appearance = normalizeAppearance(value)
                saved.ui = normalizeUI(ui)
            end,
        },
        Settings = {
            getter = getSettings,
            setter = function(value)
                local host = value
                if type(value) == "table" then
                    host = value.Host or value.host or value
                end

                local ui = saved.ui or {}
                ui.host = {
                    HideInCombat = type(host) == "table" and host.HideInCombat == true,
                }
                saved.ui = normalizeUI(ui)
            end,
        },
    }

    setmetatable(saved, {
        __index = function(_, key)
            local descriptor = legacy[key]
            if descriptor and descriptor.getter then
                return descriptor.getter()
            end

            return rawget(saved, key)
        end,
        __newindex = function(_, key, value)
            local descriptor = legacy[key]
            if descriptor and descriptor.setter then
                descriptor.setter(value)
                return
            end

            rawset(saved, key, value)
        end,
    })
end

local function ensureDefaults(saved)
    if saved.debug == nil then
        saved.debug = false
    else
        saved.debug = saved.debug == true
    end
end

local function ensureLibDefaults()
    -- Placeholder for LibSavedVars trimming integration.
end

function Nvk3UT_StateInit.BootstrapSavedVariables(addonTable)
    if type(addonTable) ~= "table" then
        return nil
    end

    local sv = addonTable.SV
    if type(sv) ~= "table" then
        sv = ZO_SavedVars:NewAccountWide("Nvk3UT_SV", SCHEMA_VERSION, nil, ROOT_DEFAULTS)
        addonTable.SV = sv
    end

    sv = ensureSchema(sv)
    ensureDefaults(sv)
    buildLegacyBridge(sv)
    ensureLibDefaults()

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
