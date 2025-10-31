local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local QuestSelection = {}
QuestSelection.__index = QuestSelection

local MODULE_NAME = addonName .. "QuestSelection"

QuestSelection.SOURCES = {
    CLICK = "click",
    JOURNAL = "journal",
    GAME = "game",
    API = "api",
}

local storage = {
    initialized = false,
    svRoot = nil,
    data = nil,
}

local function DebugLog(fmt, ...)
    if not (Nvk3UT and type(Nvk3UT.Debug) == "function") then
        return
    end

    Nvk3UT.Debug(string.format("[%s] %s", MODULE_NAME, tostring(fmt)), ...)
end

local function AcquireTimeMilliseconds()
    if type(GetFrameTimeMilliseconds) == "function" then
        local ok, value = pcall(GetFrameTimeMilliseconds)
        if ok and type(value) == "number" then
            return value
        end
    end

    if type(GetGameTimeMilliseconds) == "function" then
        local ok, value = pcall(GetGameTimeMilliseconds)
        if ok and type(value) == "number" then
            return value
        end
    end

    if type(GetSecondsSinceMidnight) == "function" then
        local ok, value = pcall(GetSecondsSinceMidnight)
        if ok and type(value) == "number" then
            return math.floor(value * 1000 + 0.5)
        end
    end

    return math.floor((os.time() or 0) * 1000)
end

local function NormalizeTimestampMs(timestampMs)
    local numeric = tonumber(timestampMs)
    if not numeric then
        return AcquireTimeMilliseconds()
    end

    if numeric < 0 then
        numeric = 0
    end

    return math.floor(numeric + 0.5)
end

local function EnsureTable(parent, key)
    if type(parent) ~= "table" then
        return {}
    end

    local child = parent[key]
    if type(child) ~= "table" then
        child = {}
        parent[key] = child
    end

    return child
end

local function NormalizeQuestId(questId)
    if questId == nil then
        return nil
    end

    local valueType = type(questId)
    if valueType == "string" then
        if questId ~= "" then
            return questId
        end
        return nil
    elseif valueType == "number" then
        if questId ~= questId or questId == math.huge or questId == -math.huge then
            return nil
        end
        return tostring(math.floor(questId + 0.5))
    end

    return tostring(questId)
end

local function NormalizeLegacyTimestampSeconds(seconds)
    local numeric = tonumber(seconds)
    if not numeric then
        return 0
    end

    if numeric < 0 then
        numeric = 0
    end

    return math.floor(numeric * 1000 + 0.5)
end

local function MigrateLegacySelection(svRoot, data)
    local migrated = {
        selected = 0,
        focused = 0,
    }

    if type(svRoot) ~= "table" then
        return migrated
    end

    local lastUpdate = data.lastUpdate
    local function applySelection(candidateId, source, timestampMs)
        local normalized = NormalizeQuestId(candidateId)
        if not normalized or data.selectedQuestId ~= nil then
            return
        end

        data.selectedQuestId = normalized
        migrated.selected = migrated.selected + 1

        local tsMs = timestampMs or 0
        if tsMs > 0 then
            if type(lastUpdate) ~= "table" then
                lastUpdate = {}
                data.lastUpdate = lastUpdate
            end
            lastUpdate.selectedId = normalized
            lastUpdate.focusedId = lastUpdate.focusedId or data.focusedQuestId
            lastUpdate.source = source or "legacy"
            lastUpdate.timestampMs = math.max(tonumber(lastUpdate.timestampMs) or 0, tsMs)
        end
    end

    local function applyFocus(candidateId, source, timestampMs)
        local normalized = NormalizeQuestId(candidateId)
        if not normalized or data.focusedQuestId ~= nil then
            return
        end

        data.focusedQuestId = normalized
        migrated.focused = migrated.focused + 1

        if timestampMs and timestampMs > 0 then
            if type(lastUpdate) ~= "table" then
                lastUpdate = {}
                data.lastUpdate = lastUpdate
            end
            lastUpdate.focusedId = normalized
            lastUpdate.selectedId = lastUpdate.selectedId or data.selectedQuestId
            lastUpdate.source = source or "legacy"
            lastUpdate.timestampMs = math.max(tonumber(lastUpdate.timestampMs) or 0, timestampMs)
        end
    end

    if data.selectedQuestId == nil then
        if svRoot.selectedQuestId ~= nil then
            applySelection(svRoot.selectedQuestId, "legacy:root", NormalizeLegacyTimestampSeconds(0))
        end

        local legacyState = svRoot.QuestState
        if type(legacyState) == "table" then
            if legacyState.selectedQuestId ~= nil then
                applySelection(legacyState.selectedQuestId, "legacy:QuestState", NormalizeLegacyTimestampSeconds(legacyState.selection and legacyState.selection.ts or 0))
            elseif type(legacyState.selection) == "table" and legacyState.selection.questId ~= nil then
                applySelection(legacyState.selection.questId, legacyState.selection.source or "legacy:QuestState", NormalizeLegacyTimestampSeconds(legacyState.selection.ts or 0))
            end
        end

        local legacyTracker = svRoot.QuestTracker
        if type(legacyTracker) == "table" then
            if type(legacyTracker.active) == "table" and legacyTracker.active.questKey ~= nil then
                applySelection(legacyTracker.active.questKey, legacyTracker.active.source or "legacy:QuestTracker", NormalizeLegacyTimestampSeconds(legacyTracker.active.ts or 0))
            elseif legacyTracker.selectedQuestKey ~= nil then
                applySelection(legacyTracker.selectedQuestKey, "legacy:QuestTracker", NormalizeLegacyTimestampSeconds(0))
            end
        end
    end

    if data.focusedQuestId == nil then
        local legacyState = svRoot.QuestState
        if type(legacyState) == "table" then
            if legacyState.focusedQuestId ~= nil then
                applyFocus(legacyState.focusedQuestId, "legacy:QuestState", NormalizeLegacyTimestampSeconds(0))
            elseif type(legacyState.focusState) == "table" and legacyState.focusState.questId ~= nil then
                applyFocus(legacyState.focusState.questId, legacyState.focusState.source or "legacy:QuestState", NormalizeLegacyTimestampSeconds(legacyState.focusState.ts or 0))
            end
        end

        local legacyTracker = svRoot.QuestTracker
        if type(legacyTracker) == "table" and legacyTracker.focusedQuestId ~= nil then
            applyFocus(legacyTracker.focusedQuestId, "legacy:QuestTracker", NormalizeLegacyTimestampSeconds(0))
        end
    end

    return migrated
