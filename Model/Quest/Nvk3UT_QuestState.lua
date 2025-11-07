-- Model/Quest/Nvk3UT_QuestState.lua
-- Persists quest tracker UI state in the refreshed character-scoped schema.
-- Stores only collapse deviations and minimal quest flags while keeping runtime
-- metadata for priority-aware writes in memory.

Nvk3UT = Nvk3UT or {}
Nvk3UT.QuestState = Nvk3UT.QuestState or {}

local QuestState = Nvk3UT.QuestState

local PRIORITY = {
    manual = 5,
    ["click-select"] = 4,
    ["external-select"] = 4,
    auto = 2,
    init = 1,
}

local savedRoot = QuestState._saved
local savedCharacter = QuestState._savedCharacter
local savedState = QuestState._savedState
local savedZones = QuestState._savedZones
local savedQuestCollapses = QuestState._savedQuests
local savedFlags = QuestState._savedFlags

local runtimeCategories = QuestState._runtimeCategories or {}
local runtimeQuests = QuestState._runtimeQuests or {}
local runtimeActive = QuestState._runtimeActive or {
    questId = nil,
    priority = PRIORITY.init,
    ts = 0,
    source = "init",
}

QuestState._runtimeCategories = runtimeCategories
QuestState._runtimeQuests = runtimeQuests
QuestState._runtimeActive = runtimeActive

local function GetQuestListModule()
    return Nvk3UT and Nvk3UT.QuestList
end

local function GetCurrentTimeSeconds()
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

local function NormalizeCategoryKey(categoryKey)
    if categoryKey == nil then
        return nil
    end

    if type(categoryKey) == "table" and categoryKey.key ~= nil then
        categoryKey = categoryKey.key
    end

    local numeric = tonumber(categoryKey)
    if numeric and numeric > 0 then
        return math.floor(numeric)
    end

    return nil
end

local function ResolveQuestId(value)
    if value == nil then
        return nil
    end

    if type(value) == "table" then
        if value.questId ~= nil then
            return ResolveQuestId(value.questId)
        end
        if value.journalIndex ~= nil then
            return ResolveQuestId(value.journalIndex)
        end
        if value.questKey ~= nil then
            return ResolveQuestId(value.questKey)
        end
    end

    local numeric = tonumber(value)
    if numeric and numeric > 0 then
        local questList = GetQuestListModule()
        if questList and questList.GetByJournalIndex then
            local ok, quest = pcall(questList.GetByJournalIndex, questList, numeric)
            if ok and type(quest) == "table" and quest.questId then
                local questNumeric = tonumber(quest.questId)
                if questNumeric and questNumeric > 0 then
                    return math.floor(questNumeric)
                end
            end
        end

        return math.floor(numeric)
    end

    return nil
end

local function NormalizeQuestKey(value)
    return ResolveQuestId(value)
end

local function evaluateWrite(metaTable, key, source, options)
    options = options or {}

    source = type(source) == "string" and source or "auto"
    local entry = metaTable[key]
    local priorityOverride = options.priorityOverride
    local priority = priorityOverride or PRIORITY[source] or 0
    local now = tonumber(options.timestamp) or GetCurrentTimeSeconds()
    local previousPriority = entry and entry.priority or 0
    local previousTimestamp = entry and entry.ts or 0
    local forceWrite = options.force == true
    local allowTimestampRegression = options.allowTimestampRegression == true

    if entry and not forceWrite then
        if previousPriority > priority then
            return false, priority, now, entry.source or source
        end

        if previousPriority == priority and not allowTimestampRegression and now < previousTimestamp then
            return false, priority, now, entry.source or source
        end
    end

    return true, priority, now, source
end

local function commitMeta(metaTable, key, priority, timestamp, source)
    metaTable[key] = {
        priority = priority,
        ts = timestamp,
        source = source,
    }
end

local function ensureStateContainer()
    if not savedRoot then
        return nil
    end

    if not savedState then
        savedState = {}
        QuestState._savedState = savedState
        savedRoot.state = savedState
    end

    return savedState
end

