local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}
Nvk3UT.QuestFilter = Nvk3UT.QuestFilter or {}

local QuestFilter = Nvk3UT.QuestFilter

local DEFAULT_MODE = 1
local ACTIVE_ONLY_CATEGORY_KEY = "ACTIVE_ONLY"

local function NormalizeQuestKey(questKey)
    local questState = Nvk3UT and Nvk3UT.QuestState
    if questState and questState.NormalizeQuestKey then
        return questState.NormalizeQuestKey(questKey)
    end

    if questKey == nil then
        return nil
    end

    if type(questKey) == "string" then
        local numeric = tonumber(questKey)
        if numeric and numeric > 0 then
            return tostring(numeric)
        end
        return questKey
    end

    if type(questKey) == "number" then
        if questKey > 0 then
            return tostring(questKey)
        end
        return nil
    end

    return tostring(questKey)
end

local function copyCategories(snapshot)
    local copy = {}
    if type(snapshot) == "table" then
        for key, value in pairs(snapshot) do
            if key ~= "categories" then
                copy[key] = value
            end
        end
    end

    copy.categories = {
        ordered = {},
        byKey = {},
    }

    return copy
end

function QuestFilter.EnsureSaved(addon)
    local addonTable = addon or Nvk3UT
    if type(addonTable) ~= "table" then
        return nil
    end

    local root = addonTable.SV
    if type(root) ~= "table" then
        return nil
    end

    local questFilter = root.questFilter
    if type(questFilter) ~= "table" then
        questFilter = {}
        root.questFilter = questFilter
    end

    if questFilter.mode == nil then
        questFilter.mode = DEFAULT_MODE
    end

    if type(questFilter.selection) ~= "table" then
        questFilter.selection = {}
    end

    return questFilter
end

function QuestFilter.GetMode(questFilter)
    if type(questFilter) ~= "table" then
        return DEFAULT_MODE
    end

    local numeric = tonumber(questFilter.mode)
    if numeric == 2 or numeric == 3 then
        return numeric
    end

    return DEFAULT_MODE
end

function QuestFilter.SetMode(questFilter, mode)
    if type(questFilter) ~= "table" then
        return DEFAULT_MODE
    end

    local numeric = tonumber(mode)
    if numeric ~= 2 and numeric ~= 3 then
        numeric = DEFAULT_MODE
    end

    questFilter.mode = numeric
    return numeric
end

function QuestFilter.IsQuestSelected(questFilter, questKey)
    if type(questFilter) ~= "table" then
        return false
    end

    local normalized = NormalizeQuestKey(questKey)
    if not normalized then
        return false
    end

    local selection = questFilter.selection
    if type(selection) ~= "table" then
        return false
    end

    return selection[normalized] == true
end

function QuestFilter.ToggleSelection(questFilter, questKey)
    if type(questFilter) ~= "table" then
        return false, nil
    end

    local normalized = NormalizeQuestKey(questKey)
    if not normalized then
        return false, nil
    end

    questFilter.selection = questFilter.selection or {}
    local currentlySelected = questFilter.selection[normalized] == true

    if currentlySelected then
        questFilter.selection[normalized] = nil
        return true, normalized, false
    end

    questFilter.selection[normalized] = true
    return true, normalized, true
end

local function findQuestByKey(categories, questKey)
    if type(categories) ~= "table" then
        return nil, nil
    end

    for index = 1, #categories do
        local category = categories[index]
        if category and type(category.quests) == "table" then
            for questIndex = 1, #category.quests do
                local quest = category.quests[questIndex]
                local normalized = NormalizeQuestKey(quest and quest.journalIndex)
                if normalized and normalized == questKey then
                    return quest, category
                end
            end
        end
    end

    return nil, nil
end

local function buildActiveOnlySnapshot(rawSnapshot, activeQuestKey, activeCategoryName)
    local normalizedActive = NormalizeQuestKey(activeQuestKey)
    if not normalizedActive then
        return copyCategories(rawSnapshot)
    end

    local baseCategories = (rawSnapshot and rawSnapshot.categories and rawSnapshot.categories.ordered)
        or {}
    local quest, category = findQuestByKey(baseCategories, normalizedActive)
    if not quest then
        return copyCategories(rawSnapshot)
    end

    local snapshot = copyCategories(rawSnapshot)
    local name = activeCategoryName or "Quests"
    local categoryCopy = {
        id = ACTIVE_ONLY_CATEGORY_KEY,
        categoryKey = ACTIVE_ONLY_CATEGORY_KEY,
        name = name,
        quests = { quest },
    }

    snapshot.categories.ordered[1] = categoryCopy
    snapshot.categories.byKey[ACTIVE_ONLY_CATEGORY_KEY] = categoryCopy

    return snapshot
end

local function appendSelectionCategory(snapshot, sourceCategory, quests)
    if #quests == 0 then
        return
    end

    local categoryCopy = {}
    for key, value in pairs(sourceCategory) do
        if key ~= "quests" then
            categoryCopy[key] = value
        end
    end

    categoryCopy.quests = quests

    local ordered = snapshot.categories.ordered
    ordered[#ordered + 1] = categoryCopy

    local categoryKey = categoryCopy.categoryKey or categoryCopy.id
    if categoryKey then
        snapshot.categories.byKey[categoryKey] = categoryCopy
    end
end

local function buildSelectionSnapshot(rawSnapshot, selection)
    local snapshot = copyCategories(rawSnapshot)

    local categories = rawSnapshot and rawSnapshot.categories and rawSnapshot.categories.ordered
    if type(categories) ~= "table" then
        return snapshot
    end

    local selectionMap = type(selection) == "table" and selection or {}

    for index = 1, #categories do
        local category = categories[index]
        local filteredQuests = {}

        if category and type(category.quests) == "table" then
            for questIndex = 1, #category.quests do
                local quest = category.quests[questIndex]
                local normalized = NormalizeQuestKey(quest and quest.journalIndex)
                if normalized and selectionMap[normalized] == true then
                    filteredQuests[#filteredQuests + 1] = quest
                end
            end
        end

        appendSelectionCategory(snapshot, category, filteredQuests)
    end

    return snapshot
end

function QuestFilter.ApplyFilter(rawSnapshot, mode, selection, activeQuestKey, activeCategoryName)
    local snapshot = rawSnapshot or { categories = { ordered = {}, byKey = {} } }
    local filterMode = tonumber(mode) or DEFAULT_MODE

    if filterMode ~= 2 and filterMode ~= 3 then
        return snapshot
    end

    if filterMode == 2 then
        return buildActiveOnlySnapshot(snapshot, activeQuestKey, activeCategoryName)
    end

    return buildSelectionSnapshot(snapshot, selection)
end

return QuestFilter
