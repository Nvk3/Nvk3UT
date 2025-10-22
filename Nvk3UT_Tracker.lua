Nvk3UT = Nvk3UT or {}
local M = Nvk3UT

M.Tracker = M.Tracker or {}
local Module = M.Tracker

local EM = EVENT_MANAGER

local DEFAULT_TRACKER_REASON = "Nvk3UT_Tracker"
local DEFAULT_TRACKER_FRAGMENTS = {
    "FOCUSED_QUEST_TRACKER_FRAGMENT",
    "FOCUSED_QUEST_TRACKER_ALWAYS_SHOW_FRAGMENT",
    "FOCUSED_QUEST_TRACKER_TRACKED_FRAGMENT",
    "FOCUSED_QUEST_TRACKER_FOCUSED_FRAGMENT",
    "GAMEPAD_QUEST_TRACKER_FRAGMENT",
}

local function debugLog(message)
    if d then
        d(string.format("[Nvk3UT] Tracker: %s", tostring(message)))
    end
end

local function getRootSV()
    return M and M.sv
end

local function ensureSettings()
    local root = getRootSV()
    if not root then
        return nil
    end
    root.settings = root.settings or {}
    root.settings.quest = root.settings.quest or {}
    root.settings.ach = root.settings.ach or {}
    root.settings.tracker = root.settings.tracker or {}
    return root.settings
end

local function getTrackerSV()
    local root = getRootSV()
    if not root then
        return nil
    end
    root.tracker = root.tracker or {}
    local sv = root.tracker
    sv.behavior = sv.behavior or {}
    sv.background = sv.background or {}
    sv.fonts = sv.fonts or {}
    sv.pos = sv.pos or {}
    sv.collapseState = sv.collapseState or { zones = {}, quests = {}, achieves = {} }
    return sv
end

local function getQuestSettings()
    local settings = ensureSettings()
    return settings and settings.quest or {}
end

local function getAchSettings()
    local settings = ensureSettings()
    return settings and settings.ach or {}
end

local function getTrackerSettings()
    local settings = ensureSettings()
    return settings and settings.tracker or {}
end

local function publishSettingsChanged(key)
    if M and M.Publish then
        M.Publish("settings:changed", key)
    elseif M and M.Core and M.Core.Publish then
        M.Core.Publish("settings:changed", key)
    end
end

local function markViewDirty()
    if M and M.TrackerView and M.TrackerView.MarkDirty then
        M.TrackerView.MarkDirty()
    end
end

local function applyViewSettings()
    if M and M.TrackerView and M.TrackerView.ApplySettingsFromSV then
        M.TrackerView.ApplySettingsFromSV()
    end
end

local function applyLockState()
    if M and M.TrackerView and M.TrackerView.ApplyLockState then
        M.TrackerView.ApplyLockState()
    end
end

local function applyBackground()
    if M and M.TrackerView and M.TrackerView.ApplyBackground then
        M.TrackerView.ApplyBackground()
    end
end

local function applyScale()
    if M and M.TrackerView and M.TrackerView.ApplyScaleFromSettings then
        M.TrackerView.ApplyScaleFromSettings()
    end
end

local function setDefaultTrackerHidden(hidden)
    for _, fragmentName in ipairs(DEFAULT_TRACKER_FRAGMENTS) do
        local fragment = _G and _G[fragmentName]
        if fragment and fragment.SetHiddenForReason then
            fragment:SetHiddenForReason(DEFAULT_TRACKER_REASON, hidden)
        end
    end

    local focusedTracker = _G and _G.FOCUSED_QUEST_TRACKER
    if focusedTracker then
        if focusedTracker.SetHiddenForReason then
            focusedTracker.SetHiddenForReason(DEFAULT_TRACKER_REASON, hidden)
        elseif focusedTracker.SetHidden then
            focusedTracker:SetHidden(hidden)
        end
        local control = focusedTracker.control
        if control and control.SetHidden then
            control:SetHidden(hidden)
        end
    end
end

