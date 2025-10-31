local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local AchievementModel = {}
AchievementModel.__index = AchievementModel

local MODEL_NAME = addonName .. "AchievementModel"
local EVENT_NAMESPACE = MODEL_NAME .. "_Event"
local REBUILD_IDENTIFIER = MODEL_NAME .. "_Rebuild"

local MIN_DEBOUNCE_MS = 50
local MAX_DEBOUNCE_MS = 120
local DEFAULT_DEBOUNCE_MS = 80

local function ClampDebounce(value)
    if value < MIN_DEBOUNCE_MS then
        return MIN_DEBOUNCE_MS
    elseif value > MAX_DEBOUNCE_MS then
        return MAX_DEBOUNCE_MS
    end
    return value
end

local function GetTimestampMs()
    if GetFrameTimeMilliseconds then
        return GetFrameTimeMilliseconds()
    end

    if GetGameTimeMilliseconds then
        return GetGameTimeMilliseconds()
    end

    if GetFrameTimeSeconds then
        return math.floor(GetFrameTimeSeconds() * 1000 + 0.5)
    end

    return nil
end

local function LogDebug(self, ...)
    if not self.debugEnabled then
        return
    end

    if d then
        d(string.format("[%s]", MODEL_NAME), ...)
    elseif print then
        print("[" .. MODEL_NAME .. "]", ...)
    end
end

local function NotifySubscribers(self)
    if not self.subscribers then
        return
    end

    for callback in pairs(self.subscribers) do
        local success, err = pcall(callback, self.currentSnapshot)
        if not success then
            LogDebug(self, "Subscriber callback failed", err)
        end
    end
end

local function AppendSignaturePart(parts, value)
    parts[#parts + 1] = tostring(value)
end

local function BuildAchievementSignature(entry)
    local parts = {}
    AppendSignaturePart(parts, entry.id or "nil")
    AppendSignaturePart(parts, entry.name or "")
    AppendSignaturePart(parts, entry.progress.current or "nil")
    AppendSignaturePart(parts, entry.progress.max or "nil")
    AppendSignaturePart(parts, entry.flags.isComplete and 1 or 0)
    AppendSignaturePart(parts, entry.sortOrder or 0)

    if entry.objectives then
        for index = 1, #entry.objectives do
            local objective = entry.objectives[index]
            AppendSignaturePart(parts, objective.description or "")
            AppendSignaturePart(parts, objective.current or "nil")
            AppendSignaturePart(parts, objective.max or "nil")
            AppendSignaturePart(parts, objective.isComplete and 1 or 0)
        end
    end

    return table.concat(parts, "|")
end

local function BuildSnapshot(self)
    local List = Nvk3UT and Nvk3UT.AchievementList
    local raw

    if List and type(List.RefreshFromGame) == "function" then
        local ok, result = pcall(List.RefreshFromGame, List)
        if ok then
            raw = result
        else
            LogDebug(self, "AchievementList.RefreshFromGame failed", tostring(result))
        end
    end

    if not raw and List and type(List.GetRaw) == "function" then
        local ok, result = pcall(List.GetRaw, List)
        if ok then
            raw = result
        else
            LogDebug(self, "AchievementList.GetRaw failed", tostring(result))
        end
    end

    raw = raw or {}

    local entries = raw.achievements or {}
    local total = raw.total
    if type(total) ~= "number" then
        total = #entries
    end

    local totalComplete = raw.totalComplete or 0
    local totalIncomplete = raw.totalIncomplete
    if type(totalIncomplete) ~= "number" then
        totalIncomplete = total - totalComplete
    end

    local signatureParts = {}

    for index = 1, #entries do
        local entry = entries[index]
        entry.sortOrder = index
        entry.signature = BuildAchievementSignature(entry)
        signatureParts[index] = entry.signature
    end

    local snapshot = {
        achievements = entries,
        total = total,
        totalComplete = totalComplete,
        totalIncomplete = totalIncomplete,
        hasIncomplete = (raw.hasIncomplete ~= nil) and (raw.hasIncomplete == true) or (totalIncomplete > 0),
        updatedAtMs = GetTimestampMs(),
    }

    snapshot.signature = table.concat(signatureParts, "\31")

    return snapshot
end

local function SnapshotsDiffer(previous, current)
    if not previous then
        return true
    end

    return previous.signature ~= current.signature
end

local function PerformRebuild(self)
    if not self.isInitialized then
        return
    end

    local snapshot = BuildSnapshot(self)
    if not SnapshotsDiffer(self.currentSnapshot, snapshot) then
        return
    end

    snapshot.revision = (self.currentSnapshot and self.currentSnapshot.revision or 0) + 1
    self.currentSnapshot = snapshot
    NotifySubscribers(self)
end

local function ScheduleRebuild(self)
    if self.pendingRebuild then
        return
    end

    self.pendingRebuild = true

    local interval = self.debounceMs or DEFAULT_DEBOUNCE_MS

    EVENT_MANAGER:RegisterForUpdate(
        REBUILD_IDENTIFIER,
        interval,
        function()
            EVENT_MANAGER:UnregisterForUpdate(REBUILD_IDENTIFIER)
            self.pendingRebuild = false
            PerformRebuild(self)
        end
    )
end

local function ForceRebuild(self)
    if not self.isInitialized then
        return
    end

    if self.pendingRebuild then
        EVENT_MANAGER:UnregisterForUpdate(REBUILD_IDENTIFIER)
        self.pendingRebuild = false
    end

    PerformRebuild(self)
end

local function OnAchievementChanged(...)
    local self = AchievementModel
    if not self.isInitialized then
        return
    end

    ScheduleRebuild(self)
end

local function RegisterForEvent(eventId)
    if not eventId then
        return
    end

    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE .. tostring(eventId), eventId, OnAchievementChanged)
