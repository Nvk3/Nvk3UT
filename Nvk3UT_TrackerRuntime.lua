--[[
    Nvk3UT_TrackerRuntime.lua

    TrackerRuntime is the host-facing runtime that owns shared tracker state
    and visibility behavior. It receives normalized ESO events from
    Nvk3UT_EventHandler and decides when the tracker host and its children
    should react. This module does **not** perform any throttling, batching,
    debounce, or coordinator work yet – it simply mirrors the timing from the
    working main branch while centralizing ownership of host-level decisions.
    Runtime owns visibility policy (such as hide-in-combat) for the shared
    tracker host and applies it consistently to every child tracker. LAM
    settings feed into the runtime directly so the host reacts immediately
    without batching or debounce layers.
]]

local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local TrackerRuntime = {}
TrackerRuntime.__index = TrackerRuntime

local MODULE_NAME = addonName .. "TrackerRuntime"

local TRACKER_KEYS = {
    quest = "QuestTrackerController",
    achievement = "AchievementTrackerController",
}

local state = {
    hostControl = nil,
    hostHidden = false,
    isInCombat = false,
    hideInCombatEnabled = false,
    visibilityInitialized = false,
    update = nil,
    quest = {
        tracker = nil,
        control = nil,
        hidden = false,
        appliedHidden = nil,
    },
    achievement = {
        tracker = nil,
        control = nil,
        hidden = false,
        appliedHidden = nil,
    },
}

local function GetSavedVars()
    return Nvk3UT and Nvk3UT.sv
end

local function GetRuntimeSettings()
    local sv = GetSavedVars()
    if not sv then
        return nil
    end

    sv.TrackerRuntime = sv.TrackerRuntime or {}
    return sv.TrackerRuntime
end

local function EnsureVisibilitySettings()
    if state.visibilityInitialized then
        return
    end

    local sv = GetSavedVars()
    if not sv then
        return
    end

    state.visibilityInitialized = true

    local settings = GetRuntimeSettings()
    if settings.hideInCombat == nil then
        local questSettings = sv and sv.QuestTracker
        settings.hideInCombat = questSettings and questSettings.hideInCombat == true or false
    end

    state.hideInCombatEnabled = settings.hideInCombat == true
end

local function IsDebugLoggingEnabled()
    local sv = Nvk3UT and Nvk3UT.sv
    return sv and sv.debug == true
end

local function DebugLog(...)
    if not IsDebugLoggingEnabled() then
        return
    end

    if d then
        d(string.format("[%s]", MODULE_NAME), ...)
    elseif print then
        print("[" .. MODULE_NAME .. "]", ...)
    end
end

local function SafeCall(description, func, ...)
    if type(func) ~= "function" then
        return nil, nil
    end

    local ok, result = pcall(func, ...)
    if not ok then
        DebugLog(string.format("%s failed: %s", description or "callback", tostring(result)))
        return nil, result
    end

    return result, nil
end

local function ResolveTrackerModule(key)
    local trackerState = state[key]
    if trackerState and trackerState.tracker then
        return trackerState.tracker
    end

    local globalName = TRACKER_KEYS[key]
    local tracker = globalName and Nvk3UT and Nvk3UT[globalName]
    if trackerState then
        trackerState.tracker = tracker
    end
    return tracker
end

local function GetUpdateState()
    if not state.update then
        state.update = {
            questsDirty = false,
            achievementsDirty = false,
            layoutDirty = false,
            questReason = nil,
            achievementReason = nil,
            layoutReason = nil,
        }
    end

    return state.update
end

