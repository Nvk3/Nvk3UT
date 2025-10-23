Nvk3UT = Nvk3UT or {}

local M = Nvk3UT

M.QuestModel = M.QuestModel or {}
local Module = M.QuestModel

local EM = EVENT_MANAGER

local EVENT_NAMESPACE = "Nvk3UT_QuestModel"
local REFRESH_HANDLE = EVENT_NAMESPACE .. "_Refresh"

local DEFAULT_DEBOUNCE_MS = 120
local MAX_QUESTS = 25

local callbacks = {}

Module._snapshot = Module._snapshot or { meta = { total = 0, lastUpdated = 0 }, quests = {} }
Module._signature = Module._signature or ""
Module._debounceMs = Module._debounceMs or DEFAULT_DEBOUNCE_MS
Module._debug = false
Module._initialized = Module._initialized or false
Module._refreshQueued = false

local function debugLog(message)
    if not Module._debug then
        return
    end

    if type(message) ~= "string" then
        message = tostring(message)
    end

    if d then
        d(string.format("[Nvk3UT] QuestModel: %s", message))
    end
end

local function sanitizeText(text)
    if text == nil or text == "" then
        return ""
    end

    if zo_strformat then
        local ok, formatted = pcall(zo_strformat, "<<1>>", text)
        if ok and formatted then
            return formatted
        end
    end

    return text
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    local ok, value1, value2, value3, value4, value5, value6, value7 = pcall(fn, ...)
    if not ok then
        return nil
    end

    return value1, value2, value3, value4, value5, value6, value7
end

local function isQuestTracked(journalIndex)
    local tracked = safeCall(IsJournalQuestTracked, journalIndex)
    if tracked ~= nil then
        return tracked == true
    end

    local altTracked = safeCall(GetIsJournalQuestTracked, journalIndex)
    if altTracked ~= nil then
        return altTracked == true
    end

    local trackerFlag = safeCall(GetJournalQuestIsTracked, journalIndex)
    if trackerFlag ~= nil then
        return trackerFlag == true
    end

    return false
end

local function isQuestAssisted(journalIndex)
    local assisted = safeCall(GetTrackedIsAssisted, journalIndex)
    if assisted ~= nil then
        return assisted == true
    end

    local focusedIndex = safeCall(GetTrackedQuestIndex)
    if focusedIndex and focusedIndex == journalIndex then
        return true
    end

    return false
end

local function buildConditions(journalIndex, stepIndex)
    local conditions = {}
    local conditionCount = safeCall(GetJournalQuestNumConditions, journalIndex, stepIndex) or 0

    for conditionIndex = 1, conditionCount do
        local ok,
            text,
            cur,
            max,
            isFailCondition,
            isComplete,
            isVisible = pcall(GetJournalQuestConditionInfo, journalIndex, stepIndex, conditionIndex)

        if ok then
            local sanitized = sanitizeText(text)

            if sanitized ~= "" and not isFailCondition and (isVisible ~= false) and not isComplete then
                conditions[#conditions + 1] = {
                    conditionIndex = conditionIndex,
                    text = sanitized,
                    cur = tonumber(cur),
                    max = tonumber(max),
                    isComplete = isComplete == true,
                }
            end
        end
    end

    return conditions
end

