Nvk3UT = Nvk3UT or {}

Nvk3UT.UI = Nvk3UT.UI or {}
local D = Nvk3UT.Diagnostics
local M = {}
Nvk3UT.UI = M

-- Apply toggles (no re-hooking). Only refresh UI/status.
function M.ApplyFeatureToggles()
  -- Update status first and only once
  if Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
    Nvk3UT.UI.UpdateStatus()
  end

  local SM = SCENE_MANAGER
  local ach = (SYSTEMS and SYSTEMS.GetObject and SYSTEMS:GetObject("achievements")) or ACHIEVEMENTS
  local isShowing = SM and SM.IsShowing and SM:IsShowing("achievements")

  if isShowing then
    -- Hard rebuild by briefly closing and re-opening the scene
    SM:Hide("achievements")
    zo_callLater(function()
      SM:Show("achievements")
    end, 50)
  else
    -- Soft refresh so the next open is up-to-date
    if ach and ach.refreshGroups then
      ach.refreshGroups:RefreshAll("FullUpdate")
    end
  end
  -- Toggle category tooltips
  if Nvk3UT and Nvk3UT.Tooltips and Nvk3UT.Tooltips.Enable then
    local on = (Nvk3UT.sv and Nvk3UT.sv.features and (Nvk3UT.sv.features.tooltips ~= false))
    Nvk3UT.Tooltips.Enable(on)
  end
end


-- Refresh the achievements lists to reflect data changes immediately.
function M.RefreshAchievements()
  local ach = (SYSTEMS and SYSTEMS.GetObject and SYSTEMS:GetObject("achievements")) or ACHIEVEMENTS
  if not ach then
    return
  end
  if ach.refreshGroups then
    ach.refreshGroups:RefreshAll("FullUpdate")
  end
  if Nvk3UT and Nvk3UT.RebuildSelected then
    pcall(Nvk3UT.RebuildSelected, ach)
  end
end

local TITLE = "Nvk3's Ultimate Tracker"

local function ensureStatusLabel()
  local parent = _G["ZO_CompassFrame"] or _G["ZO_Compass"] or GuiRoot
  if not Nvk3UT._status then
    local ctl = WINDOW_MANAGER:CreateControl("Nvk3UT_Status", parent, CT_LABEL)
    ctl:SetFont("ZoFontGameSmall")
    ctl:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, -18)
    Nvk3UT._status = ctl
  end
  return Nvk3UT._status
end
M.GetStatusLabel = ensureStatusLabel

local function Nvk3UT_UI_ComputeCounts()
  local total, done = 0, 0
  local numCats = GetNumAchievementCategories and GetNumAchievementCategories() or 0
  for top = 1, numCats do
    local _, numSub, numAch = GetAchievementCategoryInfo(top)
    if numAch and numAch > 0 then
      for a = 1, numAch do
        local id = GetAchievementId(top, nil, a)
        local _, _, _, _, completed = GetAchievementInfo(id)
        total = total + 1
        if completed then
          done = done + 1
        end
      end
    end
    for sub = 1, (numSub or 0) do
      local _, numAch2 = GetAchievementSubCategoryInfo(top, sub)
      if numAch2 and numAch2 > 0 then
        for a = 1, numAch2 do
          local id = GetAchievementId(top, sub, a)
          local _, _, _, _, completed = GetAchievementInfo(id)
          total = total + 1
          if completed then
            done = done + 1
          end
        end
      end
    end
  end
  return done, total
