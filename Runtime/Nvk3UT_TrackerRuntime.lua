-- Runtime/Nvk3UT_TrackerRuntime.lua
-- Central runtime scheduler that batches tracker refresh work.

Nvk3UT = Nvk3UT or {}
local Addon = Nvk3UT

Addon.TrackerRuntime = Addon.TrackerRuntime or {}
local Runtime = Addon.TrackerRuntime

local DIRTY_KEY_QUEST = "quest"
local DIRTY_KEY_ACHIEVEMENT = "achievement"
local DIRTY_KEY_HOST_LAYOUT = "hostLayout"

local VALID_DIRTY_KEYS = {
    [DIRTY_KEY_QUEST] = true,
    [DIRTY_KEY_ACHIEVEMENT] = true,
    [DIRTY_KEY_HOST_LAYOUT] = true,
}

local WEAK_VALUE_MT = { __mode = "v" }
local unpack = unpack or table.unpack

Runtime._hostRef = Runtime._hostRef or setmetatable({}, WEAK_VALUE_MT)
Runtime._questDirty = Runtime._questDirty == true
Runtime._achievementDirty = Runtime._achievementDirty == true
Runtime._layoutDirty = Runtime._layoutDirty == true
Runtime._isInCombat = Runtime._isInCombat == true
Runtime._isInCursorMode = Runtime._isInCursorMode == true
Runtime._scheduled = Runtime._scheduled == true
Runtime._scheduledCallId = Runtime._scheduledCallId or nil
Runtime._initialized = Runtime._initialized == true
Runtime._dirtySet = type(Runtime._dirtySet) == "table" and Runtime._dirtySet or {}
Runtime._dirtyQueue = type(Runtime._dirtyQueue) == "table" and Runtime._dirtyQueue or {}

local function debug(fmt, ...)
    if Addon and type(Addon.Debug) == "function" then
        Addon.Debug(fmt, ...)
    end
end

local function ensureDirtyState()
    local dirtySet = Runtime._dirtySet
    if type(dirtySet) ~= "table" then
        dirtySet = {}
        Runtime._dirtySet = dirtySet
    end

    local dirtyQueue = Runtime._dirtyQueue
    if type(dirtyQueue) ~= "table" then
        dirtyQueue = {}
        Runtime._dirtyQueue = dirtyQueue
    end

    return dirtySet, dirtyQueue
end

local function setLegacyFlag(key, value)
    local normalized = value == true
    if key == DIRTY_KEY_QUEST then
        Runtime._questDirty = normalized
    elseif key == DIRTY_KEY_ACHIEVEMENT then
        Runtime._achievementDirty = normalized
    elseif key == DIRTY_KEY_HOST_LAYOUT then
        Runtime._layoutDirty = normalized
    end
end

