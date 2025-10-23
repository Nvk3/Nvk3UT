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

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end

    local ok, value = pcall(func, ...)
    if ok then
        return value
    end

    return nil
end

local tableUnpack = table.unpack or unpack

local function SafeCallMulti(func, ...)
    if type(func) ~= "function" then
        return nil
    end

    local results = { pcall(func, ...) }
    if not results[1] then
        return nil
    end

    table.remove(results, 1)
    return tableUnpack(results)
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

local function BuildObjectiveData(achievementId)
    local objectives = {}

    local numCriteria = SafeCall(GetAchievementNumCriteria, achievementId)
    if not numCriteria or numCriteria <= 0 then
        return objectives
    end

    for criterionIndex = 1, numCriteria do
        local description, numCompleted, numRequired, isFailCondition, isVisible, isComplete = SafeCallMulti(
            GetAchievementCriterion,
            achievementId,
            criterionIndex
        )

        objectives[#objectives + 1] = {
            description = description,
            current = numCompleted,
            max = numRequired,
            isComplete = isComplete or (numRequired ~= nil and numRequired > 0 and numCompleted ~= nil and numCompleted >= numRequired) or false,
            isFailCondition = isFailCondition or false,
            isVisible = isVisible ~= false,
        }
    end

    return objectives
end

local function DetermineCategoryInfo(categoryIndex, subCategoryIndex)
    if not categoryIndex then
        return nil
    end

    local categoryName
    if GetAchievementCategoryInfo then
        local infoName = SafeCallMulti(GetAchievementCategoryInfo, categoryIndex)
        if infoName ~= nil then
            categoryName = infoName
        end
    end

    local subCategoryName
    if subCategoryIndex and GetAchievementSubCategoryInfo then
        local infoName = SafeCallMulti(GetAchievementSubCategoryInfo, categoryIndex, subCategoryIndex)
        if infoName ~= nil then
            subCategoryName = infoName
        end
    end

    return {
        categoryIndex = categoryIndex,
        subCategoryIndex = subCategoryIndex,
        categoryName = categoryName,
        subCategoryName = subCategoryName,
    }
end