local function ApplyVisibility(trackerKey, hidden, reason)
    local trackerState = state[trackerKey]
    if not trackerState then
        return
    end

    local normalizedHidden = hidden and true or false
    trackerState.hidden = normalizedHidden

    local effectiveHidden = normalizedHidden or state.hostHidden
    if trackerState.appliedHidden == effectiveHidden then
        return
    end

    trackerState.appliedHidden = effectiveHidden

    local tracker = ResolveTrackerModule(trackerKey)
    if tracker and tracker.ApplyHostVisibility then
        SafeCall(string.format("%s.ApplyHostVisibility", TRACKER_KEYS[trackerKey] or trackerKey), tracker.ApplyHostVisibility, effectiveHidden, reason)
        return
    end

    local control = trackerState.control
    if control and control.SetHidden then
        control:SetHidden(effectiveHidden)
    end
end

local function ReapplyTrackerVisibility(trackerKey, reason)
    local trackerState = state[trackerKey]
    if not trackerState then
        return
    end

    ApplyVisibility(trackerKey, trackerState.hidden, reason)
end

local function ApplyHostHiddenState(shouldHide, reason, forceReapply)
    local normalized = shouldHide and true or false

    local host = state.hostControl
    if host and host.SetHidden then
        host:SetHidden(normalized)
    end

    local changed = state.hostHidden ~= normalized
    state.hostHidden = normalized

    if changed or forceReapply then
        for trackerKey in pairs(TRACKER_KEYS) do
            ReapplyTrackerVisibility(trackerKey, reason or "host-visibility")
        end
    end
end

local function ApplyVisibilityPolicy(reason, forceReapply)
    EnsureVisibilitySettings()

    local shouldHide = state.hideInCombatEnabled and state.isInCombat
    ApplyHostHiddenState(shouldHide, reason, forceReapply)
end

local function IsTrackerActive(trackerKey)
    local tracker = ResolveTrackerModule(trackerKey)
    if not tracker or type(tracker.IsActive) ~= "function" then
        return true
    end

    local result = SafeCall(string.format("%s.IsActive", TRACKER_KEYS[trackerKey] or trackerKey), tracker.IsActive)
    if result == nil then
        return true
    end

    return result ~= false
end

local function UpdateQuestVisibility(reason)
    local hidden = false
    local hiddenReason = reason or "state"

    if not IsTrackerActive("quest") then
        hidden = true
        hiddenReason = "inactive"
    end

    ApplyVisibility("quest", hidden, hiddenReason)
end

local function UpdateAchievementVisibility(reason)
    local hidden = false
    local hiddenReason = reason or "state"

    if not IsTrackerActive("achievement") then
        hidden = true
        hiddenReason = "inactive"
    end

    ApplyVisibility("achievement", hidden, hiddenReason)
end

function TrackerRuntime.RegisterHostControls(options)
    if type(options) ~= "table" then
        options = {}
    end

    EnsureVisibilitySettings()

    state.hostControl = options.host or state.hostControl
    if options.quest then
        state.quest.control = options.quest
        state.quest.appliedHidden = nil
    end
    if options.achievement then
        state.achievement.control = options.achievement
        state.achievement.appliedHidden = nil
    end

    UpdateQuestVisibility("host-register")
    UpdateAchievementVisibility("host-register")
    ApplyVisibilityPolicy("host-register", true)
end

function TrackerRuntime.UnregisterHostControls()
    state.hostControl = nil
    state.quest.control = nil
    state.achievement.control = nil
    state.quest.hidden = false
    state.achievement.hidden = false
    state.quest.appliedHidden = nil
    state.achievement.appliedHidden = nil
end

function TrackerRuntime.RegisterQuestTracker(options)
    if type(options) ~= "table" then
        options = {}
    end

    EnsureVisibilitySettings()

    state.quest.tracker = options.tracker or ResolveTrackerModule("quest")
    if options.control then
        state.quest.control = options.control
        state.quest.appliedHidden = nil
    end

    UpdateQuestVisibility("register")

    if state.update and state.update.questsDirty then
        TrackerRuntime.ProcessUpdates("quest-register")
    end
end

function TrackerRuntime.UnregisterQuestTracker()
    state.quest.tracker = nil
    state.quest.control = nil
    state.quest.hidden = false
    state.quest.appliedHidden = nil
