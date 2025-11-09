-- Centralized SavedVariables bootstrap and first-login defaults for Nvk3UT.
-- Defines the account-wide schema introduced with schemaVersion 1.

Nvk3UT_StateInit = Nvk3UT_StateInit or {}

local SAVED_VARIABLES_NAME = "Nvk3UT_SV"
local SCHEMA_VERSION = 1

local DEFAULT_FONT_FACE_BOLD = "$(BOLD_FONT)"
local DEFAULT_FONT_OUTLINE = "soft-shadow-thick"

local DEFAULT_FONT_SIZES = {
    quest = { category = 20, title = 16, line = 14 },
    achievement = { category = 20, title = 16, line = 14 },
}

local DEFAULT_APPEARANCE = {
    enabled = true,
    alpha = 0.6,
    edgeEnabled = true,
    edgeAlpha = 0.65,
    edgeThickness = 2,
    padding = 12,
    cornerRadius = 0,
    theme = "dark",
}

local DEFAULT_LAYOUT = {
    autoGrowV = false,
    autoGrowH = false,
    minWidth = 260,
    minHeight = 240,
    maxWidth = 640,
    maxHeight = 900,
}

local DEFAULT_WINDOW_BARS = {
    headerHeightPx = 40,
    footerHeightPx = 100,
}

local DEFAULT_HOST = {
    x = 200,
    y = 200,
    width = 360,
    height = 640,
    locked = false,
    visible = true,
    clamp = true,
    onTop = false,
    hideInCombat = false,
}

local DEFAULT_AC_RECENT_LIMIT = 100

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, field in pairs(value) do
        copy[key] = deepCopy(field)
    end

    return copy
end

local function getRepo()
    return Nvk3UT_StateRepo or (Nvk3UT and Nvk3UT.StateRepo)
end

local function getAchievementRepo()
    return Nvk3UT_StateRepo_Achievements or (Nvk3UT and Nvk3UT.AchievementRepo)
end

local function rgbaToHex(r, g, b, a)
    local function component(value)
        local numeric = tonumber(value) or 0
        numeric = math.max(0, math.min(1, numeric))
        return string.format("%02X", math.floor(numeric * 255 + 0.5))
    end

    return string.format("#%s%s%s%s", component(r), component(g), component(b), component(a))
end

local DEFAULT_UI = {
    theme = "dark",
    palette = "default",
    favoritesScope = "account",
    recentWindow = 0,
    fonts = {
        quest = {
            category = { face = DEFAULT_FONT_FACE_BOLD, size = DEFAULT_FONT_SIZES.quest.category, outline = DEFAULT_FONT_OUTLINE },
            title = { face = DEFAULT_FONT_FACE_BOLD, size = DEFAULT_FONT_SIZES.quest.title, outline = DEFAULT_FONT_OUTLINE },
            line = { face = DEFAULT_FONT_FACE_BOLD, size = DEFAULT_FONT_SIZES.quest.line, outline = DEFAULT_FONT_OUTLINE },
        },
        achievement = {
            category = { face = DEFAULT_FONT_FACE_BOLD, size = DEFAULT_FONT_SIZES.achievement.category, outline = DEFAULT_FONT_OUTLINE },
            title = { face = DEFAULT_FONT_FACE_BOLD, size = DEFAULT_FONT_SIZES.achievement.title, outline = DEFAULT_FONT_OUTLINE },
            line = { face = DEFAULT_FONT_FACE_BOLD, size = DEFAULT_FONT_SIZES.achievement.line, outline = DEFAULT_FONT_OUTLINE },
        },
    },
    colors = {
        questTracker = {
            categoryTitle = rgbaToHex(0.7725, 0.7608, 0.6196, 1),
            objectiveText = rgbaToHex(0.7725, 0.7608, 0.6196, 1),
            entryTitle = rgbaToHex(1, 1, 0, 1),
            activeTitle = rgbaToHex(1, 1, 1, 1),
        },
        achievementTracker = {
            categoryTitle = rgbaToHex(0.7725, 0.7608, 0.6196, 1),
            objectiveText = rgbaToHex(0.7725, 0.7608, 0.6196, 1),
            entryTitle = rgbaToHex(1, 1, 0, 1),
            activeTitle = rgbaToHex(1, 1, 1, 1),
        },
    },
    statusVisible = true,
    categoryCounts = {
        quest = true,
        achievement = true,
    },
    appearance = DEFAULT_APPEARANCE,
    layout = DEFAULT_LAYOUT,
    windowBars = DEFAULT_WINDOW_BARS,
}

