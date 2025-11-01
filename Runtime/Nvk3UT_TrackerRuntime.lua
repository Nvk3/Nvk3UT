Nvk3UT = Nvk3UT or {}

local Runtime = Nvk3UT.TrackerRuntime or {}
Nvk3UT.TrackerRuntime = Runtime

local tableInsert = table.insert
local tableUnpack = table.unpack or unpack
local tableConcat = table.concat

local function runtimeDebug(fmt, ...)
    local root = Nvk3UT
    if root and type(root.Debug) == "function" then
        root.Debug(fmt, ...)
    end
end

local function safeCall(method, ...)
    local SafeCall = Nvk3UT and Nvk3UT.SafeCall
    if type(SafeCall) == "function" then
        return SafeCall(method, ...)
    end

    if type(method) ~= "function" then
        return nil
    end

    local results = { pcall(method, ...) }
    if not results[1] then
        return nil
    end

    table.remove(results, 1)
    return tableUnpack(results)
end

local function ensureInit(self)
    if type(self.Init) == "function" then
        self:Init()
    end
end

function Runtime:Init()
    if self._inited then
        return
    end

    self._inited = true
    self._scheduled = false
    self.questDirty, self.achievementDirty = false, false
    self.hostDirty, self.appearanceDirty, self.layoutDirty = false, false, false
    self.isInCombat, self.isCursorShown = false, false

    self._debugPending = false
    self._debugDirtySet = {}
    self._debugDirtyList = {}
end

local function resetDebugState(self)
    self._debugPending = false

    local dirtySet = self._debugDirtySet
    for key in pairs(dirtySet) do
        dirtySet[key] = nil
    end

    local dirtyList = self._debugDirtyList
    for index = #dirtyList, 1, -1 do
        dirtyList[index] = nil
    end
end

local function markDebugKind(self, kind)
    if not kind then
        return
    end

    local dirtySet = self._debugDirtySet
    if dirtySet[kind] then
        return
    end

    dirtySet[kind] = true
    tableInsert(self._debugDirtyList, kind)
    self._debugPending = true
end

local function markDirty(self, kind)
    if kind == "quest" then
        if not self.questDirty then
            self.questDirty = true
            markDebugKind(self, "quest")
        end
        return true
    elseif kind == "achievement" then
        if not self.achievementDirty then
            self.achievementDirty = true
            markDebugKind(self, "achievement")
        end
        return true
    elseif kind == "host" then
        if not self.hostDirty then
            self.hostDirty = true
            markDebugKind(self, "host")
        end
        return true
    elseif kind == "appearance" then
        if not self.appearanceDirty then
            self.appearanceDirty = true
            markDebugKind(self, "appearance")
        end
        return true
    elseif kind == "layout" then
        if not self.layoutDirty then
            self.layoutDirty = true
            markDebugKind(self, "layout")
        end
        return true
    end

    return false
end

local function queueAll(self)
    markDirty(self, "quest")
    markDirty(self, "achievement")
    markDirty(self, "host")
    markDirty(self, "appearance")
    markDirty(self, "layout")
end

local function flushDebug(self)
    if not self._debugPending then
        return
    end

    local kinds = self._debugDirtyList
    if #kinds > 0 then
        runtimeDebug("TrackerRuntime: coalesced dirty: %s", tableConcat(kinds, ","))
    else
        runtimeDebug("TrackerRuntime: coalesced dirty (none)")
    end

    self._debugPending = false
end

local function scheduleNextFrame(self)
    if self._scheduled then
        return
    end

    self._scheduled = true

    zo_callLater(function()
        self._scheduled = false
        flushDebug(self)
        self:ProcessFrame()
    end, 0)
end

function Runtime:QueueDirty(kind)
    ensureInit(self)

    local request = kind
    if type(request) == "string" then
        request = request:lower()
    else
        request = nil
    end

    local dirtyQueued = false
    if request == nil or request == "all" then
        queueAll(self)
        dirtyQueued = true
    else
        dirtyQueued = markDirty(self, request) or dirtyQueued
    end

    if dirtyQueued then
        scheduleNextFrame(self)
    end
end

function Runtime:SetCombatState(isInCombat)
    ensureInit(self)

    self.isInCombat = isInCombat and true or false
    self:QueueDirty("layout")
end

function Runtime:SetCursorMode(isCursorShown)
    ensureInit(self)

    self.isCursorShown = isCursorShown and true or false
    self:QueueDirty("layout")
end

function Runtime:ProcessFrame()
    ensureInit(self)

    local processed = false
    local root = Nvk3UT

    local questTracker = root and root.QuestTracker
    local achievementTracker = root and root.AchievementTracker
    local trackerHostLayout = root and root.TrackerHostLayout

    local hasQuest = type(questTracker) == "table" and type(questTracker.Refresh) == "function"
    local hasAchievement = type(achievementTracker) == "table" and type(achievementTracker.Refresh) == "function"
    local hasLayout = type(trackerHostLayout) == "table" and type(trackerHostLayout.ApplyLayout) == "function"

    if self.questDirty and hasQuest then
        safeCall(questTracker.Refresh, questTracker, nil)
        processed = true
    end

    if self.achievementDirty and hasAchievement then
        safeCall(achievementTracker.Refresh, achievementTracker, nil)
        processed = true
    end

    if (self.hostDirty or self.appearanceDirty or self.layoutDirty) and hasLayout then
        safeCall(trackerHostLayout.ApplyLayout, trackerHostLayout)
        processed = true
    end

    self.questDirty, self.achievementDirty = false, false
    self.hostDirty, self.appearanceDirty, self.layoutDirty = false, false, false

    resetDebugState(self)

    if processed then
        runtimeDebug("TrackerRuntime: ProcessFrame done")
    end
end

Runtime:Init()

return true