end

local function UnregisterEvent(eventId)
    if not eventId then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. tostring(eventId), eventId)
end

function AchievementModel.OnFavoritesChanged()
    if not AchievementModel.isInitialized then
        return
    end

    ScheduleRebuild(AchievementModel)
end

function AchievementModel.Init(opts)
    if AchievementModel.isInitialized then
        return
    end

    opts = opts or {}

    AchievementModel.debugEnabled = opts.debug or false

    local requestedDebounce = tonumber(opts.debounceMs)
    if requestedDebounce then
        AchievementModel.debounceMs = ClampDebounce(requestedDebounce)
    else
        AchievementModel.debounceMs = DEFAULT_DEBOUNCE_MS
    end

    local List = Nvk3UT and Nvk3UT.AchievementList
    if List and type(List.Init) == "function" then
        pcall(List.Init, List)
    end

    AchievementModel.subscribers = {}
    AchievementModel.isInitialized = true

    RegisterForEvent(EVENT_ACHIEVEMENTS_UPDATED)
    RegisterForEvent(EVENT_ACHIEVEMENT_UPDATED)
    RegisterForEvent(EVENT_ACHIEVEMENT_AWARDED)

    local trackedListEvent = rawget(_G, "EVENT_ACHIEVEMENT_TRACKED_LIST_UPDATED")
    if trackedListEvent then
        RegisterForEvent(trackedListEvent)
    end

    ForceRebuild(AchievementModel)
    NotifySubscribers(AchievementModel)
end

function AchievementModel.Shutdown()
    if not AchievementModel.isInitialized then
        return
    end

    UnregisterEvent(EVENT_ACHIEVEMENTS_UPDATED)
    UnregisterEvent(EVENT_ACHIEVEMENT_UPDATED)
    UnregisterEvent(EVENT_ACHIEVEMENT_AWARDED)

    local trackedListEvent = rawget(_G, "EVENT_ACHIEVEMENT_TRACKED_LIST_UPDATED")
    if trackedListEvent then
        UnregisterEvent(trackedListEvent)
    end

    EVENT_MANAGER:UnregisterForUpdate(REBUILD_IDENTIFIER)

    local List = Nvk3UT and Nvk3UT.AchievementList
    if List and type(List.Init) == "function" then
        pcall(List.Init, List)
    end

    AchievementModel.isInitialized = false
    AchievementModel.subscribers = nil
    AchievementModel.currentSnapshot = nil
    AchievementModel.pendingRebuild = nil
end

function AchievementModel.GetSnapshot()
    return AchievementModel.currentSnapshot
end

function AchievementModel.Subscribe(callback)
    assert(type(callback) == "function", "AchievementModel.Subscribe expects a function")

    AchievementModel.subscribers = AchievementModel.subscribers or {}
    AchievementModel.subscribers[callback] = true

    if AchievementModel.isInitialized and not AchievementModel.currentSnapshot then
        ForceRebuild(AchievementModel)
    end

    callback(AchievementModel.currentSnapshot)
end

function AchievementModel.Unsubscribe(callback)
    if AchievementModel.subscribers then
        AchievementModel.subscribers[callback] = nil
    end
end

Nvk3UT.AchievementModel = AchievementModel

return AchievementModel
