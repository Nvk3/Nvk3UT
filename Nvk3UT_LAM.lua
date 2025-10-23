Nvk3UT = Nvk3UT or {}

local L = {}
Nvk3UT.LAM = L

local FONT_FACE_CHOICES = {
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
    quest = { category = 20, title = 18, line = 16 },
    achievement = { category = 20, title = 18, line = 16 },
}

local DEFAULT_WINDOW = {
    left = 200,
    top = 200,
    width = 360,
    height = 640,
    locked = false,
}

local function getSavedVars()
    return Nvk3UT and Nvk3UT.sv
end

local function getGeneral()
    local sv = getSavedVars()
    sv.General = sv.General or {}
    sv.General.features = sv.General.features or {}
    sv.General.window = sv.General.window or {}
    local window = sv.General.window
    window.left = tonumber(window.left) or DEFAULT_WINDOW.left
    window.top = tonumber(window.top) or DEFAULT_WINDOW.top
    window.width = tonumber(window.width) or DEFAULT_WINDOW.width
    window.height = tonumber(window.height) or DEFAULT_WINDOW.height
    if window.locked == nil then
        window.locked = DEFAULT_WINDOW.locked
    end
    return sv.General
end

local function getQuestSettings()
    local sv = getSavedVars()
    sv.QuestTracker = sv.QuestTracker or {}
    sv.QuestTracker.background = sv.QuestTracker.background or {}
    sv.QuestTracker.fonts = sv.QuestTracker.fonts or {}
    return sv.QuestTracker
end

local function getAchievementSettings()
    local sv = getSavedVars()
    sv.AchievementTracker = sv.AchievementTracker or {}
    sv.AchievementTracker.background = sv.AchievementTracker.background or {}
    sv.AchievementTracker.fonts = sv.AchievementTracker.fonts or {}
    sv.AchievementTracker.sections = sv.AchievementTracker.sections or {}
    return sv.AchievementTracker
end

local function ensureFont(settings, key, defaults)
    settings.fonts[key] = settings.fonts[key] or {}
    local font = settings.fonts[key]
    font.face = font.face or defaults.face or FONT_FACE_CHOICES[1].face
    font.size = font.size or defaults.size or 16
    font.outline = font.outline or defaults.outline or "soft-shadow-thin"
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
    local outline = "soft-shadow-thin"
    local size = defaults[key] or 16
    return { face = face, size = size, outline = outline }
end

local function achievementFontDefaults(key)
    local defaults = DEFAULT_FONT_SIZE.achievement
    local face = FONT_FACE_CHOICES[1].face
    local outline = "soft-shadow-thin"
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