local DEFAULT_FEATURES = {
    completed = true,
    favorites = true,
    recent = true,
    todo = true,
    tooltips = true,
    hideDefaultQuestTracker = false,
}

local DEFAULTS = {
    schemaVersion = SCHEMA_VERSION,
    debug = false,
    ui = DEFAULT_UI,
    features = DEFAULT_FEATURES,
    host = DEFAULT_HOST,
    ac = {
        favorites = {},
        recent = {
            list = {},
            limit = DEFAULT_AC_RECENT_LIMIT,
        },
        collapse = {
            block_favorites_collapsed = false,
            achievements = {},
        },
    },
}

local CHARACTER_DEFAULTS = {
    schemaVersion = SCHEMA_VERSION,
    quests = {
        state = {
            zones = {},
            quests = {},
        },
        flags = {},
    },
}

local function ensureTable(parent, key)
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

local function sanitizeAcRecentList(list)
    if type(list) ~= "table" then
        return {}
    end

    local sanitized = {}
    local count = 0
    for index = 1, #list do
        local numeric = tonumber(list[index])
        if numeric and numeric > 0 then
            count = count + 1
            sanitized[count] = math.floor(numeric)
        end
    end

    return sanitized
end

local function normalizeAcStructure(saved)
    local ac = ensureTable(saved, "ac")

    ac.favorites = ac.favorites or {}
    ac.recent = ac.recent or {}
    ac.recent.list = sanitizeAcRecentList(ac.recent.list)
    if type(ac.recent.progress) ~= "table" then
        ac.recent.progress = {}
    end

    local limit = tonumber(ac.recent.limit) or DEFAULT_AC_RECENT_LIMIT
    if limit ~= 50 and limit ~= 100 and limit ~= 250 then
        limit = DEFAULT_AC_RECENT_LIMIT
    end
    ac.recent.limit = limit

    ac.collapse = ac.collapse or {}
    local collapse = ac.collapse
    if collapse.block_favorites_collapsed ~= true then
        collapse.block_favorites_collapsed = nil
    end
    collapse.achievements = collapse.achievements or {}

    saved.ac = ac
end

