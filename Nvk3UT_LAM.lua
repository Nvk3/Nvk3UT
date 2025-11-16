Nvk3UT = Nvk3UT or {}

local ADDON_NAME = "Nvk3UT"
local DEFAULT_PANEL_TITLE = "Nvk3's Ultimate Tracker"

local L = {}
Nvk3UT.LAM = L

local function registerString(id, text)
    if type(id) ~= "string" or id == "" then
        return
    end

    if type(text) ~= "string" then
        text = tostring(text or "")
    end

    local stringId = _G[id]
    if type(stringId) == "number" then
        if type(SafeAddString) == "function" then
            SafeAddString(stringId, text, 1)
        end
        return
    end

    if type(ZO_CreateStringId) == "function" then
        ZO_CreateStringId(id, text)
    else
        _G[id] = text
    end
end

registerString("SI_NVK3UT_LAM_ENDEAVOR_SECTION_FUNCTIONS", "FUNKTIONEN")
registerString("SI_NVK3UT_LAM_ENDEAVOR_ENABLE", "Aktivieren")
registerString("SI_NVK3UT_LAM_ENDEAVOR_ENABLE_TOOLTIP", "Schaltet den Bestrebungen-Tracker ein oder aus.")
registerString("SI_NVK3UT_LAM_ENDEAVOR_SHOW_COUNTS", "Zähler in Abschnittsüberschriften anzeigen")
registerString(
    "SI_NVK3UT_LAM_ENDEAVOR_SHOW_COUNTS_TOOLTIP",
    "Zeigt die verbleibende Anzahl direkt hinter den Überschriften an.\nWirkt nur auf die Hauptkategorie. Täglich und Wöchentlich zeigen Zähler immer."
)
registerString("SI_NVK3UT_LAM_ENDEAVOR_COMPLETED_HEADER", "Abgeschlossen-Handling")
registerString(
    "SI_NVK3UT_LAM_ENDEAVOR_COMPLETED_TOOLTIP",
    "Legt fest, wie abgeschlossene Ziele dargestellt werden."
)
registerString("SI_NVK3UT_LAM_ENDEAVOR_COMPLETED_HIDE", "Ausblenden")
registerString("SI_NVK3UT_LAM_ENDEAVOR_COMPLETED_RECOLOR", "Umfärben")
registerString("SI_NVK3UT_LAM_ENDEAVOR_SECTION_COLORS", "ERSCHEINUNG – FARBEN")
registerString("SI_NVK3UT_LAM_ENDEAVOR_COLOR_CATEGORY", "Kategorie- / Abschnittstitel")
registerString(
    "SI_NVK3UT_LAM_ENDEAVOR_COLOR_CATEGORY_TOOLTIP",
    "Farbe für den oberen Bestrebungen-Block."
)
registerString("SI_NVK3UT_LAM_ENDEAVOR_COLOR_ENTRY", "Eintragsname")
registerString(
    "SI_NVK3UT_LAM_ENDEAVOR_COLOR_ENTRY_TOOLTIP",
    "Farbe für tägliche und wöchentliche Bestrebungen."
)
registerString("SI_NVK3UT_LAM_ENDEAVOR_COLOR_OBJECTIVE", "Zieltext")
registerString(
    "SI_NVK3UT_LAM_ENDEAVOR_COLOR_OBJECTIVE_TOOLTIP",
    "Farbe für die Fortschrittszeilen der einzelnen Ziele."
)
registerString("SI_NVK3UT_LAM_ENDEAVOR_COLOR_ACTIVE", "Aktiver / fokussierter Eintrag")
registerString(
    "SI_NVK3UT_LAM_ENDEAVOR_COLOR_ACTIVE_TOOLTIP",
    "Farbe, wenn ein Abschnitt geöffnet oder fokussiert ist."
)
registerString("SI_NVK3UT_LAM_ENDEAVOR_COLOR_COMPLETED", "Abgeschlossener Eintrag")
registerString(
    "SI_NVK3UT_LAM_ENDEAVOR_COLOR_COMPLETED_TOOLTIP",
    "Farbe für abgeschlossene Ziele, wenn \"Umfärben\" aktiv ist."
)
registerString("SI_NVK3UT_LAM_ENDEAVOR_SECTION_FONTS", "ERSCHEINUNG – SCHRIFTARTEN")
registerString("SI_NVK3UT_LAM_ENDEAVOR_FONT_FAMILY", "Schriftart")
registerString(
    "SI_NVK3UT_LAM_ENDEAVOR_FONT_FAMILY_TOOLTIP",
    "Wählt die Schriftart für Kategorien, Abschnitte und Ziele."
)
registerString("SI_NVK3UT_LAM_ENDEAVOR_FONT_SIZE", "Größe")
registerString(
    "SI_NVK3UT_LAM_ENDEAVOR_FONT_SIZE_TOOLTIP",
    "Legt die Basisschriftgröße des Trackers fest."
)
registerString("SI_NVK3UT_LAM_ENDEAVOR_FONT_OUTLINE", "Kontur")
registerString(
    "SI_NVK3UT_LAM_ENDEAVOR_FONT_OUTLINE_TOOLTIP",
    "Bestimmt die Kontur bzw. den Schatten der Schrift."
)