end
function M.BuildLAM()
  local LAM = LibAddonMenu2
  if not LAM then
    return
  end

  local panel = {
    type = "panel",
    name = TITLE,
    displayName = "|c66CCFF" .. TITLE .. "|r",
    author = "Nvk3",
    version = "{VERSION}",
    registerForRefresh = true,
    registerForDefaults = true,
  }
  local panelControl = LAM:RegisterAddonPanel("Nvk3UT_Panel", panel)
  if Nvk3UT and Nvk3UT.Tracker and Nvk3UT.Tracker.RegisterLamPanel then
    Nvk3UT.Tracker.RegisterLamPanel(panelControl)
  end

  local function getTracker()
    return Nvk3UT and Nvk3UT.Tracker
  end

  local function trackerSV()
    local root = Nvk3UT and Nvk3UT.sv
    if root then
      root.tracker = root.tracker or {}
      local sv = root.tracker
      sv.behavior = sv.behavior or {}
      sv.background = sv.background or {}
      sv.fonts = sv.fonts or {}
      sv.pos = sv.pos or {}
      sv.collapseState = sv.collapseState or { zones = {}, quests = {}, achieves = {} }
      return sv
    end
    local tracker = getTracker()
    if tracker and tracker.sv then
      return tracker.sv
    end
    return nil
  end

  local FONT_FACES = {
    "ZoFontGame",
    "ZoFontGameBold",
    "ZoFontGameMedium",
    "ZoFontGameLargeBold",
    "ZoFontHeader",
    "ZoFontHeader2",
    "ZoFontHeader3",
    "ZoFontWinH1",
    "ZoFontWinH2",
    "ZoFontWinH3",
  }

  local FONT_EFFECT_LABELS = {
    "Keine",
    "Outline",
    "Dicke Outline",
    "Shadow",
    "Soft Shadow (dünn)",
    "Soft Shadow (dick)",
  }

  local FONT_EFFECT_VALUES = {
    "none",
    "outline",
    "thick-outline",
    "shadow",
    "soft-shadow-thin",
    "soft-shadow-thick",
  }

  local TRACKER_FONT_DEFAULTS = {
    category = { face = "ZoFontHeader2", effect = "soft-shadow-thin", size = 24, color = { r = 0.89, g = 0.82, b = 0.67, a = 1 } },
    quest = { face = "ZoFontGameBold", effect = "soft-shadow-thin", size = 20, color = { r = 1, g = 0.82, b = 0.1, a = 1 } },
    task = { face = "ZoFontGame", effect = "soft-shadow-thin", size = 18, color = { r = 0.9, g = 0.9, b = 0.9, a = 1 } },
    achieve = { face = "ZoFontGameBold", effect = "soft-shadow-thin", size = 20, color = { r = 1, g = 0.82, b = 0.1, a = 1 } },
    achieveTask = { face = "ZoFontGame", effect = "soft-shadow-thin", size = 18, color = { r = 0.9, g = 0.9, b = 0.9, a = 1 } },
  }

  local TRACKER_THROTTLE_DEFAULT = 150

  local BEHAVIOR_DEFAULTS = {
    hideDefault = false,
    hideInCombat = false,
    locked = false,
    autoGrowV = true,
    autoGrowH = false,
    autoExpandNewQuests = false,
    alwaysExpandAchievements = false,
    tooltips = true,
  }

  local BACKGROUND_DEFAULTS = {
    enabled = false,
    border = false,
    alpha = 60,
    hideWhenLocked = false,
  }

  local function roundToInt(value)
    return math.floor((value or 0) + 0.5)
  end

  local function getFontConfig(section)
    local sv = trackerSV()
    if not sv then
      return TRACKER_FONT_DEFAULTS[section]
    end
    sv.fonts = sv.fonts or {}
    sv.fonts[section] = sv.fonts[section] or {}
    return sv.fonts[section]
  end

  local function applyFontChange(section, field, value)
    local cfg = getFontConfig(section)
    cfg[field] = value
    local tracker = getTracker()
    if tracker and tracker.SetFontOption then
      tracker.SetFontOption(section, field, value)
    end
  end

  local function getFontFace(section)
    local cfg = getFontConfig(section)
    return cfg.face or TRACKER_FONT_DEFAULTS[section].face
  end

  local function setFontFace(section, face)
    applyFontChange(section, "face", face)
  end

  local function getFontEffect(section)
    local cfg = getFontConfig(section)
    return cfg.effect or TRACKER_FONT_DEFAULTS[section].effect
  end

  local function setFontEffect(section, effect)
    applyFontChange(section, "effect", effect)
  end

  local function getFontSize(section)
    local cfg = getFontConfig(section)
    return cfg.size or TRACKER_FONT_DEFAULTS[section].size
  end

  local function setFontSize(section, size)
    applyFontChange(section, "size", roundToInt(size))
  end

  local function getFontColor(section)
    local cfg = getFontConfig(section)
    local color = cfg.color or TRACKER_FONT_DEFAULTS[section].color
    return color.r or 1, color.g or 1, color.b or 1, color.a or 1
  end

  local function setFontColor(section, r, g, b, a)
    local cfg = getFontConfig(section)
    cfg.color = { r = r, g = g, b = b, a = a }
    local tracker = getTracker()
    if tracker and tracker.SetFontColor then
      tracker.SetFontColor(section, r, g, b, a)
    end
  end

  local function trackerEnabled()
    local sv = trackerSV()
    if not sv then
      return true
    end
    return sv.enabled ~= false
  end

  local function setTrackerEnabled(value)
    local sv = trackerSV()
    if sv then
      sv.enabled = value and true or false
    end
    local tracker = getTracker()
    if tracker and tracker.SetEnabled then
      tracker.SetEnabled(value)
    end
  end

  local function trackerShowsQuests()
    local sv = trackerSV()
    if not sv then
      return true
    end
    return sv.showQuests ~= false
  end

  local function setTrackerShowsQuests(value)
    local sv = trackerSV()
    if sv then
      sv.showQuests = value and true or false
    end
    local tracker = getTracker()
    if tracker and tracker.SetShowQuests then
      tracker.SetShowQuests(value)
    end
  end

  local function trackerShowsAchievements()
    local sv = trackerSV()
    if not sv then
      return true
    end
    return sv.showAchievements ~= false
  end

  local function setTrackerShowsAchievements(value)
    local sv = trackerSV()
    if sv then
      sv.showAchievements = value and true or false
    end
    local tracker = getTracker()
    if tracker and tracker.SetShowAchievements then
      tracker.SetShowAchievements(value)
    end
  end

  local function getBehavior(key)
    local sv = trackerSV()
    if not sv then
      if key == "tooltips" then
        return BEHAVIOR_DEFAULTS.tooltips
      end
      return BEHAVIOR_DEFAULTS[key] == true
    end
    local behavior = sv.behavior or {}
    if key == "tooltips" then
      if behavior.tooltips == nil then
        return true
      end
      return behavior.tooltips
    end
    return behavior[key] == true
  end

  local function setBehavior(key, value)
    local sv = trackerSV()
    if sv then
      sv.behavior = sv.behavior or {}
      if key == "tooltips" then
        sv.behavior.tooltips = value and true or false
      else
        sv.behavior[key] = value and true or false
      end
    end
    local tracker = getTracker()
    if tracker and tracker.SetBehaviorOption then
      tracker.SetBehaviorOption(key, value)
    end
  end

  local function getBackgroundValue(key)
    local sv = trackerSV()
    if not sv then
      return BACKGROUND_DEFAULTS[key]
    end
    local bg = sv.background or {}
    if key == "alpha" then
      return tonumber(bg.alpha) or BACKGROUND_DEFAULTS.alpha
    end
    local flag = bg[key]
    if flag == nil then
      return BACKGROUND_DEFAULTS[key]
    end
    return flag
  end

  local function setBackgroundValue(key, value)
    local sv = trackerSV()
    if not sv then
      return
    end
    sv.background = sv.background or {}
    if key == "alpha" then
      sv.background.alpha = value
    else
      sv.background[key] = value and true or false
    end
    local tracker = getTracker()
    if tracker and tracker.SetBackgroundOption then
      tracker.SetBackgroundOption(key, value)
    end
  end

  local function getThrottle()
    local sv = trackerSV()
    if not sv then
      return TRACKER_THROTTLE_DEFAULT
    end
    local delay = tonumber(sv.throttleMs)
    if not delay then
      return TRACKER_THROTTLE_DEFAULT
    end
    return delay
  end

  local function setThrottle(value)
    local numeric = roundToInt(value)
    if numeric < 0 then
      numeric = 0
    end
    local sv = trackerSV()
    if sv then
      sv.throttleMs = numeric
    end
    local tracker = getTracker()
    if tracker and tracker.SetThrottle then
      tracker.SetThrottle(numeric)
    end
  end

  local opts = {
    {
      type = "submenu",
      name = "Funktionen",
      reference = "Nvk3UT_LAM_Functions",
      controls = {
        {
          type = "checkbox",
          name = "Status über dem Kompass anzeigen",
          getFunc = function()
            return Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.showStatus
          end,
          setFunc = function(value)
            if Nvk3UT.sv and Nvk3UT.sv.ui then
              Nvk3UT.sv.ui.showStatus = value
            end
            M.UpdateStatus()
          end,
          default = true,
        },
        {
          type = "dropdown",
          name = "Favoritenspeicherung:",
          choices = { "Account-Weit", "Charakter-Weit" },
          choicesValues = { "account", "character" },
          getFunc = function()
            return (Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.favScope) or "account"
          end,
          setFunc = function(value)
            local old = (Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.favScope) or "account"
            if Nvk3UT.sv and Nvk3UT.sv.ui then
              Nvk3UT.sv.ui.favScope = value
            end
            if Nvk3UT.FavoritesData and Nvk3UT.FavoritesData.MigrateScope then
              Nvk3UT.FavoritesData.MigrateScope(old, value)
            end
            M.UpdateStatus()
          end,
          tooltip = "Speichert und zählt Favoriten account-weit oder charakter-weit.",
        },
        {
          type = "dropdown",
          name = "Kürzlich-Zeitraum:",
          choices = { "Alle", "7 Tage", "30 Tage" },
          choicesValues = { 0, 7, 30 },
          getFunc = function()
            return (Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.recentWindow) or 0
          end,
          setFunc = function(value)
            if Nvk3UT.sv and Nvk3UT.sv.ui then
              Nvk3UT.sv.ui.recentWindow = value
            end
            M.UpdateStatus()
          end,
          tooltip = "Wähle, welche Zeitspanne für Kürzlich gezählt/angezeigt wird.",
        },
        {
          type = "dropdown",
          name = "Kürzlich - Maximum:",
          choices = { "50", "100", "250" },
          choicesValues = { 50, 100, 250 },
          getFunc = function()
            return (Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.recentMax) or 100
          end,
          setFunc = function(value)
            if Nvk3UT.sv and Nvk3UT.sv.ui then
              Nvk3UT.sv.ui.recentMax = value
            end
            M.UpdateStatus()
          end,
          tooltip = "Hardcap für die Anzahl der Kürzlich-Einträge.",
        },
        {
          type = "checkbox",
          name = "Errungenschafts-Tooltips ein",
          getFunc = function()
            return (Nvk3UT.sv and Nvk3UT.sv.features and (Nvk3UT.sv.features.tooltips ~= false))
          end,
          setFunc = function(value)
            if Nvk3UT.sv then
              Nvk3UT.sv.features = Nvk3UT.sv.features or {}
              Nvk3UT.sv.features.tooltips = value
            end
            if Nvk3UT.Tooltips and Nvk3UT.Tooltips.Enable then
              Nvk3UT.Tooltips.Enable(value)
            end
          end,
          default = true,
        },
        {
          type = "checkbox",
          name = "Abgeschlossen aktiv",
          getFunc = function()
            return Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features.completed
          end,
          setFunc = function(value)
            Nvk3UT.sv.features = Nvk3UT.sv.features or {}
            Nvk3UT.sv.features.completed = value
            M.ApplyFeatureToggles()
          end,
          default = true,
        },
        {
          type = "checkbox",
          name = "Favoriten aktiv",
          getFunc = function()
            return Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features.favorites
          end,
          setFunc = function(value)
            Nvk3UT.sv.features = Nvk3UT.sv.features or {}
            Nvk3UT.sv.features.favorites = value
            M.ApplyFeatureToggles()
          end,
          default = true,
        },
        {
          type = "checkbox",
          name = "Kürzlich aktiv",
          getFunc = function()
            return Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features.recent
          end,
          setFunc = function(value)
            Nvk3UT.sv.features = Nvk3UT.sv.features or {}
            Nvk3UT.sv.features.recent = value
            M.ApplyFeatureToggles()
          end,
          default = true,
        },
        {
          type = "checkbox",
          name = "To-Do-Liste aktiv",
          getFunc = function()
            return Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features.todo
          end,
          setFunc = function(value)
            Nvk3UT.sv.features = Nvk3UT.sv.features or {}
            Nvk3UT.sv.features.todo = value
            M.ApplyFeatureToggles()
          end,
          default = true,
        },
        {
          type = "checkbox",
          name = "Questtracker aktiv",
          getFunc = trackerEnabled,
          setFunc = setTrackerEnabled,
          default = true,
        },
        {
          type = "checkbox",
          name = "Quests im Questtracker tracken",
          getFunc = trackerShowsQuests,
          setFunc = setTrackerShowsQuests,
          default = true,
        },
        {
          type = "checkbox",
          name = "Errungenschaften im Questtracker tracken",
          getFunc = trackerShowsAchievements,
          setFunc = setTrackerShowsAchievements,
          default = true,
        },
      },
    },
    {
      type = "submenu",
      name = "QuestTracker Verhalten",
      reference = "Nvk3UT_LAM_Behavior",
      controls = {
        {
          type = "checkbox",
          name = "Default Questtracker verbergen",
          getFunc = function()
            return getBehavior("hideDefault")
          end,
          setFunc = function(value)
            setBehavior("hideDefault", value)
          end,
          default = BEHAVIOR_DEFAULTS.hideDefault,
        },
        {
          type = "checkbox",
          name = "Quest Tracker im Kampf ausblenden",
          getFunc = function()
            return getBehavior("hideInCombat")
          end,
          setFunc = function(value)
            setBehavior("hideInCombat", value)
          end,
          default = BEHAVIOR_DEFAULTS.hideInCombat,
        },
        {
          type = "checkbox",
          name = "Quest Tracker sperren",
          getFunc = function()
            return getBehavior("locked")
          end,
          setFunc = function(value)
            setBehavior("locked", value)
          end,
          default = BEHAVIOR_DEFAULTS.locked,
        },
        {
          type = "checkbox",
          name = "Quest Tracker automatisch vertikal vergrößern",
          getFunc = function()
            return getBehavior("autoGrowV")
          end,
          setFunc = function(value)
            setBehavior("autoGrowV", value)
          end,
          default = BEHAVIOR_DEFAULTS.autoGrowV,
        },
        {
          type = "checkbox",
          name = "Questtracker automatisch horizontal vergrößern",
          getFunc = function()
            return getBehavior("autoGrowH")
          end,
          setFunc = function(value)
            setBehavior("autoGrowH", value)
          end,
          default = BEHAVIOR_DEFAULTS.autoGrowH,
        },
        {
          type = "checkbox",
          name = "Neue Quests automatisch aufklappen",
          getFunc = function()
            return getBehavior("autoExpandNewQuests")
          end,
          setFunc = function(value)
            setBehavior("autoExpandNewQuests", value)
          end,
          default = BEHAVIOR_DEFAULTS.autoExpandNewQuests,
        },
        {
          type = "checkbox",
          name = "Errungenschaften immer aufklappen",
          getFunc = function()
            return getBehavior("alwaysExpandAchievements")
          end,
          setFunc = function(value)
            setBehavior("alwaysExpandAchievements", value)
          end,
          default = BEHAVIOR_DEFAULTS.alwaysExpandAchievements,
        },
        {
          type = "checkbox",
          name = "Tooltips im Questtracker anzeigen",
          getFunc = function()
            return getBehavior("tooltips")
          end,
          setFunc = function(value)
            setBehavior("tooltips", value)
          end,
          default = BEHAVIOR_DEFAULTS.tooltips,
        },
        {
          type = "slider",
          name = "Aktualisierungsverzögerung (ms)",
          min = 0,
          max = 1000,
          step = 10,
          getFunc = getThrottle,
          setFunc = setThrottle,
          default = TRACKER_THROTTLE_DEFAULT,
          tooltip = "Zeit zwischen automatischen Aktualisierungen. 0 deaktiviert die Verzögerung.",
        },
      },
    },
    {
      type = "submenu",
      name = "Questtracker Background",
      reference = "Nvk3UT_LAM_Background",
      controls = {
        {
          type = "checkbox",
          name = "Background aktivieren",
          getFunc = function()
            return getBackgroundValue("enabled")
          end,
          setFunc = function(value)
            setBackgroundValue("enabled", value)
          end,
          default = BACKGROUND_DEFAULTS.enabled,
        },
        {
          type = "checkbox",
          name = "Rand aktivieren",
          getFunc = function()
            return getBackgroundValue("border")
          end,
          setFunc = function(value)
            setBackgroundValue("border", value)
          end,
          default = BACKGROUND_DEFAULTS.border,
        },
        {
          type = "slider",
          name = "Background Transparenz",
          min = 0,
          max = 100,
          step = 5,
          getFunc = function()
            return getBackgroundValue("alpha")
          end,
          setFunc = function(value)
            setBackgroundValue("alpha", roundToInt(value))
          end,
          default = BACKGROUND_DEFAULTS.alpha,
        },
        {
          type = "checkbox",
          name = "Background bei Sperren ausblenden",
          getFunc = function()
            return getBackgroundValue("hideWhenLocked")
          end,
          setFunc = function(value)
            setBackgroundValue("hideWhenLocked", value)
          end,
          default = BACKGROUND_DEFAULTS.hideWhenLocked,
        },
      },
    },
    {
      type = "submenu",
      name = "Kategorie Optionen",
      reference = "Nvk3UT_LAM_Font_Category",
      controls = {
        {
          type = "dropdown",
          name = "Kategorie Font",
          choices = FONT_FACES,
          getFunc = function()
            return getFontFace("category")
          end,
          setFunc = function(value)
            setFontFace("category", value)
          end,
          default = TRACKER_FONT_DEFAULTS.category.face,
        },
        {
          type = "dropdown",
          name = "Kategorie Font Effekte",
          choices = FONT_EFFECT_LABELS,
          choicesValues = FONT_EFFECT_VALUES,
          getFunc = function()
            return getFontEffect("category")
          end,
          setFunc = function(value)
            setFontEffect("category", value)
          end,
          default = TRACKER_FONT_DEFAULTS.category.effect,
        },
        {
          type = "slider",
          name = "Kategorie Schriftgröße",
          min = 16,
          max = 40,
          step = 1,
          getFunc = function()
            return getFontSize("category")
          end,
          setFunc = function(value)
            setFontSize("category", value)
          end,
          default = TRACKER_FONT_DEFAULTS.category.size,
        },
        {
          type = "colorpicker",
          name = "Kategorie Font Farbe",
          getFunc = function()
            return getFontColor("category")
          end,
          setFunc = function(r, g, b, a)
            setFontColor("category", r, g, b, a)
          end,
          default = {
            TRACKER_FONT_DEFAULTS.category.color.r,
            TRACKER_FONT_DEFAULTS.category.color.g,
            TRACKER_FONT_DEFAULTS.category.color.b,
            TRACKER_FONT_DEFAULTS.category.color.a,
          },
        },
      },
    },
    {
      type = "submenu",
      name = "Quest Optionen",
      reference = "Nvk3UT_LAM_Font_Quest",
      controls = {
        {
          type = "dropdown",
          name = "Quest Font",
          choices = FONT_FACES,
          getFunc = function()
            return getFontFace("quest")
          end,
          setFunc = function(value)
            setFontFace("quest", value)
          end,
          default = TRACKER_FONT_DEFAULTS.quest.face,
        },
        {
          type = "dropdown",
          name = "Quest Font Effekte",
          choices = FONT_EFFECT_LABELS,
          choicesValues = FONT_EFFECT_VALUES,
          getFunc = function()
            return getFontEffect("quest")
          end,
          setFunc = function(value)
            setFontEffect("quest", value)
          end,
          default = TRACKER_FONT_DEFAULTS.quest.effect,
        },
        {
          type = "slider",
          name = "Quest Size",
          min = 14,
          max = 32,
          step = 1,
          getFunc = function()
            return getFontSize("quest")
          end,
          setFunc = function(value)
            setFontSize("quest", value)
          end,
          default = TRACKER_FONT_DEFAULTS.quest.size,
        },
        {
          type = "colorpicker",
          name = "Quest Color",
          getFunc = function()
            return getFontColor("quest")
          end,
          setFunc = function(r, g, b, a)
            setFontColor("quest", r, g, b, a)
          end,
          default = {
            TRACKER_FONT_DEFAULTS.quest.color.r,
            TRACKER_FONT_DEFAULTS.quest.color.g,
            TRACKER_FONT_DEFAULTS.quest.color.b,
            TRACKER_FONT_DEFAULTS.quest.color.a,
          },
        },
      },
    },
    {
      type = "submenu",
      name = "Quest Aufgaben",
      reference = "Nvk3UT_LAM_Font_QuestTasks",
      controls = {
        {
          type = "dropdown",
          name = "Aufgaben Font",
          choices = FONT_FACES,
          getFunc = function()
            return getFontFace("task")
          end,
          setFunc = function(value)
            setFontFace("task", value)
          end,
          default = TRACKER_FONT_DEFAULTS.task.face,
        },
        {
          type = "dropdown",
          name = "Aufgaben Font Effekte",
          choices = FONT_EFFECT_LABELS,
          choicesValues = FONT_EFFECT_VALUES,
          getFunc = function()
            return getFontEffect("task")
          end,
          setFunc = function(value)
            setFontEffect("task", value)
          end,
          default = TRACKER_FONT_DEFAULTS.task.effect,
        },
        {
          type = "slider",
          name = "Aufgaben Größe",
          min = 12,
          max = 28,
          step = 1,
          getFunc = function()
            return getFontSize("task")
          end,
          setFunc = function(value)
            setFontSize("task", value)
          end,
          default = TRACKER_FONT_DEFAULTS.task.size,
        },
        {
          type = "colorpicker",
          name = "Aufgaben Farbe",
          getFunc = function()
            return getFontColor("task")
          end,
          setFunc = function(r, g, b, a)
            setFontColor("task", r, g, b, a)
          end,
          default = {
            TRACKER_FONT_DEFAULTS.task.color.r,
            TRACKER_FONT_DEFAULTS.task.color.g,
            TRACKER_FONT_DEFAULTS.task.color.b,
            TRACKER_FONT_DEFAULTS.task.color.a,
          },
        },
      },
    },
    {
      type = "submenu",
      name = "Errungenschaften Optionen",
      reference = "Nvk3UT_LAM_Font_Achievements",
      controls = {
        {
          type = "dropdown",
          name = "Errungenschaft Font",
          choices = FONT_FACES,
          getFunc = function()
            return getFontFace("achieve")
          end,
          setFunc = function(value)
            setFontFace("achieve", value)
          end,
          default = TRACKER_FONT_DEFAULTS.achieve.face,
        },
        {
          type = "dropdown",
          name = "Errungenschaft Font Effekte",
          choices = FONT_EFFECT_LABELS,
          choicesValues = FONT_EFFECT_VALUES,
          getFunc = function()
            return getFontEffect("achieve")
          end,
          setFunc = function(value)
            setFontEffect("achieve", value)
          end,
          default = TRACKER_FONT_DEFAULTS.achieve.effect,
        },
        {
          type = "slider",
          name = "Errungenschaft Size",
          min = 14,
          max = 32,
          step = 1,
          getFunc = function()
            return getFontSize("achieve")
          end,
          setFunc = function(value)
            setFontSize("achieve", value)
          end,
          default = TRACKER_FONT_DEFAULTS.achieve.size,
        },
        {
          type = "colorpicker",
          name = "Errungenschaft Color",
          getFunc = function()
            return getFontColor("achieve")
          end,
          setFunc = function(r, g, b, a)
            setFontColor("achieve", r, g, b, a)
          end,
          default = {
            TRACKER_FONT_DEFAULTS.achieve.color.r,
            TRACKER_FONT_DEFAULTS.achieve.color.g,
            TRACKER_FONT_DEFAULTS.achieve.color.b,
            TRACKER_FONT_DEFAULTS.achieve.color.a,
          },
        },
      },
    },
    {
      type = "submenu",
      name = "Errungenschaften Aufgaben",
      reference = "Nvk3UT_LAM_Font_AchievementTasks",
      controls = {
        {
          type = "dropdown",
          name = "Aufgaben Font (Errungenschaften)",
          choices = FONT_FACES,
          getFunc = function()
            return getFontFace("achieveTask")
          end,
          setFunc = function(value)
            setFontFace("achieveTask", value)
          end,
          default = TRACKER_FONT_DEFAULTS.achieveTask.face,
        },
        {
          type = "dropdown",
          name = "Aufgaben Font Effekte (Errungenschaften)",
          choices = FONT_EFFECT_LABELS,
          choicesValues = FONT_EFFECT_VALUES,
          getFunc = function()
            return getFontEffect("achieveTask")
          end,
          setFunc = function(value)
            setFontEffect("achieveTask", value)
          end,
          default = TRACKER_FONT_DEFAULTS.achieveTask.effect,
        },
        {
          type = "slider",
          name = "Aufgaben Größe (Errungenschaften)",
          min = 12,
          max = 28,
          step = 1,
          getFunc = function()
            return getFontSize("achieveTask")
          end,
          setFunc = function(value)
            setFontSize("achieveTask", value)
          end,
          default = TRACKER_FONT_DEFAULTS.achieveTask.size,
        },
        {
          type = "colorpicker",
          name = "Aufgaben Farbe (Errungenschaften)",
          getFunc = function()
            return getFontColor("achieveTask")
          end,
          setFunc = function(r, g, b, a)
            setFontColor("achieveTask", r, g, b, a)
          end,
          default = {
            TRACKER_FONT_DEFAULTS.achieveTask.color.r,
            TRACKER_FONT_DEFAULTS.achieveTask.color.g,
            TRACKER_FONT_DEFAULTS.achieveTask.color.b,
            TRACKER_FONT_DEFAULTS.achieveTask.color.a,
          },
        },
      },
    },
    {
      type = "submenu",
      name = "Debug",
      reference = "Nvk3UT_LAM_Debug",
      controls = {
        {
          type = "checkbox",
          name = "Debug aktivieren",
          getFunc = function()
            return Nvk3UT.sv and Nvk3UT.sv.debug
          end,
          setFunc = function(value)
            if Nvk3UT.sv then
              Nvk3UT.sv.debug = value
            end
          end,
          default = false,
        },
        {
          type = "button",
          name = "Self-Test ausführen",
          func = function()
            if Nvk3UT and Nvk3UT.SelfTest and Nvk3UT.SelfTest.Run then
              Nvk3UT.SelfTest.Run()
            end
          end,
          tooltip = "Führt einen kompakten Integritäts-Check aus. Bei aktiviertem Debug erscheinen ausführliche Chat-Logs.",
        },
        {
          type = "button",
          name = "UI neu laden",
          func = function()
            ReloadUI()
          end,
        },
      },
    },
  }

  LAM:RegisterOptionControls("Nvk3UT_Panel", opts)
