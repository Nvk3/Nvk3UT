local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local AchievementModel = {}
AchievementModel.__index = AchievementModel

local MODEL_NAME = addonName .. "AchievementModel"
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

local function FormatDisplayString(text)
    if text == nil then
        return nil
    end

    if type(text) ~= "string" then
        return text
    end

    if text == "" then
        return ""
    end

    if type(ZO_CachedStrFormat) == "function" then
        local ok, formatted = pcall(ZO_CachedStrFormat, "<<1>>", text)
        if ok and formatted ~= nil then
            return formatted
        end
    end

    if type(zo_strformat) == "function" then
        local ok, formatted = pcall(zo_strformat, "<<1>>", text)
        if ok and formatted ~= nil then
            return formatted
        end
    end

    return text
end

local function NormalizeAchievementId(value)
    if type(value) == "number" then
        return value
    end

    if type(value) == "string" then
        local numeric = tonumber(value)
        if numeric then
            return numeric
        end
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

        description = FormatDisplayString(description)

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

local function DetermineCategoryInfo(categoryIndex, subCategoryIndex, achievementIndex)
    if not categoryIndex then
        return nil
    end

    local categoryName
    if GetAchievementCategoryInfo then
        local infoName = SafeCallMulti(GetAchievementCategoryInfo, categoryIndex)
        if infoName ~= nil then
            categoryName = FormatDisplayString(infoName)
        end
    end

    local subCategoryName
    if subCategoryIndex and GetAchievementSubCategoryInfo then
        local infoName = SafeCallMulti(GetAchievementSubCategoryInfo, categoryIndex, subCategoryIndex)
        if infoName ~= nil then
            subCategoryName = FormatDisplayString(infoName)
        end
    end

    return {
        categoryIndex = categoryIndex,
        subCategoryIndex = subCategoryIndex,
        achievementIndex = achievementIndex,
        categoryName = categoryName,
        subCategoryName = subCategoryName,
    }
end