local function syncStateContainer()
    if not savedRoot then
        savedState = nil
        QuestState._savedState = nil
        return
    end

    local hasZones = savedZones and next(savedZones) ~= nil
    local hasQuests = savedQuestCollapses and next(savedQuestCollapses) ~= nil

    if hasZones or hasQuests then
        ensureStateContainer()
        if savedState then
            savedRoot.state = savedState
        end
    else
        savedRoot.state = nil
        savedState = nil
        QuestState._savedState = nil
    end
end

local function getZoneStorage(create)
    if not savedRoot then
        return nil
    end

    if not savedState and create then
        ensureStateContainer()
    end

    if not savedState then
        return nil
    end

    if not savedZones and create then
        savedZones = {}
        QuestState._savedZones = savedZones
    end

    return savedZones
end

local function syncZoneStorage()
    if not savedState then
        savedZones = nil
        QuestState._savedZones = nil
        syncStateContainer()
        return
    end

    if savedZones and next(savedZones) ~= nil then
        savedState.zones = savedZones
    else
        savedState.zones = nil
        savedZones = nil
        QuestState._savedZones = nil
    end

    syncStateContainer()
end

local function getQuestStorage(create)
    if not savedRoot then
        return nil
    end

    if not savedState and create then
        ensureStateContainer()
    end

    if not savedState then
        return nil
    end

    if not savedQuestCollapses and create then
        savedQuestCollapses = {}
        QuestState._savedQuests = savedQuestCollapses
    end

    return savedQuestCollapses
end

local function syncQuestStorage()
    if not savedState then
        savedQuestCollapses = nil
        QuestState._savedQuests = nil
        syncStateContainer()
        return
    end

    if savedQuestCollapses and next(savedQuestCollapses) ~= nil then
        savedState.quests = savedQuestCollapses
    else
        savedState.quests = nil
        savedQuestCollapses = nil
        QuestState._savedQuests = nil
    end

    syncStateContainer()
end

local function getFlagsStorage(create)
    if not savedRoot then
        return nil
    end

    if not savedFlags and create then
        savedFlags = {}
        QuestState._savedFlags = savedFlags
    end

    return savedFlags
end

local function syncFlagsStorage()
    if not savedRoot then
        savedFlags = nil
        QuestState._savedFlags = nil
        return
    end

    if savedFlags and next(savedFlags) ~= nil then
        savedRoot.flags = savedFlags
    else
        savedRoot.flags = nil
        savedFlags = nil
        QuestState._savedFlags = nil
    end
end

local function sanitizeFlagEntry(flags)
    if type(flags) ~= "table" then
        return nil
    end

    local entry = {}

    if flags.tracked == true then
        entry.tracked = true
    end

    if flags.assisted == true then
        entry.assisted = true
    end

    if flags.isDaily == true then
        entry.isDaily = true
    end

    local categoryKey = NormalizeCategoryKey(flags.categoryKey)
    if categoryKey then
        entry.categoryKey = categoryKey
    end

    local journalIndex = tonumber(flags.journalIndex)
    if journalIndex and journalIndex > 0 then
        entry.journalIndex = math.floor(journalIndex)
    end

    if next(entry) == nil then
        return nil
    end

    return entry
end

local function flagsEqual(left, right)
    if left == right then
        return true
    end
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end

    local keys = {
        "tracked",
        "assisted",
        "isDaily",
        "categoryKey",
        "journalIndex",
    }

    for index = 1, #keys do
        local key = keys[index]
        if left[key] ~= right[key] then
            return false
        end
    end

    return true
end

local function assignSavedReferences(character)
    savedCharacter = character
    QuestState._savedCharacter = character
    savedRoot = character and character.quests or nil
    QuestState._saved = savedRoot

    if savedRoot then
        if type(savedRoot.state) == "table" and next(savedRoot.state) ~= nil then
            savedState = savedRoot.state
            QuestState._savedState = savedState
        else
            savedState = nil
            savedRoot.state = nil
            QuestState._savedState = nil
        end

        if savedState and type(savedState.zones) == "table" and next(savedState.zones) ~= nil then
            savedZones = savedState.zones
            QuestState._savedZones = savedZones
        else
            savedZones = nil
            QuestState._savedZones = nil
        end

        if savedState and type(savedState.quests) == "table" and next(savedState.quests) ~= nil then
            savedQuestCollapses = savedState.quests
            QuestState._savedQuests = savedQuestCollapses
        else
            savedQuestCollapses = nil
            QuestState._savedQuests = nil
        end

        if type(savedRoot.flags) == "table" and next(savedRoot.flags) ~= nil then
            savedFlags = savedRoot.flags
            QuestState._savedFlags = savedFlags
        else
            savedFlags = nil
            savedRoot.flags = nil
            QuestState._savedFlags = nil
        end
    else
        savedState = nil
        savedZones = nil
        savedQuestCollapses = nil
        savedFlags = nil
        QuestState._savedState = nil
        QuestState._savedZones = nil
        QuestState._savedQuests = nil
        QuestState._savedFlags = nil
    end