local function getAddonVersionString()
    local addon = Nvk3UT
    if type(addon) ~= "table" then
        return nil
    end

    local versionString = addon.versionString or addon.addonVersion
    if type(versionString) == "number" then
        versionString = tostring(versionString)
    elseif type(versionString) ~= "string" then
        versionString = nil
    end

    if versionString == nil or versionString == "" then
        return nil
    end

    local major, minor, patch = versionString:match("(%d+)%.(%d+)%.(%d+)")
    if major and minor and patch then
        return string.format("%d.%d.%d", tonumber(major), tonumber(minor), tonumber(patch))
    end

    return versionString
end

local FONT_FACE_CHOICES = {
    { name = "Bold (Game Default)", face = "$(BOLD_FONT)" },
    { name = "Univers 67 (Game)", face = "EsoUI/Common/Fonts/univers67.otf" },
    { name = "Univers 57 (Game)", face = "EsoUI/Common/Fonts/univers57.otf" },
    { name = "Futura (Antique)", face = "EsoUI/Common/Fonts/ProseAntiquePSMT.otf" },
    { name = "Handschrift", face = "EsoUI/Common/Fonts/Handwritten_Bold.otf" },
    { name = "Trajan", face = "EsoUI/Common/Fonts/TrajanPro-Regular.otf" },
}

local FONT_FACE_NAMES, FONT_FACE_VALUES = (function()
    local names, values = {}, {}
    for index = 1, #FONT_FACE_CHOICES do
        names[index] = FONT_FACE_CHOICES[index].name
        values[index] = FONT_FACE_CHOICES[index].face
    end
    return names, values
end)()

local OUTLINE_CHOICES = {
    { name = "Keiner", value = "none" },
    { name = "Weich (dünn)", value = "soft-shadow-thin" },
    { name = "Weich (dick)", value = "soft-shadow-thick" },
    { name = "Schatten", value = "shadow" },
    { name = "Kontur", value = "outline" },
}

local OUTLINE_NAMES, OUTLINE_VALUES = (function()
    local names, values = {}, {}
    for index = 1, #OUTLINE_CHOICES do
        names[index] = OUTLINE_CHOICES[index].name
        values[index] = OUTLINE_CHOICES[index].value
    end
    return names, values
end)()

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
        layout.autoGrowV = layout.autoGrowV == true
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

local ENDEAVOR_COLOR_ROLES = {
    CategoryTitle = "categoryTitle",
    EntryName = "entryTitle",
    Objective = "objectiveText",
    Active = "activeTitle",
    Completed = "completed",
}

local function getEndeavorConfig()
    local sv = getSavedVars()
    sv.Endeavor = sv.Endeavor or {}
    local config = sv.Endeavor
    config.Colors = config.Colors or {}
    config.Font = config.Font or {}
    config.Tracker = config.Tracker or {}
    config.Tracker.Fonts = config.Tracker.Fonts or {}
    return config
end

local function LamQueueFullRebuild(reason)
    local context = "lam"
    if reason ~= nil then
        local suffix = tostring(reason)
        if suffix ~= "" then
            context = string.format("lam:%s", suffix)
        end
    end

    local addon = type(Nvk3UT) == "table" and Nvk3UT or nil
    local rebuild = addon and addon.Rebuild
    if type(rebuild) ~= "table" then
        local globalRoot = type(_G) == "table" and _G.Nvk3UT_Rebuild or Nvk3UT_Rebuild
        if type(globalRoot) == "table" then
            rebuild = globalRoot
        end
    end

    if type(rebuild) ~= "table" then
        return false
    end

    local sections = rebuild.Sections or rebuild.sections
    if type(sections) == "function" then
        local ok, triggered = pcall(sections, { "trackers", "layout" }, context)
        if ok then
            if triggered == nil then
                return true
            end
            return triggered ~= false
        end
        return false
    end

    local rebuildAll = rebuild.All or rebuild.all
    if type(rebuildAll) == "function" then
        local ok, triggered = pcall(rebuildAll, context)
        if ok then
            if triggered == nil then
                return true
            end
            return triggered ~= false
        end
    end

    return false
