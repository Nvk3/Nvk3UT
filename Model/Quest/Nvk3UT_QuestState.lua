-- Model/Quest/Nvk3UT_QuestState.lua
-- Centralizes persistent quest tracker UI state (categories and quests) while forwarding
-- active selection responsibilities to Nvk3UT.QuestSelection.

Nvk3UT = Nvk3UT or {}
Nvk3UT.QuestState = Nvk3UT.QuestState or {}

local QuestState = Nvk3UT.QuestState

local saved = QuestState._saved

local function GetQuestSelectionModule()
    return Nvk3UT and Nvk3UT.QuestSelection
end

local STATE_VERSION = 1

local PRIORITY = {
    manual = 5,
    ["click-select"] = 4,
    ["external-select"] = 4,
    auto = 2,
    init = 1,
}

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

    if type(categoryKey) == "string" then
        return categoryKey
    end

    if type(categoryKey) == "number" then
        return tostring(categoryKey)
    end

    return tostring(categoryKey)
end

local lastSnapshot

local function GetSnapshot(candidate)
    if candidate ~= nil then
        return candidate
    end

    if lastSnapshot ~= nil then
        return lastSnapshot
    end

    local questModel = Nvk3UT and Nvk3UT.QuestModel
    if questModel and type(questModel.GetSnapshot) == "function" then
        local ok, snapshot = pcall(questModel.GetSnapshot)
        if ok then
            lastSnapshot = snapshot
            return snapshot
        end
    end

    return nil
end

local function NormalizeQuestKey(questRef, snapshot)
    if questRef == nil then
        return nil
    end

    if type(questRef) == "table" then
        if questRef.questKey ~= nil then
            return tostring(questRef.questKey)
        end

        if questRef.questId ~= nil then
            return tostring(questRef.questId)
        end

        if questRef.journalIndex ~= nil then
            return NormalizeQuestKey(questRef.journalIndex, snapshot)
        end
    end

    local resolvedSnapshot = GetSnapshot(snapshot)
    local candidate = questRef

    if type(candidate) == "string" then
        local numeric = tonumber(candidate)
        if resolvedSnapshot then
            if resolvedSnapshot.questByKey and resolvedSnapshot.questByKey[candidate] then
                return resolvedSnapshot.questByKey[candidate].questKey or candidate
            end

            if numeric and resolvedSnapshot.questByJournalIndex then
                local quest = resolvedSnapshot.questByJournalIndex[numeric]
                if quest and quest.questKey then
                    return tostring(quest.questKey)
                end
            end
        end

        if numeric and numeric > 0 then
            return tostring(numeric)
        end

        return candidate
    end

    if type(candidate) == "number" then
        local numeric = math.floor(candidate + 0.5)
        if numeric > 0 and resolvedSnapshot and resolvedSnapshot.questByJournalIndex then
            local quest = resolvedSnapshot.questByJournalIndex[numeric]
            if quest and quest.questKey then
                return tostring(quest.questKey)
            end
        end

        if numeric > 0 then
            return tostring(numeric)
        end

        return nil
    end

    return tostring(candidate)
end

local function EnsureSavedDefaults(target)
    if type(target) ~= "table" then
        return
    end

    target.defaults = target.defaults or {}
    if target.defaults.categoryExpanded == nil then
        target.defaults.categoryExpanded = true
    else
        target.defaults.categoryExpanded = target.defaults.categoryExpanded and true or false
    end

    if target.defaults.questExpanded == nil then
        target.defaults.questExpanded = true
    else
        target.defaults.questExpanded = target.defaults.questExpanded and true or false
    end
end

local function MigrateLegacySavedState(target)
    if type(target) ~= "table" then
        return
    end

    target.cat = target.cat or {}
    target.quest = target.quest or {}

    local legacyCategories = target.catExpanded
    if type(legacyCategories) == "table" then
        for key, value in pairs(legacyCategories) do
            local normalized = NormalizeCategoryKey(key)
            if normalized then
                target.cat[normalized] = {
                    expanded = value and true or false,
                    source = "init",
                    ts = 0,
                }
            end
        end
    end
    target.catExpanded = nil

    local legacyQuests = target.questExpanded
    if type(legacyQuests) == "table" then
        for key, value in pairs(legacyQuests) do
            local normalized = NormalizeQuestKey(key)
            if normalized then
                target.quest[normalized] = {
                    expanded = value and true or false,
                    source = "init",
                    ts = 0,
                }
            end
        end
    end
    target.questExpanded = nil

    if type(target.active) ~= "table" then
        target.active = {
            questKey = nil,
            source = "init",
            ts = 0,
        }
    else
        if target.active.questKey ~= nil then
            target.active.questKey = NormalizeQuestKey(target.active.questKey)
        end
        target.active.source = target.active.source or "init"
        target.active.ts = target.active.ts or 0
    end

    EnsureSavedDefaults(target)