local function BuildFavoriteScopes()
    local scope = "account"
    local general = Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.General
    if general and type(general.favScope) == "string" and general.favScope ~= "" then
        scope = general.favScope
    end

    local ordered = {}
    local seen = {}

    local function addScope(value)
        if not value or seen[value] then
            return
        end
        seen[value] = true
        ordered[#ordered + 1] = value
    end

    addScope(scope)
    addScope("account")
    addScope("character")

    return ordered
end

local function CollectFavoriteIds(self)
    local Fav = Nvk3UT and Nvk3UT.FavoritesData
    if not (Fav and Fav.Iterate) then
        return {}
    end

    local scopes = BuildFavoriteScopes()
    local lookup = {}
    local ids = {}

    for index = 1, #scopes do
        local scope = scopes[index]
        local ok, iterator, state, key = pcall(Fav.Iterate, scope)
        if ok and type(iterator) == "function" then
            local currentKey = key
            while true do
                local rawId, flagged = iterator(state, currentKey)
                currentKey = rawId
                if rawId == nil then
                    break
                end

                if flagged then
                    local normalizedId = NormalizeAchievementId(rawId)
                    if normalizedId then
                        if not lookup[normalizedId] then
                            lookup[normalizedId] = true
                            ids[#ids + 1] = normalizedId
                        end
                    else
                        LogDebug(self, "Skipping invalid favorite id", tostring(rawId), tostring(scope))
                    end
                end
            end
        else
            LogDebug(self, "Unable to iterate favorites for scope", tostring(scope))
        end
    end

    return ids
end

local function BuildAchievementEntry(self, achievementId)
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

    name = FormatDisplayString(name)
    description = FormatDisplayString(description)

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

    local objectives = BuildObjectiveData(achievementId)

    local timestamp = completedTimestamp or SafeCall(GetAchievementTimestamp, achievementId)

    local categoryIndex
    local subCategoryIndex
    local achievementIndex

    if GetCategoryInfoFromAchievementId then
        categoryIndex, subCategoryIndex, achievementIndex = SafeCallMulti(GetCategoryInfoFromAchievementId, achievementId)
    end

    local categoryInfo = DetermineCategoryInfo(categoryIndex, subCategoryIndex, achievementIndex)

    if (not categoryInfo or not categoryInfo.categoryName) and GetAchievementCategoryInfoFromAchievementId then
        local ok, fallbackCategoryIndex, fallbackSubCategoryIndex = pcall(
            GetAchievementCategoryInfoFromAchievementId,
            achievementId
        )
        if ok then
            categoryInfo = DetermineCategoryInfo(
                fallbackCategoryIndex,
                fallbackSubCategoryIndex,
                achievementIndex
            )
        end
    end

    local entry = {
        id = achievementId,
        name = (name and name ~= "" and name) or string.format("Achievement %d", achievementId),
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
            isFavorite = true,
        },
        category = categoryInfo,
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
    local favoriteIds = CollectFavoriteIds(self)
    local entries = {}
    local completeCount = 0

    for index = 1, #favoriteIds do
        local achievementId = favoriteIds[index]
        local entry = BuildAchievementEntry(self, achievementId)
        if entry then
            entries[#entries + 1] = entry
            if entry.flags.isComplete then
                completeCount = completeCount + 1
            end

            local category = entry.category or {}
            LogDebug(
                self,
                "Favorite entry",
                achievementId,
                category.categoryIndex,
                category.subCategoryIndex,
                category.achievementIndex
            )
        end
    end

    table.sort(entries, function(left, right)
        local leftCategory = left.category or {}
        local rightCategory = right.category or {}

        local leftCategoryIndex = leftCategory.categoryIndex
        local rightCategoryIndex = rightCategory.categoryIndex
        if leftCategoryIndex ~= rightCategoryIndex then
            if leftCategoryIndex == nil then
                return false
            elseif rightCategoryIndex == nil then
                return true
            end
            return leftCategoryIndex < rightCategoryIndex
        end

        local leftSubCategoryIndex = leftCategory.subCategoryIndex
        local rightSubCategoryIndex = rightCategory.subCategoryIndex
        if leftSubCategoryIndex ~= rightSubCategoryIndex then
            if leftSubCategoryIndex == nil then
                return false
            elseif rightSubCategoryIndex == nil then
                return true
            end
            return leftSubCategoryIndex < rightSubCategoryIndex
        end

        local leftAchievementIndex = leftCategory.achievementIndex
        local rightAchievementIndex = rightCategory.achievementIndex
        if leftAchievementIndex ~= rightAchievementIndex then
            if leftAchievementIndex == nil then
                return false
            elseif rightAchievementIndex == nil then
                return true
            end
            return leftAchievementIndex < rightAchievementIndex
        end

        if left.name ~= right.name then
            return (left.name or "") < (right.name or "")
        end

        return (left.id or 0) < (right.id or 0)
    end)

    local signatureParts = {}

    for index = 1, #entries do
        local entry = entries[index]
        entry.sortOrder = index
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
        return false
    end

    local snapshot = BuildSnapshot(self)
    if not SnapshotsDiffer(self.currentSnapshot, snapshot) then
        return false
    end

    snapshot.revision = (self.currentSnapshot and self.currentSnapshot.revision or 0) + 1
    self.currentSnapshot = snapshot
    NotifySubscribers(self)

    return true
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
        return false
    end

    if self.pendingRebuild then
        EVENT_MANAGER:UnregisterForUpdate(REBUILD_IDENTIFIER)
        self.pendingRebuild = false
    end

    local updated = PerformRebuild(self)
    return updated == true
end

local function OnAchievementChanged(...)
    local self = AchievementModel
    if not self.isInitialized then
        return
    end

    ScheduleRebuild(self)
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

    AchievementModel.subscribers = {}
    AchievementModel.isInitialized = true

    ForceRebuild(AchievementModel)
    NotifySubscribers(AchievementModel)
end

function AchievementModel.Shutdown()
    if not AchievementModel.isInitialized then
        return
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

function AchievementModel.OnAchievementChanged(eventCode, ...)
    OnAchievementChanged(eventCode, ...)
end

function AchievementModel.Unsubscribe(callback)
    if AchievementModel.subscribers then
        AchievementModel.subscribers[callback] = nil
    end
end

function AchievementModel.RequestImmediateRebuild(reason)
    if type(ForceRebuild) ~= "function" then
        return false
    end

    if not AchievementModel.isInitialized then
        return false
    end

    if AchievementModel.debugEnabled then
        LogDebug(AchievementModel, string.format("[ImmediateRebuild] reason=%s", tostring(reason)))
    end

    local updated = ForceRebuild(AchievementModel)

    if updated ~= true then
        ScheduleRebuild(AchievementModel)
    end

    return updated == true
end

Nvk3UT.AchievementModel = AchievementModel

return AchievementModel
