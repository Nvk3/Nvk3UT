Nvk3UT = Nvk3UT or {}
local M = Nvk3UT

M.Tracker = M.Tracker or {}
local Module = M.Tracker

local function debugLog(message)
    if d then
        d(string.format("[Nvk3UT] Tracker: %s", tostring(message)))
    end
end

local function getTrackerSV()
    local root = M and M.sv
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

    Module.sv = sv
    return sv
end

local function publishSettingsChanged(key)
    local payload = key
    if M and M.Publish then
        M.Publish("settings:changed", payload)
        return
    end
    if M and M.Core and M.Core.Publish then
        M.Core.Publish("settings:changed", payload)
    end
end

local function markViewDirty()
    if M and M.TrackerView and M.TrackerView.MarkDirty then
        M.TrackerView.MarkDirty()
    end
end

local function forceViewRefresh()
    if M and M.TrackerView and M.TrackerView.ForceRefresh then
        M.TrackerView.ForceRefresh()
        return true
    end
    return false
end

local function applyViewSettings()
    if M and M.TrackerView then
        if M.TrackerView.ApplyDefaultTrackerVisibility then
            M.TrackerView.ApplyDefaultTrackerVisibility()
        end
        if M.TrackerView.ApplySettingsFromSV then
            M.TrackerView.ApplySettingsFromSV()
        end
    end
end

function Module.Init()
    getTrackerSV()
    Module.initialized = true
    debugLog("Init() complete")
end

function Module.RegisterLamPanel(panelControl)
    Module.lamPanelControl = panelControl
end

function Module.GetSavedVars()
    return getTrackerSV()
end

function Module.ForceRefresh()
    if not forceViewRefresh() then
        markViewDirty()
    end
end

function Module.NotifyViewReady()
    applyViewSettings()
    markViewDirty()
end

local function setAndNotify(key, value)
    local sv = getTrackerSV()
    if not sv then
        return
    end

    if sv[key] == value then
        return
    end

    sv[key] = value
    publishSettingsChanged(key)
    markViewDirty()
end

function Module.SetEnabled(value)
    setAndNotify("enabled", value == true)
end

function Module.SetShowQuests(value)
    setAndNotify("showQuests", value == true)
end

function Module.SetShowAchievements(value)
    setAndNotify("showAchievements", value == true)
end

local function updateBehaviorOption(key, value)
    local sv = getTrackerSV()
    if not sv then
        return
    end

    sv.behavior = sv.behavior or {}
    if sv.behavior[key] == value then
        return
    end

    sv.behavior[key] = value
    publishSettingsChanged({ behavior = key })
    applyViewSettings()
    markViewDirty()
end

function Module.SetBehaviorOption(key, value)
    updateBehaviorOption(key, value)
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
    publishSettingsChanged("throttle")
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
    publishSettingsChanged({ background = key })
    applyViewSettings()
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
    publishSettingsChanged({ font = section, field = field })
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

    publishSettingsChanged({ fontColor = section })
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
    applyViewSettings()
end

function Module.MarkDirty()
    markViewDirty()
end

return