local function normalizeUiStructure(saved)
    local ui = ensureTable(saved, "ui")

    local fonts = ensureTable(ui, "fonts")
    fonts.quest = fonts.quest or {}
    fonts.achievement = fonts.achievement or {}

    local function ensureFontSet(target, defaults)
        target.category = target.category or {}
        target.category.face = target.category.face or defaults.category.face
        target.category.size = tonumber(target.category.size) or defaults.category.size
        target.category.outline = target.category.outline or defaults.category.outline

        target.title = target.title or {}
        target.title.face = target.title.face or defaults.title.face
        target.title.size = tonumber(target.title.size) or defaults.title.size
        target.title.outline = target.title.outline or defaults.title.outline

        target.line = target.line or {}
        target.line.face = target.line.face or defaults.line.face
        target.line.size = tonumber(target.line.size) or defaults.line.size
        target.line.outline = target.line.outline or defaults.line.outline
    end

    ensureFontSet(fonts.quest, DEFAULT_UI.fonts.quest)
    ensureFontSet(fonts.achievement, DEFAULT_UI.fonts.achievement)

    ui.colors = ui.colors or {}
    ui.colors.questTracker = ui.colors.questTracker or {}
    ui.colors.achievementTracker = ui.colors.achievementTracker or {}

    local function ensureColor(tableRef, defaults)
        for key, value in pairs(defaults) do
            local text = tableRef[key]
            if type(text) ~= "string" then
                tableRef[key] = value
            end
        end
    end

    ensureColor(ui.colors.questTracker, DEFAULT_UI.colors.questTracker)
    ensureColor(ui.colors.achievementTracker, DEFAULT_UI.colors.achievementTracker)

    if ui.statusVisible == nil then
        ui.statusVisible = DEFAULT_UI.statusVisible
    else
        ui.statusVisible = ui.statusVisible ~= false
    end

    ui.palette = ui.palette or DEFAULT_UI.palette
    ui.theme = ui.theme or DEFAULT_UI.theme

    if type(ui.favoritesScope) ~= "string" or ui.favoritesScope == "" then
        ui.favoritesScope = DEFAULT_UI.favoritesScope
    end

    local window = tonumber(ui.recentWindow)
    if not window then
        window = DEFAULT_UI.recentWindow
    end
    ui.recentWindow = window

    local function ensureNumberRange(target, key, fallback, minValue)
        local numeric = tonumber(target[key])
        if not numeric then
            numeric = fallback
        end
        if minValue then
            numeric = math.max(minValue, numeric)
        end
        target[key] = numeric
    end

    ui.appearance = ui.appearance or {}
    local appearance = ui.appearance
    appearance.enabled = appearance.enabled ~= false
    ensureNumberRange(appearance, "alpha", DEFAULT_APPEARANCE.alpha)
    appearance.edgeEnabled = appearance.edgeEnabled ~= false
    ensureNumberRange(appearance, "edgeAlpha", DEFAULT_APPEARANCE.edgeAlpha)
    ensureNumberRange(appearance, "edgeThickness", DEFAULT_APPEARANCE.edgeThickness, 1)
    ensureNumberRange(appearance, "padding", DEFAULT_APPEARANCE.padding, 0)
    ensureNumberRange(appearance, "cornerRadius", DEFAULT_APPEARANCE.cornerRadius, 0)
    appearance.theme = appearance.theme or DEFAULT_APPEARANCE.theme

    ui.layout = ui.layout or {}
    local layout = ui.layout
    layout.autoGrowV = layout.autoGrowV ~= false
    layout.autoGrowH = layout.autoGrowH == true
    ensureNumberRange(layout, "minWidth", DEFAULT_LAYOUT.minWidth, 1)
    ensureNumberRange(layout, "maxWidth", DEFAULT_LAYOUT.maxWidth, 1)
    if layout.maxWidth < layout.minWidth then
        layout.maxWidth = layout.minWidth
    end
    ensureNumberRange(layout, "minHeight", DEFAULT_LAYOUT.minHeight, 1)
    ensureNumberRange(layout, "maxHeight", DEFAULT_LAYOUT.maxHeight, 1)
    if layout.maxHeight < layout.minHeight then
        layout.maxHeight = layout.minHeight
    end

    ui.windowBars = ui.windowBars or {}
    local bars = ui.windowBars
    ensureNumberRange(bars, "headerHeightPx", DEFAULT_WINDOW_BARS.headerHeightPx, 0)
    ensureNumberRange(bars, "footerHeightPx", DEFAULT_WINDOW_BARS.footerHeightPx, 0)

    ui.categoryCounts = ui.categoryCounts or {}
    local counts = ui.categoryCounts
    if counts.quest == nil then
        counts.quest = DEFAULT_UI.categoryCounts.quest
    else
        counts.quest = counts.quest ~= false
    end
    if counts.achievement == nil then
        counts.achievement = DEFAULT_UI.categoryCounts.achievement
    else
        counts.achievement = counts.achievement ~= false
    end

    saved.ui = ui
end

local function normalizeFeatureStructure(saved)
    local features = ensureTable(saved, "features")
    for key, value in pairs(DEFAULT_FEATURES) do
        if features[key] == nil then
            features[key] = value
        else
            features[key] = features[key] ~= false
        end
    end
    saved.features = features
end