end

function QuestSelection:Init(svRoot)
    if type(svRoot) ~= "table" then
        return nil
    end

    local data = svRoot.QuestSelection
    if type(data) ~= "table" then
        data = {}
        svRoot.QuestSelection = data
    end

    data.selectedQuestId = NormalizeQuestId(data.selectedQuestId)
    data.focusedQuestId = NormalizeQuestId(data.focusedQuestId)

    local lastUpdate = EnsureTable(data, "lastUpdate")
    lastUpdate.selectedId = NormalizeQuestId(lastUpdate.selectedId)
    lastUpdate.focusedId = NormalizeQuestId(lastUpdate.focusedId)
    lastUpdate.source = lastUpdate.source or ""
    if lastUpdate.timestampMs ~= nil then
        lastUpdate.timestampMs = NormalizeTimestampMs(lastUpdate.timestampMs)
    else
        lastUpdate.timestampMs = 0
    end

    local migrated = MigrateLegacySelection(svRoot, data)

    storage.svRoot = svRoot
    storage.data = data
    storage.initialized = true

    if migrated.selected > 0 or migrated.focused > 0 then
        DebugLog("migration selected=%d focused=%d", migrated.selected, migrated.focused)
    else
        DebugLog("initialized")
    end

    return data
end

local function EnsureInitialized()
    if storage.initialized and type(storage.data) == "table" then
        return true
    end

    local addon = Nvk3UT
    if type(addon) ~= "table" then
        return false
    end

    local root = addon.sv or addon.SV
    if type(root) ~= "table" then
        return false
    end

    QuestSelection:Init(root)
    return storage.initialized and type(storage.data) == "table"
end

local function GetData()
    if not EnsureInitialized() then
        return nil
    end

    return storage.data
end

local function UpdateLastUpdate(data, source, timestampMs)
    local lastUpdate = EnsureTable(data, "lastUpdate")
    lastUpdate.selectedId = data.selectedQuestId
    lastUpdate.focusedId = data.focusedQuestId
    lastUpdate.source = source or ""
    lastUpdate.timestampMs = timestampMs
end

function QuestSelection.GetSelectedQuestId()
    local data = GetData()
    if not data then
        return nil
    end

    return data.selectedQuestId
end

function QuestSelection.GetFocusedQuestId()
    local data = GetData()
    if not data then
        return nil
    end

    return data.focusedQuestId
end

function QuestSelection.GetLastUpdate()
    local data = GetData()
    if not data then
        return {
            selectedId = nil,
            focusedId = nil,
            source = "",
            timestampMs = 0,
        }
    end

    local lastUpdate = EnsureTable(data, "lastUpdate")
    return {
        selectedId = lastUpdate.selectedId or data.selectedQuestId,
        focusedId = lastUpdate.focusedId or data.focusedQuestId,
        source = lastUpdate.source or "",
        timestampMs = tonumber(lastUpdate.timestampMs) or 0,
    }
