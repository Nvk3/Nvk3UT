local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local QuestState = {}
QuestState.__index = QuestState

local MODULE_NAME = addonName .. "QuestState"

local PRIORITY = {
    manual = 5,
    ["click-select"] = 4,
    ["external-select"] = 4,
    auto = 2,
    init = 1,
}

local function DebugLog(fmt, ...)
    if not (Nvk3UT and type(Nvk3UT.Debug) == "function") then
        return
    end

    Nvk3UT.Debug(string.format("[%s] %s", MODULE_NAME, tostring(fmt)), ...)
end

local function AcquireTimeSeconds()
    if type(GetCurrentTimeSeconds) == "function" then
        local ok, value = pcall(GetCurrentTimeSeconds)
        if ok and type(value) == "number" then
            return value
        end
    end

    if type(GetSecondsSinceMidnight) == "function" then
        local ok, value = pcall(GetSecondsSinceMidnight)
        if ok and type(value) == "number" then
            return value
        end
    end

    return os.time() or 0
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

    local seconds = AcquireTimeSeconds()
    return math.floor((seconds or 0) * 1000 + 0.5)
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

local function NormalizeKey(key)
    if key == nil then
        return nil
    end

    if type(key) == "string" then
        if key ~= "" then
            return key
        end
        return nil
    end

    if type(key) == "number" then
        if key == key and key ~= math.huge and key ~= -math.huge then
            return tostring(math.floor(key + 0.5))
        end
        return nil
    end

    return tostring(key)
end

local function CopyEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    return {
        expanded = entry.expanded and true or false,
        source = entry.source or "auto",
        ts = tonumber(entry.ts) or 0,
    }
end

local storage = {
    svRoot = nil,
    data = nil,
    initialized = false,
}

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

    QuestState:Init(root)
    return storage.initialized and type(storage.data) == "table"
end

local function ResolvePriority(source, override)
    if override ~= nil then
        return override
    end

    if type(source) ~= "string" or source == "" then
        return PRIORITY.auto
    end

    return PRIORITY[source] or PRIORITY.auto
end

local function ResolveTimestamp(options)
    if type(options) == "table" and options.timestamp ~= nil then
        local numeric = tonumber(options.timestamp)
        if numeric then
            return numeric
        end
    end

    return AcquireTimeSeconds()
end

local function ShouldWrite(prev, priority, timestamp, options)
    if type(prev) ~= "table" then
        return true
    end

    local forceWrite = type(options) == "table" and options.force == true
    if forceWrite then
        return true
    end

    local allowRegression = type(options) == "table" and options.allowTimestampRegression == true
    local prevPriority = ResolvePriority(prev.source, prev.priorityOverride)
    local prevTs = tonumber(prev.ts) or 0

    if prevPriority > priority then
        return false
    end

    if prevPriority == priority and not allowRegression and timestamp < prevTs then
        return false
    end

    return true
end

local function ApplyWrite(targetTable, key, expanded, source, timestamp, priority)
    if type(targetTable) ~= "table" or not key then
        return nil
    end

    local entry = targetTable[key]
    if type(entry) ~= "table" then
        entry = {}
        targetTable[key] = entry
    end

    entry.expanded = expanded and true or false
    entry.source = source or "auto"
    entry.ts = timestamp or AcquireTimeSeconds()
    entry.priorityOverride = priority

    return entry
end

local function ApplySelection(data, questId, source, timestamp, priority)
    if type(data) ~= "table" then
        return nil
    end

    local entry = data.selection or {}
    data.selection = entry

    entry.questId = questId
    entry.source = source or "auto"
    entry.ts = timestamp or AcquireTimeSeconds()
    entry.priorityOverride = priority

    data.selectedQuestId = questId

    return entry
end

