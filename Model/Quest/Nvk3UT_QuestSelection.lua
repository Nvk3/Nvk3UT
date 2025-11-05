-- Model/Quest/Nvk3UT_QuestSelection.lua
-- Centralizes quest tracker active selection state while preserving legacy behavior.

Nvk3UT = Nvk3UT or {}
Nvk3UT.QuestSelection = Nvk3UT.QuestSelection or {}

local QuestSelection = Nvk3UT.QuestSelection
local saved = QuestSelection._saved

local PRIORITY = {
    manual = 5,
    ["click-select"] = 4,
    ["external-select"] = 4,
    auto = 2,
    init = 1,
}

local function GetQuestStateModule()
    return Nvk3UT and Nvk3UT.QuestState
end

local function GetCurrentTimeSeconds()
    local questState = GetQuestStateModule()
    if questState and questState.GetCurrentTimeSeconds then
        local ok, value = pcall(questState.GetCurrentTimeSeconds)
        if ok then
            return value
        end
    end

    if GetFrameTimeSeconds then
        local ok, now = pcall(GetFrameTimeSeconds)
        if ok and type(now) == "number" then
            return now
        end
    end

    if GetGameTimeMilliseconds then
        local ok, ms = pcall(GetGameTimeMilliseconds)
        if ok and type(ms) == "number" then
            return ms / 1000
        end
    end

    if os and os.clock then
        return os.clock()
    end

    return 0
end

local function NormalizeQuestKey(journalIndex)
    local questState = GetQuestStateModule()
    if questState and questState.NormalizeQuestKey then
        return questState.NormalizeQuestKey(journalIndex)
    end

    if journalIndex == nil then
        return nil
    end

    if type(journalIndex) == "string" then
        local numeric = tonumber(journalIndex)
        if numeric and numeric > 0 then
            return tostring(numeric)
        end
        return journalIndex
    end

    if type(journalIndex) == "number" then
        if journalIndex > 0 then
            return tostring(journalIndex)
        end
        return nil
    end

    return tostring(journalIndex)
end

local function EnsureActiveSavedStateInternal(target)
    if type(target) ~= "table" then
        return nil
    end

    local active = target.active
    if type(active) ~= "table" then
        active = {
            questKey = nil,
            source = "init",
            ts = 0,
        }
        target.active = active
    end

    if active.questKey ~= nil then
        active.questKey = NormalizeQuestKey(active.questKey)
    end

    if type(active.source) ~= "string" or active.source == "" then
        active.source = "init"
    end

    active.ts = tonumber(active.ts) or 0

    return active
end

local function ResolveWrite(source, options, previous)
    options = options or {}

    local priorityOverride = options.priorityOverride
    local priority = priorityOverride or PRIORITY[source] or 0
    local previousPriority = previous and (PRIORITY[previous.source] or 0) or 0
    local overrideTimestamp = tonumber(options.timestamp)
    local now = overrideTimestamp or GetCurrentTimeSeconds()
    local previousTimestamp = (previous and previous.ts) or 0
    local forceWrite = options.force == true
    local allowTimestampRegression = options.allowTimestampRegression == true

    if previous and not forceWrite then
        if previousPriority > priority then
            return false, priority, now
        end

        if previousPriority == priority and not allowTimestampRegression and now < previousTimestamp then
            return false, priority, now
        end
    end

    return true, priority, now
end

local function ApplyActiveWrite(questKey, source, options)
    if not saved then
        return false
    end

    source = source or "auto"
    options = options or {}

    local normalized = questKey and NormalizeQuestKey(questKey) or nil
    local previous = EnsureActiveSavedStateInternal(saved)
    local shouldWrite, priority, timestamp = ResolveWrite(source, options, previous)
    if not shouldWrite then
        return false, normalized, priority, source
    end

    saved.active = {
        questKey = normalized,
        source = source,
        ts = timestamp,
    }

    return true, normalized, priority, source
end

local function AssignSaved(container)
    if type(container) ~= "table" then
        saved = nil
        QuestSelection._saved = nil
        return nil
    end

    saved = container
    QuestSelection._saved = saved
    return saved
end

function QuestSelection.Bind(root, questTrackerOverride)
    local container = questTrackerOverride

    if type(container) ~= "table" then
        if type(root) ~= "table" then
            return AssignSaved(nil)
        end

        container = root.questState
        if type(container) ~= "table" then
            container = {}
            root.questState = container
        end

        if type(root.QuestTracker) == "table" and next(container) == nil then
            for key, value in pairs(root.QuestTracker) do
                container[key] = value
            end
        end
    end

    EnsureActiveSavedStateInternal(container)

    return AssignSaved(container)
end

function QuestSelection.GetSaved()
    return saved
end

function QuestSelection.EnsureActiveSavedState(target)
    if target then
        return EnsureActiveSavedStateInternal(target)
    end

    return EnsureActiveSavedStateInternal(saved)
end

function QuestSelection.SetActive(questKey, source, options)
    return ApplyActiveWrite(questKey, source, options)
end

function QuestSelection.GetActive()
    return EnsureActiveSavedStateInternal(saved)
end

function QuestSelection.GetActiveQuestKey()
    local active = EnsureActiveSavedStateInternal(saved)
    return active and active.questKey or nil
end

function QuestSelection.IsActive(questKey)
    if not saved then
        return false
    end

    local normalized = NormalizeQuestKey(questKey)
    local active = EnsureActiveSavedStateInternal(saved)

    if normalized == nil then
        return active and active.questKey == nil
    end

    return active and active.questKey == normalized
end

function QuestSelection.NormalizeQuestKey(journalIndex)
    return NormalizeQuestKey(journalIndex)
end

return QuestSelection