end

function QuestState.Bind(root)
    local addon = Nvk3UT
    local character = addon and (addon.SVCharacter or addon.svCharacter)

    if type(character) ~= "table" then
        character = root
    end

    if type(character) ~= "table" then
        assignSavedReferences(nil)
        return nil
    end

    character.quests = character.quests or {}
    character.quests.state = character.quests.state or {}

    assignSavedReferences(character)

    syncZoneStorage()
    syncQuestStorage()
    syncFlagsStorage()

    return savedRoot
end

function QuestState.GetSaved()
    return savedRoot
end

function QuestState.GetCurrentTimeSeconds()
    return GetCurrentTimeSeconds()
end

function QuestState.NormalizeCategoryKey(categoryKey)
    return NormalizeCategoryKey(categoryKey)
end

function QuestState.NormalizeQuestKey(value)
    return NormalizeQuestKey(value)
end

function QuestState.EnsureActiveSavedState()
    return runtimeActive
end

function QuestState.SetCategoryExpanded(categoryKey, expanded, source, options)
    if not savedState then
        return false
    end

    local key = NormalizeCategoryKey(categoryKey)
    if not key then
        return false
    end

    local shouldWrite, priority, timestamp, resolvedSource = evaluateWrite(runtimeCategories, key, source, options)
    if not shouldWrite then
        local zones = savedZones
        local isCollapsed = zones and zones[key] == true
        return false, key, not isCollapsed, priority, resolvedSource
    end

    local zones = getZoneStorage(not expanded)
    local changed = false

    if expanded then
        if zones and zones[key] ~= nil then
            zones[key] = nil
            changed = true
        end
    else
        zones = getZoneStorage(true)
        if zones[key] ~= true then
            zones[key] = true
            changed = true
        end
    end

    if changed then
        commitMeta(runtimeCategories, key, priority, timestamp, resolvedSource)
        syncZoneStorage()
        return true, key, expanded and true or false, priority, resolvedSource
    end

    return false, key, expanded and true or false, priority, resolvedSource
end

function QuestState.SetQuestExpanded(questKey, expanded, source, options)
    if not savedState then
        return false
    end

    local questId = NormalizeQuestKey(questKey)
    if not questId then
        return false
    end

    local shouldWrite, priority, timestamp, resolvedSource = evaluateWrite(runtimeQuests, questId, source, options)
    if not shouldWrite then
        local storage = savedQuestCollapses
        local isCollapsed = storage and storage[questId] == true
        return false, questId, not isCollapsed, priority, resolvedSource
    end

    local storage = getQuestStorage(not expanded)
    local changed = false

    if expanded then
        if storage and storage[questId] ~= nil then
            storage[questId] = nil
            changed = true
        end
    else
        storage = getQuestStorage(true)
        if storage[questId] ~= true then
            storage[questId] = true
            changed = true
        end
    end

    if changed then
        commitMeta(runtimeQuests, questId, priority, timestamp, resolvedSource)
        syncQuestStorage()
        return true, questId, expanded and true or false, priority, resolvedSource
    end

    return false, questId, expanded and true or false, priority, resolvedSource
end

local function evaluateActiveWrite(source, options)
    options = options or {}

    source = type(source) == "string" and source or "auto"
    local priorityOverride = options.priorityOverride
    local priority = priorityOverride or PRIORITY[source] or 0
    local now = tonumber(options.timestamp) or GetCurrentTimeSeconds()
    local previousPriority = runtimeActive.priority or 0
    local previousTimestamp = runtimeActive.ts or 0
    local forceWrite = options.force == true
    local allowTimestampRegression = options.allowTimestampRegression == true

    if not forceWrite then
        if previousPriority > priority then
            return false, priority, now, runtimeActive.source or source
        end

        if previousPriority == priority and not allowTimestampRegression and now < previousTimestamp then
            return false, priority, now, runtimeActive.source or source
        end
    end

    return true, priority, now, source