end

local function clampEndeavorFontSize(value)
    local numeric = tonumber(value)
    if numeric == nil then
        numeric = DEFAULT_FONT_SIZE.achievement.title
    end
    numeric = math.floor(numeric + 0.5)
    if numeric < 12 then
        numeric = 12
    elseif numeric > 36 then
        numeric = 36
    end
    return numeric
end

local function getEndeavorColor(colorKey, role)
    ensureTrackerAppearance()
    local config = getEndeavorConfig()
    local color = config.Colors[colorKey]
    if type(color) == "table" then
        local r = color.r or color[1] or 1
        local g = color.g or color[2] or 1
        local b = color.b or color[3] or 1
        local a = color.a or color[4] or 1
        return r, g, b, a
    end
    return getTrackerColor("endeavorTracker", role)
end

local function setEndeavorColor(colorKey, role, r, g, b, a)
    local config = getEndeavorConfig()
    local resolvedR = r or 1
    local resolvedG = g or 1
    local resolvedB = b or 1
    local resolvedA = a or 1
    local color = config.Colors[colorKey]
    if type(color) ~= "table" then
        color = {}
        config.Colors[colorKey] = color
    end
    color[1], color[2], color[3], color[4] = resolvedR, resolvedG, resolvedB, resolvedA
    color.r, color.g, color.b, color.a = resolvedR, resolvedG, resolvedB, resolvedA
    setTrackerColor("endeavorTracker", role, resolvedR, resolvedG, resolvedB, resolvedA)
end

local function refreshEndeavorModel()
    local model = Nvk3UT and Nvk3UT.EndeavorModel
    if type(model) == "table" then
        local refresh = model.RefreshFromGame or model.Refresh
        if type(refresh) == "function" then
            pcall(refresh, model)
        end
    end
end

local function markEndeavorDirty(reason)
    local controller = Nvk3UT and Nvk3UT.EndeavorTrackerController
    if type(controller) == "table" then
        local markDirty = controller.MarkDirty or controller.RequestRefresh
        if type(markDirty) == "function" then
            pcall(markDirty, controller, reason)
        end
    end
end

local function queueEndeavorDirty()
    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if type(runtime) == "table" then
        local queueDirty = runtime.QueueDirty or runtime.MarkDirty or runtime.RequestRefresh
        if type(queueDirty) == "function" then
            pcall(queueDirty, runtime, "endeavor")
        end
    end
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

local function endeavorFontDefaults(key)
    local defaults = DEFAULT_FONT_SIZE.achievement
    local normalized = type(key) == "string" and string.lower(key) or ""
    local size = defaults.title
    if normalized == "category" then
        size = defaults.category
    elseif normalized == "objective" then
        size = defaults.line
    end
    return {
        Face = FONT_FACE_CHOICES[1].face,
        Size = size,
        Outline = "soft-shadow-thick",
    }
end

local function ensureEndeavorFontGroup(config, key, defaults)
    local defaultsValue = defaults
    if type(defaultsValue) == "function" then
        defaultsValue = defaults()
    end
    if defaultsValue == nil then
        defaultsValue = endeavorFontDefaults(key)
    end

    if type(config) ~= "table" then
        return defaultsValue
    end

    config.Tracker = config.Tracker or {}
    local tracker = config.Tracker
    tracker.Fonts = tracker.Fonts or {}
    local fonts = tracker.Fonts

    local group = fonts[key]
    if type(group) ~= "table" then
        local altKey = type(key) == "string" and string.lower(key) or nil
        if altKey and type(fonts[altKey]) == "table" then
            group = fonts[altKey]
        else
            group = {}
        end
        fonts[key] = group
    else
        fonts[key] = group
    end

    if type(group.face) == "string" and (group.Face == nil or group.Face == "") then
        group.Face = group.face
    end
    if group.size ~= nil and (group.Size == nil or group.Size == 0) then
        group.Size = group.size
    end
    if type(group.outline) == "string" and (group.Outline == nil or group.Outline == "") then
        group.Outline = group.outline
    end

    if type(group.Face) ~= "string" or group.Face == "" then
        group.Face = defaultsValue.Face or FONT_FACE_CHOICES[1].face
    end

    group.Size = clampEndeavorFontSize(group.Size or defaultsValue.Size)

    if type(group.Outline) ~= "string" or group.Outline == "" then
        group.Outline = defaultsValue.Outline or OUTLINE_CHOICES[3].value
    end

    return group