local function MigrateLegacyState(root, data)
    local migrated = {
        categories = 0,
        quests = 0,
        selected = 0,
        focused = 0,
        categoryToggles = 0,
        questToggles = 0,
    }

    if type(root) ~= "table" then
        return migrated
    end

    local legacyTracker = root.QuestTracker
    if type(legacyTracker) ~= "table" then
        return migrated
    end

    local function migrateExpansionTable(sourceTable, targetStates, targetExpanded, targetTimestamps, counterKey)
        if type(sourceTable) ~= "table" then
            return
        end

        for key, value in pairs(sourceTable) do
            local normalized = NormalizeKey(key)
            if normalized then
                local expanded
                local stateSource
                local timestamp

                if type(value) == "table" then
                    expanded = value.expanded and true or false
                    stateSource = value.source or "auto"
                    timestamp = tonumber(value.ts) or 0
                else
                    expanded = value and true or false
                    stateSource = "init"
                    timestamp = 0
                end

                if targetExpanded[normalized] == nil then
                    targetExpanded[normalized] = expanded
                end

                local entry = targetStates[normalized]
                if type(entry) ~= "table" then
                    entry = {}
                    targetStates[normalized] = entry
                end

                entry.expanded = expanded
                entry.source = stateSource
                entry.ts = timestamp

                if timestamp and timestamp > 0 then
                    targetTimestamps[normalized] = math.max(
                        targetTimestamps[normalized] or 0,
                        math.floor(timestamp * 1000 + 0.5)
                    )
                end

                migrated[counterKey] = migrated[counterKey] + 1
            end
        end
    end

    migrateExpansionTable(legacyTracker.cat, data.categoryStates, data.expandedCategories, data.toggleTimestamps.categories, "categories")
    migrateExpansionTable(legacyTracker.quest, data.questStates, data.expandedQuests, data.toggleTimestamps.quests, "quests")
    migrateExpansionTable(legacyTracker.catExpanded, data.categoryStates, data.expandedCategories, data.toggleTimestamps.categories, "categories")
    migrateExpansionTable(legacyTracker.questExpanded, data.questStates, data.expandedQuests, data.toggleTimestamps.quests, "quests")

    if type(legacyTracker.active) == "table" then
        local questId = NormalizeKey(legacyTracker.active.questKey)
        if questId ~= nil and data.selectedQuestId == nil then
            data.selectedQuestId = questId
            local timestamp = tonumber(legacyTracker.active.ts) or AcquireTimeSeconds()
            ApplySelection(data, questId, legacyTracker.active.source or "init", timestamp, ResolvePriority(legacyTracker.active.source))
            migrated.selected = migrated.selected + 1
        end
    elseif type(legacyTracker.selectedQuestKey) ~= "nil" and data.selectedQuestId == nil then
        local questId = NormalizeKey(legacyTracker.selectedQuestKey)
        if questId ~= nil then
            data.selectedQuestId = questId
            ApplySelection(data, questId, "init", AcquireTimeSeconds(), PRIORITY.init)
            migrated.selected = migrated.selected + 1
        end
    end

    if legacyTracker.focusedQuestId ~= nil and data.focusedQuestId == nil then
        local questId = NormalizeKey(legacyTracker.focusedQuestId)
        if questId ~= nil then
            data.focusedQuestId = questId
            migrated.focused = migrated.focused + 1
        end
    end

    return migrated
end

function QuestState:Init(svRoot)
    if type(svRoot) ~= "table" then
        return nil
    end

    local data = svRoot.QuestState
    if type(data) ~= "table" then
        data = {}
        svRoot.QuestState = data
    end

    data.expandedCategories = EnsureTable(data, "expandedCategories")
    data.expandedQuests = EnsureTable(data, "expandedQuests")
    data.categoryStates = EnsureTable(data, "categoryStates")
    data.questStates = EnsureTable(data, "questStates")
    data.toggleTimestamps = EnsureTable(data, "toggleTimestamps")
    data.toggleTimestamps.categories = EnsureTable(data.toggleTimestamps, "categories")
    data.toggleTimestamps.quests = EnsureTable(data.toggleTimestamps, "quests")
    data.selection = EnsureTable(data, "selection")
    data.focusState = EnsureTable(data, "focusState")

    if data.selectedQuestId == nil and data.selection.questId ~= nil then
        data.selectedQuestId = data.selection.questId
    end

    if data.focusedQuestId == nil and data.focusState.questId ~= nil then
        data.focusedQuestId = data.focusState.questId
    end

    local migrated = MigrateLegacyState(svRoot, data)

    storage.svRoot = svRoot
    storage.data = data
    storage.initialized = true

    if migrated.categories > 0 or migrated.quests > 0 or migrated.selected > 0 or migrated.focused > 0 then
        DebugLog("migration categories=%d quests=%d selected=%d focused=%d", migrated.categories, migrated.quests, migrated.selected, migrated.focused)
    else
        DebugLog("initialized without migration")
    end

    return data
