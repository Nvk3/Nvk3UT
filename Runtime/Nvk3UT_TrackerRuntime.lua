Nvk3UT = Nvk3UT or {}

local Runtime = Nvk3UT.TrackerRuntime or {}
Nvk3UT.TrackerRuntime = Runtime

local DIRTY_KINDS = {
    quest = "quest",
    achievement = "achievement",
    host = "host",
    appearance = "appearance",
    layout = "layout",
}

local DIRTY_KIND_ORDER = {
    DIRTY_KINDS.quest,
    DIRTY_KINDS.achievement,
    DIRTY_KINDS.host,
    DIRTY_KINDS.appearance,
    DIRTY_KINDS.layout,
}

local function ensureSafeCall()
    local safeCall = Nvk3UT and Nvk3UT.SafeCall
    if type(safeCall) == "function" then
        return safeCall
    end

    return function(func, ...)
        if type(func) == "function" then
            return func(...)
        end
    end
end

function Runtime:Init()
    if self._inited then
        return
    end

    self._inited = true
    self._scheduled = false

    self.questDirty = false
    self.achievementDirty = false
    self.hostDirty = false
    self.appearanceDirty = false
    self.layoutDirty = false

    self.isInCombat = false
    self.isCursorShown = false

    self._debugDirtyKinds = {}
end

local function scheduleNextFrame(self)
    if self._scheduled then
        return
    end

    self._scheduled = true

    zo_callLater(function()
        self._scheduled = false
        self:ProcessFrame()
    end, 0)
end

local function markDirty(self, kind)
    if kind == DIRTY_KINDS.quest then
        self.questDirty = true
    elseif kind == DIRTY_KINDS.achievement then
        self.achievementDirty = true
    elseif kind == DIRTY_KINDS.host then
        self.hostDirty = true
    elseif kind == DIRTY_KINDS.appearance then
        self.appearanceDirty = true
    elseif kind == DIRTY_KINDS.layout then
        self.layoutDirty = true
    end

    local debugKinds = self._debugDirtyKinds
    if debugKinds then
        debugKinds[kind] = true
    end
end

local function markAllDirty(self)
    markDirty(self, DIRTY_KINDS.quest)
    markDirty(self, DIRTY_KINDS.achievement)
    markDirty(self, DIRTY_KINDS.host)
    markDirty(self, DIRTY_KINDS.appearance)
    markDirty(self, DIRTY_KINDS.layout)
end

function Runtime:QueueDirty(kind)
    self:Init()

    if kind == nil or kind == "all" then
        markAllDirty(self)
    elseif DIRTY_KINDS[kind] ~= nil then
        markDirty(self, DIRTY_KINDS[kind])
    end

    scheduleNextFrame(self)
end

function Runtime:SetCombatState(isInCombat)
    self:Init()

    self.isInCombat = isInCombat and true or false
    self:QueueDirty("layout")
end

function Runtime:SetCursorMode(isCursorShown)
    self:Init()

    self.isCursorShown = isCursorShown and true or false
    self:QueueDirty("layout")
end

local function collectDirtyKinds(self)
    local kinds = self._debugDirtyKinds
    if not kinds then
        return {}
    end

    local ordered = {}
    for index = 1, #DIRTY_KIND_ORDER do
        local kind = DIRTY_KIND_ORDER[index]
        if kinds[kind] then
            ordered[#ordered + 1] = kind
        end
    end

    return ordered
end

local function resetDirty(self)
    self.questDirty = false
    self.achievementDirty = false
    self.hostDirty = false
    self.appearanceDirty = false
    self.layoutDirty = false

    local kinds = self._debugDirtyKinds
    if kinds then
        for key in pairs(kinds) do
            kinds[key] = nil
        end
    end
end

function Runtime:ProcessFrame()
    self:Init()

    local questDirty = self.questDirty
    local achievementDirty = self.achievementDirty
    local hostDirty = self.hostDirty
    local appearanceDirty = self.appearanceDirty
    local layoutDirty = self.layoutDirty

    if not (questDirty or achievementDirty or hostDirty or appearanceDirty or layoutDirty) then
        resetDirty(self)
        return
    end

    local debugKinds = collectDirtyKinds(self)
    if #debugKinds > 0 and Nvk3UT and type(Nvk3UT.Debug) == "function" then
        Nvk3UT.Debug("TrackerRuntime: coalesced dirty: %s", table.concat(debugKinds, ","))
    end

    local questTracker = Nvk3UT and Nvk3UT.QuestTracker
    local hasQuestTracker = questDirty and type(questTracker) == "table" and type(questTracker.Refresh) == "function"

    local achievementTracker = Nvk3UT and Nvk3UT.AchievementTracker
    local hasAchievementTracker = achievementDirty and type(achievementTracker) == "table" and type(achievementTracker.Refresh) == "function"

    local trackerHostLayout = Nvk3UT and Nvk3UT.TrackerHostLayout
    local hasLayout = (hostDirty or appearanceDirty or layoutDirty) and type(trackerHostLayout) == "table" and type(trackerHostLayout.ApplyLayout) == "function"

    local safeCall = ensureSafeCall()

    if hasQuestTracker then
        safeCall(function()
            questTracker:Refresh(nil)
        end)
    end

    if hasAchievementTracker then
        safeCall(function()
            achievementTracker:Refresh(nil)
        end)
    end

    if hasLayout then
        safeCall(function()
            trackerHostLayout:ApplyLayout()
        end)
    end

    resetDirty(self)

    if Nvk3UT and type(Nvk3UT.Debug) == "function" then
        Nvk3UT.Debug("TrackerRuntime: ProcessFrame complete")
    end
end

Runtime:Init()

return Runtime