end

function TrackerRuntime.RegisterAchievementTracker(options)
    if type(options) ~= "table" then
        options = {}
    end

    EnsureVisibilitySettings()

    state.achievement.tracker = options.tracker or ResolveTrackerModule("achievement")
    if options.control then
        state.achievement.control = options.control
        state.achievement.appliedHidden = nil
    end

    UpdateAchievementVisibility("register")

    if state.update and state.update.achievementsDirty then
        TrackerRuntime.ProcessUpdates("achievement-register")
    end
end

function TrackerRuntime.UnregisterAchievementTracker()
    state.achievement.tracker = nil
    state.achievement.control = nil
    state.achievement.hidden = false
    state.achievement.appliedHidden = nil
end

function TrackerRuntime.UpdateQuestVisibility(reason)
    UpdateQuestVisibility(reason)
end

function TrackerRuntime.UpdateAchievementVisibility(reason)
    UpdateAchievementVisibility(reason)
end

function TrackerRuntime.UpdateAllVisibility(reason)
    UpdateQuestVisibility(reason)
    UpdateAchievementVisibility(reason)
end

function TrackerRuntime.GetHideInCombatEnabled()
    EnsureVisibilitySettings()
    return state.hideInCombatEnabled == true
end

function TrackerRuntime.SetHideInCombatEnabled(enabled)
    EnsureVisibilitySettings()

    local normalized = enabled and true or false
    local changed = state.hideInCombatEnabled ~= normalized

    state.hideInCombatEnabled = normalized

    local settings = GetRuntimeSettings()
    if settings then
        settings.hideInCombat = normalized
    end

    ApplyVisibilityPolicy("settings", not changed)
end

function TrackerRuntime.ApplyVisibilityPolicy(reason, forceReapply)
    ApplyVisibilityPolicy(reason, forceReapply)
end

---Returns whether the runtime currently suppresses the host due to
---visibility policy (for example hide-in-combat).
---@return boolean
function TrackerRuntime.IsHostHiddenByPolicy()
    return state.hostHidden == true
end

local function CallRefresh(trackerKey, methodNames, reason)
    local tracker = ResolveTrackerModule(trackerKey)
    if not tracker then
        return false
    end

    local readiness = tracker.IsInitialized
    if type(readiness) == "function" then
        local ok, ready = pcall(readiness, tracker, methodNames and methodNames[1])
        if not ok then
            DebugLog(string.format("IsInitialized check failed for %s: %s", tostring(trackerKey), tostring(ready)))
            return false
        end

        if ready == false then
            return false
        end
    elseif readiness == false then
        return false
    end

    for index = 1, #methodNames do
        local methodName = methodNames[index]
        local func = tracker[methodName]
        if type(func) == "function" then
            SafeCall(string.format("%s.%s", TRACKER_KEYS[trackerKey] or trackerKey, methodName), func, reason)
            return true
        end
    end

    return false
end

local function SyncStructureIfDirty(trackerKey, reason)
    local tracker = ResolveTrackerModule(trackerKey)
    if not tracker then
        return false
    end

    local syncFunc = tracker.SyncStructureIfDirty
    if type(syncFunc) ~= "function" then
        return false
    end

    local description = string.format("%s.SyncStructureIfDirty", TRACKER_KEYS[trackerKey] or trackerKey)
    local result = SafeCall(description, syncFunc, reason)

    return result ~= false
end

function TrackerRuntime.ForceQuestTrackerRefresh(reason)
    return CallRefresh("quest", { "RefreshNow", "RequestRefresh", "Refresh" }, reason)
end

function TrackerRuntime.ForceAchievementTrackerRefresh(reason)
    return CallRefresh("achievement", { "RefreshNow", "RequestRefresh", "Refresh" }, reason)
end

function TrackerRuntime.RequestFullRefresh(reason)
    local questRefreshed = TrackerRuntime.ForceQuestTrackerRefresh(reason)
    local achievementRefreshed = TrackerRuntime.ForceAchievementTrackerRefresh(reason)
    return questRefreshed or achievementRefreshed