local function normalizeHostStructure(saved)
    local host = ensureTable(saved, "host")

    host.x = tonumber(host.x) or DEFAULT_HOST.x
    host.y = tonumber(host.y) or DEFAULT_HOST.y
    host.width = tonumber(host.width) or DEFAULT_HOST.width
    host.height = tonumber(host.height) or DEFAULT_HOST.height

    if host.locked == nil then
        host.locked = DEFAULT_HOST.locked
    else
        host.locked = host.locked == true
    end

    if host.visible == nil then
        host.visible = DEFAULT_HOST.visible
    else
        host.visible = host.visible ~= false
    end

    if host.clamp == nil then
        host.clamp = DEFAULT_HOST.clamp
    else
        host.clamp = host.clamp ~= false
    end

    if host.onTop == nil then
        host.onTop = DEFAULT_HOST.onTop
    else
        host.onTop = host.onTop == true
    end

    if host.hideInCombat == nil then
        host.hideInCombat = DEFAULT_HOST.hideInCombat
    else
        host.hideInCombat = host.hideInCombat == true
    end

    saved.host = host
end

local function normalizeRoot(saved)
    if type(saved) ~= "table" then
        return
    end

    if tonumber(saved.schemaVersion) ~= SCHEMA_VERSION then
        saved.schemaVersion = SCHEMA_VERSION
    end

    if saved.debug == nil then
        saved.debug = DEFAULTS.debug
    else
        saved.debug = saved.debug == true
    end

    normalizeUiStructure(saved)
    normalizeFeatureStructure(saved)
    normalizeHostStructure(saved)
    normalizeAcStructure(saved)
end

local function normalizeCategoryKeyString(key)
    if key == nil then
        return nil
    end

    if type(key) == "string" then
        local trimmed = key:match("^%s*(.-)%s*$") or ""
        if trimmed == "" then
            return nil
        end
        return trimmed
    end

    local numeric = tonumber(key)
    if numeric and numeric == numeric then
        numeric = math.floor(numeric + 0.5)
        if numeric > 0 then
            return tostring(numeric)
        end
    end

    return nil
end

local function normalizeCharacterCollapseMap(source, keyNormalizer)
    local normalized = {}

    if type(source) ~= "table" then
        return normalized
    end

    for key, value in pairs(source) do
        local normalizedKey
        if keyNormalizer then
            normalizedKey = keyNormalizer(key)
        else
            normalizedKey = normalizeCategoryKeyString(key)
        end

        if normalizedKey and (value == true or value == 1 or value == "true") then
            normalized[normalizedKey] = true
        end
    end

    return normalized
end

local function normalizeQuestFlags(source)
    if type(source) ~= "table" then
        return {}
    end

    local normalized = {}

    for questId, flags in pairs(source) do
        local numericId = tonumber(questId)
        if numericId and numericId > 0 and type(flags) == "table" then
            local entry = {}

            if flags.tracked == true then
                entry.tracked = true
            end

            if flags.assisted == true then
                entry.assisted = true
            end

            if flags.isDaily == true then
                entry.isDaily = true
            end

            local categoryKey = tonumber(flags.categoryKey)
            if categoryKey and categoryKey > 0 then
                entry.categoryKey = math.floor(categoryKey)
            end

            local journalIndex = tonumber(flags.journalIndex)
            if journalIndex and journalIndex > 0 then
                entry.journalIndex = math.floor(journalIndex)
            end

            if next(entry) ~= nil then
                normalized[math.floor(numericId)] = entry
            end
        end
    end

    return normalized
end

