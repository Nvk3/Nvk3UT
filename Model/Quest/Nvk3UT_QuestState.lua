local ADDON = Nvk3UT
local M = ADDON and (ADDON.QuestState or {}) or {}

if ADDON then
    ADDON.QuestState = M
end

local DEFAULTS = {
    expandedCategories = {},
    expandedQuests = {},
    activeQuestId = nil,
    focusedQuestId = nil,
}

local function shallowCopyTable(src)
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = v
    end
    return copy
end

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = shallowCopyTable(v)
            else
                dst[k] = v
            end
        end
    end
end

local function normalizeQuestKey(value)
    if value == nil then
        return nil
    end

    if type(value) == "number" then
        if value > 0 then
            return tostring(value)
        end
        return nil
    end

    if type(value) == "string" then
        local numeric = tonumber(value)
        if numeric and numeric > 0 then
            return tostring(numeric)
        end
        if value ~= "" then
            return value
        end
        return nil
    end

    return tostring(value)
end

local function normalizeCategoryKey(value)
    if value == nil then
        return nil
    end

    if type(value) == "string" then
        if value ~= "" then
            return value
        end
        return nil
    end

    if type(value) == "number" then
        return tostring(value)
    end

    return tostring(value)
end

local function migrateLegacyState(self, sv)
    local legacy = sv and sv.QuestTracker
    if type(legacy) ~= "table" then
        return
    end

    local questState = self.db
    if type(questState) ~= "table" then
        return
    end

    local migratedAny = false

    local function adoptCategoryEntry(key, entry)
        local expanded
        if type(entry) == "table" then
            if entry.expanded ~= nil then
                expanded = entry.expanded == true
            end
        elseif entry ~= nil then
            expanded = entry == true
        end

        if expanded ~= nil then
            questState.expandedCategories[key] = expanded and true or nil
            migratedAny = true
        end
    end

    local function adoptQuestEntry(key, entry)
        local expanded
        if type(entry) == "table" then
            if entry.expanded ~= nil then
                expanded = entry.expanded == true
            end
        elseif entry ~= nil then
            expanded = entry == true
        end

        if expanded ~= nil then
            questState.expandedQuests[key] = expanded and true or nil
            migratedAny = true
        end
    end

    if type(legacy.cat) == "table" then
        for key, entry in pairs(legacy.cat) do
            local normalized = normalizeCategoryKey(key)
            if normalized then
                adoptCategoryEntry(normalized, entry)
            end
        end
    end

    if type(legacy.quest) == "table" then
        for key, entry in pairs(legacy.quest) do
            local normalized = normalizeQuestKey(key)
            if normalized then
                adoptQuestEntry(normalized, entry)
            end
        end
    end

    if type(legacy.catExpanded) == "table" then
        for key, value in pairs(legacy.catExpanded) do
            local normalized = normalizeCategoryKey(key)
            if normalized then
                questState.expandedCategories[normalized] = value and true or nil
                migratedAny = true
            end
        end
        legacy.catExpanded = nil
    end

    if type(legacy.questExpanded) == "table" then
        for key, value in pairs(legacy.questExpanded) do
            local normalized = normalizeQuestKey(key)
            if normalized then
                questState.expandedQuests[normalized] = value and true or nil
                migratedAny = true
            end
        end
        legacy.questExpanded = nil
    end

    if type(legacy.active) == "table" and legacy.active.questKey ~= nil then
        local normalized = normalizeQuestKey(legacy.active.questKey)
        if normalized then
            questState.activeQuestId = questState.activeQuestId or normalized
            migratedAny = true
        end
    end

    if type(legacy.focusedQuestId) ~= "nil" then
        local normalized = normalizeQuestKey(legacy.focusedQuestId)
        if normalized or legacy.focusedQuestId == nil then
            questState.focusedQuestId = questState.focusedQuestId or normalized
            migratedAny = true
        end
    end

    if migratedAny and ADDON and ADDON.Debug then
        ADDON:Debug("QuestState: Migrated legacy quest tracker state")
    end
end

function M:Init()
    local sv = ADDON and ADDON.SV
    if not sv then
        if ADDON and ADDON.Debug then
            ADDON:Debug("QuestState:Init before SV; deferring to first use.")
        end
        return
    end

    sv.QuestState = sv.QuestState or {}
    applyDefaults(sv.QuestState, DEFAULTS)
    self.db = sv.QuestState

    migrateLegacyState(self, sv)
end

function M:GetActiveQuestId()
    return self.db and self.db.activeQuestId or nil
end

function M:SetActiveQuestId(id)
    if not self.db then
        return
    end
    if id ~= nil then
        id = normalizeQuestKey(id)
    end
    self.db.activeQuestId = id
end

function M:GetFocusedQuestId()
    return self.db and self.db.focusedQuestId or nil
end

function M:SetFocusedQuestId(id)
    if not self.db then
        return
    end
    if id ~= nil then
        id = normalizeQuestKey(id)
    end
    self.db.focusedQuestId = id
end

function M:IsCategoryExpanded(key)
    if not self.db then
        return false
    end

    local normalized = normalizeCategoryKey(key)
    if not normalized then
        return false
    end

    return self.db.expandedCategories[normalized] == true
end

function M:SetCategoryExpanded(key, expanded)
    if not self.db then
        return
    end

    local normalized = normalizeCategoryKey(key)
    if not normalized then
        return
    end

    if expanded then
        self.db.expandedCategories[normalized] = true
    else
        self.db.expandedCategories[normalized] = nil
    end
end

function M:ToggleCategoryExpanded(key)
    local newValue = not self:IsCategoryExpanded(key)
    self:SetCategoryExpanded(key, newValue)
    return self:IsCategoryExpanded(key)
end

function M:IsQuestExpanded(qKey)
    if not self.db then
        return false
    end

    local normalized = normalizeQuestKey(qKey)
    if not normalized then
        return false
    end

    return self.db.expandedQuests[normalized] == true
end

function M:SetQuestExpanded(qKey, expanded)
    if not self.db then
        return
    end

    local normalized = normalizeQuestKey(qKey)
    if not normalized then
        return
    end

    if expanded then
        self.db.expandedQuests[normalized] = true
    else
        self.db.expandedQuests[normalized] = nil
    end
end

function M:ToggleQuestExpanded(qKey)
    local newValue = not self:IsQuestExpanded(qKey)
    self:SetQuestExpanded(qKey, newValue)
    return self:IsQuestExpanded(qKey)
end

function M:OnQuestRemoved(qKey)
    if not self.db then
        return
    end

    local normalized = normalizeQuestKey(qKey)
    if not normalized then
        return
    end

    self.db.expandedQuests[normalized] = nil
    if self.db.activeQuestId == normalized then
        self.db.activeQuestId = nil
    end
    if self.db.focusedQuestId == normalized then
        self.db.focusedQuestId = nil
    end

    local addon = ADDON
    if addon and addon.sv then
        local tracker = addon.sv.QuestTracker
        if type(tracker) == "table" and type(tracker.quest) == "table" then
            tracker.quest[normalized] = nil
        end
    end
end

if ADDON and ADDON.RegisterModule then
    ADDON:RegisterModule("QuestState", function()
        if type(M.Init) == "function" then
            M:Init()
        end
    end)
end

return M