local function ExtractIndicesFromTrackedInfo(infoValues)
    if not infoValues then
        return nil
    end

    local numericValues = {}
    for index = 1, #infoValues do
        if type(infoValues[index]) == "number" then
            numericValues[#numericValues + 1] = infoValues[index]
        end
    end

    -- Best guess: the last three numeric values usually correspond to category/subcategory/index
    if #numericValues >= 3 then
        local categoryIndex = numericValues[#numericValues - 2]
        local subCategoryIndex = numericValues[#numericValues - 1]
        local achievementIndex = numericValues[#numericValues]
        if categoryIndex and subCategoryIndex and achievementIndex then
            return categoryIndex, subCategoryIndex, achievementIndex
        end
    end

    return nil
end

local function ResolveAchievementIdFromIndices(categoryIndex, subCategoryIndex, achievementIndex)
    if not categoryIndex or not achievementIndex then
        return nil
    end

    if type(GetAchievementId) ~= "function" then
        return nil
    end

    local ok, achievementId = pcall(GetAchievementId, categoryIndex, subCategoryIndex or 0, achievementIndex)
    if ok then
        return achievementId
    end

    return nil
end

local function ExtractAchievementIdFromInfoValues(infoValues)
    if not infoValues then
        return nil
    end

    for index = 1, #infoValues do
        local value = infoValues[index]
        if type(value) == "number" then
            if GetAchievementInfo then
                local ok, name = pcall(GetAchievementInfo, value)
                if ok and type(name) == "string" and name ~= "" then
                    return value
                end
            elseif IsAchievementComplete then
                local ok, _ = pcall(IsAchievementComplete, value)
                if ok then
                    return value
                end
            end
        end
    end

    return nil
end

local function CollectTrackedIds(self)
    local tracked = {}
    local infoCache = {}

    local numTracked = SafeCall(GetNumTrackedAchievements)
    if numTracked and numTracked > 0 then
        for trackedIndex = 1, numTracked do
            local achievementId
            local categoryIndex
            local subCategoryIndex
            local achievementIndex

            if GetTrackedAchievementId then
                achievementId = SafeCall(GetTrackedAchievementId, trackedIndex)
            end

            local infoValues
            if GetTrackedAchievementInfo then
                local ok, ... = pcall(GetTrackedAchievementInfo, trackedIndex)
                if ok then
                    infoValues = { ... }
                    infoCache[trackedIndex] = infoValues
                end
            end

            if (not achievementId or achievementId == 0) and infoValues then
                achievementId = ExtractAchievementIdFromInfoValues(infoValues)
            end

            if GetTrackedAchievementIndices then
                categoryIndex, subCategoryIndex, achievementIndex = SafeCallMulti(
                    GetTrackedAchievementIndices,
                    trackedIndex
                )
            elseif infoValues then
                categoryIndex, subCategoryIndex, achievementIndex = ExtractIndicesFromTrackedInfo(infoValues)
            end

            if (not achievementId or achievementId == 0) and categoryIndex and achievementIndex then
                achievementId = ResolveAchievementIdFromIndices(categoryIndex, subCategoryIndex, achievementIndex)
            end

            if achievementId then
                tracked[#tracked + 1] = {
                    trackedIndex = trackedIndex,
                    achievementId = achievementId,
                    categoryIndex = categoryIndex,
                    subCategoryIndex = subCategoryIndex,
                    achievementIndex = achievementIndex,
                    rawInfo = infoCache[trackedIndex],
                }
            else
                LogDebug(self, "Unable to resolve achievement id for tracked index", trackedIndex)
            end
        end
    end

    return tracked
end

local function BuildAchievementEntry(self, trackedEntry)
    local achievementId = trackedEntry.achievementId
    if not achievementId then
        return nil
    end

    local name
    local description
    local points
    local icon
    local isComplete
    local completedTimestamp

    if GetAchievementInfo then
        local ok, infoName, infoDescription, infoPoints, infoIcon, infoCompleted, infoDate, infoTimeStamp = pcall(
            GetAchievementInfo,
            achievementId
        )
        if ok then
            name = infoName
            description = infoDescription
            points = infoPoints
            icon = infoIcon
            isComplete = infoCompleted
            completedTimestamp = infoTimeStamp or infoDate
        end
    end

    local current
    local maximum
    local progressPercent

    if GetAchievementProgress then
        local ok, completed, total = pcall(GetAchievementProgress, achievementId)
        if ok then
            current = completed
            maximum = total
            if total and total > 0 and completed then
                local percent = (completed / total) * 100
                if zo_roundToNearest then
                    progressPercent = zo_roundToNearest(percent, 0.1)
                else
                    progressPercent = math.floor(percent * 10 + 0.5) / 10
                end
            end
        end
    end

    if not current and trackedEntry.rawInfo then
        -- attempt to interpret the raw tracked info for progress values
        for index = 1, #trackedEntry.rawInfo do
            if type(trackedEntry.rawInfo[index]) == "number" then
                if not current then
                    current = trackedEntry.rawInfo[index]
                elseif not maximum then
                    maximum = trackedEntry.rawInfo[index]
                    break
                end
            end
        end
    end

    local objectives = BuildObjectiveData(achievementId)

    local timestamp = completedTimestamp or SafeCall(GetAchievementTimestamp, achievementId)

    local categoryInfo = trackedEntry.categoryIndex and DetermineCategoryInfo(
        trackedEntry.categoryIndex,
        trackedEntry.subCategoryIndex
    )

    if (not categoryInfo or not categoryInfo.categoryName) and GetAchievementCategoryInfoFromAchievementId then
        local ok, categoryIndex, subCategoryIndex = pcall(GetAchievementCategoryInfoFromAchievementId, achievementId)
        if ok then
            categoryInfo = DetermineCategoryInfo(categoryIndex, subCategoryIndex)
        end
    end

    local entry = {
        id = achievementId,
        name = name or string.format("Achievement %d", achievementId),
        description = description,
        icon = icon,
        points = points,
        progress = {
            current = current,
            max = maximum,
            percent = progressPercent,
        },
        objectives = objectives,
        earnedTimestamp = timestamp,
        flags = {
            isComplete = isComplete == true,
            isTracked = true,
        },
        category = categoryInfo,
        trackedIndex = trackedEntry.trackedIndex,
    }

    return entry
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
    AppendSignaturePart(parts, entry.trackedIndex or 0)

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
    local tracked = CollectTrackedIds(self)
    local entries = {}
    local completeCount = 0

    for index = 1, #tracked do
        local entry = BuildAchievementEntry(self, tracked[index])
        if entry then
            entries[#entries + 1] = entry
            if entry.flags.isComplete then
                completeCount = completeCount + 1
            end
        end
    end

    table.sort(entries, function(left, right)
        if left.trackedIndex and right.trackedIndex and left.trackedIndex ~= right.trackedIndex then
            return left.trackedIndex < right.trackedIndex
        end

        if left.name ~= right.name then
            return (left.name or "") < (right.name or "")
        end

        return (left.id or 0) < (right.id or 0)
    end)

    local signatureParts = {}

    for index = 1, #entries do
        local entry = entries[index]
        entry.signature = BuildAchievementSignature(entry)
        signatureParts[index] = entry.signature
    end

    local snapshot = {
        achievements = entries,
        total = #entries,
        totalComplete = completeCount,
        totalIncomplete = #entries - completeCount,
        hasIncomplete = (#entries - completeCount) > 0,
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
