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

local function createWindowFacade(saved)
    local host = ensureTable(saved, "host")
    local proxy = {}

    local function readNumeric(field, fallback)
        local value = tonumber(host[field])
        if not value then
            value = fallback
            host[field] = value
        end
        rawset(proxy, field == "x" and "left" or field == "y" and "top" or field, value)
        return value
    end

    local function readBoolean(field, fallback, trueWhenTrue)
        local value = host[field]
        if value == nil then
            value = fallback
            host[field] = value
        else
            value = value == trueWhenTrue
        end
        local key
        if field == "locked" then
            key = "locked"
        elseif field == "visible" then
            key = "visible"
        elseif field == "clamp" then
            key = "clamp"
        elseif field == "onTop" then
            key = "onTop"
        else
            key = field
        end
        rawset(proxy, key, value)
        return value
    end

    local function refresh()
        readNumeric("x", DEFAULT_HOST.x)
        readNumeric("y", DEFAULT_HOST.y)
        readNumeric("width", DEFAULT_HOST.width)
        readNumeric("height", DEFAULT_HOST.height)
        readBoolean("locked", DEFAULT_HOST.locked, true)
        readBoolean("visible", DEFAULT_HOST.visible, true)
        readBoolean("clamp", DEFAULT_HOST.clamp, true)
        readBoolean("onTop", DEFAULT_HOST.onTop, true)
    end

    local mt = {
        __index = function(_, key)
            if key == "left" then
                return readNumeric("x", DEFAULT_HOST.x)
            elseif key == "top" then
                return readNumeric("y", DEFAULT_HOST.y)
            elseif key == "width" then
                return readNumeric("width", DEFAULT_HOST.width)
            elseif key == "height" then
                return readNumeric("height", DEFAULT_HOST.height)
            elseif key == "locked" then
                return readBoolean("locked", DEFAULT_HOST.locked, true)
            elseif key == "visible" then
                return readBoolean("visible", DEFAULT_HOST.visible, true)
            elseif key == "clamp" then
                return readBoolean("clamp", DEFAULT_HOST.clamp, true)
            elseif key == "onTop" then
                return readBoolean("onTop", DEFAULT_HOST.onTop, true)
            end
            return rawget(proxy, key)
        end,
        __newindex = function(_, key, value)
            if key == "left" then
                host.x = math.floor((tonumber(value) or host.x or DEFAULT_HOST.x) + 0.5)
                rawset(proxy, key, host.x)
                return
            elseif key == "top" then
                host.y = math.floor((tonumber(value) or host.y or DEFAULT_HOST.y) + 0.5)
                rawset(proxy, key, host.y)
                return
            elseif key == "width" then
                host.width = math.floor((tonumber(value) or host.width or DEFAULT_HOST.width) + 0.5)
                rawset(proxy, key, host.width)
                return
            elseif key == "height" then
                host.height = math.floor((tonumber(value) or host.height or DEFAULT_HOST.height) + 0.5)
                rawset(proxy, key, host.height)
                return
            elseif key == "locked" then
                host.locked = value and true or false
                rawset(proxy, key, host.locked)
                return
            elseif key == "visible" then
                host.visible = value ~= false
                rawset(proxy, key, host.visible)
                return
            elseif key == "clamp" then
                host.clamp = value ~= false
                rawset(proxy, key, host.clamp)
                return
            elseif key == "onTop" then
                host.onTop = value and true or false
                rawset(proxy, key, host.onTop)
                return
            end
            rawset(proxy, key, value)
        end,
    }

    setmetatable(proxy, mt)
    refresh()
    return proxy
end

local function createHostSettingsFacade(saved)
    local host = ensureTable(saved, "host")
    local proxy = {}

    setmetatable(proxy, {
        __index = function(_, key)
            if key == "HideInCombat" then
                local value = host.hideInCombat == true
                rawset(proxy, key, value)
                return value
            end
            return rawget(proxy, key)
        end,
        __newindex = function(_, key, value)
            if key == "HideInCombat" then
                host.hideInCombat = value == true
                rawset(proxy, key, host.hideInCombat)
                return
            end
            rawset(proxy, key, value)
        end,
    })

    proxy.HideInCombat = host.hideInCombat == true
    return proxy
end