end

function QuestState.SetSelectedQuestId(questKey, source, options)
    local questId = NormalizeQuestKey(questKey)
    local shouldWrite, priority, timestamp, resolvedSource = evaluateActiveWrite(source, options)
    if not shouldWrite then
        return false, questId, priority, resolvedSource
    end

    local previous = runtimeActive.questId
    if previous == questId then
        runtimeActive.priority = priority
        runtimeActive.ts = timestamp
        runtimeActive.source = resolvedSource
        return false, questId, priority, resolvedSource
    end

    runtimeActive.questId = questId
    runtimeActive.priority = priority
    runtimeActive.ts = timestamp
    runtimeActive.source = resolvedSource

    return true, questId, priority, resolvedSource
end

function QuestState.IsCategoryExpanded(categoryKey)
    if not savedState then
        return nil
    end

    local key = NormalizeCategoryKey(categoryKey)
    if not key then
        return nil
    end

    local zones = savedZones
    if zones and zones[key] == true then
        return false
    end

    return nil
end

function QuestState.IsQuestExpanded(questKey)
    if not savedState then
        return nil
    end

    local questId = NormalizeQuestKey(questKey)
    if not questId then
        return nil
    end

    local storage = savedQuestCollapses
    if storage and storage[questId] == true then
        return false
    end

    return nil
end

function QuestState.GetSelectedQuestId()
    return runtimeActive.questId
end

function QuestState.GetCategoryDefaultExpanded()
    return true
end

function QuestState.GetQuestDefaultExpanded()
    return true
end

function QuestState.SetQuestFlags(questKey, flags)
    if not savedRoot then
        return false
    end

    local questId = NormalizeQuestKey(questKey)
    if not questId then
        return false
    end

    local entry = sanitizeFlagEntry(flags)
    local storage = getFlagsStorage(entry ~= nil)
    local previous = storage and storage[questId] or nil

    if not entry then
        if storage and previous then
            storage[questId] = nil
            syncFlagsStorage()
            return true, questId
        end
        return false
    end

    if previous and flagsEqual(previous, entry) then
        return false, questId
    end

    storage = storage or getFlagsStorage(true)
    storage[questId] = entry
    syncFlagsStorage()

    return true, questId
end

function QuestState.ClearQuestFlags(questKey)
    return QuestState.SetQuestFlags(questKey, nil)
end

function QuestState.GetQuestFlags(questKey)
    if not savedFlags then
        return nil
    end

    local questId = NormalizeQuestKey(questKey)
    if not questId then
        return nil
    end

    local entry = savedFlags[questId]
    if not entry then
        return nil
    end

    local copy = {}
    for key, value in pairs(entry) do
        copy[key] = value
    end
    return copy
end

function QuestState.UpdateQuestFlagsFromQuest(quest)
    if type(quest) ~= "table" then
        return false
    end

    local questId = NormalizeQuestKey(quest.questId or quest.journalIndex)
    if not questId then
        return false
    end

    local flags = quest.flags or {}
    local payload = {
        tracked = flags.tracked == true,
        assisted = flags.assisted == true,
        isDaily = flags.isDaily == true,
        journalIndex = quest.journalIndex,
    }

    local category = quest.category or {}
    payload.categoryKey = category.key or (quest.meta and quest.meta.categoryKey)

    return QuestState.SetQuestFlags(questId, payload)
end

function QuestState.PruneQuestFlags(valid)
    if not savedFlags or type(savedFlags) ~= "table" then
        return 0
    end

    local removed = 0
    for questId in pairs(savedFlags) do
        local keep = false
        if type(valid) == "table" then
            if valid[questId] or valid[tostring(questId)] then
                keep = true
            end
        end

        if not keep then
            savedFlags[questId] = nil
            removed = removed + 1
        end
    end

    if removed > 0 then
        syncFlagsStorage()
    end

    return removed
end

return QuestState
