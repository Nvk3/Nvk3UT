local ADDON = Nvk3UT
local M = ADDON and (ADDON.QuestSelection or {}) or {}

if ADDON then
    ADDON.QuestSelection = M
end

local DEFAULTS = {
    activeQuestId = nil,
    focusedQuestId = nil,
    lastReason = nil,
    lastChangedAt = nil,
}

local function shallowFill(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return
    end

    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
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

local function now()
    if type(GetTimeStamp) == "function" then
        local ok, ts = pcall(GetTimeStamp)
        if ok then
            return ts
        end
    end

    if type(os) == "table" and type(os.time) == "function" then
        local ok, ts = pcall(os.time)
        if ok then
            return ts
        end
    end

    return nil
end

local function migrateFromQuestState(self, sv)
    if type(self) ~= "table" or type(sv) ~= "table" then
        return
    end

    local questState = sv.QuestState
    if type(questState) ~= "table" then
        return
    end

    local moved = false

    if self.db.activeQuestId == nil and questState.activeQuestId ~= nil then
        local normalized = normalizeQuestKey(questState.activeQuestId)
        self.db.activeQuestId = normalized
        questState.activeQuestId = nil
        moved = moved or normalized ~= nil
    end

    if self.db.focusedQuestId == nil and questState.focusedQuestId ~= nil then
        local normalized = normalizeQuestKey(questState.focusedQuestId)
        self.db.focusedQuestId = normalized
        questState.focusedQuestId = nil
        moved = moved or normalized ~= nil
    end

    if moved then
        self.db.lastReason = self.db.lastReason or "migration"
        self.db.lastChangedAt = self.db.lastChangedAt or now()
        if ADDON and ADDON.Debug then
            ADDON:Debug("QuestSelection: migrated active/focused from QuestState.")
        end
    end
end

local function migrateLegacyTracker(self, sv)
    if type(self) ~= "table" or type(sv) ~= "table" then
        return
    end

    local legacy = sv.QuestTracker
    if type(legacy) ~= "table" then
        return
    end

    local changed = false

    if self.db.activeQuestId == nil and type(legacy.active) == "table" and legacy.active.questKey ~= nil then
        local normalized = normalizeQuestKey(legacy.active.questKey)
        if normalized ~= nil then
            self.db.activeQuestId = normalized
            changed = true
        end
    end

    if self.db.focusedQuestId == nil and legacy.focusedQuestId ~= nil then
        local normalized = normalizeQuestKey(legacy.focusedQuestId)
        if normalized ~= nil or legacy.focusedQuestId == nil then
            self.db.focusedQuestId = normalized
            changed = true
        end
    end

    if changed then
        self.db.lastReason = self.db.lastReason or "legacy"
        self.db.lastChangedAt = self.db.lastChangedAt or now()
        if ADDON and ADDON.Debug then
            ADDON:Debug("QuestSelection: adopted legacy tracker selection state.")
        end
    end
end

function M:Init()
    local sv = ADDON and ADDON.SV
    if not sv then
        if ADDON and ADDON.Debug then
            ADDON:Debug("QuestSelection:Init before SV; will init on first use.")
        end
        return
    end

    sv.QuestSelection = sv.QuestSelection or {}
    shallowFill(sv.QuestSelection, DEFAULTS)
    self.db = sv.QuestSelection

    migrateFromQuestState(self, sv)
    migrateLegacyTracker(self, sv)
end

function M:GetActiveQuestId()
    return self.db and self.db.activeQuestId or nil
end

function M:GetFocusedQuestId()
    return self.db and self.db.focusedQuestId or nil
end

function M:SetActiveQuestId(id, reason)
    if not self.db then
        return
    end

    if id == nil then
        self:ClearActive(reason)
        return
    end

    self.db.activeQuestId = normalizeQuestKey(id)
    self.db.lastReason = reason
    self.db.lastChangedAt = now()
end

function M:ClearActive(reason)
    if not self.db then
        return
    end

    self.db.activeQuestId = nil
    self.db.lastReason = reason
    self.db.lastChangedAt = now()
end

function M:SetFocusedQuestId(id, reason)
    if not self.db then
        return
    end

    self.db.focusedQuestId = normalizeQuestKey(id)
    self.db.lastReason = reason
    self.db.lastChangedAt = now()
end

function M:OnQuestRemoved(questKey, reason)
    if not self.db then
        return
    end

    local normalized = normalizeQuestKey(questKey)
    if not normalized then
        return
    end

    local changed = false
    if self.db.activeQuestId == normalized then
        self.db.activeQuestId = nil
        changed = true
    end

    if self.db.focusedQuestId == normalized then
        self.db.focusedQuestId = nil
        changed = true
    end

    if changed then
        self.db.lastReason = reason or "removed"
        self.db.lastChangedAt = now()
    end
end

if ADDON and ADDON.RegisterModule then
    ADDON:RegisterModule("QuestSelection", function()
        if type(M.Init) == "function" then
            M:Init()
        end
    end)
end

return M