local function updateDefaultTrackerVisibility()
    local settings = getTrackerSettings()
    local hideDefault = settings and settings.hideDefault == true
    setDefaultTrackerHidden(hideDefault)
end

function Module.ApplyDefaultTrackerVisibility()
    updateDefaultTrackerVisibility()
end

local function isEnabled()
    local sv = getTrackerSV()
    if not sv then
        return true
    end
    if sv.enabled == nil then
        return true
    end
    return sv.enabled
end

function Module.IsCombatHidden()
    if not Module.inCombat then
        return false
    end
    local settings = getTrackerSettings()
    return settings and settings.hideInCombat == true
end

function Module.ShouldHideTracker()
    if not isEnabled() then
        return true
    end
    if Module.IsCombatHidden() then
        return true
    end
    return false
end

local function updateRootHidden()
    if M and M.TrackerView and M.TrackerView.GetRootControl then
        local root = M.TrackerView.GetRootControl()
        if root then
            root:SetHidden(Module.ShouldHideTracker())
        end
    end
end

local function notifyQuestSection()
    publishSettingsChanged("quest.enabled")
end

local function notifyAchSection()
    publishSettingsChanged("ach.enabled")
end

function Module.SetEnabled(value)
    local sv = getTrackerSV()
    if not sv then
        return
    end
    local flag = value == true
    if sv.enabled == flag then
        return
    end
    sv.enabled = flag
    publishSettingsChanged("tracker.enabled")
    updateRootHidden()
end

function Module.RegisterLamPanel(panelControl)
    Module.lamPanelControl = panelControl
end

function Module.GetSavedVars()
    return getTrackerSV()
end

function Module.SetShowQuests(value)
    local settings = getQuestSettings()
    local flag = value == true
    if settings.enabled == flag then
        return
    end
    settings.enabled = flag
    local sv = getTrackerSV()
    if sv then
        sv.showQuests = flag
    end
    notifyQuestSection()
    markViewDirty()
end

function Module.SetShowAchievements(value)
    local settings = getAchSettings()
    local flag = value == true
    if settings.enabled == flag then
        return
    end
    settings.enabled = flag
    local sv = getTrackerSV()
    if sv then
        sv.showAchievements = flag
    end
    notifyAchSection()
    markViewDirty()
end

local function setTrackerBehavior(key, value)
    local sv = getTrackerSV()
    if not sv then
        return
    end
    sv.behavior = sv.behavior or {}
    if sv.behavior[key] == value then
        return
    end
    sv.behavior[key] = value
end

local function setTrackerSetting(key, value)
    local settings = getTrackerSettings()
    if not settings then
        return
    end
    if settings[key] == value then
        return
    end
    settings[key] = value
    publishSettingsChanged("tracker." .. key)
end

function Module.SetBehaviorOption(key, value)
    local sv = getTrackerSV()
    if not sv then
        return
    end

    if key == "autoExpandNewQuests" then
        local questSettings = getQuestSettings()
        local flag = value == true
        if questSettings.autoExpandNew ~= flag then
            questSettings.autoExpandNew = flag
            publishSettingsChanged("quest.autoExpandNew")
        end
        sv.behavior[key] = flag
        return
    end

    if key == "alwaysExpandAchievements" then
        local achSettings = getAchSettings()
        local flag = value == true
        if achSettings.alwaysExpand ~= flag then
            achSettings.alwaysExpand = flag
            publishSettingsChanged("ach.alwaysExpand")
        end
        sv.behavior[key] = flag
        return
    end

    if key == "tooltips" then
        local questSettings = getQuestSettings()
        local achSettings = getAchSettings()
        local enabled = value ~= false
        if questSettings.tooltips ~= enabled then
            questSettings.tooltips = enabled
            publishSettingsChanged("quest.tooltips")
        end
        if achSettings.tooltips ~= enabled then
            achSettings.tooltips = enabled
            publishSettingsChanged("ach.tooltips")
        end
        sv.behavior[key] = enabled
        return
    end

    if key == "hideDefault" then
        setTrackerSetting("hideDefault", value == true)
        sv.behavior[key] = value == true
        updateDefaultTrackerVisibility()
        return
    end

    if key == "hideInCombat" then
        setTrackerSetting("hideInCombat", value == true)
        sv.behavior[key] = value == true
        updateRootHidden()
        return
    end

    if key == "locked" then
        setTrackerSetting("locked", value == true)
        sv.behavior[key] = value == true
        applyLockState()
        return
    end

    if key == "autoGrowV" or key == "autoGrowH" then
        setTrackerBehavior(key, value == true)
        publishSettingsChanged("tracker." .. key)
        applyViewSettings()
        return
    end

    setTrackerBehavior(key, value)
    publishSettingsChanged("tracker.behavior." .. key)
    applyViewSettings()