end

function TrackerRuntime.OnCombatStateChanged(inCombat)
    EnsureVisibilitySettings()

    local normalized = inCombat and true or false
    state.isInCombat = normalized
    ApplyVisibilityPolicy("combat")
    UpdateQuestVisibility("combat")
end

function TrackerRuntime.GetCombatState()
    return state.isInCombat == true
end

local function FlushCoordinatorUpdates(triggerReason)
    local update = state.update
    if not update then
        return
    end

    local questsDirty = update.questsDirty
    local achievementsDirty = update.achievementsDirty
    local layoutDirty = update.layoutDirty

    local questReason = update.questReason or triggerReason or "quest-dirty"
    local achievementReason = update.achievementReason or triggerReason or "achievement-dirty"
    local layoutReason = update.layoutReason or triggerReason or "layout-dirty"

    if IsDebugLoggingEnabled() then
        DebugLog(string.format(
            "FlushCoordinatorUpdates questsDirty=%s achievementsDirty=%s layoutDirty=%s",
            tostring(questsDirty),
            tostring(achievementsDirty),
            tostring(layoutDirty)
        ))
    end

    if questsDirty then
        local questSynced = SyncStructureIfDirty("quest", questReason)
        if IsDebugLoggingEnabled() then
            DebugLog(string.format(
                "ProcessUpdates quest syncBeforeRefresh=%s",
                tostring(questSynced)
            ))
        end
        update.questsDirty = false
        update.questReason = nil
        local refreshed = CallRefresh("quest", { "RefreshNow", "RequestRefresh", "Refresh" }, questReason)
        if not refreshed then
            update.questsDirty = true
            update.questReason = questReason
        end
    end

    if achievementsDirty then
        local achievementSynced = SyncStructureIfDirty("achievement", achievementReason)
        if IsDebugLoggingEnabled() then
            DebugLog(string.format(
                "ProcessUpdates achievement syncBeforeRefresh=%s",
                tostring(achievementSynced)
            ))
        end
        update.achievementsDirty = false
        update.achievementReason = nil
        local refreshed = CallRefresh("achievement", { "RefreshNow", "RequestRefresh", "Refresh" }, achievementReason)
        if not refreshed then
            update.achievementsDirty = true
            update.achievementReason = achievementReason
        end
    end

    if layoutDirty then
        update.layoutDirty = false
        update.layoutReason = nil

        if not questsDirty and not achievementsDirty then
            local refreshed = TrackerRuntime.RequestFullRefresh(layoutReason)
            if not refreshed then
                update.layoutDirty = true
                update.layoutReason = layoutReason
            end
        end
    end
end

function TrackerRuntime.ProcessUpdates(triggerReason)
    if IsDebugLoggingEnabled() then
        DebugLog(string.format("ProcessUpdates(%s)", tostring(triggerReason)))
    end

    FlushCoordinatorUpdates(triggerReason)
end

local function MarkDirty(flagName, reasonKey, reason)
    local update = GetUpdateState()
    update[flagName] = true
    if reason and reason ~= "" then
        update[reasonKey] = reason
    end

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("MarkDirty %s -> %s", tostring(flagName), tostring(reason or "")))
    end

    TrackerRuntime.ProcessUpdates(reason)
end

function TrackerRuntime.MarkQuestDirty(reason)
    MarkDirty("questsDirty", "questReason", reason)
end

function TrackerRuntime.MarkAchievementDirty(reason)
    MarkDirty("achievementsDirty", "achievementReason", reason)
end

function TrackerRuntime.MarkLayoutDirty(reason)
    MarkDirty("layoutDirty", "layoutReason", reason)
end

function TrackerRuntime:IsInitialized()
    return true
end

Nvk3UT.TrackerRuntime = TrackerRuntime

return TrackerRuntime