local function normalizeCharacterRoot(saved)
    if type(saved) ~= "table" then
        return
    end

    if tonumber(saved.schemaVersion) ~= SCHEMA_VERSION then
        saved.schemaVersion = SCHEMA_VERSION
    end

    local quests = ensureTable(saved, "quests")
    quests.state = quests.state or {}
    quests.flags = normalizeQuestFlags(quests.flags)

    local state = quests.state
    if type(state) ~= "table" then
        state = {}
        quests.state = state
    end

    local zones = normalizeCharacterCollapseMap(state.zones, normalizeCategoryKeyString)

    if next(zones) ~= nil then
        state.zones = zones
    else
        state.zones = nil
    end

    local questsMap = normalizeCharacterCollapseMap(state.quests, function(key)
        local numeric = tonumber(key)
        if numeric and numeric > 0 then
            return math.floor(numeric)
        end
        return nil
    end)

    if next(questsMap) ~= nil then
        state.quests = questsMap
    else
        state.quests = nil
    end

    if next(state) ~= nil then
        quests.state = state
    else
        quests.state = nil
    end

    if next(quests.flags) ~= nil then
        quests.flags = quests.flags
    else
        quests.flags = nil
    end

    saved.quests = quests
end

local function createWindowFacade(saved)
    local proxy = {}
    local achievementRepo = getAchievementRepo()

    local function readRect()
        local repo = getRepo()
        local rect = repo and repo.Host_GetRect and repo.Host_GetRect()
        if type(rect) ~= "table" then
            rect = deepCopy(DEFAULT_HOST)
        end
        return rect
    end

    local function readField(key)
        local rect = readRect()
        if key == "left" then
            return rect.x or rect.left or DEFAULT_HOST.x
        elseif key == "top" then
            return rect.y or rect.top or DEFAULT_HOST.y
        elseif key == "width" then
            return rect.width or DEFAULT_HOST.width
        elseif key == "height" then
            return rect.height or DEFAULT_HOST.height
        elseif key == "locked" then
            return rect.locked == true
        elseif key == "visible" then
            return rect.visible ~= false
        elseif key == "clamp" then
            return rect.clamp ~= false
        elseif key == "onTop" then
            return rect.onTop == true
        end
        return nil
    end

    local function writeField(key, value)
        local repo = getRepo()
        if not (repo and repo.Host_SetRect) then
            return
        end

        local payload = {}
        if key == "left" then
            payload.x = value
        elseif key == "top" then
            payload.y = value
        elseif key == "width" then
            payload.width = value
        elseif key == "height" then
            payload.height = value
        elseif key == "locked" then
            payload.locked = value
        elseif key == "visible" then
            payload.visible = value
        elseif key == "clamp" then
            payload.clamp = value
        elseif key == "onTop" then
            payload.onTop = value
        else
            payload[key] = value
        end

        repo.Host_SetRect(payload)
    end

    local function snapshot()
        local rect = readRect()
        return {
            left = rect.x or rect.left or DEFAULT_HOST.x,
            top = rect.y or rect.top or DEFAULT_HOST.y,
            width = rect.width or DEFAULT_HOST.width,
            height = rect.height or DEFAULT_HOST.height,
            locked = rect.locked == true,
            visible = rect.visible ~= false,
            clamp = rect.clamp ~= false,
            onTop = rect.onTop == true,
        }
    end

    setmetatable(proxy, {
        __index = function(_, key)
            if key == "left" or key == "top" or key == "width" or key == "height" or
                key == "locked" or key == "visible" or key == "clamp" or key == "onTop" then
                return readField(key)
            end
            return rawget(proxy, key)
        end,
        __newindex = function(_, key, value)
            if key == "left" or key == "top" or key == "width" or key == "height" or
                key == "locked" or key == "visible" or key == "clamp" or key == "onTop" then
                writeField(key, value)
                return
            end
            rawset(proxy, key, value)
        end,
        __pairs = function()
            local values = snapshot()
            return next, values, nil
        end,
    })

    return proxy
end

local function createHostSettingsFacade(saved)
    local proxy = {}

    setmetatable(proxy, {
        __index = function(_, key)
            if key == "HideInCombat" then
                local repo = getRepo()
                local rect = repo and repo.Host_GetRect and repo.Host_GetRect()
                return rect and rect.hideInCombat == true or false
            end
            return rawget(proxy, key)
        end,
        __newindex = function(_, key, value)
            if key == "HideInCombat" then
                local repo = getRepo()
                if repo and repo.Host_SetRect then
                    repo.Host_SetRect({ hideInCombat = value })
                end
                return
            end
            rawset(proxy, key, value)
        end,
    })

    local repo = getRepo()
    local rect = repo and repo.Host_GetRect and repo.Host_GetRect()
    proxy.HideInCombat = rect and rect.hideInCombat == true or false
    return proxy