end

local function buildFontControls(label, settings, key, defaults, onChanged, adapter)
    adapter = adapter or {}
    local ensureTarget = adapter.ensureFont or ensureFont
    local clampSize = adapter.clampSize or function(value)
        local numeric = tonumber(value)
        if numeric == nil then
            return 16
        end
        return math.floor(numeric + 0.5)
    end
    local getFace = adapter.getFace or function(font)
        return font.face
    end
    local setFace = adapter.setFace or function(font, value)
        font.face = value
    end
    local getSize = adapter.getSize or function(font)
        return font.size
    end
    local setSize = adapter.setSize or function(font, value)
        font.size = value
    end
    local getOutline = adapter.getOutline or function(font)
        return font.outline
    end
    local setOutline = adapter.setOutline or function(font, value)
        font.outline = value
    end

    local defaultsFactory
    if type(defaults) == "function" then
        defaultsFactory = defaults
    else
        defaultsFactory = function()
            return defaults
        end
    end

    local function ensureFontInstance()
        return ensureTarget(settings, key, defaultsFactory())
    end

    local function triggerChanged()
        if type(onChanged) == "function" then
            onChanged()
        end
    end

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
                local font = ensureFontInstance()
                return getFace(font)
            end,
            setFunc = function(value)
                local font = ensureFontInstance()
                setFace(font, value)
                triggerChanged()
            end,
        },
        {
            type = "slider",
            name = label .. " - Größe",
            min = 12,
            max = 36,
            step = 1,
            getFunc = function()
                local font = ensureFontInstance()
                return getSize(font)
            end,
            setFunc = function(value)
                local font = ensureFontInstance()
                setSize(font, clampSize(value))
                triggerChanged()
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
                local font = ensureFontInstance()
                return getOutline(font)
            end,
            setFunc = function(value)
                local font = ensureFontInstance()
                setOutline(font, value)
                triggerChanged()
            end,
        },
    }
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

    local panel = {
        type = "panel",
        name = displayTitle or DEFAULT_PANEL_TITLE,
        displayName = "|c66CCFF" .. (displayTitle or DEFAULT_PANEL_TITLE) .. "|r",
        author = "Nvk3",
        version = getAddonVersionString() or "Unknown",
        registerForRefresh = true,
        registerForDefaults = false,
    }

    local options = {}
    options[#options + 1] = {
        type = "submenu",
        name = "Journal Erweiterungen",
        controls = (function()
            local controls = {}

            controls[#controls + 1] = { type = "header", name = "Favoriten & Daten" }

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
                        cache.OnOptionsChanged({ key = "favorites" })
                    end
                    updateStatus()
                end,
                tooltip = "Bestimmt, ob Favoriten global (Account) oder je Charakter gespeichert werden.",
                default = "account",
            }

            controls[#controls + 1] = {
                type = "slider",
                name = "Kürzlich-History (max. Einträge)",
                min = 25,
                max = 200,
                step = 5,
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
        end)(),
    }

    options[#options + 1] = {
        type = "submenu",
        name = "Status Text",
        controls = (function()
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

            return controls
        end)(),
    }

    options[#options + 1] = {
        type = "submenu",
        name = "Tracker Host",
        controls = (function()
            local controls = {}

            controls[#controls + 1] = { type = "header", name = "Fenster & Darstellung" }

            local function addControl(control)
                controls[#controls + 1] = control
            end

            addControl({
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
            })

            addControl({
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
            })

            addControl({
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
            })

            addControl({
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
            })

            addControl({
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
                    return getLayoutSettings().autoGrowV == true
                end,
                default = DEFAULT_WINDOW.height,
            })

            addControl({
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
                    local numeric = math.max(0, math.min(MAX_BAR_HEIGHT, math.floor((tonumber(value) or 0) + 0.5)))
                    bars.headerHeightPx = numeric
                    if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplyWindowBars then
                        Nvk3UT.TrackerHost.ApplyWindowBars()
                    end
                end,
                tooltip = "0 px blendet den Bereich aus.",
                default = DEFAULT_WINDOW_BARS.headerHeightPx,
            })

            addControl({
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
                    local numeric = math.max(0, math.min(MAX_BAR_HEIGHT, math.floor((tonumber(value) or 0) + 0.5)))
                    bars.footerHeightPx = numeric
                    if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplyWindowBars then
                        Nvk3UT.TrackerHost.ApplyWindowBars()
                    end
                end,
                tooltip = "0 px blendet den Bereich aus.",
                default = DEFAULT_WINDOW_BARS.footerHeightPx,
            })

            addControl({
                type = "button",
                name = "Position zurücksetzen",
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
            })

            addControl({
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
            })

            addControl({
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
            })

            addControl({
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
            })

            addControl({
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
            })

            addControl({
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
            })

            addControl({
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
                    return getAppearanceSettings().edgeEnabled == false
                end,
                default = DEFAULT_APPEARANCE.edgeThickness,
            })

            addControl({
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
            })

            controls[#controls + 1] = { type = "header", name = "Auto-Resize & Layout" }

            addControl({
                type = "checkbox",
                name = "Automatisch vertikal anpassen",
                getFunc = function()
                    local layout = getLayoutSettings()
                    return layout.autoGrowV == true
                end,
                setFunc = function(value)
                    local layout = getLayoutSettings()
                    layout.autoGrowV = value == true
                    if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                        Nvk3UT.TrackerHost.ApplySettings()
                    end
                end,
                default = DEFAULT_LAYOUT.autoGrowV,
            })

            addControl({
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
            })

            addControl({
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
            })

            addControl({
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
            })

            addControl({
                type = "slider",
                name = "Mindesthöhe",
                min = 240,
                max = 800,
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
            })

            addControl({
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
            })

            controls[#controls + 1] = { type = "header", name = "Verhalten" }

            addControl({
                type = "checkbox",
                name = "Hide tracker during combat",
                tooltip = "When enabled, the entire tracker host hides while you are in combat. The tracker remains visible while the AddOn Settings (LAM) are open.",
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
            })

            return controls
        end)(),
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
                    if LamQueueFullRebuild("questActive") then
                        return
                    end
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
        controls = (function()
            local controls = {}
            controls[#controls + 1] = { type = "header", name = GetString(SI_NVK3UT_LAM_ENDEAVOR_SECTION_FUNCTIONS) }

            controls[#controls + 1] = {
                type = "checkbox",
                name = GetString(SI_NVK3UT_LAM_ENDEAVOR_ENABLE),
                tooltip = GetString(SI_NVK3UT_LAM_ENDEAVOR_ENABLE_TOOLTIP),
                getFunc = function()
                    local config = getEndeavorConfig()
                    if config.Enabled == nil then
                        local achievement = getAchievementSettings()
                        return achievement.active ~= false
                    end
                    return config.Enabled ~= false
                end,
                setFunc = function(value)
                    local config = getEndeavorConfig()
                    config.Enabled = value ~= false
                    refreshEndeavorModel()
                    if LamQueueFullRebuild("endeavorEnable") then
                        return
                    end
                    markEndeavorDirty("enable")
                    queueEndeavorDirty()
                end,
                default = (function()
                    local achievement = getAchievementSettings()
                    return achievement.active ~= false
                end)(),
            }

            controls[#controls + 1] = {
                type = "checkbox",
                name = GetString(SI_NVK3UT_LAM_ENDEAVOR_SHOW_COUNTS),
                tooltip = GetString(SI_NVK3UT_LAM_ENDEAVOR_SHOW_COUNTS_TOOLTIP),
                getFunc = function()
                    local config = getEndeavorConfig()
                    if config.ShowCountsInHeaders == nil then
                        local general = getGeneral()
                        return general.showAchievementCategoryCounts ~= false
                    end
                    return config.ShowCountsInHeaders ~= false
                end,
                setFunc = function(value)
                    local config = getEndeavorConfig()
                    config.ShowCountsInHeaders = value ~= false
                    markEndeavorDirty("headers")
                    queueEndeavorDirty()
                end,
                default = (function()
                    local general = getGeneral()
                    return general.showAchievementCategoryCounts ~= false
                end)(),
            }

            controls[#controls + 1] = {
                type = "dropdown",
                name = GetString(SI_NVK3UT_LAM_ENDEAVOR_COMPLETED_HEADER),
                tooltip = GetString(SI_NVK3UT_LAM_ENDEAVOR_COMPLETED_TOOLTIP),
                choices = {
                    GetString(SI_NVK3UT_LAM_ENDEAVOR_COMPLETED_HIDE),
                    GetString(SI_NVK3UT_LAM_ENDEAVOR_COMPLETED_RECOLOR),
                },
                choicesValues = { "hide", "recolor" },
                getFunc = function()
                    local config = getEndeavorConfig()
                    if config.CompletedHandling == "recolor" then
                        return "recolor"
                    end
                    return "hide"
                end,
                setFunc = function(value)
                    local config = getEndeavorConfig()
                    local resolved = value == "recolor" and "recolor" or "hide"
                    config.CompletedHandling = resolved
                    refreshEndeavorModel()
                    if LamQueueFullRebuild("endeavorCompletedHandling") then
                        return
                    end
                    if resolved == "hide" then
                        markEndeavorDirty("filter")
                    else
                        markEndeavorDirty("appearance")
                    end
                    queueEndeavorDirty()
                end,
                default = "hide",
            }

            controls[#controls + 1] = { type = "header", name = GetString(SI_NVK3UT_LAM_ENDEAVOR_SECTION_COLORS) }

            local colorEntries = {
                {
                    key = "CategoryTitle",
                    role = ENDEAVOR_COLOR_ROLES.CategoryTitle,
                    name = SI_NVK3UT_LAM_ENDEAVOR_COLOR_CATEGORY,
                    tooltip = SI_NVK3UT_LAM_ENDEAVOR_COLOR_CATEGORY_TOOLTIP,
                },
                {
                    key = "EntryName",
                    role = ENDEAVOR_COLOR_ROLES.EntryName,
                    name = SI_NVK3UT_LAM_ENDEAVOR_COLOR_ENTRY,
                    tooltip = SI_NVK3UT_LAM_ENDEAVOR_COLOR_ENTRY_TOOLTIP,
                },
                {
                    key = "Objective",
                    role = ENDEAVOR_COLOR_ROLES.Objective,
                    name = SI_NVK3UT_LAM_ENDEAVOR_COLOR_OBJECTIVE,
                    tooltip = SI_NVK3UT_LAM_ENDEAVOR_COLOR_OBJECTIVE_TOOLTIP,
                },
                {
                    key = "Active",
                    role = ENDEAVOR_COLOR_ROLES.Active,
                    name = SI_NVK3UT_LAM_ENDEAVOR_COLOR_ACTIVE,
                    tooltip = SI_NVK3UT_LAM_ENDEAVOR_COLOR_ACTIVE_TOOLTIP,
                },
                {
                    key = "Completed",
                    role = ENDEAVOR_COLOR_ROLES.Completed,
                    name = SI_NVK3UT_LAM_ENDEAVOR_COLOR_COMPLETED,
                    tooltip = SI_NVK3UT_LAM_ENDEAVOR_COLOR_COMPLETED_TOOLTIP,
                },
            }

            local function getAchievementColorDefault(colorKey)
                local sv = getSavedVars()
                if type(sv) ~= "table" then
                    return nil
                end

                local achievement = sv.Achievement
                if type(achievement) ~= "table" then
                    return nil
                end

                local colors = achievement.Colors
                if type(colors) ~= "table" then
                    return nil
                end

                local candidate = colors[colorKey]
                if candidate == nil and colorKey == "Completed" then
                    candidate = colors.Completed or colors.Objective
                end

                if type(candidate) ~= "table" then
                    return nil
                end

                local r = candidate[1] or candidate.r or 1
                local g = candidate[2] or candidate.g or 1
                local b = candidate[3] or candidate.b or 1
                local a = candidate[4] or candidate.a or 1
                return r, g, b, a
            end

            local function getEndeavorDefaultColor(colorKey, role)
                local r, g, b, a = getAchievementColorDefault(colorKey)
                if r ~= nil then
                    return r, g, b, a
                end

                local fallback = getTrackerColorDefaultTable("endeavorTracker", role)
                if type(fallback) == "table" then
                    local fallbackR = fallback[1] or fallback.r or 1
                    local fallbackG = fallback[2] or fallback.g or 1
                    local fallbackB = fallback[3] or fallback.b or 1
                    local fallbackA = fallback[4] or fallback.a or 1
                    return fallbackR, fallbackG, fallbackB, fallbackA
                end

                if colorKey == "Completed" then
                    return 0.8, 0.8, 0.8, 1
                end

                return 1, 1, 1, 1
            end

            for index = 1, #colorEntries do
                local entry = colorEntries[index]
                controls[#controls + 1] = {
                    type = "colorpicker",
                    name = GetString(entry.name),
                    tooltip = GetString(entry.tooltip),
                    width = "full",
                    getFunc = function()
                        local config = getEndeavorConfig()
                        local colors = config.Colors or {}
                        local color = colors[entry.key]
                        local r = (color and (color[1] or color.r)) or 1
                        local g = (color and (color[2] or color.g)) or 1
                        local b = (color and (color[3] or color.b)) or 1
                        local a = (color and (color[4] or color.a)) or 1
                        return r, g, b, a
                    end,
                    setFunc = function(r, g, b, a)
                        local config = getEndeavorConfig()
                        config.Colors = config.Colors or {}
                        config.Colors[entry.key] = config.Colors[entry.key] or { 1, 1, 1, 1 }
                        local color = config.Colors[entry.key]
                        local alpha = a or 1
                        color[1], color[2], color[3], color[4] = r, g, b, alpha
                        color.r, color.g, color.b, color.a = r, g, b, alpha
                        setTrackerColor("endeavorTracker", entry.role, r, g, b, alpha)
                        markEndeavorDirty("appearance")
                        queueEndeavorDirty()
                    end,
                    default = function()
                        return getEndeavorDefaultColor(entry.key, entry.role)
                    end,
                }
            end

            controls[#controls + 1] = { type = "header", name = GetString(SI_NVK3UT_LAM_ENDEAVOR_SECTION_FONTS) }

            local fontGroups = {
                { key = "Category", label = "Kategorie-Header" },
                { key = "Title", label = "Titel" },
                { key = "Objective", label = "Zeilen" },
            }

            local config = getEndeavorConfig()
            for index = 1, #fontGroups do
                local group = fontGroups[index]
                local defaultsFactory = function()
                    return endeavorFontDefaults(group.key)
                end
                local defaultsValue = defaultsFactory()
                local fontControls = buildFontControls(
                    group.label,
                    config,
                    group.key,
                    defaultsFactory,
                    function()
                        markEndeavorDirty("appearance")
                        queueEndeavorDirty()
                    end,
                    {
                        ensureFont = ensureEndeavorFontGroup,
                        getFace = function(font)
                            return font.Face
                        end,
                        setFace = function(font, value)
                            font.Face = value
                        end,
                        getSize = function(font)
                            return font.Size
                        end,
                        setSize = function(font, value)
                            font.Size = clampEndeavorFontSize(value)
                        end,
                        getOutline = function(font)
                            return font.Outline
                        end,
                        setOutline = function(font, value)
                            font.Outline = value
                        end,
                        clampSize = clampEndeavorFontSize,
                    }
                )

                for i = 1, #fontControls do
                    local control = fontControls[i]
                    if i == 1 then
                        control.tooltip = GetString(SI_NVK3UT_LAM_ENDEAVOR_FONT_FAMILY_TOOLTIP)
                        control.default = defaultsValue.Face
                    elseif i == 2 then
                        control.tooltip = GetString(SI_NVK3UT_LAM_ENDEAVOR_FONT_SIZE_TOOLTIP)
                        control.default = defaultsValue.Size
                    else
                        control.tooltip = GetString(SI_NVK3UT_LAM_ENDEAVOR_FONT_OUTLINE_TOOLTIP)
                        control.default = defaultsValue.Outline
                    end
                    controls[#controls + 1] = control
                end
            end
            return controls
        end)(),
    }

    options[#options + 1] = {
        type = "submenu",
        name = "Achievement Tracker",
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
                    if LamQueueFullRebuild("achievementActive") then
                        return
                    end
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
                    local addon = Nvk3UT
                    if addon and type(addon.SetDebugEnabled) == "function" then
                        addon:SetDebugEnabled(enabled)
                    end
                    local diagnostics = (addon and addon.Diagnostics) or Nvk3UT_Diagnostics
                    if diagnostics and type(diagnostics.SetDebugEnabled) == "function" then
                        diagnostics.SetDebugEnabled(enabled)
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
