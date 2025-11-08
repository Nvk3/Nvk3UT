Nvk3UT = Nvk3UT or {}

local Repo = {}
Nvk3UT.StateRepo_Quests = Repo
Nvk3UT_StateRepo_Quests = Repo

local FLAG_BOOLEAN_KEYS = {
    tracked = true,
    assisted = true,
    isDaily = true,
}

local state = {
    addon = nil,
    character = nil,
    quests = nil,
    questState = nil,
    zones = nil,
    questsCollapsed = nil,
    flags = nil,
}

local function getAddon()
    if state.addon then
        return state.addon
    end

    if Nvk3UT then
        state.addon = Nvk3UT
        return state.addon
    end

    return nil
end

local function isDebugEnabled()
    local addon = getAddon()
    if not addon then
        return false
    end

    if addon.IsDebugEnabled then
        return addon:IsDebugEnabled() == true
    end

    return addon.debugEnabled == true
end

local function debugLog(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local addon = getAddon()
    if addon and addon.Debug then
        addon.Debug("[StateRepo.Quests] " .. tostring(fmt), ...)
        return
    end

    if d then
        local ok, message = pcall(string.format, tostring(fmt), ...)
        if not ok then
            message = tostring(fmt)
        end
        d(string.format("[Nvk3UT][StateRepo.Quests] %s", message))
    end
end

local function normalizeKey(value)
    if value == nil then
        return nil
    end

    local numeric = tonumber(value)
    if not numeric then
        return nil
    end

    numeric = math.floor(numeric + 0.5)
    if numeric <= 0 then
        return nil
    end

    return numeric
end

local function normalizeZoneKey(value)
    if value == nil then
        return nil
    end

    if type(value) == "table" then
        if value.key ~= nil then
            return normalizeZoneKey(value.key)
        end
        if value.categoryKey ~= nil then
            return normalizeZoneKey(value.categoryKey)
        end
        if value.zoneKey ~= nil then
            return normalizeZoneKey(value.zoneKey)
        end
        return nil
    end

    if type(value) == "string" then
        local trimmed = value:match("^%s*(.-)%s*$") or ""
        if trimmed == "" then
            return nil
        end
        return trimmed
    end

    if type(value) == "number" then
        if value ~= value then
            return nil
        end
        local rounded = math.floor(value + 0.5)
        if rounded <= 0 then
            return nil
        end
        return tostring(rounded)
    end

    local numeric = tonumber(value)
    if numeric then
        local rounded = math.floor(numeric + 0.5)
        if rounded <= 0 then
            return nil
        end
        return tostring(rounded)
    end

    return nil
end

local function ensureCharacter()
    if type(state.character) == "table" then
        return state.character
    end

    local addon = getAddon()
    if not addon then
        return nil
    end

    local character = addon.SVCharacter or addon.svCharacter
    if type(character) ~= "table" then
        return nil
    end

    state.character = character
    return character
end

local function ensureQuestsRoot(create)
    local character = ensureCharacter()
    if type(character) ~= "table" then
        return nil
    end

    local quests = state.quests
    if type(quests) ~= "table" then
        quests = character.quests
        if type(quests) ~= "table" then
            if not create then
                return nil
            end
            quests = {}
            character.quests = quests
        end
        state.quests = quests
    end

    return quests
end

local function ensureQuestState(create)
    local quests = ensureQuestsRoot(create)
    if type(quests) ~= "table" then
        return nil
    end

    local questState = state.questState
    if type(questState) ~= "table" then
        questState = quests.state
        if type(questState) ~= "table" then
            if not create then
                return nil
            end
            questState = {}
            quests.state = questState
        end
        state.questState = questState
    end

    return questState
end

local function ensureZones(create)
    local questState = ensureQuestState(create)
    if type(questState) ~= "table" then
        return nil
    end

    local zones = state.zones
    if type(zones) ~= "table" then
        zones = questState.zones
        if type(zones) ~= "table" then
            if not create then
                return nil
            end
            zones = {}
            questState.zones = zones
        end
        state.zones = zones
    end

    return zones
end

local function ensureQuestCollapses(create)
    local questState = ensureQuestState(create)
    if type(questState) ~= "table" then
        return nil
    end

    local questsCollapsed = state.questsCollapsed
    if type(questsCollapsed) ~= "table" then
        questsCollapsed = questState.quests
        if type(questsCollapsed) ~= "table" then
            if not create then
                return nil
            end
            questsCollapsed = {}
            questState.quests = questsCollapsed
        end
        state.questsCollapsed = questsCollapsed
    end

    return questsCollapsed
end

local function ensureFlags(create)
    local quests = ensureQuestsRoot(create)
    if type(quests) ~= "table" then
        return nil
    end

    local flags = state.flags
    if type(flags) ~= "table" then
        flags = quests.flags
        if type(flags) ~= "table" then
            if not create then
                return nil
            end
            flags = {}
            quests.flags = flags
        end
        state.flags = flags
    end

    return flags
end

local function pruneEmpty()
    local questState = state.questState
    if type(questState) == "table" then
        local zones = state.zones
        if type(zones) == "table" and next(zones) == nil then
            questState.zones = nil
            state.zones = nil
        end

        local questsCollapsed = state.questsCollapsed
        if type(questsCollapsed) == "table" and next(questsCollapsed) == nil then
            questState.quests = nil
            state.questsCollapsed = nil
        end

        if next(questState) == nil then
            local quests = state.quests
            if type(quests) == "table" and quests.state == questState then
                quests.state = nil
            end
            state.questState = nil
        end
    end

    local flags = state.flags
    if type(flags) == "table" and next(flags) == nil then
        local quests = state.quests
        if type(quests) == "table" and quests.flags == flags then
            quests.flags = nil
        end
        state.flags = nil
    end

    local quests = state.quests
    if type(quests) == "table" and next(quests) == nil then
        local character = ensureCharacter()
        if type(character) == "table" and character.quests == quests then
            character.quests = nil
        end
        state.quests = nil
    end
end

local function sanitizeFlags(flags)
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

    local categoryKey = normalizeKey(flags.categoryKey)
    if categoryKey then
        entry.categoryKey = categoryKey
    end

    local journalIndex = normalizeKey(flags.journalIndex)
    if journalIndex then
        entry.journalIndex = journalIndex
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

local function copyFlagDefaults(source)
    local result = {
        tracked = false,
        assisted = false,
        isDaily = false,
        categoryKey = nil,
        journalIndex = nil,
    }

    if type(source) == "table" then
        for key, value in pairs(source) do
            if FLAG_BOOLEAN_KEYS[key] then
                result[key] = value == true
            elseif key == "categoryKey" or key == "journalIndex" then
                result[key] = value
            end
        end
    end

    return result
end

function Repo.Q_IsZoneCollapsed(zoneKey)
    local normalized = normalizeZoneKey(zoneKey)
    if not normalized then
        debugLog("Repo.Q_IsZoneCollapsed key=nil (source=%s) -> false", tostring(zoneKey))
        return false
    end

    local zones = ensureZones(false)
    local collapsed = false
    if zones then
        collapsed = zones[normalized] == true
        if not collapsed then
            local numericFallback = tonumber(normalized)
            if numericFallback then
                collapsed = zones[numericFallback] == true
            end
        end
    end

    debugLog("Repo.Q_IsZoneCollapsed key=%s -> %s", tostring(normalized), tostring(collapsed))
    return collapsed
end

function Repo.Q_SetZoneCollapsed(zoneKey, collapsed)
    local normalized = normalizeZoneKey(zoneKey)
    if not normalized then
        debugLog(
            "Repo.Q_SetZoneCollapsed key=nil (source=%s) collapsed=%s -> false",
            tostring(zoneKey),
            tostring(collapsed)
        )
        return false
    end

    debugLog(
        "Repo.Q_SetZoneCollapsed key=%s collapsed=%s",
        tostring(normalized),
        tostring(collapsed)
    )

    if collapsed then
        local zones = ensureZones(true)
        if not zones then
            return false
        end

        if zones[normalized] == true then
            return false
        end

        zones[normalized] = true
        local numericFallback = tonumber(normalized)
        if numericFallback then
            zones[numericFallback] = nil
        end
        return true
    end

    local zones = ensureZones(false)
    if not zones then
        return false
    end

    local removed = false
    if zones[normalized] ~= nil then
        zones[normalized] = nil
        removed = true
    end

    local numericFallback = tonumber(normalized)
    if numericFallback and zones[numericFallback] ~= nil then
        zones[numericFallback] = nil
        removed = true
    end

    if not removed then
        return false
    end

    pruneEmpty()
    return true
end

function Repo.Q_IsQuestCollapsed(questId)
    local normalized = normalizeKey(questId)
    if not normalized then
        return false
    end

    local questsCollapsed = ensureQuestCollapses(false)
    if not questsCollapsed then
        return false
    end

    return questsCollapsed[normalized] == true
end

function Repo.Q_SetQuestCollapsed(questId, collapsed)
    local normalized = normalizeKey(questId)
    if not normalized then
        return false
    end

    if collapsed then
        local questsCollapsed = ensureQuestCollapses(true)
        if not questsCollapsed then
            return false
        end

        if questsCollapsed[normalized] == true then
            return false
        end

        questsCollapsed[normalized] = true
        debugLog("Quest %d collapsed", normalized)
        return true
    end

    local questsCollapsed = ensureQuestCollapses(false)
    if not questsCollapsed or questsCollapsed[normalized] == nil then
        return false
    end

    questsCollapsed[normalized] = nil
    pruneEmpty()
    debugLog("Quest %d expanded (trimmed)", normalized)
    return true
end

function Repo.Q_GetFlags(questId)
    local normalized = normalizeKey(questId)
    if not normalized then
        return copyFlagDefaults()
    end

    local flags = ensureFlags(false)
    local entry = flags and flags[normalized] or nil

    return copyFlagDefaults(entry)
end

function Repo.Q_SetFlags(questId, flags)
    local normalized = normalizeKey(questId)
    if not normalized then
        return false
    end

    local sanitized = sanitizeFlags(flags)
    local storage = ensureFlags(sanitized ~= nil)

    if not sanitized then
        if not (storage and storage[normalized]) then
            return false
        end

        storage[normalized] = nil
        pruneEmpty()
        debugLog("Quest %d flags cleared", normalized)
        return true
    end

    storage = storage or ensureFlags(true)
    local previous = storage and storage[normalized]
    if previous and flagsEqual(previous, sanitized) then
        return false
    end

    storage[normalized] = sanitized
    debugLog("Quest %d flags persisted", normalized)
    return true
end

function Repo.Q_PruneFlags(valid)
    local flags = ensureFlags(false)
    if not flags then
        return 0
    end

    if type(valid) ~= "table" then
        local removed = 0
        for key in pairs(flags) do
            flags[key] = nil
            removed = removed + 1
        end
        if removed > 0 then
            pruneEmpty()
        end
        return removed
    end

    local removed = 0
    for key in pairs(flags) do
        local keep = false
        if valid[key] or valid[tostring(key)] then
            keep = true
        end
        if not keep then
            flags[key] = nil
            removed = removed + 1
        end
    end

    if removed > 0 then
        pruneEmpty()
    end

    return removed
end

function Repo.Init(characterSaved)
    getAddon()

    if type(characterSaved) == "table" then
        state.character = characterSaved
    else
        state.character = ensureCharacter()
    end

    state.quests = nil
    state.questState = nil
    state.zones = nil
    state.questsCollapsed = nil
    state.flags = nil

    local quests = ensureQuestsRoot(false)
    if type(quests) == "table" then
        state.quests = quests
        if type(quests.state) == "table" then
            state.questState = quests.state
            if type(quests.state.zones) == "table" then
                state.zones = quests.state.zones
            end
            if type(quests.state.quests) == "table" then
                state.questsCollapsed = quests.state.quests
            end
        end
        if type(quests.flags) == "table" then
            state.flags = quests.flags
        end
    end

    pruneEmpty()
    debugLog("Quest state repository initialised")
end

function Repo.AttachToRoot(addon)
    if type(addon) ~= "table" then
        return
    end

    state.addon = addon
    addon.QuestRepo = Repo
end

return Repo