local function buildSteps(journalIndex)
    local steps = {}
    local numSteps = safeCall(GetJournalQuestNumSteps, journalIndex) or 0

    for stepIndex = 1, numSteps do
        local ok,
            stepText,
            visibility,
            stepType,
            trackerComplete,
            stepOverrideText,
            stepDescription,
            stepComplete = pcall(GetJournalQuestStepInfo, journalIndex, stepIndex)

        if ok then
            local text = stepOverrideText ~= nil and stepOverrideText ~= "" and stepOverrideText or stepText
            local sanitized = sanitizeText(text)

            local conditions = buildConditions(journalIndex, stepIndex)

            local stepEntry = {
                stepIndex = stepIndex,
                stepText = sanitized,
                isOptional = visibility == QUEST_STEP_VISIBILITY_OPTIONAL,
                isComplete = trackerComplete == true or stepComplete == true,
                stepType = stepType,
                conditions = conditions,
            }

            steps[#steps + 1] = stepEntry
        end
    end

    return steps
end

local function questSortKey(entry)
    if entry.isAssisted then
        return 0
    end
    if entry.isTracked then
        return 1
    end
    return 2
end

local function questSortComparator(a, b)
    local priorityA = questSortKey(a)
    local priorityB = questSortKey(b)

    if priorityA ~= priorityB then
        return priorityA < priorityB
    end

    if a.zoneName ~= b.zoneName then
        return a.zoneName < b.zoneName
    end

    if a.name ~= b.name then
        return a.name < b.name
    end

    return a.journalIndex < b.journalIndex
end

local function computeQuestHash(entry)
    local parts = {
        tostring(entry.journalIndex or ""),
        entry.name or "",
        entry.zoneName or "",
        tostring(entry.isTracked),
        tostring(entry.isAssisted),
        tostring(entry.isComplete),
    }

    for stepIdx = 1, #entry.steps do
        local step = entry.steps[stepIdx]
        parts[#parts + 1] = tostring(step.stepIndex)
        parts[#parts + 1] = tostring(step.stepText)
        parts[#parts + 1] = tostring(step.isComplete)
        for condIdx = 1, #(step.conditions) do
            local cond = step.conditions[condIdx]
            parts[#parts + 1] = tostring(cond.text)
            parts[#parts + 1] = tostring(cond.cur or "")
            parts[#parts + 1] = tostring(cond.max or "")
        end
    end

    return table.concat(parts, "|")
end

local function buildSnapshot()
    local quests = {}
    local hashes = {}
    local total = 0

    local numQuests = safeCall(GetNumJournalQuests) or 0

    for journalIndex = 1, numQuests do
        local ok,
            questName,
            _,
            _,
            _,
            _,
            _,
            questType = pcall(GetJournalQuestInfo, journalIndex)

        if ok and questName and questName ~= "" then
            total = total + 1

            local zoneName = ""
            local zoneOk, zone = pcall(GetJournalQuestZoneInfo, journalIndex)
            if zoneOk and zone and zone ~= "" then
                zoneName = sanitizeText(zone)
            end

            local questEntry = {
                journalIndex = journalIndex,
                questId = safeCall(GetJournalQuestId, journalIndex),
                name = sanitizeText(questName),
                zoneName = zoneName,
                questType = questType,
                isTracked = isQuestTracked(journalIndex),
                isAssisted = isQuestAssisted(journalIndex),
                isComplete = safeCall(IsJournalQuestComplete, journalIndex) == true,
            }

            questEntry.steps = buildSteps(journalIndex)

            quests[#quests + 1] = questEntry
        end
    end

    table.sort(quests, questSortComparator)

    if #quests > MAX_QUESTS then
        for index = #quests, MAX_QUESTS + 1, -1 do
            table.remove(quests, index)
        end
    end

    for index = 1, #quests do
        hashes[#hashes + 1] = computeQuestHash(quests[index])
    end

    local signature = table.concat(hashes, "||")

    return {
        meta = {
            total = total,
            lastUpdated = GetFrameTimeMilliseconds and GetFrameTimeMilliseconds() or GetGameTimeMilliseconds(),
            signature = signature,
        },
        quests = quests,
    }
end

local function notifySubscribers(snapshot)
    for index = 1, #callbacks do
        local cb = callbacks[index]
        if type(cb) == "function" then
            local ok, err = pcall(cb, snapshot)
            if not ok then
                debugLog(string.format("callback error: %s", tostring(err)))
            end
        end
    end

    if M.Publish then
        M.Publish("quests:changed", snapshot)
    elseif M.Core and M.Core.Publish then
        M.Core.Publish("quests:changed", snapshot)
    end
end

local function applySnapshot(snapshot)
    Module._snapshot = snapshot
    Module._signature = snapshot.meta.signature or ""

    notifySubscribers(snapshot)
end

local function refreshSnapshot(force)
    if not Module._initialized then
        return
    end

    Module._refreshQueued = false
    EM:UnregisterForUpdate(REFRESH_HANDLE)

    local snapshot = buildSnapshot()
    if force or snapshot.meta.signature ~= Module._signature then
        debugLog("snapshot updated")
        applySnapshot(snapshot)
    else
        debugLog("snapshot unchanged")
    end
end

local function queueRefresh()
    if Module._refreshQueued then
        return
    end

    Module._refreshQueued = true

    EM:RegisterForUpdate(REFRESH_HANDLE, Module._debounceMs, function()
        refreshSnapshot(false)
    end)
end

local function onQuestEvent()
    queueRefresh()
end

local EVENT_LIST = {
    EVENT_QUEST_ADDED,
    EVENT_QUEST_REMOVED,
    EVENT_QUEST_ADVANCED,
    EVENT_QUEST_CONDITION_COUNTER_CHANGED,
    EVENT_QUEST_LOG_UPDATED,
    EVENT_TRACKING_UPDATE,
}

local function registerEvents()
    for index = 1, #EVENT_LIST do
        local eventId = EVENT_LIST[index]
        EM:RegisterForEvent(EVENT_NAMESPACE, eventId, onQuestEvent)
    end
end

local function unregisterEvents()
    for index = 1, #EVENT_LIST do
        local eventId = EVENT_LIST[index]
        EM:UnregisterForEvent(EVENT_NAMESPACE, eventId)
    end
end

function Module.Init(opts)
    if Module._initialized then
        return
    end

    opts = opts or {}
    Module._debounceMs = tonumber(opts.debounceMs) or DEFAULT_DEBOUNCE_MS
    Module._debug = opts.debug == true

    registerEvents()

    Module._initialized = true

    refreshSnapshot(true)
end

function Module.Shutdown()
    if not Module._initialized then
        return
    end

    unregisterEvents()

    EM:UnregisterForUpdate(REFRESH_HANDLE)
    Module._refreshQueued = false

    Module._initialized = false
    Module._signature = ""
end

function Module.GetSnapshot()
    if not Module._initialized then
        Module.Init()
    end

    return Module._snapshot
end

function Module.Subscribe(callback)
    if type(callback) ~= "function" then
        return
    end

    callbacks[#callbacks + 1] = callback

    callback(Module.GetSnapshot())
end

function Module.Unsubscribe(callback)
    if type(callback) ~= "function" then
        return
    end

    for index = #callbacks, 1, -1 do
        if callbacks[index] == callback then
            table.remove(callbacks, index)
        end
    end
end

function Module.DebugRefresh()
    refreshSnapshot(true)
end