end

local migrationState = { attempted = false }

local function MigrateSavedQuestKeys(snapshot)
    if migrationState.attempted then
        return false
    end

    if not saved then
        return false
    end

    local resolvedSnapshot = GetSnapshot(snapshot)
    if not (resolvedSnapshot and resolvedSnapshot.questByKey and resolvedSnapshot.questByJournalIndex) then
        return false
    end

    migrationState.attempted = true

    local changed = false

    local questTable = saved.quest
    if type(questTable) == "table" then
        local migrated = {}
        for key, entry in pairs(questTable) do
            local normalized = NormalizeQuestKey(key, resolvedSnapshot)
            if normalized and resolvedSnapshot.questByKey[normalized] then
                migrated[normalized] = entry
                if normalized ~= key then
                    changed = true
                end
            else
                changed = true
            end
        end
        saved.quest = migrated
    end

    local active = EnsureActiveSavedStateFallback(saved)
    if active then
        local normalized = NormalizeQuestKey(active.questKey, resolvedSnapshot)
        if normalized and resolvedSnapshot.questByKey[normalized] then
            if normalized ~= active.questKey then
                active.questKey = normalized
                changed = true
            end
        else
            if active.questKey ~= nil then
                active.questKey = nil
                changed = true
            end
        end
    end

    lastSnapshot = resolvedSnapshot

    return changed
end

local function EnsureActiveSavedStateFallback(target)
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

local function EnsureSavedTables(target)
    if type(target) ~= "table" then
        return nil, nil
    end

    target.cat = target.cat or {}
    target.quest = target.quest or {}
    return target.cat, target.quest
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

local function ApplyCategoryWrite(categoryKey, expanded, source, options)
    if not saved then
        return false
    end

    local key = NormalizeCategoryKey(categoryKey)
    if not key then
        return false
    end

    source = source or "auto"
    local catTable = EnsureSavedTables(saved)
    if not catTable then
        return false
    end

    local previous = catTable[key]
    local shouldWrite, priority, timestamp = ResolveWrite(source, options, previous)
    if not shouldWrite then
        return false, key, previous and previous.expanded, priority, source
    end

    local newExpanded = expanded and true or false
    catTable[key] = {
        expanded = newExpanded,
        source = source,
        ts = timestamp,
    }

    return true, key, newExpanded, priority, source
end

local function ApplyQuestWrite(questKey, expanded, source, options)
    if not saved then
        return false
    end

    local key = NormalizeQuestKey(questKey)
    if not key then
        return false
    end

    source = source or "auto"
    local _, questTable = EnsureSavedTables(saved)
    if not questTable then
        return false
    end

    local previous = questTable[key]
    local shouldWrite, priority, timestamp = ResolveWrite(source, options, previous)
    if not shouldWrite then
        return false, key, previous and previous.expanded, priority, source
    end

    local newExpanded = expanded and true or false
    questTable[key] = {
        expanded = newExpanded,
        source = source,
        ts = timestamp,
    }

    return true, key, newExpanded, priority, source
end

local function ApplyActiveWriteFallback(questKey, source, options)
    if not saved then
        return false
    end

    source = source or "auto"
    options = options or {}

    local normalized = questKey and NormalizeQuestKey(questKey) or nil
    local previous = EnsureActiveSavedStateFallback(saved)
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