end

local function GetData()
    if not EnsureInitialized() then
        return nil
    end

    return storage.data
end

function QuestState.IsCategoryExpanded(categoryId)
    local data = GetData()
    if not data then
        return false, false
    end

    local key = NormalizeKey(categoryId)
    if not key then
        return false, false
    end

    local entry = data.categoryStates[key]
    if type(entry) == "table" and entry.expanded ~= nil then
        return entry.expanded and true or false, true
    end

    local expanded = data.expandedCategories[key]
    if expanded ~= nil then
        return expanded and true or false, true
    end

    return false, false
end

local function SetCategoryState(categoryId, expanded, options)
    local data = GetData()
    if not data then
        return false
    end

    local key = NormalizeKey(categoryId)
    if not key then
        return false
    end

    expanded = expanded and true or false
    local source = (type(options) == "table" and options.source) or "auto"
    local priority = ResolvePriority(source, type(options) == "table" and options.priorityOverride)
    local timestamp = ResolveTimestamp(options)
    local prev = data.categoryStates[key]

    if not ShouldWrite(prev, priority, timestamp, options) then
        return false
    end

    local entry = ApplyWrite(data.categoryStates, key, expanded, source, timestamp, priority)
    data.expandedCategories[key] = entry.expanded

    DebugLog("category %s expanded=%s source=%s", tostring(key), tostring(entry.expanded), tostring(source))

    return true
end

function QuestState.SetCategoryExpanded(categoryId, expanded, options)
    local changed = SetCategoryState(categoryId, expanded, options)
    if changed then
        QuestState.MarkCategoryToggled(categoryId, options and options.toggleTimestamp)
    end
    return changed
end

function QuestState.ToggleCategoryExpanded(categoryId, options)
    local current = QuestState.IsCategoryExpanded(categoryId)
    return QuestState.SetCategoryExpanded(categoryId, not current, options)
end

function QuestState.GetCategoryState(categoryId)
    local data = GetData()
    if not data then
        return nil
    end

    local key = NormalizeKey(categoryId)
    if not key then
        return nil
    end

    local entry = data.categoryStates[key]
    if type(entry) ~= "table" then
        return nil
    end

    return CopyEntry(entry)
end

function QuestState.MarkCategoryToggled(categoryId, timestampMs)
    local data = GetData()
    if not data then
        return nil
    end

    local key = NormalizeKey(categoryId)
    if not key then
        return nil
    end

    local value = timestampMs or AcquireTimeMilliseconds()
    data.toggleTimestamps.categories[key] = value
    return value
end

function QuestState.GetCategoryToggleTimestamp(categoryId)
    local data = GetData()
    if not data then
        return nil
    end

    local key = NormalizeKey(categoryId)
    if not key then
        return nil
    end

    local value = data.toggleTimestamps.categories[key]
    if value == nil then
        return nil
    end

    return tonumber(value)
end

local function SetQuestState(questId, expanded, options)
    local data = GetData()
    if not data then
        return false
    end

    local key = NormalizeKey(questId)
    if not key then
        return false
    end

    expanded = expanded and true or false
    local source = (type(options) == "table" and options.source) or "auto"
    local priority = ResolvePriority(source, type(options) == "table" and options.priorityOverride)
    local timestamp = ResolveTimestamp(options)
    local prev = data.questStates[key]

    if not ShouldWrite(prev, priority, timestamp, options) then
        return false
    end

    local entry = ApplyWrite(data.questStates, key, expanded, source, timestamp, priority)
    data.expandedQuests[key] = entry.expanded

    DebugLog("quest %s expanded=%s source=%s", tostring(key), tostring(entry.expanded), tostring(source))

    return true
end

function QuestState.IsQuestExpanded(questId)
    local data = GetData()
    if not data then
        return false, false
    end

    local key = NormalizeKey(questId)
    if not key then
        return false, false
    end

    local entry = data.questStates[key]
    if type(entry) == "table" and entry.expanded ~= nil then
        return entry.expanded and true or false, true
    end

    local expanded = data.expandedQuests[key]
    if expanded ~= nil then
        return expanded and true or false, true
    end

    return false, false
end

