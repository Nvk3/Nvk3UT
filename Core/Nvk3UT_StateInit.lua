-- Core/Nvk3UT_StateInit.lua
-- SavedVariables bootstrap, schema migrations, and facade helpers for Nvk3UT.

local addonName = "Nvk3UT"

Nvk3UT_StateInit = Nvk3UT_StateInit or {}
local StateInit = Nvk3UT_StateInit

local SCHEMA_VERSION = 3
StateInit.SCHEMA_VERSION = SCHEMA_VERSION

local LibSavedVars = LibSavedVars

local COLOR_PALETTE = {
    warmKhaki = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
    brightYellow = { r = 1, g = 1, b = 0, a = 1 },
    pureWhite = { r = 1, g = 1, b = 1, a = 1 },
}

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

local QUEST_TRACKER_SETTING_KEYS = {
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

local QUEST_STATE_KEYS = {
    cat = true,
    quest = true,
    defaults = true,
    active = true,
    initializedAt = true,
    stateVersion = true,
}

local ACCOUNT_DEFAULTS = {
    schema = SCHEMA_VERSION,
    debug = false,
    ui = {
        showStatus = true,
        favorites = { scope = "account" },
        recents = { window = 0, max = 100 },
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
        Appearance = {},
        layout = {},
        WindowBars = {},
        features = {
            completed = true,
            favorites = true,
            recent = true,
            todo = true,
            tooltips = true,
        },
        trackers = {
            quest = {
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
            achievement = {
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
        },
        appearance = {
            questTracker = {
                colors = {
                    categoryTitle = "warmKhaki",
                    objectiveText = "warmKhaki",
                    entryTitle = "brightYellow",
                    activeTitle = "pureWhite",
                },
            },
            achievementTracker = {
                colors = {
                    categoryTitle = "warmKhaki",
                    objectiveText = "warmKhaki",
                    entryTitle = "brightYellow",
                    activeTitle = "pureWhite",
                },
            },
        },
        host = {
            hideInCombat = false,
        },
    },
}

local CHARACTER_DEFAULTS = {
    schema = SCHEMA_VERSION,
    questState = {
        stateVersion = 1,
        cat = {},
        quest = {},
        defaults = {
            categoryExpanded = true,
            questExpanded = true,
        },
        active = {
            questKey = nil,
            source = "init",
            ts = 0,
        },
        initializedAt = 0,
    },
    questSelection = {
        active = {
            questKey = nil,
            source = "init",
            ts = 0,
        },
    },
}

local function CopyTableDeep(source)
    if type(source) ~= "table" then
        return source
    end

    local copy = {}
    for key, value in pairs(source) do
        copy[key] = CopyTableDeep(value)
    end
    return copy
end

local function OverwriteTable(target, source)
    for key in pairs(target) do
        target[key] = nil
    end
    for key, value in pairs(source) do
        target[key] = value
    end
end

local function NormalizeBoolean(value, defaultValue)
    if value == nil then
        return defaultValue or false
    end
    return value and true or false
end

local function NormalizeNumber(value, defaultValue)
    if type(value) == "number" then
        return value
    end
    local numeric = tonumber(value)
    if numeric ~= nil then
        return numeric
    end
    return defaultValue
end

local function NormalizeString(value, defaultValue)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return defaultValue
end

local function NormalizePaletteKey(colorTable)
    if type(colorTable) == "string" then
        return colorTable
    end

    if type(colorTable) == "table" then
        local r = NormalizeNumber(colorTable.r)
        local g = NormalizeNumber(colorTable.g)
        local b = NormalizeNumber(colorTable.b)
        local a = NormalizeNumber(colorTable.a, 1)

        for paletteKey, entry in pairs(COLOR_PALETTE) do
            if math.abs((entry.r or 0) - (r or 0)) < 0.0001
                and math.abs((entry.g or 0) - (g or 0)) < 0.0001
                and math.abs((entry.b or 0) - (b or 0)) < 0.0001
                and math.abs((entry.a or 0) - (a or 1)) < 0.0001 then
                return paletteKey
            end
        end

        local function clampHex(component)
            component = component or 0
            component = math.max(0, math.min(1, component))
            return math.floor(component * 255 + 0.5)
        end

        return string.format("#%02X%02X%02X%02X", clampHex(r), clampHex(g), clampHex(b), clampHex(a))
    end

    return "warmKhaki"
end

local function ApplyTrackerSettings(target, source)
    target = target or {}
    source = type(source) == "table" and source or {}

    target.active = NormalizeBoolean(source.active, target.active)
    target.hideDefault = NormalizeBoolean(source.hideDefault, target.hideDefault)
    target.hideInCombat = NormalizeBoolean(source.hideInCombat, target.hideInCombat)
    target.lock = NormalizeBoolean(source.lock, target.lock)
    target.autoGrowV = NormalizeBoolean(source.autoGrowV, target.autoGrowV)
    target.autoGrowH = NormalizeBoolean(source.autoGrowH, target.autoGrowH)
    target.autoExpand = NormalizeBoolean(source.autoExpand, target.autoExpand)
    target.autoTrack = NormalizeBoolean(source.autoTrack, target.autoTrack)

    target.background = target.background or {}
    local background = type(source.background) == "table" and source.background or {}
    target.background.enabled = NormalizeBoolean(background.enabled, target.background.enabled)
    target.background.alpha = NormalizeNumber(background.alpha, target.background.alpha)
    target.background.edgeAlpha = NormalizeNumber(background.edgeAlpha, target.background.edgeAlpha)
    target.background.padding = NormalizeNumber(background.padding, target.background.padding)

    target.fonts = target.fonts or {}
    local fonts = type(source.fonts) == "table" and source.fonts or {}
    for key, font in pairs(DEFAULT_QUEST_FONTS) do
        local fontSource = type(fonts[key]) == "table" and fonts[key] or {}
        target.fonts[key] = target.fonts[key] or {}
        target.fonts[key].face = NormalizeString(fontSource.face, font.face)
        target.fonts[key].size = NormalizeNumber(fontSource.size, font.size)
        target.fonts[key].outline = NormalizeString(fontSource.outline, font.outline)
    end

    if type(source.sections) == "table" then
        target.sections = target.sections or {}
        for section, _ in pairs(source.sections) do
            target.sections[section] = NormalizeBoolean(source.sections[section], target.sections[section])
        end
    end

    if source.tooltips ~= nil then
        target.tooltips = NormalizeBoolean(source.tooltips, target.tooltips)
    end

    return target
end

local function BuildAppearanceColors(source)
    local colors = {}
    for role, paletteKey in pairs(source or {}) do
        colors[role] = NormalizePaletteKey(paletteKey)
    end
    return colors
end

local function BuildAppearanceDefaults()
    return CopyTableDeep(ACCOUNT_DEFAULTS.ui.appearance)
end

local function MigrateAccountSavedVars(saved)
    saved = type(saved) == "table" and saved or {}

    local migrated = CopyTableDeep(ACCOUNT_DEFAULTS)
    local ui = migrated.ui

    local general = type(saved.General) == "table" and saved.General or {}
    local features = type(general.features) == "table" and general.features or {}
    local rootFeatures = type(saved.features) == "table" and saved.features or {}

    ui.showStatus = NormalizeBoolean(general.showStatus, ui.showStatus)
    ui.favorites.scope = NormalizeString(general.favScope, ui.favorites.scope)
    ui.recents.window = NormalizeNumber(general.recentWindow, ui.recents.window)
    ui.recents.max = NormalizeNumber(general.recentMax, ui.recents.max)
    ui.showCategoryCounts = NormalizeBoolean(general.showCategoryCounts, ui.showCategoryCounts)
    ui.showQuestCategoryCounts = NormalizeBoolean(general.showQuestCategoryCounts, ui.showQuestCategoryCounts)
    ui.showAchievementCategoryCounts = NormalizeBoolean(general.showAchievementCategoryCounts, ui.showAchievementCategoryCounts)

    ui.window.left = NormalizeNumber(general.window and general.window.left, ui.window.left)
    ui.window.top = NormalizeNumber(general.window and general.window.top, ui.window.top)
    ui.window.width = NormalizeNumber(general.window and general.window.width, ui.window.width)
    ui.window.height = NormalizeNumber(general.window and general.window.height, ui.window.height)
    ui.window.locked = NormalizeBoolean(general.window and general.window.locked, ui.window.locked)

    for key, defaultValue in pairs(ui.features) do
        local value = features[key]
        if value == nil then
            value = rootFeatures[key]
        end
        ui.features[key] = NormalizeBoolean(value, defaultValue)
    end

    local questTracker = ApplyTrackerSettings(ui.trackers.quest, saved.QuestTracker)
    questTracker.hideInCombat = NormalizeBoolean(saved.Settings and saved.Settings.Host and saved.Settings.Host.HideInCombat, questTracker.hideInCombat)
    ui.host.hideInCombat = questTracker.hideInCombat

    ui.trackers.achievement = ApplyTrackerSettings(ui.trackers.achievement, saved.AchievementTracker)

    local appearanceSource = type(saved.appearance) == "table" and saved.appearance or {}
    local questAppearance = type(appearanceSource.questTracker) == "table" and appearanceSource.questTracker or {}
    local achievementAppearance = type(appearanceSource.achievementTracker) == "table" and appearanceSource.achievementTracker or {}

    ui.appearance.questTracker = ui.appearance.questTracker or {}
    ui.appearance.questTracker.colors = BuildAppearanceColors(questAppearance.colors)

    ui.appearance.achievementTracker = ui.appearance.achievementTracker or {}
    ui.appearance.achievementTracker.colors = BuildAppearanceColors(achievementAppearance.colors)

    migrated.debug = NormalizeBoolean(saved.debug, migrated.debug)

    return migrated
end

local function NormalizeQuestStateEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local normalized = {
        expanded = NormalizeBoolean(entry.expanded, false),
        source = NormalizeString(entry.source, "init"),
        ts = NormalizeNumber(entry.ts, 0),
    }

    return normalized
end

local function MigrateQuestState(saved)
    local questTracker = type(saved.QuestTracker) == "table" and saved.QuestTracker or {}
    local migrated = CopyTableDeep(CHARACTER_DEFAULTS.questState)

    migrated.stateVersion = NormalizeNumber(questTracker.stateVersion, migrated.stateVersion)
    migrated.initializedAt = NormalizeNumber(questTracker.initializedAt, migrated.initializedAt)

    migrated.defaults.categoryExpanded = NormalizeBoolean(
        questTracker.defaults and questTracker.defaults.categoryExpanded,
        migrated.defaults.categoryExpanded
    )
    migrated.defaults.questExpanded = NormalizeBoolean(
        questTracker.defaults and questTracker.defaults.questExpanded,
        migrated.defaults.questExpanded
    )

    local function normalizeCollection(source)
        local collection = {}
        if type(source) == "table" then
            for key, entry in pairs(source) do
                local normalizedKey = tostring(key)
                local normalizedEntry = NormalizeQuestStateEntry(entry)
                if normalizedKey ~= nil and normalizedEntry ~= nil then
                    collection[normalizedKey] = normalizedEntry
                end
            end
        end
        return collection
    end

    migrated.cat = normalizeCollection(questTracker.cat or questTracker.catExpanded)
    migrated.quest = normalizeCollection(questTracker.quest or questTracker.questExpanded)

    local active = NormalizeQuestStateEntry(questTracker.active) or CopyTableDeep(CHARACTER_DEFAULTS.questState.active)
    migrated.active = active

    return migrated
end

local function MigrateQuestSelection(saved)
    local questTracker = type(saved.QuestTracker) == "table" and saved.QuestTracker or {}
    local migrated = CopyTableDeep(CHARACTER_DEFAULTS.questSelection)

    local active = NormalizeQuestStateEntry(questTracker.active)
    if active then
        migrated.active = active
    end

    return migrated
end

local function EnsureSchema(target, defaults)
    if type(target) ~= "table" then
        return CopyTableDeep(defaults)
    end

    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = EnsureSchema(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end

    return target
end

local function BuildQuestTrackerFacade(account, character)
    local questSettings = account.ui.trackers.quest
    local questState = character.questState
    local questSelection = character.questSelection

    if type(questSelection) ~= "table" then
        questSelection = {}
        character.questSelection = questSelection
    end

    if type(questSelection.active) == "table" then
        questState.active = questSelection.active
    elseif type(questState.active) == "table" then
        questSelection.active = questState.active
    end

    local facade = {}

    facade._nvkSettings = questSettings
    facade._nvkState = questState
    facade._nvkIsQuestTrackerFacade = true

    return setmetatable(facade, {
        __index = function(_, key)
            if QUEST_STATE_KEYS[key] then
                return questState[key]
            end
            if QUEST_TRACKER_SETTING_KEYS[key] then
                return questSettings[key]
            end
            if key == "fonts" then
                return questSettings.fonts
            end
            if key == "background" then
                return questSettings.background
            end
            return questSettings[key]
        end,
        __newindex = function(_, key, value)
            if QUEST_STATE_KEYS[key] then
                questState[key] = value
                return
            end
            questSettings[key] = value
        end,
    })
end

local function BuildAchievementTrackerFacade(account)
    local settings = account.ui.trackers.achievement
    local facade = {}

    facade._nvkSettings = settings

    return setmetatable(facade, {
        __index = function(_, key)
            return settings[key]
        end,
        __newindex = function(_, key, value)
            settings[key] = value
        end,
    })
end

local function BuildFacade(account, character)
    local facade = {}

    rawset(facade, "ui", account.ui)
    rawset(facade, "General", account.ui)
    rawset(facade, "features", account.ui.features)
    rawset(facade, "appearance", account.ui.appearance)
    rawset(facade, "Settings", { Host = account.ui.host })

    local questTrackerFacade = BuildQuestTrackerFacade(account, character)
    rawset(facade, "QuestTracker", questTrackerFacade)

    local achievementTrackerFacade = BuildAchievementTrackerFacade(account)
    rawset(facade, "AchievementTracker", achievementTrackerFacade)

    facade._nvkAccount = account
    facade._nvkCharacter = character

    return setmetatable(facade, {
        __index = function(self, key)
            if key == "debug" then
                return account.debug
            end
            return rawget(self, key)
        end,
        __newindex = function(self, key, value)
            if key == "debug" then
                account.debug = value and true or false
                rawset(self, "debug", account.debug)
                return
            end

            if key == "ui" or key == "General" then
                if type(value) == "table" then
                    account.ui = value
                    rawset(self, "ui", value)
                    rawset(self, "General", value)
                end
                return
            end

            if key == "features" then
                if type(value) == "table" then
                    account.ui.features = value
                    rawset(self, "features", value)
                end
                return
            end

            if key == "appearance" then
                if type(value) == "table" then
                    account.ui.appearance = value
                    rawset(self, "appearance", value)
                end
                return
            end

            if key == "Settings" then
                if type(value) == "table" and type(value.Host) == "table" then
                    account.ui.host = value.Host
                end
                rawset(self, "Settings", { Host = account.ui.host })
                return
            end

            if key == "QuestTracker" or key == "AchievementTracker" then
                -- Preserve the facade instances; ignore external overrides to avoid schema drift.
                return
            end

            rawset(self, key, value)
        end,
    })
end

local function AcquireAccountSavedVars()
    if LibSavedVars and LibSavedVars.NewAccountWide then
        local ok, saved = pcall(LibSavedVars.NewAccountWide, LibSavedVars, "Nvk3UT_SV", SCHEMA_VERSION, CopyTableDeep(ACCOUNT_DEFAULTS))
        if ok and saved then
            if saved.UseDefaultsTrimming then
                saved:UseDefaultsTrimming(true)
            end
            return saved
        end
    end

    return ZO_SavedVars:NewAccountWide("Nvk3UT_SV", SCHEMA_VERSION, nil, CopyTableDeep(ACCOUNT_DEFAULTS))
end

local function AcquireCharacterSavedVars()
    if LibSavedVars and LibSavedVars.NewCharacterIdSettings then
        local ok, saved = pcall(LibSavedVars.NewCharacterIdSettings, LibSavedVars, "Nvk3UT_SV", SCHEMA_VERSION, nil, CopyTableDeep(CHARACTER_DEFAULTS))
        if ok and saved then
            if saved.UseDefaultsTrimming then
                saved:UseDefaultsTrimming(true)
            end
            return saved
        end
    end

    return ZO_SavedVars:NewCharacterIdSettings("Nvk3UT_SV", SCHEMA_VERSION, nil, CopyTableDeep(CHARACTER_DEFAULTS))
end

local function RunMigration(accountSV, characterSV)
    local schema = tonumber(accountSV.schema)
    if schema == SCHEMA_VERSION then
        EnsureSchema(accountSV.ui, ACCOUNT_DEFAULTS.ui)
        EnsureSchema(characterSV.questState, CHARACTER_DEFAULTS.questState)
        EnsureSchema(characterSV.questSelection, CHARACTER_DEFAULTS.questSelection)
        return
    end

    local migratedAccount = MigrateAccountSavedVars(accountSV)
    local migratedQuestState = MigrateQuestState(accountSV)
    local migratedQuestSelection = MigrateQuestSelection(accountSV)

    OverwriteTable(accountSV, migratedAccount)
    accountSV.schema = SCHEMA_VERSION

    characterSV.questState = characterSV.questState or {}
    characterSV.questSelection = characterSV.questSelection or {}
    OverwriteTable(characterSV.questState, migratedQuestState)
    OverwriteTable(characterSV.questSelection, migratedQuestSelection)
    characterSV.schema = SCHEMA_VERSION

    accountSV.General = nil
    accountSV.features = nil
    accountSV.QuestTracker = nil
    accountSV.AchievementTracker = nil
    accountSV.Settings = nil
end

local function ResolveColorDefinition(key)
    local entry = COLOR_PALETTE[key]
    if entry then
        return entry.r, entry.g, entry.b, entry.a
    end

    if type(key) == "string" and key:match("^#%x%x%x%x%x%x%x%x$") then
        local function parseHex(startIndex)
            return tonumber(key:sub(startIndex, startIndex + 1), 16) / 255
        end
        return parseHex(2), parseHex(4), parseHex(6), parseHex(8)
    end

    local fallback = COLOR_PALETTE.warmKhaki
    return fallback.r, fallback.g, fallback.b, fallback.a
end

function StateInit.ResolveColor(value)
    return ResolveColorDefinition(value)
end

function StateInit.EncodeColor(value)
    return NormalizePaletteKey(value)
end

function StateInit.BootstrapSavedVariables(addonTable)
    addonTable = addonTable or _G[addonName] or {}
    _G[addonName] = addonTable

    local accountSV = AcquireAccountSavedVars()
    local characterSV = AcquireCharacterSavedVars()

    RunMigration(accountSV, characterSV)

    local facade = BuildFacade(accountSV, characterSV)

    addonTable.account = accountSV
    addonTable.character = characterSV
    addonTable.storage = { account = accountSV, character = characterSV }
    addonTable.SV = accountSV
    addonTable.sv = facade

    if type(addonTable.SetDebugEnabled) == "function" then
        addonTable:SetDebugEnabled(accountSV.debug)
    end

    if Nvk3UT_Diagnostics and Nvk3UT_Diagnostics.SyncFromSavedVariables then
        Nvk3UT_Diagnostics.SyncFromSavedVariables(facade)
    end

    return facade
end

function StateInit.GetColorPalette()
    return COLOR_PALETTE
end

return StateInit
