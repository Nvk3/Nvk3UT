-- Model/Quest/Nvk3UT_QuestSelection.lua
-- Thin wrapper around QuestState for active quest selection tracking.

Nvk3UT = Nvk3UT or {}
Nvk3UT.QuestSelection = Nvk3UT.QuestSelection or {}

local QuestSelection = Nvk3UT.QuestSelection

local function GetQuestStateModule()
    return Nvk3UT and Nvk3UT.QuestState
end

local function ensureRuntimeFallback()
    QuestSelection._runtime = QuestSelection._runtime or {
        questKey = nil,
        questId = nil,
        source = "init",
        ts = 0,
        priority = 0,
    }
    return QuestSelection._runtime
end

local function normalizeQuestKey(value)
    local questState = GetQuestStateModule()
    if questState and questState.NormalizeQuestKey then
        return questState.NormalizeQuestKey(value)
    end

    if value == nil then
        return nil
    end

    local numeric = tonumber(value)
    if numeric and numeric > 0 then
        return math.floor(numeric)
    end

    return value
end

function QuestSelection.Bind(root, questTrackerOverride)
    local questState = GetQuestStateModule()
    if questState and questState.Bind and Nvk3UT and Nvk3UT.sv then
        questState.Bind(Nvk3UT.sv)
    end

    local runtime = ensureRuntimeFallback()
    QuestSelection._saved = runtime
    return runtime
end

function QuestSelection.GetSaved()
    local questState = GetQuestStateModule()
    if questState and questState.EnsureActiveSavedState then
        return questState.EnsureActiveSavedState()
    end

    return ensureRuntimeFallback()
end

function QuestSelection.EnsureActiveSavedState()
    local questState = GetQuestStateModule()
    if questState and questState.EnsureActiveSavedState then
        return questState.EnsureActiveSavedState()
    end

    local runtime = ensureRuntimeFallback()
    runtime.ts = runtime.ts or 0
    runtime.source = runtime.source or "init"
    return runtime
end

function QuestSelection.SetActive(questKey, source, options)
    local questState = GetQuestStateModule()
    if questState and questState.SetSelectedQuestId then
        return questState.SetSelectedQuestId(questKey, source, options)
    end

    local runtime = ensureRuntimeFallback()
    local normalized = normalizeQuestKey(questKey)
    local previous = runtime.questId
    runtime.questKey = normalized
    runtime.questId = normalized
    runtime.source = source or "auto"
    runtime.ts = GetFrameTimeSeconds and GetFrameTimeSeconds() or runtime.ts or 0
    runtime.priority = 0
    return previous ~= normalized, normalized, runtime.priority, runtime.source
end

function QuestSelection.GetActive()
    return QuestSelection.EnsureActiveSavedState()
end

function QuestSelection.GetActiveQuestKey()
    local active = QuestSelection.EnsureActiveSavedState()
    if not active then
        return nil
    end

    return active.questId or active.questKey or nil
end

function QuestSelection.IsActive(questKey)
    local normalized = normalizeQuestKey(questKey)
    local questState = GetQuestStateModule()
    if questState and questState.GetSelectedQuestId then
        local selected = questState.GetSelectedQuestId()
        if normalized == nil then
            return selected == nil
        end
        return selected == normalized
    end

    local runtime = ensureRuntimeFallback()
    if normalized == nil then
        return runtime.questKey == nil
    end

    return runtime.questKey == normalized
end

function QuestSelection.NormalizeQuestKey(value)
    return normalizeQuestKey(value)
end

function QuestSelection.SetActiveByQuestId(questId, source, options)
    return QuestSelection.SetActive(questId, source, options)
end

return QuestSelection
