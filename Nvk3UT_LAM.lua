Nvk3UT = Nvk3UT or {}

local ADDON_NAME = "Nvk3UT"
local DEFAULT_PANEL_TITLE = "Nvk3's Ultimate Tracker"
local VERSION_FALLBACK = "0.11.1"

local function getVersionString()
    local getter = Nvk3UT and Nvk3UT.GetVersionString
    if type(getter) == "function" then
        local version = getter()
        if version and version ~= "" then
            return tostring(version)
        end
    end
    return VERSION_FALLBACK
end

local L = {}
Nvk3UT.LAM = L

local FONT_FACE_CHOICES = {
    { name = "Bold (Game Default)", face = "$(BOLD_FONT)" },
    { name = "Univers 67 (Game)", face = "EsoUI/Common/Fonts/univers67.otf" },
    { name = "Univers 57 (Game)", face = "EsoUI/Common/Fonts/univers57.otf" },
    { name = "Futura (Antique)", face = "EsoUI/Common/Fonts/ProseAntiquePSMT.otf" },
    { name = "Handschrift", face = "EsoUI/Common/Fonts/Handwritten_Bold.otf" },
    { name = "Trajan", face = "EsoUI/Common/Fonts/TrajanPro-Regular.otf" },
}

local OUTLINE_CHOICES = {
    { name = "Keiner", value = "none" },
    { name = "Weich (dünn)", value = "soft-shadow-thin" },
    { name = "Weich (dick)", value = "soft-shadow-thick" },
    { name = "Schatten", value = "shadow" },
    { name = "Kontur", value = "outline" },
}

local DEFAULT_FONT_SIZE = {
    quest = { category = 20, title = 16, line = 14 },
    achievement = { category = 20, title = 16, line = 14 },
}

