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
  LAM:RegisterAddonPanel("Nvk3UT_Panel", panel)

  local tracker = Nvk3UT and Nvk3UT.QuestTracker
  if tracker and tracker.SetLamPanelName then
    tracker:SetLamPanelName("Nvk3UT_Panel")
  end
  if tracker and tracker.Init then
    tracker:Init()
  end

  local trackerDefaults = (Nvk3UT and Nvk3UT.GetTrackerDefaults and Nvk3UT.GetTrackerDefaults()) or {}

  local function ensureLamGroups()
    local sv = Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui
    if not sv then
      return
    end
    sv.lamGroups = sv.lamGroups or {}
  end

  local function isGroupOpen(key)
    ensureLamGroups()
    local groups = Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.lamGroups
    if not groups then
      return true
    end
    if groups[key] == nil then
      groups[key] = true
    end
    return groups[key]
  end

  local function requestRefresh()
    if LAM.util and LAM.util.RequestRefreshIfNeeded then
      LAM.util.RequestRefreshIfNeeded("Nvk3UT_Panel")
    elseif LAM.RequestRefreshIfNeeded then
      LAM:RequestRefreshIfNeeded("Nvk3UT_Panel")
    elseif CALLBACK_MANAGER then
      CALLBACK_MANAGER:FireCallbacks("LAM-RefreshPanel", "Nvk3UT_Panel")
    end
  end

  local function toggleGroup(key)
    ensureLamGroups()
    local groups = Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.lamGroups
    if not groups then
      return
    end
    groups[key] = not groups[key]
    requestRefresh()
  end

  local function wrapHidden(key, existing)
    return function(...)
      if not isGroupOpen(key) then
        return true
      end
      if existing then
        return existing(...)
      end
      return false
    end
  end

  local TEXTURE_COLLAPSED = "/esoui/art/tree/tree_icon_closed.dds"
  local TEXTURE_EXPANDED = "/esoui/art/tree/tree_icon_open.dds"
  local HEADER_NORMAL = { 1, 1, 1, 1 }
  local HEADER_HOVER = { 1, 0.95, 0.7, 1 }

  local function createGroupHeader(key, label)
    return {
      type = "custom",
      width = "full",
      reference = "Nvk3UT_LAM_Header_" .. key,
      refreshFunc = function(control)
        control:SetResizeToFitDescendents(false)
        control:SetHeight(32)
        if not control._nvkInitialized then
          control:SetMouseEnabled(true)
          local arrow = CreateControl(nil, control, CT_TEXTURE)
          arrow:SetDimensions(18, 18)
          arrow:SetAnchor(LEFT, control, LEFT, 4, 0)
          control.arrow = arrow

          local lbl = CreateControl(nil, control, CT_LABEL)
          lbl:SetAnchor(LEFT, arrow, RIGHT, 8, 0)
          lbl:SetAnchor(RIGHT, control, RIGHT, -4, 0)
          lbl:SetFont("ZoFontHeader")
          lbl:SetText(label)
          lbl:SetColor(unpack(HEADER_NORMAL))
          control.label = lbl

          control:SetHandler("OnMouseEnter", function()
            if control.label then
              control.label:SetColor(unpack(HEADER_HOVER))
            end
          end)
          control:SetHandler("OnMouseExit", function()
            if control.label then
              control.label:SetColor(unpack(HEADER_NORMAL))
            end
          end)
          control:SetHandler("OnMouseUp", function(_, button)
            if button == MOUSE_BUTTON_INDEX_LEFT then
              toggleGroup(key)
            end
          end)
          control._nvkInitialized = true
        end
        if control.arrow then
          control.arrow:SetTexture(isGroupOpen(key) and TEXTURE_EXPANDED or TEXTURE_COLLAPSED)
        end
        if control.label then
          control.label:SetText(label)
        end
      end,
    }
  end

  local FONT_CHOICES = {
    { name = "ZoFontGame", label = "Spiel (Standard)" },
    { name = "ZoFontGameBold", label = "Spiel (Fett)" },
    { name = "ZoFontGameLarge", label = "Spiel (Groß)" },
    { name = "ZoFontHeader", label = "Header" },
    { name = "ZoFontWinH1", label = "Titel" },
    { name = "ZoFontWinH2", label = "Untertitel" },
    { name = "ZoFontGameSmall", label = "Spiel (Klein)" },
  }

  local EFFECT_CHOICES = {
    { value = "", label = "Normal" },
    { value = "soft-shadow-thin", label = "Soft Shadow (Dünn)" },
    { value = "soft-shadow-thick", label = "Soft Shadow (Dick)" },
    { value = "shadow", label = "Schatten" },
    { value = "outline", label = "Outline" },
    { value = "thick-outline", label = "Dicke Outline" },
  }

  local fontChoiceLabels, fontChoiceValues = {}, {}
  for index, entry in ipairs(FONT_CHOICES) do
    fontChoiceLabels[index] = entry.label
    fontChoiceValues[index] = entry.name
  end

  local effectChoiceLabels, effectChoiceValues = {}, {}
  for index, entry in ipairs(EFFECT_CHOICES) do
    effectChoiceLabels[index] = entry.label
    effectChoiceValues[index] = entry.value
  end

  local function getFontConfig(key)
    if tracker and tracker.sv and tracker.sv.fonts and tracker.sv.fonts[key] then
      return tracker.sv.fonts[key]
    end
    return trackerDefaults.fonts and trackerDefaults.fonts[key] or {}
  end

  local function cloneFontConfig(key)
    local src = getFontConfig(key)
    local out = {}
    for k, v in pairs(src) do
      if type(v) == "table" then
        out[k] = { r = v.r, g = v.g, b = v.b, a = v.a }
      else
        out[k] = v
      end
    end
    return out
  end

  local function setFontField(key, field, value)
    if not (tracker and tracker.SetFontConfig) then
      return
    end
    local config = cloneFontConfig(key)
    if field == "color" then
      config.color = value
    else
      config[field] = value
    end
    tracker:SetFontConfig(key, config)
  end

  local function colorComponents(color, fallback)
    local src = color or fallback or {}
    local r = tonumber(src.r) or tonumber(src[1]) or 1
    local g = tonumber(src.g) or tonumber(src[2]) or 1
    local b = tonumber(src.b) or tonumber(src[3]) or 1
    local a = tonumber(src.a) or tonumber(src[4]) or 1
    return r, g, b, a
  end

  local opts = {}

  local function addGroup(key, label, controls)
    opts[#opts + 1] = createGroupHeader(key, label)
    for _, option in ipairs(controls) do
      option.width = option.width or "full"
      option.hidden = wrapHidden(key, option.hidden)
      opts[#opts + 1] = option
    end
  end

  local function trackerAvailable()
    return tracker ~= nil
  end

  local function trackerEnabledFlag(defaultValue)
    if tracker and tracker.sv and tracker.sv.enabled ~= nil then
      return tracker.sv.enabled
    end
    if trackerDefaults.enabled == nil then
      return defaultValue
    end
    return trackerDefaults.enabled
  end

  local function trackerBehavior(key, defaultValue)
    if tracker and tracker.sv and tracker.sv.behavior and tracker.sv.behavior[key] ~= nil then
      return tracker.sv.behavior[key]
    end
    local defaults = trackerDefaults.behavior or {}
    if defaults[key] ~= nil then
      return defaults[key]
    end
    return defaultValue
  end

  local function trackerBackground(key, defaultValue)
    if tracker and tracker.sv and tracker.sv.background and tracker.sv.background[key] ~= nil then
      return tracker.sv.background[key]
    end
    local defaults = trackerDefaults.background or {}
    if defaults[key] ~= nil then
      return defaults[key]
    end
    return defaultValue
  end

  local generalControls = {
    {
      type = "checkbox",
      name = "Status über dem Kompass anzeigen",
      getFunc = function()
        return Nvk3UT.sv and Nvk3UT.sv.ui and (Nvk3UT.sv.ui.showStatus ~= false)
      end,
      setFunc = function(value)
        if Nvk3UT.sv and Nvk3UT.sv.ui then
          Nvk3UT.sv.ui.showStatus = value
        end
        if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
          Nvk3UT.UI.UpdateStatus()
        end
      end,
      default = true,
    },
    {
      type = "dropdown",
      name = "Favoritenspeicherung",
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
        if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
          Nvk3UT.UI.UpdateStatus()
        end
      end,
      tooltip = "Speichert Favoriten account- oder charakterweit.",
      default = "account",
    },
    {
      type = "dropdown",
      name = "Kürzlich-Zeitraum",
      choices = { "Alle", "7 Tage", "30 Tage" },
      choicesValues = { 0, 7, 30 },
      getFunc = function()
        return (Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.recentWindow) or 0
      end,
      setFunc = function(value)
        if Nvk3UT.sv and Nvk3UT.sv.ui then
          Nvk3UT.sv.ui.recentWindow = value
        end
        if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
          Nvk3UT.UI.UpdateStatus()
        end
      end,
      tooltip = "Zeitraum für Kürzlich-Berechnung.",
      default = 0,
    },
    {
      type = "dropdown",
      name = "Kürzlich - Maximum",
      choices = { "50", "100", "250" },
      choicesValues = { 50, 100, 250 },
      getFunc = function()
        return (Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.recentMax) or 100
      end,
      setFunc = function(value)
        if Nvk3UT.sv and Nvk3UT.sv.ui then
          Nvk3UT.sv.ui.recentMax = value
        end
        if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
          Nvk3UT.UI.UpdateStatus()
        end
      end,
      tooltip = "Maximale Anzahl der Kürzlich-Einträge.",
      default = 100,
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
    { type = "header", name = "Debug" },
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
      tooltip = "Führt einen kompakten Integritäts-Check aus.",
    },
    {
      type = "button",
      name = "UI neu laden",
      func = function()
        ReloadUI()
      end,
    },
  }

  addGroup("general", "Allgemein", generalControls)

  addGroup("funktionen", "Funktionen", {
    {
      type = "checkbox",
      name = "Questtracker aktiv",
      getFunc = function()
        return trackerEnabledFlag(true)
      end,
      setFunc = function(value)
        if tracker and tracker.SetEnabled then
          tracker:SetEnabled(value)
        end
      end,
      default = trackerDefaults.enabled ~= false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "checkbox",
      name = "Quests im Questtracker tracken",
      getFunc = function()
        if tracker and tracker.sv then
          return tracker.sv.showQuests ~= false
        end
        return true
      end,
      setFunc = function(value)
        if tracker and tracker.SetShowQuests then
          tracker:SetShowQuests(value)
        end
      end,
      default = trackerDefaults.showQuests ~= false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "checkbox",
      name = "Errungenschaften im Questtracker tracken",
      getFunc = function()
        if tracker and tracker.sv then
          return tracker.sv.showAchievements ~= false
        end
        return true
      end,
      setFunc = function(value)
        if tracker and tracker.SetShowAchievements then
          tracker:SetShowAchievements(value)
        end
      end,
      default = trackerDefaults.showAchievements ~= false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
  })

  addGroup("behavior", "QuestTracker Verhalten", {
    {
      type = "checkbox",
      name = "Default Questtracker verbergen",
      getFunc = function()
        return trackerBehavior("hideDefault", false)
      end,
      setFunc = function(value)
        if tracker and tracker.SetHideDefault then
          tracker:SetHideDefault(value)
        end
      end,
      default = trackerDefaults.behavior and trackerDefaults.behavior.hideDefault or false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "checkbox",
      name = "Quest Tracker im Kampf ausblenden",
      getFunc = function()
        return trackerBehavior("hideInCombat", false)
      end,
      setFunc = function(value)
        if tracker and tracker.SetHideInCombat then
          tracker:SetHideInCombat(value)
        end
      end,
      default = trackerDefaults.behavior and trackerDefaults.behavior.hideInCombat or false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "checkbox",
      name = "Quest Tracker sperren",
      getFunc = function()
        return trackerBehavior("locked", false)
      end,
      setFunc = function(value)
        if tracker and tracker.SetLocked then
          tracker:SetLocked(value)
        end
      end,
      default = trackerDefaults.behavior and trackerDefaults.behavior.locked or false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "checkbox",
      name = "Quest Tracker automatisch vertikal vergrößern",
      getFunc = function()
        return trackerBehavior("autoGrowV", true)
      end,
      setFunc = function(value)
        if tracker and tracker.SetAutoGrowV then
          tracker:SetAutoGrowV(value)
        end
      end,
      default = trackerDefaults.behavior and trackerDefaults.behavior.autoGrowV ~= false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "checkbox",
      name = "Questtracker automatisch horizontal vergrößern",
      getFunc = function()
        return trackerBehavior("autoGrowH", false)
      end,
      setFunc = function(value)
        if tracker and tracker.SetAutoGrowH then
          tracker:SetAutoGrowH(value)
        end
      end,
      default = trackerDefaults.behavior and trackerDefaults.behavior.autoGrowH or false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "checkbox",
      name = "Neue Quests automatisch aufklappen",
      getFunc = function()
        return trackerBehavior("autoExpandNewQuests", false)
      end,
      setFunc = function(value)
        if tracker and tracker.SetAutoExpandNewQuests then
          tracker:SetAutoExpandNewQuests(value)
        end
      end,
      default = trackerDefaults.behavior and trackerDefaults.behavior.autoExpandNewQuests or false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "checkbox",
      name = "Errungenschaften immer aufklappen",
      getFunc = function()
        return trackerBehavior("alwaysExpandAchievements", false)
      end,
      setFunc = function(value)
        if tracker and tracker.SetAlwaysExpandAchievements then
          tracker:SetAlwaysExpandAchievements(value)
        end
      end,
      default = trackerDefaults.behavior and trackerDefaults.behavior.alwaysExpandAchievements or false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "checkbox",
      name = "Tooltips im Questtracker anzeigen",
      getFunc = function()
        return trackerBehavior("tooltips", true)
      end,
      setFunc = function(value)
        if tracker and tracker.SetTooltipsEnabled then
          tracker:SetTooltipsEnabled(value)
        end
      end,
      default = trackerDefaults.behavior and (trackerDefaults.behavior.tooltips ~= false) or true,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "slider",
      name = "Refresh-Throttle (ms)",
      min = 0,
      max = 1000,
      step = 10,
      getFunc = function()
        if tracker and tracker.sv and tracker.sv.throttleMs then
          return tracker.sv.throttleMs
        end
        return trackerDefaults.throttleMs or 150
      end,
      setFunc = function(value)
        if tracker and tracker.SetThrottleMs then
          tracker:SetThrottleMs(value)
        end
      end,
      default = trackerDefaults.throttleMs or 150,
      disabled = function()
        return not trackerAvailable()
      end,
    },
  })

  addGroup("background", "Questtracker Background", {
    {
      type = "checkbox",
      name = "Background aktivieren",
      getFunc = function()
        return trackerBackground("enabled", false)
      end,
      setFunc = function(value)
        if tracker and tracker.SetBackgroundEnabled then
          tracker:SetBackgroundEnabled(value)
        end
      end,
      default = trackerDefaults.background and trackerDefaults.background.enabled or false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "slider",
      name = "Background Transparenz",
      min = 0,
      max = 100,
      step = 5,
      getFunc = function()
        return trackerBackground("alpha", 60)
      end,
      setFunc = function(value)
        if tracker and tracker.SetBackgroundAlpha then
          tracker:SetBackgroundAlpha(value)
        end
      end,
      default = trackerDefaults.background and trackerDefaults.background.alpha or 60,
      disabled = function()
        return not trackerAvailable()
      end,
    },
    {
      type = "checkbox",
      name = "Background bei Sperren ausblenden",
      getFunc = function()
        return trackerBackground("hideWhenLocked", false)
      end,
      setFunc = function(value)
        if tracker and tracker.SetBackgroundHideWhenLocked then
          tracker:SetBackgroundHideWhenLocked(value)
        end
      end,
      default = trackerDefaults.background and trackerDefaults.background.hideWhenLocked or false,
      disabled = function()
        return not trackerAvailable()
      end,
    },
  })

  local fontLabels = {
    category = {
      font = "Kategorie Font",
      effect = "Kategorie Font Effekte",
      size = "Kategorie Schriftgröße",
      color = "Kategorie Font Farbe",
    },
    quest = {
      font = "Quest Font",
      effect = "Quest Font Effekte",
      size = "Quest Size",
      color = "Quest Color",
    },
    task = {
      font = "Quest Aufgaben Font",
      effect = "Quest Aufgaben Font Effekte",
      size = "Quest Aufgaben Größe",
      color = "Quest Aufgaben Farbe",
    },
    achieve = {
      font = "Errungenschaft Font",
      effect = "Errungenschaft Font Effekte",
      size = "Errungenschaft Size",
      color = "Errungenschaft Color",
    },
    achieveTask = {
      font = "Errungenschaft Aufgaben Font",
      effect = "Errungenschaft Aufgaben Effekte",
      size = "Errungenschaft Aufgaben Größe",
      color = "Errungenschaft Aufgaben Farbe",
    },
  }

  local function fontControls(key, labels)
    local defaults = trackerDefaults.fonts and trackerDefaults.fonts[key] or {}
    return {
      {
        type = "dropdown",
        name = labels.font,
        choices = fontChoiceLabels,
        choicesValues = fontChoiceValues,
        getFunc = function()
          local cfg = getFontConfig(key)
          return cfg.face or defaults.face or "ZoFontGame"
        end,
        setFunc = function(value)
          setFontField(key, "face", value)
        end,
        default = defaults.face or "ZoFontGame",
        disabled = function()
          return not trackerAvailable()
        end,
      },
      {
        type = "dropdown",
        name = labels.effect,
        choices = effectChoiceLabels,
        choicesValues = effectChoiceValues,
        getFunc = function()
          local cfg = getFontConfig(key)
          return cfg.effect or defaults.effect or ""
        end,
        setFunc = function(value)
          setFontField(key, "effect", value)
        end,
        default = defaults.effect or "soft-shadow-thin",
        disabled = function()
          return not trackerAvailable()
        end,
      },
      {
        type = "slider",
        name = labels.size,
        min = 12,
        max = 36,
        step = 1,
        getFunc = function()
          local cfg = getFontConfig(key)
          return cfg.size or defaults.size or 18
        end,
        setFunc = function(value)
          setFontField(key, "size", value)
        end,
        default = defaults.size or 18,
        disabled = function()
          return not trackerAvailable()
        end,
      },
      {
        type = "colorpicker",
        name = labels.color,
        getFunc = function()
          local cfg = getFontConfig(key)
          return colorComponents(cfg.color, defaults.color)
        end,
        setFunc = function(r, g, b, a)
          setFontField(key, "color", { r = r, g = g, b = b, a = a })
        end,
        default = { colorComponents(defaults.color, { r = 1, g = 1, b = 1, a = 1 }) },
        disabled = function()
          return not trackerAvailable()
        end,
      },
    }
  end

  addGroup("category", "Kategorie Optionen", fontControls("category", fontLabels.category))
  addGroup("quest", "Quest Optionen", fontControls("quest", fontLabels.quest))
  addGroup("task", "Quest Aufgaben", fontControls("task", fontLabels.task))
  addGroup("achieve", "Errungenschaften Optionen", fontControls("achieve", fontLabels.achieve))
  addGroup("achieveTask", "Errungenschaften Aufgaben", fontControls("achieveTask", fontLabels.achieveTask))

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