local function bootstrapLegacyFlags()
    local dirtySet, dirtyQueue = ensureDirtyState()

    if Runtime._questDirty and not dirtySet[DIRTY_KEY_QUEST] then
        dirtySet[DIRTY_KEY_QUEST] = true
        dirtyQueue[#dirtyQueue + 1] = DIRTY_KEY_QUEST
    end

    if Runtime._achievementDirty and not dirtySet[DIRTY_KEY_ACHIEVEMENT] then
        dirtySet[DIRTY_KEY_ACHIEVEMENT] = true
        dirtyQueue[#dirtyQueue + 1] = DIRTY_KEY_ACHIEVEMENT
    end

    if Runtime._layoutDirty and not dirtySet[DIRTY_KEY_HOST_LAYOUT] then
        dirtySet[DIRTY_KEY_HOST_LAYOUT] = true
        dirtyQueue[#dirtyQueue + 1] = DIRTY_KEY_HOST_LAYOUT
    end
end

local function hasPendingDirty()
    bootstrapLegacyFlags()

    local dirtyQueue = Runtime._dirtyQueue
    return type(dirtyQueue) == "table" and #dirtyQueue > 0
end

local function safeCall(fn, ...)
    if Addon and type(Addon.SafeCall) == "function" then
        return Addon.SafeCall(fn, ...)
    end

    if type(fn) == "function" then
        local ok, result = pcall(fn, ...)
        if ok then
            return result
        end
    end

    return nil
end

local function getHostWindow()
    local ref = Runtime._hostRef
    if type(ref) ~= "table" then
        return nil
    end

    return ref.hostWindow
end

local function setHostWindow(hostWindow)
    local ref = Runtime._hostRef
    if type(ref) ~= "table" then
        ref = setmetatable({}, WEAK_VALUE_MT)
        Runtime._hostRef = ref
    end

    ref.hostWindow = hostWindow
end

local function callWithOptionalSelf(targetTable, fn, preferPlainCall, ...)
    if type(fn) ~= "function" then
        return false
    end

    local invoked = false
    local args = { ... }

    local function tryInvoke(withSelf)
        if withSelf and targetTable == nil then
            return false
        end

        local ok
        if withSelf then
            ok = pcall(fn, targetTable, unpack(args))
        else
            ok = pcall(fn, unpack(args))
        end

        if ok then
            invoked = true
            return true
        end

        return false
    end

    safeCall(function()
        if preferPlainCall then
            if tryInvoke(false) then
                return
            end
            tryInvoke(true)
            return
        end

        if tryInvoke(true) then
            return
        end

        tryInvoke(false)
    end)

    return invoked
end

local function buildQuestViewModel()
    local controller = rawget(Addon, "QuestTrackerController")
    if type(controller) ~= "table" then
        return false
    end

    local build = controller.BuildViewModel or controller.Build
    if type(build) ~= "function" then
        return false
    end

    return callWithOptionalSelf(controller, build, false)
end

local function refreshQuestTracker()
    local tracker = rawget(Addon, "QuestTracker")
    if type(tracker) ~= "table" then
        return false
    end

    local requestRefresh = tracker.RequestRefresh
    if type(requestRefresh) == "function" then
        safeCall(requestRefresh)
        return true
    end

    local refresh = tracker.Refresh
    if type(refresh) == "function" then
        safeCall(refresh)
        return true
    end

    return false
end

local function buildAchievementViewModel()
    local controller = rawget(Addon, "AchievementTrackerController")
    if type(controller) ~= "table" then
        return false
    end

    local build = controller.BuildViewModel or controller.Build
    if type(build) ~= "function" then
        return false
    end

    return callWithOptionalSelf(controller, build, false)
end

local function refreshAchievementTracker()
    local tracker = rawget(Addon, "AchievementTracker")
    if type(tracker) ~= "table" then
        return false
    end

    local requestRefresh = tracker.RequestRefresh
    if type(requestRefresh) == "function" then
        safeCall(requestRefresh)
        return true
    end

    local refresh = tracker.Refresh
    if type(refresh) == "function" then
        safeCall(refresh)
        return true
    end

    return false
end

local function applyTrackerHostLayout()
    local layout = rawget(Addon, "TrackerHostLayout")
    if type(layout) ~= "table" then
        return false
    end

    local apply = layout.Apply or layout.ApplyLayout or layout.Refresh or layout.Update
    if type(apply) ~= "function" then
        return false
    end

    local hostWindow = getHostWindow()

    if hostWindow ~= nil then
        local applied = callWithOptionalSelf(layout, apply, true, hostWindow)
        if applied then
            return true
        end
    end

    return callWithOptionalSelf(layout, apply, true)
end

local function clearDirtyFlags()
    Runtime._questDirty = false
    Runtime._achievementDirty = false
    Runtime._layoutDirty = false
end

local function clearDirtyState()
    clearDirtyFlags()

    Runtime._dirtySet = {}
    Runtime._dirtyQueue = {}
end

local function executeProcessing()
    Runtime._scheduled = false
    Runtime._scheduledCallId = nil

    safeCall(function()
        Runtime:ProcessFrame()
    end)
end

local function scheduleProcessing()
    if Runtime._scheduled then
        return
    end

    if not hasPendingDirty() then
        return
    end

    Runtime._scheduled = true

    if type(zo_callLater) == "function" then
        Runtime._scheduledCallId = zo_callLater(executeProcessing, 0)
        return
    end

    executeProcessing()
end

function Runtime:Init(hostWindow)
    setHostWindow(hostWindow)
    self._initialized = true
    debug("TrackerRuntime.Init(%s)", tostring(hostWindow))
end

function Runtime:QueueDirty(kind, reason)
    if kind == "layout" then
        kind = DIRTY_KEY_HOST_LAYOUT
    end

    if not VALID_DIRTY_KEYS[kind] then
        debug("TrackerRuntime.QueueDirty ignored unknown kind '%s'", tostring(kind))
        return
    end

    local dirtySet, dirtyQueue = ensureDirtyState()

    if not dirtySet[kind] then
        dirtySet[kind] = true
        dirtyQueue[#dirtyQueue + 1] = kind
    end

    setLegacyFlag(kind, true)

    scheduleProcessing()
end

function Runtime:ProcessFrame()
    bootstrapLegacyFlags()

    local dirtyQueue = self._dirtyQueue
    if type(dirtyQueue) ~= "table" or #dirtyQueue == 0 then
        return
    end

    local dirtyKeys = {}
    for index = 1, #dirtyQueue do
        dirtyKeys[index] = dirtyQueue[index]
    end

    local dirtySet = self._dirtySet
    local questDirty = dirtySet and dirtySet[DIRTY_KEY_QUEST] == true
    local achievementDirty = dirtySet and dirtySet[DIRTY_KEY_ACHIEVEMENT] == true
    local hostLayoutDirty = dirtySet and dirtySet[DIRTY_KEY_HOST_LAYOUT] == true

    clearDirtyState()

    if #dirtyKeys > 0 then
        local formatted = {}
        for index = 1, #dirtyKeys do
            formatted[index] = string.format("'%s'", tostring(dirtyKeys[index]))
        end

        debug("Runtime: batched dirty=[%s] (n=%d)", table.concat(formatted, ","), #dirtyKeys)
    end

    local refreshed = false

    if questDirty then
        local built = buildQuestViewModel()
        local refreshedQuest = refreshQuestTracker()
        refreshed = refreshed or refreshedQuest or built
    end

    if achievementDirty then
        local built = buildAchievementViewModel()
        local refreshedAchievement = refreshAchievementTracker()
        refreshed = refreshed or refreshedAchievement or built
    end

    if refreshed or hostLayoutDirty then
        applyTrackerHostLayout()
    end

    if hasPendingDirty() then
        scheduleProcessing()
    end
end

function Runtime:SetCombatState(isInCombat)
    local normalized = isInCombat == true
    if self._isInCombat == normalized then
        return
    end

    self._isInCombat = normalized
    self:QueueDirty(DIRTY_KEY_HOST_LAYOUT, "combat-state")
end

function Runtime:SetCursorMode(isInCursorMode)
    local normalized = isInCursorMode == true
    if self._isInCursorMode == normalized then
        return
    end

    self._isInCursorMode = normalized
    self:QueueDirty(DIRTY_KEY_HOST_LAYOUT, "cursor-mode")
end

return Runtime