end

local function SuppressReason(kind, normalized, timestampMs, lastTimestamp, reason)
    DebugLog(
        "suppress %s=%s timestamp=%d last=%d reason=%s",
        kind,
        tostring(normalized),
        timestampMs,
        lastTimestamp,
        tostring(reason)
    )
end

local function ApplySelection(kind, questId, source, timestampMs)
    local data = GetData()
    if not data then
        return false
    end

    local normalized = NormalizeQuestId(questId)
    local timestamp = NormalizeTimestampMs(timestampMs)
    local lastUpdate = EnsureTable(data, "lastUpdate")
    local lastTimestamp = tonumber(lastUpdate.timestampMs) or 0

    if timestamp < lastTimestamp then
        SuppressReason(kind, normalized, timestamp, lastTimestamp, "older")
        return false
    end

    local current = kind == "selected" and data.selectedQuestId or data.focusedQuestId
    if current == normalized then
        SuppressReason(kind, normalized, timestamp, lastTimestamp, "unchanged")
        return false
    end

    if kind == "selected" then
        data.selectedQuestId = normalized
    else
        data.focusedQuestId = normalized
    end

    UpdateLastUpdate(data, source, timestamp)

    DebugLog(
        "%s quest %s -> %s source=%s timestamp=%d",
        kind,
        tostring(current),
        tostring(normalized),
        tostring(source),
        timestamp
    )

    return true
end

function QuestSelection.SetSelectedQuestId(questId, source, timestampMs)
    return ApplySelection("selected", questId, source or QuestSelection.SOURCES.API, timestampMs)
end

function QuestSelection.SetFocusedQuestId(questId, source, timestampMs)
    return ApplySelection("focused", questId, source or QuestSelection.SOURCES.API, timestampMs)
end

function QuestSelection.ClearSelection()
    local data = GetData()
    if not data then
        return false
    end

    local changed = false
    if data.selectedQuestId ~= nil then
        data.selectedQuestId = nil
        changed = true
    end

    if data.focusedQuestId ~= nil then
        data.focusedQuestId = nil
        changed = true
    end

    if changed then
        UpdateLastUpdate(data, "clear", NormalizeTimestampMs(nil))
        DebugLog("clear selection")
    end

    return changed
end

function QuestSelection.IsSelected(questId)
    local data = GetData()
    if not data then
        return false
    end

    local normalized = NormalizeQuestId(questId)
    return normalized ~= nil and normalized == data.selectedQuestId
end

function QuestSelection.IsFocused(questId)
    local data = GetData()
    if not data then
        return false
    end

    local normalized = NormalizeQuestId(questId)
    return normalized ~= nil and normalized == data.focusedQuestId
end

local function ResolveTimestamp(timestampMs)
    if timestampMs ~= nil then
        return NormalizeTimestampMs(timestampMs)
    end

    return AcquireTimeMilliseconds()
end

function QuestSelection.OnClickSelect(questId, timestampMs)
    local timestamp = ResolveTimestamp(timestampMs)
    local changed = QuestSelection.SetSelectedQuestId(questId, QuestSelection.SOURCES.CLICK, timestamp)
    local focusChanged = QuestSelection.SetFocusedQuestId(questId, QuestSelection.SOURCES.CLICK, timestamp)
    return changed or focusChanged
end

function QuestSelection.OnJournalSelect(questId, timestampMs)
    local timestamp = ResolveTimestamp(timestampMs)
    local changed = QuestSelection.SetSelectedQuestId(questId, QuestSelection.SOURCES.JOURNAL, timestamp)
    local focusChanged = QuestSelection.SetFocusedQuestId(questId, QuestSelection.SOURCES.JOURNAL, timestamp)
    return changed or focusChanged
end

function QuestSelection.OnGameAutoTrack(questId, timestampMs)
    local timestamp = ResolveTimestamp(timestampMs)
    return QuestSelection.SetSelectedQuestId(questId, QuestSelection.SOURCES.GAME, timestamp)
end

function QuestSelection.OnApiSelect(questId, timestampMs)
    local timestamp = ResolveTimestamp(timestampMs)
    local changed = QuestSelection.SetSelectedQuestId(questId, QuestSelection.SOURCES.API, timestamp)
    return changed
end

function QuestSelection.OnDeselection(reason, timestampMs)
    local timestamp = ResolveTimestamp(timestampMs)
    local source = reason or "deselect"
    local clearedSelected = QuestSelection.SetSelectedQuestId(nil, source, timestamp)
    local clearedFocused = QuestSelection.SetFocusedQuestId(nil, source, timestamp)
    return clearedSelected or clearedFocused
end

Nvk3UT.QuestSelection = QuestSelection

return QuestSelection