end

local function __nvk3_IsOn(key)
  local sv = Nvk3UT and Nvk3UT.sv
  return sv and sv.features and sv.features[key] == true
end

local function __nvk3_CountFavorites()
  local Fav = Nvk3UT and Nvk3UT.FavoritesData
  if not Fav or not Fav.Iterate then
    return 0
  end
  local sv = Nvk3UT and Nvk3UT.sv
  local scope = (sv and sv.ui and sv.ui.favScope) or "account"
  local n = 0
  for _ in Fav.Iterate(scope) do
    n = n + 1
  end
  return n
end

local function __nvk3_CountRecent()
  local RD = Nvk3UT and Nvk3UT.RecentData
  if not RD then
    return 0
  end
  if RD.CountConfigured then
    return RD.CountConfigured()
  end
  if RD.ListConfigured then
    local l = RD.ListConfigured()
    return type(l) == "table" and #l or 0
  end
  return 0
end

local function __nvk3_CountTodo()
  local TD = Nvk3UT and Nvk3UT.TodoData
  if not TD then
    return 0
  end
  if TD.CountOpen then
    return TD.CountOpen()
  end
  if TD.ListAllOpen then
    local list = TD.ListAllOpen(999999, false)
    return type(list) == "table" and #list or 0
  end
  return 0