function QuestState.Bind(root)
    if type(root) ~= "table" then
        saved = nil
        QuestState._saved = nil
        return nil
    end

    local questTracker = root.QuestTracker
    if type(questTracker) ~= "table" then
        questTracker = {}
        root.QuestTracker = questTracker
    end

    if type(questTracker.stateVersion) ~= "number" or questTracker.stateVersion < STATE_VERSION then
        MigrateLegacySavedState(questTracker)
        questTracker.stateVersion = STATE_VERSION
    end

    EnsureSavedTables(questTracker)
    EnsureSavedDefaults(questTracker)
    MigrateSavedQuestKeys()

    local questSelection = GetQuestSelectionModule()
    if questSelection and questSelection.EnsureActiveSavedState then
        questSelection.EnsureActiveSavedState(questTracker)
    else
        EnsureActiveSavedStateFallback(questTracker)
    end

    saved = questTracker
    QuestState._saved = saved

    if questSelection and questSelection.Bind then
        questSelection.Bind(root, questTracker)
    end

    return questTracker
end

function QuestState.GetSaved()
    return saved
end

function QuestState.GetCurrentTimeSeconds()
    return GetCurrentTimeSeconds()
end

function QuestState.NormalizeCategoryKey(categoryKey)
    return NormalizeCategoryKey(categoryKey)
end

function QuestState.NormalizeQuestKey(journalIndex)
    return NormalizeQuestKey(journalIndex)
end

function QuestState.ApplySnapshot(snapshot)
    lastSnapshot = snapshot or lastSnapshot
    return MigrateSavedQuestKeys(snapshot)
end

-- TEMP SHIM (QMODEL_002): TODO remove on SWITCH token; forwards active-state ensures to QuestSelection.
function QuestState.EnsureActiveSavedState()
    local questSelection = GetQuestSelectionModule()
    if questSelection and questSelection.EnsureActiveSavedState then
        return questSelection.EnsureActiveSavedState(saved)
    end

    return EnsureActiveSavedStateFallback(saved)
end

function QuestState.SetCategoryExpanded(categoryKey, expanded, source, options)
    return ApplyCategoryWrite(categoryKey, expanded, source, options)
end

function QuestState.SetQuestExpanded(questKey, expanded, source, options)
    return ApplyQuestWrite(questKey, expanded, source, options)
end

-- TEMP SHIM (QMODEL_002): TODO remove on SWITCH token; forwards active selection writes to QuestSelection.
function QuestState.SetSelectedQuestId(questKey, source, options)
    local questSelection = GetQuestSelectionModule()
    if questSelection and questSelection.SetActive then
        return questSelection.SetActive(questKey, source, options)
    end

    return ApplyActiveWriteFallback(questKey, source, options)
end

function QuestState.IsCategoryExpanded(categoryKey)
    if not saved then
        return nil
    end

    local key = NormalizeCategoryKey(categoryKey)
    if not key then
        return nil
    end

    local catTable = saved.cat
    if type(catTable) ~= "table" then
        return nil
    end

    local entry = catTable[key]
    if entry and entry.expanded ~= nil then
        return entry.expanded and true or false
    end

    return nil
end

function QuestState.IsQuestExpanded(questKey)
    if not saved then
        return nil
    end

    local key = NormalizeQuestKey(questKey)
    if not key then
        return nil
    end

    local questTable = saved.quest
    if type(questTable) ~= "table" then
        return nil
    end

    local entry = questTable[key]
    if entry and entry.expanded ~= nil then
        return entry.expanded and true or false
    end

    return nil
end

-- TEMP SHIM (QMODEL_002): TODO remove on SWITCH token; forwards active selection reads to QuestSelection.
function QuestState.GetSelectedQuestId()
    local questSelection = GetQuestSelectionModule()
    if questSelection and questSelection.GetActiveQuestKey then
        return questSelection.GetActiveQuestKey()
    end

    if not saved then
        return nil
    end

    local active = EnsureActiveSavedStateFallback(saved)
    return active and active.questKey or nil
end

function QuestState.GetCategoryDefaultExpanded()
    if not saved or type(saved.defaults) ~= "table" then
        return nil
    end

    if saved.defaults.categoryExpanded == nil then
        return nil
    end

    return saved.defaults.categoryExpanded and true or false
end

function QuestState.GetQuestDefaultExpanded()
    if not saved or type(saved.defaults) ~= "table" then
        return nil
    end

    if saved.defaults.questExpanded == nil then
        return nil
    end

    return saved.defaults.questExpanded and true or false
end

return QuestState