local function createGeneralFacade(saved)
    local ui = ensureTable(saved, "ui")
    local ac = ensureTable(saved, "ac")
    ac.recent = ac.recent or {}
    local features = ensureTable(saved, "features")

    local proxy = {}
    local windowFacade = createWindowFacade(saved)

    local function updateShowCategoryCounts()
        local flag = (ui.categoryCounts.quest ~= false) and (ui.categoryCounts.achievement ~= false)
        rawset(proxy, "showCategoryCounts", flag)
    end

    setmetatable(proxy, {
        __index = function(_, key)
            if key == "window" then
                return windowFacade
            elseif key == "features" then
                return features
            elseif key == "layout" then
                return ui.layout
            elseif key == "Appearance" then
                return ui.appearance
            elseif key == "WindowBars" then
                return ui.windowBars
            elseif key == "showStatus" then
                local value = ui.statusVisible ~= false
                rawset(proxy, key, value)
                return value
            elseif key == "showQuestCategoryCounts" then
                local value = ui.categoryCounts.quest ~= false
                rawset(proxy, key, value)
                updateShowCategoryCounts()
                return value
            elseif key == "showAchievementCategoryCounts" then
                local value = ui.categoryCounts.achievement ~= false
                rawset(proxy, key, value)
                updateShowCategoryCounts()
                return value
            elseif key == "showCategoryCounts" then
                updateShowCategoryCounts()
                return rawget(proxy, key)
            elseif key == "favScope" then
                local value = ui.favoritesScope or DEFAULT_UI.favoritesScope
                rawset(proxy, key, value)
                return value
            elseif key == "recentWindow" then
                rawset(proxy, key, ui.recentWindow)
                return ui.recentWindow
            elseif key == "recentMax" then
                local limit = ac.recent.limit or DEFAULT_AC_RECENT_LIMIT
                rawset(proxy, key, limit)
                return limit
            end
            return rawget(proxy, key)
        end,
        __newindex = function(_, key, value)
            if key == "showStatus" then
                ui.statusVisible = value ~= false
                rawset(proxy, key, ui.statusVisible)
                return
            elseif key == "showQuestCategoryCounts" then
                ui.categoryCounts.quest = value ~= false
                rawset(proxy, key, ui.categoryCounts.quest)
                updateShowCategoryCounts()
                return
            elseif key == "showAchievementCategoryCounts" then
                ui.categoryCounts.achievement = value ~= false
                rawset(proxy, key, ui.categoryCounts.achievement)
                updateShowCategoryCounts()
                return
            elseif key == "showCategoryCounts" then
                local flag = value ~= false
                ui.categoryCounts.quest = flag
                ui.categoryCounts.achievement = flag
                rawset(proxy, "showQuestCategoryCounts", flag)
                rawset(proxy, "showAchievementCategoryCounts", flag)
                rawset(proxy, key, flag)
                return
            elseif key == "favScope" then
                if type(value) ~= "string" or value == "" then
                    value = DEFAULT_UI.favoritesScope
                end
                ui.favoritesScope = value
                rawset(proxy, key, value)
                return
            elseif key == "recentWindow" then
                local numeric = tonumber(value)
                if not numeric then
                    numeric = DEFAULT_UI.recentWindow
                end
                ui.recentWindow = numeric
                rawset(proxy, key, numeric)
                return
            elseif key == "recentMax" then
                local limit = tonumber(value)
                if limit ~= 50 and limit ~= 100 and limit ~= 250 then
                    limit = DEFAULT_AC_RECENT_LIMIT
                end
                ac.recent.limit = limit
                rawset(proxy, key, limit)
                return
            end
            rawset(proxy, key, value)
        end,
    })

    proxy.window = windowFacade
    proxy.features = features
    proxy.layout = ui.layout
    proxy.Appearance = ui.appearance
    proxy.WindowBars = ui.windowBars
    proxy.showStatus = ui.statusVisible ~= false
    proxy.favScope = ui.favoritesScope
    proxy.recentWindow = ui.recentWindow
    proxy.recentMax = ac.recent.limit
    proxy.showQuestCategoryCounts = ui.categoryCounts.quest ~= false
    proxy.showAchievementCategoryCounts = ui.categoryCounts.achievement ~= false
    updateShowCategoryCounts()

    return proxy
end

local function createSettingsFacade(saved)
    local settings = {}
    settings.Host = createHostSettingsFacade(saved)
    return settings
end

function Nvk3UT_StateInit.CreateLegacyFacade(saved)
    if type(saved) ~= "table" then
        return nil
    end

    local generalFacade = createGeneralFacade(saved)
    local settingsFacade = createSettingsFacade(saved)

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
                return saved.ui
            elseif key == "host" then
                return saved.host
            elseif key == "ac" then
                return saved.ac
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

---Create or load SavedVariables and ensure all required subtables/fields exist.
---addonTable is expected to be the global addon table Nvk3UT.
---Returns the SavedVariables table.
function Nvk3UT_StateInit.BootstrapSavedVariables(addonTable)
    if type(addonTable) ~= "table" then
        return nil
    end

    local sv = addonTable.SV
    if type(sv) ~= "table" then
        sv = createSavedVars()
    end

    if type(sv) ~= "table" then
        return nil
    end

    normalizeRoot(sv)

    addonTable.SV = sv

    if type(addonTable.SetDebugEnabled) == "function" then
        addonTable:SetDebugEnabled(sv.debug)
    end

    if Nvk3UT_Diagnostics and Nvk3UT_Diagnostics.SyncFromSavedVariables then
        Nvk3UT_Diagnostics.SyncFromSavedVariables(sv)
    end

    return sv
end

return Nvk3UT_StateInit