end

local function createUiProxy(path, defaults)
    local proxy = {}

    local function buildPath(key)
        key = tostring(key)
        if path and path ~= "" then
            return string.format("%s.%s", path, key)
        end
        return key
    end

    local function snapshot()
        local values = {}
        if defaults then
            for key, defaultValue in pairs(defaults) do
                values[key] = deepCopy(defaultValue)
            end
        end

        local repo = getRepo()
        if repo and repo.UI_GetOption then
            local current = repo.UI_GetOption(path or "")
            if type(current) == "table" then
                for key, value in pairs(current) do
                    values[key] = value
                end
            end
        end

        return values
    end

    setmetatable(proxy, {
        __index = function(_, key)
            local fullPath = buildPath(key)
            local defaultValue = defaults and defaults[key]
            local repo = getRepo()
            local value = repo and repo.UI_GetOption and repo.UI_GetOption(fullPath) or nil

            if type(defaultValue) == "table" or type(value) == "table" then
                return createUiProxy(fullPath, defaultValue)
            end

            if value == nil then
                value = defaultValue
            end
            return value
        end,
        __newindex = function(_, key, value)
            local repo = getRepo()
            if repo and repo.UI_SetOption then
                repo.UI_SetOption(buildPath(key), value)
            end
        end,
        __pairs = function()
            local values = snapshot()
            return next, values, nil
        end,
    })

    return proxy
end