function QuestState.SetQuestExpanded(questId, expanded, options)
    local changed = SetQuestState(questId, expanded, options)
    if changed then
        QuestState.MarkQuestToggled(questId, options and options.toggleTimestamp)
    end
    return changed
end

function QuestState.ToggleQuestExpanded(questId, options)
    local current = QuestState.IsQuestExpanded(questId)
    return QuestState.SetQuestExpanded(questId, not current, options)
end

function QuestState.GetQuestState(questId)
    local data = GetData()
    if not data then
        return nil
    end

    local key = NormalizeKey(questId)
    if not key then
        return nil
    end

    local entry = data.questStates[key]
    if type(entry) ~= "table" then
        return nil
    end

    return CopyEntry(entry)
end

function QuestState.MarkQuestToggled(questId, timestampMs)
    local data = GetData()
    if not data then
        return nil
    end

    local key = NormalizeKey(questId)
    if not key then
        return nil
    end

    local value = timestampMs or AcquireTimeMilliseconds()
    data.toggleTimestamps.quests[key] = value
    return value
end

function QuestState.GetQuestToggleTimestamp(questId)
    local data = GetData()
    if not data then
        return nil
    end

    local key = NormalizeKey(questId)
    if not key then
        return nil
    end

    local value = data.toggleTimestamps.quests[key]
    if value == nil then
        return nil
    end

    return tonumber(value)
end

local function NormalizeQuestId(questId)
    if questId == nil then
        return nil
    end

    local key = NormalizeKey(questId)
    if key == nil then
        return nil
    end

    return key
end

function QuestState.GetSelectedQuestInfo()
    local data = GetData()
    if not data then
        return nil
    end

    if type(data.selection) ~= "table" then
        data.selection = {}
    end

    if data.selection.questId ~= nil then
        data.selection.questId = NormalizeQuestId(data.selection.questId)
        data.selectedQuestId = data.selection.questId
    end

    return {
        questKey = data.selection.questId,
        source = data.selection.source or "init",
        ts = tonumber(data.selection.ts) or 0,
    }
end

function QuestState.GetSelectedQuestId()
    local data = GetData()
    if not data then
        return nil
    end

    if data.selectedQuestId ~= nil then
        data.selectedQuestId = NormalizeQuestId(data.selectedQuestId)
    end

    return data.selectedQuestId
end

function QuestState.SetSelectedQuestId(questId, options)
    local data = GetData()
    if not data then
        return false
    end

    local normalized = NormalizeQuestId(questId)
    local source = (type(options) == "table" and options.source) or "auto"
    local priority = ResolvePriority(source, type(options) == "table" and options.priorityOverride)
    local timestamp = ResolveTimestamp(options)
    local prevInfo = QuestState.GetSelectedQuestInfo()

    if not ShouldWrite(prevInfo, priority, timestamp, options) then
        return false
    end

    ApplySelection(data, normalized, source, timestamp, priority)

    DebugLog("selected quest=%s source=%s", tostring(normalized), tostring(source))

    return true
end

function QuestState.GetFocusedQuestId()
    local data = GetData()
    if not data then
        return nil
    end

    if data.focusedQuestId ~= nil then
        data.focusedQuestId = NormalizeQuestId(data.focusedQuestId)
    end

    return data.focusedQuestId
end

function QuestState.SetFocusedQuestId(questId)
    local data = GetData()
    if not data then
        return false
    end

    local normalized = NormalizeQuestId(questId)
    data.focusedQuestId = normalized
    data.focusState.questId = normalized

    DebugLog("focused quest=%s", tostring(normalized))

    return true
end

function QuestState.MarkQuestSelectionTimestamp(questId, timestamp)
    local data = GetData()
    if not data then
        return nil
    end

    local normalized = NormalizeQuestId(questId)
    if normalized == nil then
        return nil
    end

    ApplySelection(data, normalized, "auto", timestamp or AcquireTimeSeconds(), PRIORITY.auto)
end

function QuestState.ResetAll()
    local data = GetData()
    if not data then
        return
    end

    data.expandedCategories = {}
    data.expandedQuests = {}
    data.categoryStates = {}
    data.questStates = {}
    data.toggleTimestamps = { categories = {}, quests = {} }
    data.selection = {}
    data.selectedQuestId = nil
    data.focusState = {}
    data.focusedQuestId = nil
end

Nvk3UT.QuestState = QuestState

return QuestState