end

function Module.SetThrottle(value)
    local numeric = tonumber(value)
    if not numeric then
        return
    end
    local sv = getTrackerSV()
    if not sv then
        return
    end
    if sv.throttleMs == numeric then
        return
    end
    sv.throttleMs = numeric
    publishSettingsChanged("tracker.throttle")
end

function Module.SetBackgroundOption(key, value)
    local sv = getTrackerSV()
    if not sv then
        return
    end
    sv.background = sv.background or {}
    if sv.background[key] == value then
        return
    end
    sv.background[key] = value
    publishSettingsChanged("tracker.background." .. tostring(key))
    applyBackground()
end

local function ensureFontSection(section)
    local sv = getTrackerSV()
    if not sv then
        return nil
    end
    sv.fonts = sv.fonts or {}
    sv.fonts[section] = sv.fonts[section] or {}
    return sv.fonts[section]
end

function Module.SetFontOption(section, field, value)
    if type(section) ~= "string" or type(field) ~= "string" then
        return
    end
    local fontSection = ensureFontSection(section)
    if not fontSection then
        return
    end
    if fontSection[field] == value then
        return
    end
    fontSection[field] = value
    publishSettingsChanged("tracker.font." .. section .. "." .. field)
    markViewDirty()
end

function Module.SetFontColor(section, r, g, b, a)
    if type(section) ~= "string" then
        return
    end
    local fontSection = ensureFontSection(section)
    if not fontSection then
        return
    end
    fontSection.color = fontSection.color or {}
    fontSection.color.r = r
    fontSection.color.g = g
    fontSection.color.b = b
    fontSection.color.a = a
    publishSettingsChanged("tracker.fontColor." .. section)
    markViewDirty()
end

function Module.SetScale(scale)
    local numeric = tonumber(scale)
    if not numeric then
        return
    end
    local sv = getTrackerSV()
    if not sv then
        return
    end
    sv.pos = sv.pos or {}
    if sv.pos.scale == numeric then
        return
    end
    sv.pos.scale = numeric
    applyScale()
end

function Module.ForceRefresh()
    if M and M.TrackerView and M.TrackerView.ForceRefresh then
        M.TrackerView.ForceRefresh()
    else
        markViewDirty()
    end
end

function Module.MarkDirty()
    markViewDirty()
end

function Module.NotifyViewReady()
    updateDefaultTrackerVisibility()
    updateRootHidden()
    applyViewSettings()
    markViewDirty()
end

local function onCombatState(_, inCombat)
    Module.inCombat = inCombat == true
    updateRootHidden()
end

function Module.Init()
    getTrackerSV()
    ensureSettings()

    if EM and EM.RegisterForEvent then
        EM:UnregisterForEvent("Nvk3UT_Tracker_Combat", EVENT_PLAYER_COMBAT_STATE)
        EM:RegisterForEvent("Nvk3UT_Tracker_Combat", EVENT_PLAYER_COMBAT_STATE, onCombatState)
    end

    if type(IsUnitInCombat) == "function" then
        local ok, state = pcall(IsUnitInCombat, "player")
        Module.inCombat = ok and state == true
    else
        Module.inCombat = false
    end

    updateDefaultTrackerVisibility()
    updateRootHidden()
    Module.initialized = true
    debugLog("Init() complete")
end

return