local function createGeneralFacade(saved)
    local ac = ensureTable(saved, "ac")
    ac.recent = ac.recent or {}
    local features = ensureTable(saved, "features")

    local proxy = {}
    local windowFacade = createWindowFacade(saved)
    local layoutProxy = createUiProxy("layout", DEFAULT_UI.layout)
    local appearanceProxy = createUiProxy("appearance", DEFAULT_UI.appearance)
    local windowBarsProxy = createUiProxy("windowBars", DEFAULT_WINDOW_BARS)

    local function getOption(path, default, coerceBoolean)
        local repo = getRepo()
        local value = repo and repo.UI_GetOption and repo.UI_GetOption(path)
        if value == nil then
            value = default
        end
        if coerceBoolean then
            if default == true then
                return value == true
            end
            return value ~= false
        end
        return value
    end

    local function updateShowCategoryCounts()
        local quest = getOption("categoryCounts.quest", DEFAULT_UI.categoryCounts.quest, true)
        local achievement = getOption("categoryCounts.achievement", DEFAULT_UI.categoryCounts.achievement, true)
        rawset(proxy, "showCategoryCounts", quest and achievement)
    end

    setmetatable(proxy, {
        __index = function(_, key)
            if key == "window" then
                return windowFacade
            elseif key == "features" then
                return features
            elseif key == "layout" then
                return layoutProxy
            elseif key == "Appearance" then
                return appearanceProxy
            elseif key == "WindowBars" then
                return windowBarsProxy
            elseif key == "showStatus" then
                local value = getOption("statusVisible", DEFAULT_UI.statusVisible, true)
                rawset(proxy, key, value)
                return value
            elseif key == "showQuestCategoryCounts" then
                local value = getOption("categoryCounts.quest", DEFAULT_UI.categoryCounts.quest, true)
                rawset(proxy, key, value)
                updateShowCategoryCounts()
                return value
            elseif key == "showAchievementCategoryCounts" then
                local value = getOption("categoryCounts.achievement", DEFAULT_UI.categoryCounts.achievement, true)
                rawset(proxy, key, value)
                updateShowCategoryCounts()
                return value
            elseif key == "showCategoryCounts" then
                updateShowCategoryCounts()
                return rawget(proxy, key)
            elseif key == "favScope" then
                local value = getOption("favoritesScope", DEFAULT_UI.favoritesScope)
                rawset(proxy, key, value)
                return value
            elseif key == "recentWindow" then
                local value = getOption("recentWindow", DEFAULT_UI.recentWindow)
                rawset(proxy, key, value)
                return value
            elseif key == "recentMax" then
                local limit
                if achievementRepo and achievementRepo.AC_Recent_GetLimit then
                    limit = achievementRepo.AC_Recent_GetLimit()
                end
                limit = limit or DEFAULT_AC_RECENT_LIMIT
                rawset(proxy, key, limit)
                return limit
            end
            return rawget(proxy, key)
        end,
        __newindex = function(_, key, value)
            local repo = getRepo()
            if key == "showStatus" then
                if repo and repo.UI_SetOption then
                    repo.UI_SetOption("statusVisible", value)
                end
                rawset(proxy, key, value ~= false)
                return
            elseif key == "showQuestCategoryCounts" then
                if repo and repo.UI_SetOption then
                    repo.UI_SetOption("categoryCounts.quest", value)
                end
                rawset(proxy, key, value ~= false)
                updateShowCategoryCounts()
                return
            elseif key == "showAchievementCategoryCounts" then
                if repo and repo.UI_SetOption then
                    repo.UI_SetOption("categoryCounts.achievement", value)
                end
                rawset(proxy, key, value ~= false)
                updateShowCategoryCounts()
                return
            elseif key == "showCategoryCounts" then
                local flag = value ~= false
                if repo and repo.UI_SetOption then
                    repo.UI_SetOption("categoryCounts.quest", flag)
                    repo.UI_SetOption("categoryCounts.achievement", flag)
                end
                rawset(proxy, "showQuestCategoryCounts", flag)
                rawset(proxy, "showAchievementCategoryCounts", flag)
                rawset(proxy, key, flag)
                return
            elseif key == "favScope" then
                if type(value) ~= "string" or value == "" then
                    value = DEFAULT_UI.favoritesScope
                end
                if repo and repo.UI_SetOption then
                    repo.UI_SetOption("favoritesScope", value)
                end
                rawset(proxy, key, value)
                return
            elseif key == "recentWindow" then
                local numeric = tonumber(value)
                if not numeric then
                    numeric = DEFAULT_UI.recentWindow
                end
                if repo and repo.UI_SetOption then
                    repo.UI_SetOption("recentWindow", numeric)
                end
                rawset(proxy, key, numeric)
                return
            elseif key == "recentMax" then
                local limit = tonumber(value)
                if limit ~= 50 and limit ~= 100 and limit ~= 250 then
                    limit = DEFAULT_AC_RECENT_LIMIT
                end
                if achievementRepo and achievementRepo.AC_Recent_SetLimit then
                    limit = achievementRepo.AC_Recent_SetLimit(limit)
                elseif ac and ac.recent then
                    ac.recent.limit = limit
                end
                rawset(proxy, key, limit)
                return
            end
            rawset(proxy, key, value)
        end,
    })

    proxy.window = windowFacade
    proxy.features = features
    proxy.layout = layoutProxy
    proxy.Appearance = appearanceProxy
    proxy.WindowBars = windowBarsProxy
    proxy.showStatus = getOption("statusVisible", DEFAULT_UI.statusVisible, true)
    proxy.favScope = getOption("favoritesScope", DEFAULT_UI.favoritesScope)
    proxy.recentWindow = getOption("recentWindow", DEFAULT_UI.recentWindow)
    if achievementRepo and achievementRepo.AC_Recent_GetLimit then
        proxy.recentMax = achievementRepo.AC_Recent_GetLimit()
    else
        proxy.recentMax = ac.recent.limit or DEFAULT_AC_RECENT_LIMIT
    end
    proxy.showQuestCategoryCounts = getOption("categoryCounts.quest", DEFAULT_UI.categoryCounts.quest, true)
    proxy.showAchievementCategoryCounts = getOption("categoryCounts.achievement", DEFAULT_UI.categoryCounts.achievement, true)
    updateShowCategoryCounts()

    return proxy