end

local function __nvk3_BuildStatusParts()
  local parts = {}

  -- Abgeschlossen zuerst
  if __nvk3_IsOn("completed") then
    if Nvk3UT_UI_ComputeCounts then
      local done, total = Nvk3UT_UI_ComputeCounts()
      parts[#parts + 1] = ("Abgeschlossen %d/%d"):format(done or 0, total or 0)
    end
  end

  if __nvk3_IsOn("favorites") then
    local n = __nvk3_CountFavorites()
    if n > 0 then
      parts[#parts + 1] = ("Favoriten %d"):format(n)
    end
  end

  if __nvk3_IsOn("recent") then
    local n = __nvk3_CountRecent()
    if n > 0 then
      parts[#parts + 1] = ("Kürzlich %d"):format(n)
    end
  end

  if __nvk3_IsOn("todo") then
    local n = __nvk3_CountTodo()
    if n > 0 then
      parts[#parts + 1] = ("To-Do-Liste %d"):format(n)
    end
  end

  return parts
end

-- Patch/define UpdateStatus in module M or Nvk3UT.UI
do
  local ns = Nvk3UT and Nvk3UT.UI
  local function __nvk3_UpdateStatus_impl()
    if not (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui) then
      return
    end
    local show = Nvk3UT.sv.ui.showStatus ~= false
    local getLabel = (ns and ns.GetStatusLabel) or (M and M.GetStatusLabel)
    if not getLabel then
      return
    end
    local ctl = getLabel()
    if not ctl then
      return
    end

    local parts = __nvk3_BuildStatusParts()
    if (not show) or (#parts == 0) then
      ctl:SetHidden(true)
      ctl._nvk3_last = ""
      return
    end

    local header = (TITLE and ("|c66CCFF" .. TITLE .. "|r  –  ") or "")
    local txt = header .. table.concat(parts, "  •  ")
    if ctl._nvk3_last ~= txt then
      ctl:SetText(txt)
      ctl._nvk3_last = txt
    end
    ctl:SetHidden(false)
  end

  if ns then
    ns.UpdateStatus = __nvk3_UpdateStatus_impl
  elseif M then
    M.UpdateStatus = __nvk3_UpdateStatus_impl
  end
end
-- <<< NVK3UT v0.10.1
