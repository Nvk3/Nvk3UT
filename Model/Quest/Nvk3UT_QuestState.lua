-- Model/Quest/Nvk3UT_QuestState.lua
-- Persists quest tracker UI state through the quest repository so only collapsed
-- deviations and minimal quest flags reach SavedVariables. Runtime helpers keep
-- priority-aware writes in memory while storage always routes through the repo.

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

local questRepo = QuestState._repo

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

local function getAddon()
    return Nvk3UT
end

local function isDebugEnabled()
    local addon = getAddon()
    if not addon then
        return false
    end

    local accessor = addon.IsDebugEnabled
    if type(accessor) == "function" then
        local ok, result = pcall(accessor, addon)
        if ok then
            return result == true
        end
    end

    if addon.debugEnabled ~= nil then
        return addon.debugEnabled == true
    end

    return addon.debug == true
end

local function debugLog(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local addon = getAddon()
    if addon and type(addon.Debug) == "function" then
        addon.Debug("[QuestState] " .. tostring(fmt), ...)
        return
    end

    local ok, message = pcall(string.format, tostring(fmt), ...)
    if not ok then
        message = tostring(fmt)
    end

    if d then
        d(string.format("[Nvk3UT][QuestState] %s", message))
    elseif print then
        print("[Nvk3UT][QuestState]", message)
    end
end

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

    if type(categoryKey) == "string" then
        local trimmed = categoryKey:match("^%s*(.-)%s*$") or ""
        if trimmed == "" then
            return nil
        end

        return trimmed
    end

    if type(categoryKey) == "number" then
        if categoryKey ~= categoryKey then
            return nil
        end

        local rounded = math.floor(categoryKey + 0.5)
        if rounded <= 0 then
            return nil
        end

        return tostring(rounded)
    end

    local numeric = tonumber(categoryKey)
    if numeric then
        local rounded = math.floor(numeric + 0.5)
        if rounded <= 0 then
            return nil
        end

        return tostring(rounded)
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

local function GetRepo()
    if questRepo then
        return questRepo
    end

    questRepo = Nvk3UT_StateRepo_Quests or (Nvk3UT and Nvk3UT.QuestRepo)
    if questRepo then
        QuestState._repo = questRepo
    end

    return questRepo
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

function QuestState.Bind(root)
    local repo = GetRepo()
    if repo and repo.Init then
        local addon = Nvk3UT
        local character = addon and (addon.SVCharacter or addon.svCharacter)
        repo.Init(character)
    end

    return nil
end

function QuestState.GetSaved()
    return nil
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
    runtimeActive.ts = runtimeActive.ts or 0
    runtimeActive.source = runtimeActive.source or "init"
    runtimeActive.priority = runtimeActive.priority or PRIORITY.init
    return runtimeActive
end

function QuestState.SetCategoryExpanded(categoryKey, expanded, source, options)
    local repo = GetRepo()
    if not (repo and repo.Q_SetZoneCollapsed and repo.Q_IsZoneCollapsed) then
        return false
    end

    local key = NormalizeCategoryKey(categoryKey)
    if not key then
        debugLog(
            "QS_WRITE key=nil expanded=%s (source=%s)",
            tostring(expanded),
            tostring(source)
        )
        return false
    end

    local shouldWrite, priority, timestamp, resolvedSource = evaluateWrite(runtimeCategories, key, source, options)
    if not shouldWrite then
        local collapsed = repo.Q_IsZoneCollapsed(key)
        local isExpanded = collapsed ~= true
        debugLog(
            "QS_AFTER key=%s collapsed=%s changed=false (skipped)",
            tostring(key),
            tostring(collapsed)
        )
        return false, key, isExpanded, priority, resolvedSource
    end

    local forceOption = options and options.force
    local allowRegression = options and options.allowTimestampRegression
    debugLog(
        "QS_WRITE key=%s expanded=%s force=%s tsreg=%s",
        tostring(key),
        tostring(expanded),
        tostring(forceOption),
        tostring(allowRegression)
    )

    local changed
    if expanded then
        changed = repo.Q_SetZoneCollapsed(key, false) == true
    else
        changed = repo.Q_SetZoneCollapsed(key, true) == true
    end

    local collapsed = repo.Q_IsZoneCollapsed(key)
    local isExpanded = collapsed ~= true

    debugLog(
        "QS_AFTER key=%s collapsed=%s changed=%s",
        tostring(key),
        tostring(collapsed),
        tostring(changed)
    )

    if changed then
        commitMeta(runtimeCategories, key, priority, timestamp, resolvedSource)
        return true, key, isExpanded, priority, resolvedSource
    end

    return false, key, isExpanded, priority, resolvedSource
end

function QuestState.SetQuestExpanded(questKey, expanded, source, options)
    local repo = GetRepo()
    if not (repo and repo.Q_SetQuestCollapsed and repo.Q_IsQuestCollapsed) then
        return false
    end

    local questId = NormalizeQuestKey(questKey)
    if not questId then
        return false
    end

    local shouldWrite, priority, timestamp, resolvedSource = evaluateWrite(runtimeQuests, questId, source, options)
    if not shouldWrite then
        local collapsed = repo.Q_IsQuestCollapsed(questId)
        local isExpanded = collapsed ~= true
        return false, questId, isExpanded, priority, resolvedSource
    end

    local changed
    if expanded then
        changed = repo.Q_SetQuestCollapsed(questId, false) == true
    else
        changed = repo.Q_SetQuestCollapsed(questId, true) == true
    end

    local collapsed = repo.Q_IsQuestCollapsed(questId)
    local isExpanded = collapsed ~= true

    if changed then
        commitMeta(runtimeQuests, questId, priority, timestamp, resolvedSource)
        return true, questId, isExpanded, priority, resolvedSource
    end

    return false, questId, isExpanded, priority, resolvedSource
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
    local repo = GetRepo()
    if not (repo and repo.Q_IsZoneCollapsed) then
        return nil
    end

    local key = NormalizeCategoryKey(categoryKey)
    if not key then
        return nil
    end

    local collapsed = repo.Q_IsZoneCollapsed(key)
    if collapsed == true then
        return false
    end

    return nil
end

function QuestState.IsQuestExpanded(questKey)
    local repo = GetRepo()
    if not (repo and repo.Q_IsQuestCollapsed) then
        return nil
    end

    local questId = NormalizeQuestKey(questKey)
    if not questId then
        return nil
    end

    local collapsed = repo.Q_IsQuestCollapsed(questId)
    if collapsed == true then
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
    local repo = GetRepo()
    if not (repo and repo.Q_SetFlags) then
        return false
    end

    local questId = NormalizeQuestKey(questKey)
    if not questId then
        return false
    end

    local entry = sanitizeFlagEntry(flags)
    local changed = repo.Q_SetFlags(questId, entry)
    if changed then
        return true, questId
    end

    return false
end

function QuestState.ClearQuestFlags(questKey)
    return QuestState.SetQuestFlags(questKey, nil)
end

function QuestState.GetQuestFlags(questKey)
    local repo = GetRepo()
    if not (repo and repo.Q_GetFlags) then
        return nil
    end

    local questId = NormalizeQuestKey(questKey)
    if not questId then
        return nil
    end

    local entry = repo.Q_GetFlags(questId)
    if type(entry) ~= "table" then
        entry = {
            tracked = false,
            assisted = false,
            isDaily = false,
            categoryKey = nil,
            journalIndex = nil,
        }
    end

    local copy = {}
    copy.tracked = entry.tracked == true
    copy.assisted = entry.assisted == true
    copy.isDaily = entry.isDaily == true
    copy.categoryKey = entry.categoryKey
    copy.journalIndex = entry.journalIndex

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
    local repo = GetRepo()
    if not (repo and repo.Q_PruneFlags) then
        return 0
    end

    return repo.Q_PruneFlags(valid)
end

return QuestState