local function registerGeneralOptions(options)
    local general = getGeneral()

    options[#options + 1] = { type = "header", name = "Anzeige" }
    options[#options + 1] = {
        type = "checkbox",
        name = "Status über dem Kompass anzeigen",
        getFunc = function()
            general = getGeneral()
            return general.showStatus ~= false
        end,
        setFunc = function(value)
            general = getGeneral()
            general.showStatus = value
            updateStatus()
        end,
        default = true,
    }

    options[#options + 1] = { type = "header", name = "Tracker-Fenster" }

    options[#options + 1] = {
        type = "checkbox",
        name = "Fenster sperren",
        getFunc = function()
            general = getGeneral()
            return general.window.locked == true
        end,
        setFunc = function(value)
            general = getGeneral()
            general.window.locked = value and true or false
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        default = false,
    }

    options[#options + 1] = {
        type = "button",
        name = "Position zurücksetzen",
        func = function()
            general = getGeneral()
            general.window.left = DEFAULT_WINDOW.left
            general.window.top = DEFAULT_WINDOW.top
            general.window.width = DEFAULT_WINDOW.width
            general.window.height = DEFAULT_WINDOW.height
            if Nvk3UT and Nvk3UT.TrackerHost and Nvk3UT.TrackerHost.ApplySettings then
                Nvk3UT.TrackerHost.ApplySettings()
            end
        end,
        tooltip = "Setzt Größe und Position des Tracker-Fensters zurück.",
    }

    options[#options + 1] = { type = "header", name = "Optionen" }

    options[#options + 1] = {
        type = "dropdown",
        name = "Favoritenspeicherung:",
        choices = { "Account-Weit", "Charakter-Weit" },
        choicesValues = { "account", "character" },
        getFunc = function()
            general = getGeneral()
            return general.favScope or "account"
        end,
        setFunc = function(value)
            general = getGeneral()
            local old = general.favScope or "account"
            general.favScope = value or "account"
            if Nvk3UT.FavoritesData and Nvk3UT.FavoritesData.MigrateScope then
                Nvk3UT.FavoritesData.MigrateScope(old, general.favScope)
            end
            updateStatus()
        end,
        tooltip = "Speichert und zählt Favoriten account-weit oder charakter-weit.",
    }

    options[#options + 1] = {
        type = "dropdown",
        name = "Kürzlich-Zeitraum:",
        choices = { "Alle", "7 Tage", "30 Tage" },
        choicesValues = { 0, 7, 30 },
        getFunc = function()
            general = getGeneral()
            return general.recentWindow or 0
        end,
        setFunc = function(value)
            general = getGeneral()
            general.recentWindow = value or 0
            updateStatus()
        end,
        tooltip = "Wähle, welche Zeitspanne für Kürzlich gezählt/angezeigt wird.",
    }

    options[#options + 1] = {
        type = "dropdown",
        name = "Kürzlich - Maximum:",
        choices = { "50", "100", "250" },
        choicesValues = { 50, 100, 250 },
        getFunc = function()
            general = getGeneral()
            return general.recentMax or 100
        end,
        setFunc = function(value)
            general = getGeneral()
            general.recentMax = value or 100
            updateStatus()
        end,
        tooltip = "Hardcap für die Anzahl der Kürzlich-Einträge.",
    }

    options[#options + 1] = { type = "header", name = "Funktionen" }

    options[#options + 1] = {
        type = "checkbox",
        name = "Errungenschafts-Tooltips ein",
        getFunc = function()
            general = getGeneral()
            return general.features.tooltips ~= false
        end,
        setFunc = function(value)
            general = getGeneral()
            general.features.tooltips = value
            updateTooltips(value)
        end,
        default = true,
    }

    local featureControls = {
        { key = "completed", label = "Abgeschlossen aktiv" },
        { key = "favorites", label = "Favoriten aktiv" },
        { key = "recent", label = "Kürzlich aktiv" },
        { key = "todo", label = "To-Do-Liste aktiv" },
    }

    for index = 1, #featureControls do
        local entry = featureControls[index]
        options[#options + 1] = {
            type = "checkbox",
            name = entry.label,
            getFunc = function()
                general = getGeneral()
                return general.features[entry.key] ~= false
            end,
            setFunc = function(value)
                general = getGeneral()
                general.features[entry.key] = value
                applyFeatureToggles()
            end,
            default = true,
        }
    end

    options[#options + 1] = { type = "header", name = "Debug" }

    options[#options + 1] = {
        type = "checkbox",
        name = "Debug aktivieren",
        getFunc = function()
            local sv = getSavedVars()
            return sv.debug == true
        end,
        setFunc = function(value)
            local sv = getSavedVars()
            sv.debug = value and true or false
        end,
        default = false,
    }

    options[#options + 1] = {
        type = "button",
        name = "Self-Test ausführen",
        func = function()
            if Nvk3UT and Nvk3UT.SelfTest and Nvk3UT.SelfTest.Run then
                Nvk3UT.SelfTest.Run()
            end
        end,
        tooltip = "Führt einen kompakten Integritäts-Check aus. Bei aktiviertem Debug erscheinen ausführliche Chat-Logs.",
    }

    options[#options + 1] = {
        type = "button",
        name = "UI neu laden",
        func = function()
            ReloadUI()
        end,
    }
end

local function registerQuestTrackerOptions(options)
    local settings = getQuestSettings()

    options[#options + 1] = { type = "header", name = "Quest-Tracker" }

    options[#options + 1] = {
        type = "checkbox",
        name = "Quest-Tracker aktiv",
        getFunc = function()
            settings = getQuestSettings()
            return settings.active ~= false
        end,
        setFunc = function(value)
            settings = getQuestSettings()
            settings.active = value
            if Nvk3UT and Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.SetActive then
                Nvk3UT.QuestTracker.SetActive(value)
            end
        end,
        default = true,
    }

    options[#options + 1] = {
        type = "checkbox",
        name = "Standard-Quest-Tracker verstecken",
        getFunc = function()
            settings = getQuestSettings()
            return settings.hideDefault == true
        end,
        setFunc = function(value)
            settings = getQuestSettings()
            settings.hideDefault = value
            applyQuestSettings()
        end,
        default = false,
    }

    options[#options + 1] = {
        type = "checkbox",
        name = "Im Kampf verstecken",
        getFunc = function()
            settings = getQuestSettings()
            return settings.hideInCombat == true
        end,
        setFunc = function(value)
            settings = getQuestSettings()
            settings.hideInCombat = value
            applyQuestSettings()
        end,
        default = false,
    }

    options[#options + 1] = {
        type = "checkbox",
        name = "Tracker sperren",
        getFunc = function()
            settings = getQuestSettings()
            return settings.lock == true
        end,
        setFunc = function(value)
            settings = getQuestSettings()
            settings.lock = value
            applyQuestSettings()
        end,
        default = false,
    }

    options[#options + 1] = {
        type = "checkbox",
        name = "Automatisch vertikal anpassen",
        getFunc = function()
            settings = getQuestSettings()
            return settings.autoGrowV ~= false
        end,
        setFunc = function(value)
            settings = getQuestSettings()
            settings.autoGrowV = value
            applyQuestSettings()
        end,
        default = true,
    }

    options[#options + 1] = {
        type = "checkbox",
        name = "Automatisch horizontal anpassen",
        getFunc = function()
            settings = getQuestSettings()
            return settings.autoGrowH == true
        end,
        setFunc = function(value)
            settings = getQuestSettings()
            settings.autoGrowH = value
            applyQuestSettings()
        end,
        default = false,
    }

    options[#options + 1] = {
        type = "checkbox",
        name = "Neue Quests automatisch aufklappen",
        getFunc = function()
            settings = getQuestSettings()
            return settings.autoExpand ~= false
        end,
        setFunc = function(value)
            settings = getQuestSettings()
            settings.autoExpand = value
            applyQuestSettings()
        end,
        default = true,
    }

    options[#options + 1] = { type = "header", name = "Quest-Tracker Hintergrund" }

    options[#options + 1] = {
        type = "checkbox",
        name = "Hintergrund anzeigen",
        getFunc = function()
            settings = getQuestSettings()
            return settings.background.enabled ~= false
        end,
        setFunc = function(value)
            settings = getQuestSettings()
            settings.background.enabled = value
            applyQuestTheme()
        end,
        default = true,
    }

    options[#options + 1] = {
        type = "slider",
        name = "Hintergrund-Transparenz",
        min = 0,
        max = 1,
        step = 0.05,
        getFunc = function()
            settings = getQuestSettings()
            return settings.background.alpha or 0.35
        end,
        setFunc = function(value)
            settings = getQuestSettings()
            settings.background.alpha = value
            applyQuestTheme()
        end,
        disabled = function()
            settings = getQuestSettings()
            return settings.background.enabled == false
        end,
    }

    options[#options + 1] = {
        type = "slider",
        name = "Rahmen-Transparenz",
        min = 0,
        max = 1,
        step = 0.05,
        getFunc = function()
            settings = getQuestSettings()
            return settings.background.edgeAlpha or 0.5
        end,
        setFunc = function(value)
            settings = getQuestSettings()
            settings.background.edgeAlpha = value
            applyQuestTheme()
        end,
        disabled = function()
            settings = getQuestSettings()
            return settings.background.enabled == false
        end,
    }

    options[#options + 1] = {
        type = "slider",
        name = "Innenabstand",
        min = 0,
        max = 48,
        step = 1,
        getFunc = function()
            settings = getQuestSettings()
            return settings.background.padding or 0
        end,
        setFunc = function(value)
            settings = getQuestSettings()
            settings.background.padding = math.floor(value + 0.5)
            applyQuestTheme()
        end,
    }

    options[#options + 1] = { type = "header", name = "Quest-Tracker Schriftarten" }

    local fontGroups = {
        { key = "category", label = "Kategorie-Header" },
        { key = "title", label = "Questtitel" },
        { key = "line", label = "Questzeilen" },
    }

    for index = 1, #fontGroups do
        local group = fontGroups[index]
        local controls = buildFontControls(
            group.label,
            settings,
            group.key,
            questFontDefaults(group.key),
            function()
                applyQuestTheme()
                refreshQuestTracker()
            end
        )
        for c = 1, #controls do
            options[#options + 1] = controls[c]
        end
    end
end

local function registerAchievementTrackerOptions(options)
    local settings = getAchievementSettings()

    options[#options + 1] = { type = "header", name = "Erfolgstracker" }

    options[#options + 1] = {
        type = "checkbox",
        name = "Erfolgstracker aktiv",
        getFunc = function()
            settings = getAchievementSettings()
            return settings.active ~= false
        end,
        setFunc = function(value)
            settings = getAchievementSettings()
            settings.active = value
            if Nvk3UT and Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.SetActive then
                Nvk3UT.AchievementTracker.SetActive(value)
            end
        end,
        default = true,
    }

    options[#options + 1] = {
        type = "checkbox",
        name = "Tracker sperren",
        getFunc = function()
            settings = getAchievementSettings()
            return settings.lock == true
        end,
        setFunc = function(value)
            settings = getAchievementSettings()
            settings.lock = value
            applyAchievementSettings()
        end,
        default = false,
    }

    options[#options + 1] = {
        type = "checkbox",
        name = "Automatisch vertikal anpassen",
        getFunc = function()
            settings = getAchievementSettings()
            return settings.autoGrowV ~= false
        end,
        setFunc = function(value)
            settings = getAchievementSettings()
            settings.autoGrowV = value
            applyAchievementSettings()
        end,
        default = true,
    }

    options[#options + 1] = {
        type = "checkbox",
        name = "Automatisch horizontal anpassen",
        getFunc = function()
            settings = getAchievementSettings()
            return settings.autoGrowH == true
        end,
        setFunc = function(value)
            settings = getAchievementSettings()
            settings.autoGrowH = value
            applyAchievementSettings()
        end,
        default = false,
    }

    options[#options + 1] = {
        type = "checkbox",
        name = "Tracker-Tooltips aktiv",
        getFunc = function()
            settings = getAchievementSettings()
            return settings.tooltips ~= false
        end,
        setFunc = function(value)
            settings = getAchievementSettings()
            settings.tooltips = value
            applyAchievementSettings()
        end,
        default = true,
    }

    options[#options + 1] = { type = "header", name = "Bereiche anzeigen" }

    local sectionToggles = {
        { key = "favorites", label = "Favoriten" },
        { key = "recent", label = "Kürzlich" },
        { key = "completed", label = "Abgeschlossen" },
        { key = "todo", label = "To-Do" },
    }

    for index = 1, #sectionToggles do
        local entry = sectionToggles[index]
        options[#options + 1] = {
            type = "checkbox",
            name = entry.label,
            getFunc = function()
                settings = getAchievementSettings()
                return settings.sections[entry.key] ~= false
            end,
            setFunc = function(value)
                settings = getAchievementSettings()
                settings.sections[entry.key] = value
                applyAchievementSettings()
                refreshAchievementTracker()
            end,
            default = true,
        }
    end

    options[#options + 1] = { type = "header", name = "Erfolgstracker Hintergrund" }

    options[#options + 1] = {
        type = "checkbox",
        name = "Hintergrund anzeigen",
        getFunc = function()
            settings = getAchievementSettings()
            return settings.background.enabled ~= false
        end,
        setFunc = function(value)
            settings = getAchievementSettings()
            settings.background.enabled = value
            applyAchievementTheme()
        end,
        default = true,
    }

    options[#options + 1] = {
        type = "slider",
        name = "Hintergrund-Transparenz",
        min = 0,
        max = 1,
        step = 0.05,
        getFunc = function()
            settings = getAchievementSettings()
            return settings.background.alpha or 0.35
        end,
        setFunc = function(value)
            settings = getAchievementSettings()
            settings.background.alpha = value
            applyAchievementTheme()
        end,
        disabled = function()
            settings = getAchievementSettings()
            return settings.background.enabled == false
        end,
    }

    options[#options + 1] = {
        type = "slider",
        name = "Rahmen-Transparenz",
        min = 0,
        max = 1,
        step = 0.05,
        getFunc = function()
            settings = getAchievementSettings()
            return settings.background.edgeAlpha or 0.5
        end,
        setFunc = function(value)
            settings = getAchievementSettings()
            settings.background.edgeAlpha = value
            applyAchievementTheme()
        end,
        disabled = function()
            settings = getAchievementSettings()
            return settings.background.enabled == false
        end,
    }

    options[#options + 1] = {
        type = "slider",
        name = "Innenabstand",
        min = 0,
        max = 48,
        step = 1,
        getFunc = function()
            settings = getAchievementSettings()
            return settings.background.padding or 0
        end,
        setFunc = function(value)
            settings = getAchievementSettings()
            settings.background.padding = math.floor(value + 0.5)
            applyAchievementTheme()
        end,
    }

    options[#options + 1] = { type = "header", name = "Erfolgstracker Schriftarten" }

    local fontGroups = {
        { key = "category", label = "Kategorie-Header" },
        { key = "title", label = "Titel" },
        { key = "line", label = "Zeilen" },
    }

    for index = 1, #fontGroups do
        local group = fontGroups[index]
        local controls = buildFontControls(
            group.label,
            settings,
            group.key,
            achievementFontDefaults(group.key),
            function()
                applyAchievementTheme()
                refreshAchievementTracker()
            end
        )
        for c = 1, #controls do
            options[#options + 1] = controls[c]
        end
    end
end

function L.Build(displayTitle)
    local LAM = LibAddonMenu2
    if not LAM then
        return
    end

    if L._registered then
        return
    end

    local panelName = "Nvk3UT_Panel"

    local panel = {
        type = "panel",
        name = displayTitle or "Nvk3UT",
        displayName = "|c66CCFF" .. (displayTitle or "Nvk3UT") .. "|r",
        author = "Nvk3",
        version = "{VERSION}",
        registerForRefresh = true,
        registerForDefaults = false,
    }

    local options = {}
    registerGeneralOptions(options)
    registerQuestTrackerOptions(options)
    registerAchievementTrackerOptions(options)

    LAM:RegisterAddonPanel(panelName, panel)
    LAM:RegisterOptionControls(panelName, options)

    L._registered = true
end

return L