local DEFAULT_WINDOW = {
    left = 200,
    top = 200,
    width = 360,
    height = 640,
    locked = false,
    visible = true,
    clamp = true,
    onTop = false,
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

local MAX_BAR_HEIGHT = 250

local function clamp(value, minimum, maximum)
    if value == nil then
        return minimum
    end
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function getSavedVars()
    return Nvk3UT and Nvk3UT.sv
end

local function getGeneral()
    local sv = getSavedVars()
    sv.General = sv.General or {}
    local general = sv.General
    general.features = general.features or {}
    general.window = general.window or {}
    local window = general.window
    window.left = tonumber(window.left) or DEFAULT_WINDOW.left
    window.top = tonumber(window.top) or DEFAULT_WINDOW.top
    window.width = tonumber(window.width) or DEFAULT_WINDOW.width
    window.height = tonumber(window.height) or DEFAULT_WINDOW.height
    if window.locked == nil then
        window.locked = DEFAULT_WINDOW.locked
    end
    if window.visible == nil then
        window.visible = DEFAULT_WINDOW.visible
    end
    if window.clamp == nil then
        window.clamp = DEFAULT_WINDOW.clamp
    end
    if window.onTop == nil then
        window.onTop = DEFAULT_WINDOW.onTop
    end
    local legacyShowCounts = general.showCategoryCounts
    if general.showQuestCategoryCounts == nil then
        if legacyShowCounts ~= nil then
            general.showQuestCategoryCounts = legacyShowCounts ~= false
        else
            general.showQuestCategoryCounts = true
        end
    end
    if general.showAchievementCategoryCounts == nil then
        if legacyShowCounts ~= nil then
            general.showAchievementCategoryCounts = legacyShowCounts ~= false
        else
            general.showAchievementCategoryCounts = true
        end
    end
    if general.showCategoryCounts == nil then
        general.showCategoryCounts = true
    end
    return general
end

local function getSettings()
    local sv = getSavedVars()
    sv.Settings = sv.Settings or {}
    return sv.Settings
end

local function getHostSettings()
    local settings = getSettings()
    settings.Host = settings.Host or {}
    local host = settings.Host
    if host.HideInCombat == nil then
        host.HideInCombat = false
    else
        host.HideInCombat = host.HideInCombat == true
    end
    return host
end

local function getFeatures()
    local general = getGeneral()
    general.features = general.features or {}
    local features = general.features
    if features.hideDefaultQuestTracker == nil then
        features.hideDefaultQuestTracker = false
    end
    return features
end

local function getAppearanceSettings()
    local general = getGeneral()
    general.Appearance = general.Appearance or {}

    local appearance = general.Appearance
    if appearance.enabled == nil then
        appearance.enabled = DEFAULT_APPEARANCE.enabled
    end
    appearance.alpha = clamp(tonumber(appearance.alpha) or DEFAULT_APPEARANCE.alpha, 0, 1)
    if appearance.edgeEnabled == nil then
        appearance.edgeEnabled = DEFAULT_APPEARANCE.edgeEnabled
    else
        appearance.edgeEnabled = appearance.edgeEnabled ~= false
    end
    appearance.edgeAlpha = clamp(tonumber(appearance.edgeAlpha) or DEFAULT_APPEARANCE.edgeAlpha, 0, 1)
    local thickness = tonumber(appearance.edgeThickness)
    if thickness == nil then
        thickness = DEFAULT_APPEARANCE.edgeThickness
    end
    appearance.edgeThickness = math.max(1, math.floor(thickness + 0.5))
    local padding = tonumber(appearance.padding)
    if padding == nil then
        padding = DEFAULT_APPEARANCE.padding
    end
    appearance.padding = math.max(0, math.floor(padding + 0.5))
    local cornerRadius = tonumber(appearance.cornerRadius)
    if cornerRadius == nil then
        cornerRadius = DEFAULT_APPEARANCE.cornerRadius
    end
    appearance.cornerRadius = math.max(0, math.floor(cornerRadius + 0.5))
    if type(appearance.theme) ~= "string" or appearance.theme == "" then
        appearance.theme = DEFAULT_APPEARANCE.theme
    else
        appearance.theme = string.lower(appearance.theme)
    end

    return appearance
end

local function getLayoutSettings()
    local general = getGeneral()
    general.layout = general.layout or {}

    local layout = general.layout

    if layout.autoGrowV == nil then
        layout.autoGrowV = DEFAULT_LAYOUT.autoGrowV
    else
        layout.autoGrowV = layout.autoGrowV ~= false
    end

    if layout.autoGrowH == nil then
        layout.autoGrowH = DEFAULT_LAYOUT.autoGrowH
    else
        layout.autoGrowH = layout.autoGrowH == true
    end

    local minWidth = tonumber(layout.minWidth)
    if not minWidth then
        minWidth = DEFAULT_LAYOUT.minWidth
    end
    layout.minWidth = math.max(260, math.floor(minWidth + 0.5))

    local maxWidth = tonumber(layout.maxWidth)
    if not maxWidth then
        maxWidth = DEFAULT_LAYOUT.maxWidth
    end
    maxWidth = math.floor(maxWidth + 0.5)
    layout.maxWidth = math.max(layout.minWidth, maxWidth)

    local minHeight = tonumber(layout.minHeight)
    if not minHeight then
        minHeight = DEFAULT_LAYOUT.minHeight
    end
    layout.minHeight = math.max(240, math.floor(minHeight + 0.5))

    local maxHeight = tonumber(layout.maxHeight)
    if not maxHeight then
        maxHeight = DEFAULT_LAYOUT.maxHeight
    end
    maxHeight = math.floor(maxHeight + 0.5)
    layout.maxHeight = math.max(layout.minHeight, maxHeight)

    return layout
end

local function getWindowBarSettings()
    local general = getGeneral()
    general.WindowBars = general.WindowBars or {}

    local bars = general.WindowBars

    local headerHeight = tonumber(bars.headerHeightPx)
    if headerHeight == nil then
        headerHeight = DEFAULT_WINDOW_BARS.headerHeightPx
    end
    headerHeight = clamp(math.floor(headerHeight + 0.5), 0, MAX_BAR_HEIGHT)
    bars.headerHeightPx = headerHeight

    local footerHeight = tonumber(bars.footerHeightPx)
    if footerHeight == nil then
        footerHeight = DEFAULT_WINDOW_BARS.footerHeightPx
    end
    footerHeight = clamp(math.floor(footerHeight + 0.5), 0, MAX_BAR_HEIGHT)
    bars.footerHeightPx = footerHeight

    return bars
end

local function getQuestSettings()
    local sv = getSavedVars()
    sv.QuestTracker = sv.QuestTracker or {}
    sv.QuestTracker.fonts = sv.QuestTracker.fonts or {}
    return sv.QuestTracker
end

local function getAchievementSettings()
    local sv = getSavedVars()
    sv.AchievementTracker = sv.AchievementTracker or {}
    sv.AchievementTracker.fonts = sv.AchievementTracker.fonts or {}
    sv.AchievementTracker.sections = sv.AchievementTracker.sections or {}
    return sv.AchievementTracker
end

local function ensureTrackerAppearance()
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.EnsureAppearanceDefaults then
        host.EnsureAppearanceDefaults()
    end
end

local function getTrackerColor(trackerType, role)
    ensureTrackerAppearance()
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.GetTrackerColor then
        return host.GetTrackerColor(trackerType, role)
    end
    if host and host.GetDefaultTrackerColor then
        return host.GetDefaultTrackerColor(trackerType, role)
    end
    return 1, 1, 1, 1
end

local function getDefaultTrackerColor(trackerType, role)
    ensureTrackerAppearance()
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.GetDefaultTrackerColor then
        return host.GetDefaultTrackerColor(trackerType, role)
    end
    return getTrackerColor(trackerType, role)
end

local function getTrackerColorDefaultTable(trackerType, role)
    local r, g, b, a = getDefaultTrackerColor(trackerType, role)
    return { r = r, g = g, b = b, a = a }
end

local function setTrackerColor(trackerType, role, r, g, b, a)
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.SetTrackerColor then
        host.SetTrackerColor(trackerType, role, r, g, b, a)
        ensureTrackerAppearance()
        return
    end

    local sv = getSavedVars()
    if not sv then
        return
    end

    sv.appearance = sv.appearance or {}
    sv.appearance[trackerType] = sv.appearance[trackerType] or {}
    local tracker = sv.appearance[trackerType]
    tracker.colors = tracker.colors or {}
    tracker.colors[role] = {
        r = r or 1,
        g = g or 1,
        b = b or 1,
        a = a or 1,
    }
end

local function ensureFont(settings, key, defaults)
    settings.fonts[key] = settings.fonts[key] or {}
    local font = settings.fonts[key]
    font.face = font.face or defaults.face or FONT_FACE_CHOICES[1].face
    font.size = font.size or defaults.size or 16
    font.outline = font.outline or defaults.outline or "soft-shadow-thick"
    return font
end

local function applyQuestSettings()
    if Nvk3UT and Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.ApplySettings then
        Nvk3UT.QuestTracker.ApplySettings(getQuestSettings())
    end
end

local function applyQuestTheme()
    if Nvk3UT and Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.ApplyTheme then
        Nvk3UT.QuestTracker.ApplyTheme(getQuestSettings())
    end
end

local function refreshQuestTracker()
    if Nvk3UT and Nvk3UT.QuestTracker then
        if Nvk3UT.QuestTracker.RequestRefresh then
            Nvk3UT.QuestTracker.RequestRefresh()
        elseif Nvk3UT.QuestTracker.Refresh then
            Nvk3UT.QuestTracker.Refresh()
        end
    end
end

local function applyAchievementSettings()
    if Nvk3UT and Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.ApplySettings then
        Nvk3UT.AchievementTracker.ApplySettings(getAchievementSettings())
    end
end

local function applyAchievementTheme()
    if Nvk3UT and Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.ApplyTheme then
        Nvk3UT.AchievementTracker.ApplyTheme(getAchievementSettings())
    end
end

local function applyHostAppearance()
    if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplyAppearance then
        Nvk3UT.TrackerHost.ApplyAppearance()
    end
end

local function refreshAchievementTracker()
    if Nvk3UT and Nvk3UT.AchievementTracker then
        if Nvk3UT.AchievementTracker.RequestRefresh then
            Nvk3UT.AchievementTracker.RequestRefresh()
        elseif Nvk3UT.AchievementTracker.Refresh then
            Nvk3UT.AchievementTracker.Refresh()
        end
    end
end

local function updateStatus()
    if Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
        Nvk3UT.UI.UpdateStatus()
    end
end

local function applyFeatureToggles()
    if Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.ApplyFeatureToggles then
        Nvk3UT.UI.ApplyFeatureToggles()
    end
end

local function updateTooltips(enabled)
    if Nvk3UT and Nvk3UT.Tooltips and Nvk3UT.Tooltips.Enable then
        Nvk3UT.Tooltips.Enable(enabled ~= false)
    end
end

local function questFontDefaults(key)
    local defaults = DEFAULT_FONT_SIZE.quest
    local face = FONT_FACE_CHOICES[1].face
    local outline = "soft-shadow-thick"
    local size = defaults[key] or 16
    return { face = face, size = size, outline = outline }
end

local function achievementFontDefaults(key)
    local defaults = DEFAULT_FONT_SIZE.achievement
    local face = FONT_FACE_CHOICES[1].face
    local outline = "soft-shadow-thick"
    local size = defaults[key] or 16
    return { face = face, size = size, outline = outline }
end

local function buildFontControls(label, settings, key, defaults, onChanged)
    local font = ensureFont(settings, key, defaults)
    return {
        {
            type = "dropdown",
            name = label .. " - Schriftart",
            choices = (function()
                local names = {}
                for index = 1, #FONT_FACE_CHOICES do
                    names[index] = FONT_FACE_CHOICES[index].name
                end
                return names
            end)(),
            choicesValues = (function()
                local values = {}
                for index = 1, #FONT_FACE_CHOICES do
                    values[index] = FONT_FACE_CHOICES[index].face
                end
                return values
            end)(),
            getFunc = function()
                font = ensureFont(settings, key, defaults)
                return font.face
            end,
            setFunc = function(value)
                font = ensureFont(settings, key, defaults)
                font.face = value
                onChanged()
            end,
        },
        {
            type = "slider",
            name = label .. " - Größe",
            min = 12,
            max = 36,
            step = 1,
            getFunc = function()
                font = ensureFont(settings, key, defaults)
                return font.size
            end,
            setFunc = function(value)
                font = ensureFont(settings, key, defaults)
                font.size = math.floor(value + 0.5)
                onChanged()
            end,
        },
        {
            type = "dropdown",
            name = label .. " - Kontur",
            choices = (function()
                local names = {}
                for index = 1, #OUTLINE_CHOICES do
                    names[index] = OUTLINE_CHOICES[index].name
                end
                return names
            end)(),
            choicesValues = (function()
                local values = {}
                for index = 1, #OUTLINE_CHOICES do
                    values[index] = OUTLINE_CHOICES[index].value
                end
                return values
            end)(),
            getFunc = function()
                font = ensureFont(settings, key, defaults)
                return font.outline
            end,
            setFunc = function(value)
                font = ensureFont(settings, key, defaults)
                font.outline = value
                onChanged()
            end,
        },
    }
end

local function buildJournalExtensionsControls()
    local controls = {}

    controls[#controls + 1] = { type = "header", name = "Funktionen" }

    local featureControls = {
        { key = "completed", label = "Abgeschlossen aktiv" },
        { key = "favorites", label = "Favoriten aktiv" },
        { key = "recent", label = "Kürzlich aktiv" },
        { key = "todo", label = "To-Do-Liste aktiv" },
    }

    for index = 1, #featureControls do
        local entry = featureControls[index]
        controls[#controls + 1] = {
            type = "checkbox",
            name = entry.label,
            getFunc = function()
                local features = getFeatures()
                return features[entry.key] ~= false
            end,
            setFunc = function(value)
                local features = getFeatures()
                features[entry.key] = value
                applyFeatureToggles()
                local cache = Nvk3UT and Nvk3UT.AchievementCache
                if cache and cache.OnOptionsChanged then
                    cache.OnOptionsChanged({ key = entry.key })
                end
            end,
            default = true,
        }
    end

    return controls
end

local function buildStatusTextControls()
    local controls = {}

    controls[#controls + 1] = { type = "header", name = "Anzeige" }

    controls[#controls + 1] = {
        type = "checkbox",
        name = "Status über dem Kompass anzeigen",
        getFunc = function()
            local general = getGeneral()
            return general.showStatus ~= false
        end,
        setFunc = function(value)
            local general = getGeneral()
            general.showStatus = value
            updateStatus()
        end,
        default = true,
    }

    controls[#controls + 1] = { type = "header", name = "Optionen" }

    controls[#controls + 1] = {
        type = "dropdown",
        name = "Favoritenspeicherung:",
        choices = { "Account-Weit", "Charakter-Weit" },
        choicesValues = { "account", "character" },
        getFunc = function()
            local general = getGeneral()
            return general.favScope or "account"
        end,
        setFunc = function(value)
            local general = getGeneral()
            local old = general.favScope or "account"
            general.favScope = value or "account"
            if Nvk3UT.FavoritesData and Nvk3UT.FavoritesData.MigrateScope then
                Nvk3UT.FavoritesData.MigrateScope(old, general.favScope)
            end
            if Nvk3UT.AchievementModel and Nvk3UT.AchievementModel.OnFavoritesChanged then
                Nvk3UT.AchievementModel.OnFavoritesChanged()
            end
            local cache = Nvk3UT and Nvk3UT.AchievementCache
            if cache and cache.OnOptionsChanged then
                cache.OnOptionsChanged({ key = "favoritesScope" })
            end
            refreshAchievementTracker()
            updateStatus()
        end,
        tooltip = "Speichert und zählt Favoriten account-weit oder charakter-weit.",
    }

    controls[#controls + 1] = {
        type = "dropdown",
        name = "Kürzlich-Zeitraum:",
        choices = { "Alle", "7 Tage", "30 Tage" },
        choicesValues = { 0, 7, 30 },
        getFunc = function()
            local general = getGeneral()
            return general.recentWindow or 0
        end,
        setFunc = function(value)
            local general = getGeneral()
            general.recentWindow = value or 0
            local cache = Nvk3UT and Nvk3UT.AchievementCache
            if cache and cache.OnOptionsChanged then
                cache.OnOptionsChanged({ key = "recentWindow" })
            end
            updateStatus()
        end,
        tooltip = "Wähle, welche Zeitspanne für Kürzlich gezählt/angezeigt wird.",
    }

    controls[#controls + 1] = {
        type = "dropdown",
        name = "Kürzlich - Maximum:",
        choices = { "50", "100", "250" },
        choicesValues = { 50, 100, 250 },
        getFunc = function()
            local general = getGeneral()
            return general.recentMax or 100
        end,
        setFunc = function(value)
            local general = getGeneral()
            general.recentMax = value or 100
            local cache = Nvk3UT and Nvk3UT.AchievementCache
            if cache and cache.OnOptionsChanged then
                cache.OnOptionsChanged({ key = "recentMax" })
            end
            updateStatus()
        end,
        tooltip = "Hardcap für die Anzahl der Kürzlich-Einträge.",
    }

    return controls
end

local function buildTrackerHostControls()
    local controls = {}

    controls[#controls + 1] = { type = "header", name = "Fenster & Darstellung" }

    controls[#controls + 1] = {
        type = "checkbox",
        name = "Fenster anzeigen",
        getFunc = function()
            local general = getGeneral()
            return general.window.visible ~= false
        end,
        setFunc = function(value)
            local general = getGeneral()
            general.window.visible = value ~= false
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        default = true,
    }

    controls[#controls + 1] = {
        type = "checkbox",
        name = "Fenster sperren",
        getFunc = function()
            local general = getGeneral()
            return general.window.locked == true
        end,
        setFunc = function(value)
            local general = getGeneral()
            general.window.locked = value and true or false
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        default = DEFAULT_WINDOW.locked,
    }

    controls[#controls + 1] = {
        type = "checkbox",
        name = "Immer im Vordergrund",
        getFunc = function()
            local general = getGeneral()
            return general.window.onTop == true
        end,
        setFunc = function(value)
            local general = getGeneral()
            general.window.onTop = value == true
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        default = DEFAULT_WINDOW.onTop,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Fensterbreite",
        min = 260,
        max = 1200,
        step = 10,
        getFunc = function()
            local general = getGeneral()
            return math.floor((general.window.width or DEFAULT_WINDOW.width) + 0.5)
        end,
        setFunc = function(value)
            local general = getGeneral()
            local layout = getLayoutSettings()
            local numeric = math.floor((tonumber(value) or general.window.width or DEFAULT_WINDOW.width) + 0.5)
            numeric = clamp(numeric, layout.minWidth or 260, layout.maxWidth or 1200)
            general.window.width = numeric
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        disabled = function()
            return getLayoutSettings().autoGrowH == true
        end,
        default = DEFAULT_WINDOW.width,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Fensterhöhe",
        min = 240,
        max = 1200,
        step = 10,
        getFunc = function()
            local general = getGeneral()
            return math.floor((general.window.height or DEFAULT_WINDOW.height) + 0.5)
        end,
        setFunc = function(value)
            local general = getGeneral()
            local layout = getLayoutSettings()
            local numeric = math.floor((tonumber(value) or general.window.height or DEFAULT_WINDOW.height) + 0.5)
            numeric = clamp(numeric, layout.minHeight or 240, layout.maxHeight or 1200)
            general.window.height = numeric
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        disabled = function()
            return getLayoutSettings().autoGrowV ~= false
        end,
        default = DEFAULT_WINDOW.height,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Header-Höhe",
        min = 0,
        max = MAX_BAR_HEIGHT,
        step = 1,
        getFunc = function()
            local bars = getWindowBarSettings()
            return bars.headerHeightPx or DEFAULT_WINDOW_BARS.headerHeightPx
        end,
        setFunc = function(value)
            local bars = getWindowBarSettings()
            local numeric = math.floor((tonumber(value) or bars.headerHeightPx or DEFAULT_WINDOW_BARS.headerHeightPx) + 0.5)
            bars.headerHeightPx = math.max(0, math.min(MAX_BAR_HEIGHT, numeric))
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplyWindowBars then
                Nvk3UT.TrackerHost.ApplyWindowBars()
            end
        end,
        default = DEFAULT_WINDOW_BARS.headerHeightPx,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Footer-Höhe",
        min = 0,
        max = MAX_BAR_HEIGHT,
        step = 1,
        getFunc = function()
            local bars = getWindowBarSettings()
            return bars.footerHeightPx or DEFAULT_WINDOW_BARS.footerHeightPx
        end,
        setFunc = function(value)
            local bars = getWindowBarSettings()
            local numeric = math.floor((tonumber(value) or bars.footerHeightPx or DEFAULT_WINDOW_BARS.footerHeightPx) + 0.5)
            bars.footerHeightPx = math.max(0, math.min(MAX_BAR_HEIGHT, numeric))
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplyWindowBars then
                Nvk3UT.TrackerHost.ApplyWindowBars()
            end
        end,
        default = DEFAULT_WINDOW_BARS.footerHeightPx,
    }

    controls[#controls + 1] = {
        type = "button",
        name = "Fenster zurücksetzen",
        func = function()
            local general = getGeneral()
            general.window.left = DEFAULT_WINDOW.left
            general.window.top = DEFAULT_WINDOW.top
            general.window.width = DEFAULT_WINDOW.width
            general.window.height = DEFAULT_WINDOW.height
            general.window.visible = DEFAULT_WINDOW.visible
            general.window.clamp = DEFAULT_WINDOW.clamp
            general.window.onTop = DEFAULT_WINDOW.onTop
            general.window.locked = DEFAULT_WINDOW.locked
            general.WindowBars = general.WindowBars or {}
            general.WindowBars.headerHeightPx = DEFAULT_WINDOW_BARS.headerHeightPx
            general.WindowBars.footerHeightPx = DEFAULT_WINDOW_BARS.footerHeightPx
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            elseif Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplyWindowBars then
                Nvk3UT.TrackerHost.ApplyWindowBars()
            end
        end,
        tooltip = "Setzt Größe, Position und Verhalten des Tracker-Fensters zurück.",
    }

    controls[#controls + 1] = {
        type = "checkbox",
        name = "Standard-Quest-Tracker verstecken",
        getFunc = function()
            local features = getFeatures()
            return features.hideDefaultQuestTracker == true
        end,
        setFunc = function(value)
            local features = getFeatures()
            features.hideDefaultQuestTracker = value == true
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        default = false,
    }

    controls[#controls + 1] = { type = "header", name = "Hintergrund & Darstellung" }

    controls[#controls + 1] = {
        type = "checkbox",
        name = "Hintergrund anzeigen",
        getFunc = function()
            local appearance = getAppearanceSettings()
            return appearance.enabled ~= false
        end,
        setFunc = function(value)
            local appearance = getAppearanceSettings()
            appearance.enabled = value ~= false
            applyHostAppearance()
        end,
        default = true,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Hintergrund-Transparenz (%)",
        min = 0,
        max = 100,
        step = 5,
        getFunc = function()
            local appearance = getAppearanceSettings()
            return math.floor((appearance.alpha or 0) * 100 + 0.5)
        end,
        setFunc = function(value)
            local appearance = getAppearanceSettings()
            appearance.alpha = clamp((tonumber(value) or 0) / 100, 0, 1)
            applyHostAppearance()
        end,
        disabled = function()
            return getAppearanceSettings().enabled == false
        end,
        default = math.floor(DEFAULT_APPEARANCE.alpha * 100 + 0.5),
    }

    controls[#controls + 1] = {
        type = "checkbox",
        name = "Rahmen anzeigen",
        getFunc = function()
            local appearance = getAppearanceSettings()
            return appearance.edgeEnabled ~= false
        end,
        setFunc = function(value)
            local appearance = getAppearanceSettings()
            appearance.edgeEnabled = value ~= false
            applyHostAppearance()
        end,
        default = true,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Rahmen-Transparenz (%)",
        min = 0,
        max = 100,
        step = 5,
        getFunc = function()
            local appearance = getAppearanceSettings()
            return math.floor((appearance.edgeAlpha or 0) * 100 + 0.5)
        end,
        setFunc = function(value)
            local appearance = getAppearanceSettings()
            appearance.edgeAlpha = clamp((tonumber(value) or 0) / 100, 0, 1)
            applyHostAppearance()
        end,
        disabled = function()
            local appearance = getAppearanceSettings()
            return appearance.edgeEnabled == false
        end,
        default = math.floor(DEFAULT_APPEARANCE.edgeAlpha * 100 + 0.5),
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Rahmenbreite",
        min = 1,
        max = 12,
        step = 1,
        getFunc = function()
            local appearance = getAppearanceSettings()
            return appearance.edgeThickness or DEFAULT_APPEARANCE.edgeThickness
        end,
        setFunc = function(value)
            local appearance = getAppearanceSettings()
            local numeric = math.max(1, math.floor((tonumber(value) or appearance.edgeThickness or 1) + 0.5))
            appearance.edgeThickness = numeric
            applyHostAppearance()
        end,
        disabled = function()
            local appearance = getAppearanceSettings()
            return appearance.edgeEnabled == false
        end,
        default = DEFAULT_APPEARANCE.edgeThickness,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Kantenradius",
        min = 0,
        max = 32,
        step = 1,
        getFunc = function()
            local appearance = getAppearanceSettings()
            return appearance.cornerRadius or DEFAULT_APPEARANCE.cornerRadius
        end,
        setFunc = function(value)
            local appearance = getAppearanceSettings()
            local numeric = math.max(0, math.floor((tonumber(value) or appearance.cornerRadius or 0) + 0.5))
            appearance.cornerRadius = numeric
            applyHostAppearance()
        end,
        default = DEFAULT_APPEARANCE.cornerRadius,
    }

    controls[#controls + 1] = {
        type = "dropdown",
        name = "Theme",
        choices = { "dark", "light" },
        getFunc = function()
            local appearance = getAppearanceSettings()
            return appearance.theme or DEFAULT_APPEARANCE.theme
        end,
        setFunc = function(value)
            local appearance = getAppearanceSettings()
            appearance.theme = value or DEFAULT_APPEARANCE.theme
            applyHostAppearance()
        end,
        default = DEFAULT_APPEARANCE.theme,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Innenabstand",
        min = 0,
        max = 48,
        step = 1,
        getFunc = function()
            local appearance = getAppearanceSettings()
            return appearance.padding or 0
        end,
        setFunc = function(value)
            local appearance = getAppearanceSettings()
            appearance.padding = math.max(0, math.floor((tonumber(value) or 0) + 0.5))
            applyHostAppearance()
        end,
        default = DEFAULT_APPEARANCE.padding,
    }

    controls[#controls + 1] = { type = "header", name = "Verhalten" }

    controls[#controls + 1] = {
        type = "checkbox",
        name = "Tracker im Kampf ausblenden",
        tooltip = "Blendet den gesamten Tracker während des Kampfes aus. Bei geöffneten AddOn-Einstellungen bleibt der Tracker sichtbar.",
        getFunc = function()
            local settings = getHostSettings()
            return settings.HideInCombat == true
        end,
        setFunc = function(value)
            local settings = getHostSettings()
            settings.HideInCombat = value == true
            local host = Nvk3UT and Nvk3UT.TrackerHost
            if host and host.ApplyVisibilityRules then
                host:ApplyVisibilityRules()
            end
        end,
        default = false,
    }

    controls[#controls + 1] = { type = "header", name = "Layout & Größe" }

    controls[#controls + 1] = {
        type = "checkbox",
        name = "Automatisch vertikal anpassen",
        getFunc = function()
            local layout = getLayoutSettings()
            return layout.autoGrowV ~= false
        end,
        setFunc = function(value)
            local layout = getLayoutSettings()
            layout.autoGrowV = value ~= false
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        default = DEFAULT_LAYOUT.autoGrowV,
    }

    controls[#controls + 1] = {
        type = "checkbox",
        name = "Automatisch horizontal anpassen",
        getFunc = function()
            local layout = getLayoutSettings()
            return layout.autoGrowH == true
        end,
        setFunc = function(value)
            local layout = getLayoutSettings()
            layout.autoGrowH = value == true
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        default = DEFAULT_LAYOUT.autoGrowH,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Mindestbreite",
        min = 260,
        max = 800,
        step = 10,
        getFunc = function()
            return getLayoutSettings().minWidth
        end,
        setFunc = function(value)
            local layout = getLayoutSettings()
            local numeric = math.floor((tonumber(value) or layout.minWidth) + 0.5)
            numeric = math.max(260, math.min(numeric, layout.maxWidth))
            layout.minWidth = numeric
            if layout.maxWidth < layout.minWidth then
                layout.maxWidth = layout.minWidth
            end
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        default = DEFAULT_LAYOUT.minWidth,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Maximalbreite",
        min = 260,
        max = 1200,
        step = 10,
        getFunc = function()
            return getLayoutSettings().maxWidth
        end,
        setFunc = function(value)
            local layout = getLayoutSettings()
            local numeric = math.floor((tonumber(value) or layout.maxWidth) + 0.5)
            numeric = math.max(layout.minWidth, math.min(numeric, 1200))
            layout.maxWidth = numeric
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        default = DEFAULT_LAYOUT.maxWidth,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Mindesthöhe",
        min = 240,
        max = 900,
        step = 10,
        getFunc = function()
            return getLayoutSettings().minHeight
        end,
        setFunc = function(value)
            local layout = getLayoutSettings()
            local numeric = math.floor((tonumber(value) or layout.minHeight) + 0.5)
            numeric = math.max(240, math.min(numeric, layout.maxHeight))
            layout.minHeight = numeric
            if layout.maxHeight < layout.minHeight then
                layout.maxHeight = layout.minHeight
            end
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        default = DEFAULT_LAYOUT.minHeight,
    }

    controls[#controls + 1] = {
        type = "slider",
        name = "Maximalhöhe",
        min = 240,
        max = 1200,
        step = 10,
        getFunc = function()
            return getLayoutSettings().maxHeight
        end,
        setFunc = function(value)
            local layout = getLayoutSettings()
            local numeric = math.floor((tonumber(value) or layout.maxHeight) + 0.5)
            numeric = math.max(layout.minHeight, math.min(numeric, 1200))
            layout.maxHeight = numeric
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        default = DEFAULT_LAYOUT.maxHeight,
    }

    return controls
end

local function buildEndeavorTrackerControls()
    local controls = {}

    controls[#controls + 1] = { type = "header", name = "Bestrebungen" }
    controls[#controls + 1] = {
        type = "description",
        text = "Bestrebungen-Tracker-Optionen werden mit einem späteren Update ergänzt.",
    }
    controls[#controls + 1] = {
        type = "description",
        text = "Der Tracker nutzt derzeit die globalen Debug- und Host-Einstellungen.",
    }

    return controls
end

local function acquireLam()
    if LibAddonMenu2 then
        return LibAddonMenu2
    end

    if LibStub then
        return LibStub("LibAddonMenu-2.0", true)
    end

    return nil
end

local function registerLamCallbacks(LAM, panelName, panel)
    if not (CALLBACK_MANAGER and LAM and panelName) then
        return
    end

    if L._lamCallbacksRegistered then
        return
    end

    L._lamCallbacksRegistered = true
    L._panelName = panelName
    L._panelDefinition = panel

    local function matchesPanel(control)
        if not control then
            return false
        end

        if L._panelControl and control == L._panelControl then
            return true
        end

        if control.GetName then
            local name = control:GetName()
            if name and name == L._panelName then
                L._panelControl = control
                return true
            end
        end

        local expected = L._panelName and _G[L._panelName]
        if expected and control == expected then
            L._panelControl = expected
            return true
        end

        if control.data and L._panelDefinition and control.data == L._panelDefinition then
            L._panelControl = control
            return true
        end

        return false
    end

    CALLBACK_MANAGER:RegisterCallback("LAM-PanelOpened", function(control)
        if not matchesPanel(control) then
            return
        end

        if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.OnLamPanelOpened then
            pcall(Nvk3UT.TrackerHost.OnLamPanelOpened, control)
        end
    end)

    CALLBACK_MANAGER:RegisterCallback("LAM-PanelClosed", function(control)
        if not matchesPanel(control) then
            return
        end

        if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.OnLamPanelClosed then
            pcall(Nvk3UT.TrackerHost.OnLamPanelClosed, control)
        end
    end)
end

local function registerPanel(displayTitle)
    local LAM = acquireLam()
    if not LAM then
        return false
    end

    if L._registered then
        return true
    end

    local panelName = "Nvk3UT_Panel"

    local versionString = getVersionString()

    local panel = {
        type = "panel",
        name = displayTitle or DEFAULT_PANEL_TITLE,
        displayName = "|c66CCFF" .. (displayTitle or DEFAULT_PANEL_TITLE) .. "|r",
        author = "Nvk3",
        version = versionString,
        registerForRefresh = true,
        registerForDefaults = false,
    }

    local options = {}
    options[#options + 1] = {
        type = "submenu",
        name = "Journal Erweiterungen",
        controls = buildJournalExtensionsControls(),
    }

    options[#options + 1] = {
        type = "submenu",
        name = "Status Text",
        controls = buildStatusTextControls(),
    }

    options[#options + 1] = {
        type = "submenu",
        name = "Tracker Host",
        controls = buildTrackerHostControls(),
    }

    options[#options + 1] = {
        type = "submenu",
        name = "Quest Tracker",
        controls = (function()
            local controls = {}
            controls[#controls + 1] = { type = "header", name = "Quest-Tracker" }

            controls[#controls + 1] = {
                type = "checkbox",
                name = "Quest-Tracker aktiv",
                getFunc = function()
                    local settings = getQuestSettings()
                    return settings.active ~= false
                end,
                setFunc = function(value)
                    local settings = getQuestSettings()
                    settings.active = value
                    if Nvk3UT and Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.SetActive then
                        Nvk3UT.QuestTracker.SetActive(value)
                    end
                    if Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
                        Nvk3UT.UI.UpdateStatus()
                    end
                end,
                default = true,
            }

            controls[#controls + 1] = {
                type = "checkbox",
                name = "Neue Quests automatisch aufklappen",
                getFunc = function()
                    local settings = getQuestSettings()
                    return settings.autoExpand ~= false
                end,
                setFunc = function(value)
                    local settings = getQuestSettings()
                    settings.autoExpand = value
                    applyQuestSettings()
                end,
                default = true,
            }

            controls[#controls + 1] = {
                type = "checkbox",
                name = "Quests beim Anklicken verfolgen",
                tooltip = "Aktiviert die automatische Verfolgung im Questjournal, wenn ein Eintrag im Tracker angeklickt wird. Deaktiviert lässt das Klicken lediglich die Anzeige im Tracker beeinflussen.",
                getFunc = function()
                    local settings = getQuestSettings()
                    return settings.autoTrack ~= false
                end,
                setFunc = function(value)
                    local settings = getQuestSettings()
                    settings.autoTrack = value ~= false
                    applyQuestSettings()
                end,
                default = true,
            }

            controls[#controls + 1] = {
                type = "checkbox",
                name = "Show counts in category headers",
                tooltip = "If enabled, category headers display the number of contained entries, e.g., 'Repeatable (12)'. Disable to hide the counts.",
                getFunc = function()
                    local general = getGeneral()
                    return general.showQuestCategoryCounts ~= false
                end,
                setFunc = function(value)
                    local general = getGeneral()
                    general.showQuestCategoryCounts = value ~= false
                    refreshQuestTracker()
                end,
                default = true,
            }

            controls[#controls + 1] = { type = "header", name = "Quest Tracker Colors" }

            controls[#controls + 1] = {
                type = "colorpicker",
                name = "Category / Section Title Color",
                tooltip = "Adjusts the color of zone headers and category titles in the quest tracker.",
                getFunc = function()
                    return getTrackerColor("questTracker", "categoryTitle")
                end,
                setFunc = function(r, g, b, a)
                    setTrackerColor("questTracker", "categoryTitle", r, g, b, a or 1)
                    refreshQuestTracker()
                end,
                default = getTrackerColorDefaultTable("questTracker", "categoryTitle"),
            }

            controls[#controls + 1] = {
                type = "colorpicker",
                name = "Quest / Achievement Name Color",
                tooltip = "Sets the color used for quest titles within the quest tracker.",
                getFunc = function()
                    return getTrackerColor("questTracker", "entryTitle")
                end,
                setFunc = function(r, g, b, a)
                    setTrackerColor("questTracker", "entryTitle", r, g, b, a or 1)
                    refreshQuestTracker()
                end,
                default = getTrackerColorDefaultTable("questTracker", "entryTitle"),
            }

            controls[#controls + 1] = {
                type = "colorpicker",
                name = "Objective / Step Text Color",
                tooltip = "Controls the color for objective and step lines beneath each quest.",
                getFunc = function()
                    return getTrackerColor("questTracker", "objectiveText")
                end,
                setFunc = function(r, g, b, a)
                    setTrackerColor("questTracker", "objectiveText", r, g, b, a or 1)
                    refreshQuestTracker()
                end,
                default = getTrackerColorDefaultTable("questTracker", "objectiveText"),
            }

            controls[#controls + 1] = {
                type = "colorpicker",
                name = "Active / Focused Entry Color",
                tooltip = "Defines the color for the currently assisted quest entry.",
                getFunc = function()
                    return getTrackerColor("questTracker", "activeTitle")
                end,
                setFunc = function(r, g, b, a)
                    setTrackerColor("questTracker", "activeTitle", r, g, b, a or 1)
                    refreshQuestTracker()
                end,
                default = getTrackerColorDefaultTable("questTracker", "activeTitle"),
            }

            controls[#controls + 1] = { type = "header", name = "Quest-Tracker Schriftarten" }

            local fontGroups = {
                { key = "category", label = "Kategorie-Header" },
                { key = "title", label = "Questtitel" },
                { key = "line", label = "Questzeilen" },
            }

            for index = 1, #fontGroups do
                local group = fontGroups[index]
                local fontControls = buildFontControls(
                    group.label,
                    getQuestSettings(),
                    group.key,
                    questFontDefaults(group.key),
                    function()
                        applyQuestTheme()
                        refreshQuestTracker()
                    end
                )
                for i = 1, #fontControls do
                    controls[#controls + 1] = fontControls[i]
                end
            end

            return controls
        end)(),
    }

    options[#options + 1] = {
        type = "submenu",
        name = "Bestrebungen Tracker",
        controls = buildEndeavorTrackerControls(),
    }

    options[#options + 1] = {
        type = "submenu",
        name = "Errungenschaften Tracker",
        controls = (function()
            local controls = {}
            controls[#controls + 1] = { type = "header", name = "Erfolgstracker" }

            controls[#controls + 1] = {
                type = "checkbox",
                name = "Erfolgstracker aktiv",
                getFunc = function()
                    local settings = getAchievementSettings()
                    return settings.active ~= false
                end,
                setFunc = function(value)
                    local settings = getAchievementSettings()
                    settings.active = value
                    if Nvk3UT and Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.SetActive then
                        Nvk3UT.AchievementTracker.SetActive(value)
                    end
                end,
                default = true,
            }

            controls[#controls + 1] = {
                type = "checkbox",
                name = "Show counts in category headers",
                tooltip = "If enabled, category headers display the number of contained entries, e.g., 'Repeatable (12)'. Disable to hide the counts.",
                getFunc = function()
                    local general = getGeneral()
                    return general.showAchievementCategoryCounts ~= false
                end,
                setFunc = function(value)
                    local general = getGeneral()
                    general.showAchievementCategoryCounts = value ~= false
                    refreshAchievementTracker()
                end,
                default = true,
            }

            controls[#controls + 1] = {
                type = "checkbox",
                name = "Tracker-Tooltips aktiv",
                getFunc = function()
                    local settings = getAchievementSettings()
                    return settings.tooltips ~= false
                end,
                setFunc = function(value)
                    local settings = getAchievementSettings()
                    settings.tooltips = value
                    applyAchievementSettings()
                end,
                default = true,
            }

            controls[#controls + 1] = {
                type = "checkbox",
                name = "Errungenschafts-Tooltips ein",
                getFunc = function()
                    local general = getGeneral()
                    return general.features.tooltips ~= false
                end,
                setFunc = function(value)
                    local general = getGeneral()
                    general.features.tooltips = value
                    updateTooltips(value)
                end,
                default = true,
            }

            controls[#controls + 1] = { type = "header", name = "Achievement Tracker Colors" }

            controls[#controls + 1] = {
                type = "colorpicker",
                name = "Category / Section Title Color",
                tooltip = "Adjusts the color of section headers in the achievement tracker.",
                getFunc = function()
                    return getTrackerColor("achievementTracker", "categoryTitle")
                end,
                setFunc = function(r, g, b, a)
                    setTrackerColor("achievementTracker", "categoryTitle", r, g, b, a or 1)
                    refreshAchievementTracker()
                end,
                default = getTrackerColorDefaultTable("achievementTracker", "categoryTitle"),
            }

            controls[#controls + 1] = {
                type = "colorpicker",
                name = "Quest / Achievement Name Color",
                tooltip = "Sets the color used for achievement titles in the tracker.",
                getFunc = function()
                    return getTrackerColor("achievementTracker", "entryTitle")
                end,
                setFunc = function(r, g, b, a)
                    setTrackerColor("achievementTracker", "entryTitle", r, g, b, a or 1)
                    refreshAchievementTracker()
                end,
                default = getTrackerColorDefaultTable("achievementTracker", "entryTitle"),
            }

            controls[#controls + 1] = {
                type = "colorpicker",
                name = "Objective / Step Text Color",
                tooltip = "Controls the color of objective lines shown beneath tracked achievements.",
                getFunc = function()
                    return getTrackerColor("achievementTracker", "objectiveText")
                end,
                setFunc = function(r, g, b, a)
                    setTrackerColor("achievementTracker", "objectiveText", r, g, b, a or 1)
                    refreshAchievementTracker()
                end,
                default = getTrackerColorDefaultTable("achievementTracker", "objectiveText"),
            }

            controls[#controls + 1] = {
                type = "colorpicker",
                name = "Active / Focused Entry Color",
                tooltip = "Reserved for future use. Defines the color for a focused achievement entry when applicable.",
                getFunc = function()
                    return getTrackerColor("achievementTracker", "activeTitle")
                end,
                setFunc = function(r, g, b, a)
                    setTrackerColor("achievementTracker", "activeTitle", r, g, b, a or 1)
                    refreshAchievementTracker()
                end,
                default = getTrackerColorDefaultTable("achievementTracker", "activeTitle"),
            }

            controls[#controls + 1] = { type = "header", name = "Erfolgstracker Schriftarten" }

            local fontGroups = {
                { key = "category", label = "Kategorie-Header" },
                { key = "title", label = "Titel" },
                { key = "line", label = "Zeilen" },
            }

            for index = 1, #fontGroups do
                local group = fontGroups[index]
                local fontControls = buildFontControls(
                    group.label,
                    getAchievementSettings(),
                    group.key,
                    achievementFontDefaults(group.key),
                    function()
                        applyAchievementTheme()
                        refreshAchievementTracker()
                    end
                )
                for i = 1, #fontControls do
                    controls[#controls + 1] = fontControls[i]
                end
            end

            return controls
        end)(),
    }

    options[#options + 1] = {
        type = "submenu",
        name = "Debug & Support",
        controls = (function()
            local controls = {}
            controls[#controls + 1] = {
                type = "checkbox",
                name = "Debug aktivieren",
                getFunc = function()
                    local sv = getSavedVars()
                    return sv.debug == true
                end,
                setFunc = function(value)
                    local sv = getSavedVars()
                    local enabled = value and true or false
                    sv.debug = enabled

                    if Nvk3UT_Diagnostics and type(Nvk3UT_Diagnostics.SetDebugEnabled) == "function" then
                        pcall(Nvk3UT_Diagnostics.SetDebugEnabled, enabled)
                    end

                    local addon = Nvk3UT
                    if addon and type(addon.SetDebugEnabled) == "function" then
                        pcall(addon.SetDebugEnabled, addon, enabled)
                    end
                end,
                default = false,
            }

            controls[#controls + 1] = {
                type = "button",
                name = "Self-Test ausführen",
                func = function()
                    local module = nil
                    if Nvk3UT and Nvk3UT.SelfTest then
                        module = Nvk3UT.SelfTest
                    elseif rawget(_G, "Nvk3UT_SelfTest") then
                        module = Nvk3UT_SelfTest
                    end

                    if module and type(module.Run) == "function" then
                        if Nvk3UT_Diagnostics and type(Nvk3UT_Diagnostics.Warn) == "function" then
                            Nvk3UT_Diagnostics.Warn("Self-Test requested from settings panel")
                        elseif type(d) == "function" then
                            d("[Nvk3UT WARN] Self-Test requested from settings panel")
                        end

                        local ok, err = pcall(module.Run)
                        if not ok then
                            local message = string.format("Self-Test failed to execute: %s", tostring(err))
                            if Nvk3UT_Diagnostics and type(Nvk3UT_Diagnostics.Error) == "function" then
                                Nvk3UT_Diagnostics.Error(message)
                            elseif type(d) == "function" then
                                d(string.format("|cFF0000[Nvk3UT ERROR]|r %s", message))
                            end
                        end
                    else
                        local message = "Self-Test module not available; cannot run diagnostics"
                        if Nvk3UT_Diagnostics and type(Nvk3UT_Diagnostics.Error) == "function" then
                            Nvk3UT_Diagnostics.Error(message)
                        elseif type(d) == "function" then
                            d(string.format("|cFF0000[Nvk3UT ERROR]|r %s", message))
                        end
                    end
                end,
                tooltip = "Führt einen kompakten Integritäts-Check aus. Bei aktiviertem Debug erscheinen ausführliche Chat-Logs.",
            }

            controls[#controls + 1] = {
                type = "button",
                name = "UI neu laden",
                func = function()
                    ReloadUI()
                end,
            }

            return controls
        end)(),
    }

    LAM:RegisterAddonPanel(panelName, panel)
    LAM:RegisterOptionControls(panelName, options)

    registerLamCallbacks(LAM, panelName, panel)

    L._registered = true
    return true
end

local lamWaitEventName = "Nvk3UT_LAM_WaitForLibrary"
local lamWaitRegistered = false
local pendingPanelTitle = nil

local function waitForLam()
    if lamWaitRegistered then
        return
    end

    if not EVENT_MANAGER then
        return
    end

    lamWaitRegistered = true

    EVENT_MANAGER:RegisterForEvent(lamWaitEventName, EVENT_ADD_ON_LOADED, function(_, addonName)
        if addonName ~= "LibAddonMenu-2.0" then
            return
        end

        if registerPanel(pendingPanelTitle) then
            EVENT_MANAGER:UnregisterForEvent(lamWaitEventName, EVENT_ADD_ON_LOADED)
            lamWaitRegistered = false
        end
    end)

    if zo_callLater then
        local attempts = 0
        local function retry()
            if L._registered then
                return
            end

            attempts = attempts + 1
            if registerPanel(pendingPanelTitle) then
                if EVENT_MANAGER then
                    EVENT_MANAGER:UnregisterForEvent(lamWaitEventName, EVENT_ADD_ON_LOADED)
                end
                lamWaitRegistered = false
                return
            end

            if attempts < 10 then
                zo_callLater(retry, 500)
            end
        end

        zo_callLater(retry, 500)
    end
end

function L.Build(displayTitle)
    if L._registered then
        return
    end

    pendingPanelTitle = displayTitle or pendingPanelTitle or DEFAULT_PANEL_TITLE

    if registerPanel(pendingPanelTitle) then
        return
    end

    waitForLam()
end

local function ensureRegisteredWhenReady()
    if L._registered then
        return
    end

    if not (Nvk3UT and Nvk3UT.sv) then
        if zo_callLater then
            zo_callLater(ensureRegisteredWhenReady, 100)
        end
        return
    end

    pendingPanelTitle = pendingPanelTitle or DEFAULT_PANEL_TITLE

    if registerPanel(pendingPanelTitle) then
        return
    end

    waitForLam()
end

if EVENT_MANAGER then
    local lamInitEvent = "Nvk3UT_LAM_OnAddonLoaded"
    EVENT_MANAGER:RegisterForEvent(lamInitEvent, EVENT_ADD_ON_LOADED, function(_, addonName)
        if addonName ~= ADDON_NAME then
            return
        end

        EVENT_MANAGER:UnregisterForEvent(lamInitEvent, EVENT_ADD_ON_LOADED)

        ensureRegisteredWhenReady()
    end)
end

return L