end

local function createSettingsFacade(saved)
    local settings = {}
    settings.Host = createHostSettingsFacade(saved)
    return settings
end

function Nvk3UT_StateInit.CreateLegacyFacade(saved, character)
    if type(saved) ~= "table" then
        return nil
    end

    local generalFacade = createGeneralFacade(saved)
    local settingsFacade = createSettingsFacade(saved)
    local uiFacade = createUiProxy(nil, DEFAULT_UI)

    local proxy = {}
    setmetatable(proxy, {
        __index = function(_, key)
            if key == "General" then
                return generalFacade
            elseif key == "Settings" then
                return settingsFacade
            elseif key == "features" then
                return saved.features
            elseif key == "ui" then
                return uiFacade
            elseif key == "host" then
                return saved.host
            elseif key == "ac" then
                return saved.ac
            elseif key == "character" or key == "Character" then
                return character
            elseif key == "QuestTracker" then
                return character and character.quests
            end
            return saved[key]
        end,
        __newindex = function(_, key, value)
            if key == "General" or key == "Settings" then
                return
            end
            saved[key] = value
        end,
    })

    return proxy
end

local function createSavedVars()
    local lib = LibSavedVars
    local sv

    if lib and lib.NewAccountWide then
        sv = lib:NewAccountWide(SAVED_VARIABLES_NAME, SCHEMA_VERSION, DEFAULTS)
        if sv and sv.EnableDefaultsTrimming then
            sv = sv:EnableDefaultsTrimming()
        end
    end

    if not sv and ZO_SavedVars then
        sv = ZO_SavedVars:NewAccountWide(SAVED_VARIABLES_NAME, SCHEMA_VERSION, nil, DEFAULTS)
    end

    return sv
end

local function createCharacterSavedVars()
    local lib = LibSavedVars
    local sv

    if lib and lib.NewCharacterIdSettings then
        sv = lib:NewCharacterIdSettings(SAVED_VARIABLES_NAME, SCHEMA_VERSION, CHARACTER_DEFAULTS)
        if sv and sv.EnableDefaultsTrimming then
            sv = sv:EnableDefaultsTrimming()
        end
    end

    if not sv and ZO_SavedVars then
        sv = ZO_SavedVars:NewCharacterIdSettings(SAVED_VARIABLES_NAME, SCHEMA_VERSION, nil, CHARACTER_DEFAULTS)
    end

    return sv
end

---Create or load SavedVariables and ensure all required subtables/fields exist.
---addonTable is expected to be the global addon table Nvk3UT.
---Returns the SavedVariables table.
function Nvk3UT_StateInit.BootstrapSavedVariables(addonTable)
    if type(addonTable) ~= "table" then
        return nil
    end

    local account = addonTable.SV
    if type(account) ~= "table" then
        account = createSavedVars()
    end

    if type(account) == "table" then
        normalizeRoot(account)
        addonTable.SV = account
    end

    local character = addonTable.SVCharacter
    if type(character) ~= "table" then
        character = createCharacterSavedVars()
    end

    if type(character) == "table" then
        normalizeCharacterRoot(character)
        addonTable.SVCharacter = character
    end

    if type(addonTable.SetDebugEnabled) == "function" and type(account) == "table" then
        addonTable:SetDebugEnabled(account.debug)
    end

    if Nvk3UT_Diagnostics and Nvk3UT_Diagnostics.SyncFromSavedVariables and type(account) == "table" then
        Nvk3UT_Diagnostics.SyncFromSavedVariables(account)
    end

    return account, character
end

function Nvk3UT_StateInit.GetAccountDefaults()
    return deepCopy(DEFAULTS)
end

function Nvk3UT_StateInit.GetUIDefaults()
    return deepCopy(DEFAULT_UI)
end

function Nvk3UT_StateInit.GetHostDefaults()
    return deepCopy(DEFAULT_HOST)
end

return Nvk3UT_StateInit
