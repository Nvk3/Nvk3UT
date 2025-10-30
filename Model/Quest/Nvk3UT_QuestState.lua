local addon = Nvk3UT
local M = {}
addon.QuestState = M

function M:Init(db)
    self.db = db
    self.sv = db.QuestState or {}
    if addon.Diagnostics and addon.Diagnostics.Debug then
        addon.Diagnostics:Debug("QuestState.Init() ok")
    end
end

function M:GetWindowPosition()
    local w = self.sv.window or {}
    return w.x, w.y
end

function M:SetWindowPosition(x, y)
    local w = self.sv.window
    if type(w) ~= "table" then
        return
    end

    if type(x) == "number" and type(y) == "number" then
        w.x, w.y = x, y
    end
end

function M:IsWindowLocked()
    local w = self.sv.window
    return type(w) == "table" and w.locked == true
end

function M:SetWindowLocked(locked)
    local w = self.sv.window
    if type(w) ~= "table" then
        return
    end

    self.sv.window.locked = locked and true or false
end

function M:IsQuestExpanded(questId)
    local quests = self.sv.expanded and self.sv.expanded.quests
    return type(quests) == "table" and quests[questId] == true
end

function M:SetQuestExpanded(questId, expanded, source)
    local expandedMap = self.sv.expanded and self.sv.expanded.quests
    local tsMap = self.sv.expanded and self.sv.expanded.quests_ts
    if type(expandedMap) ~= "table" or type(tsMap) ~= "table" then
        return
    end

    expandedMap[questId] = (expanded and true) or false
    tsMap[questId] = GetTimeStamp()

    if addon.Diagnostics and addon.Diagnostics.Debug then
        addon.Diagnostics:Debug(("QuestState: qid=%s expanded=%s src=%s"):format(
            tostring(questId),
            tostring(expanded),
            tostring(source)
        ))
    end
end

function M:PruneUnknownQuests(validQuestIdsSet)
    local expandedMap = self.sv.expanded and self.sv.expanded.quests
    local tsMap = self.sv.expanded and self.sv.expanded.quests_ts
    if type(expandedMap) ~= "table" or type(tsMap) ~= "table" then
        return
    end

    if type(validQuestIdsSet) ~= "table" then
        return
    end

    for questId in pairs(expandedMap) do
        if not validQuestIdsSet[questId] then
            expandedMap[questId] = nil
            tsMap[questId] = nil
        end
    end
end

function M:IsCategoryExpanded(categoryKey)
    local categories = self.sv.expanded and self.sv.expanded.categories
    return type(categories) == "table" and categories[categoryKey] == true
end

function M:SetCategoryExpanded(categoryKey, expanded, source)
    local categories = self.sv.expanded and self.sv.expanded.categories
    local tsMap = self.sv.expanded and self.sv.expanded.categories_ts
    if type(categories) ~= "table" or type(tsMap) ~= "table" then
        return
    end

    categories[categoryKey] = (expanded and true) or false
    tsMap[categoryKey] = GetTimeStamp()

    if addon.Diagnostics and addon.Diagnostics.Debug then
        addon.Diagnostics:Debug(("QuestState: cat=%s expanded=%s src=%s"):format(
            tostring(categoryKey),
            tostring(expanded),
            tostring(source)
        ))
    end
end

function M:ResetAll()
    local window = self.sv.window
    local expanded = self.sv.expanded
    if type(window) ~= "table" or type(expanded) ~= "table" then
        return
    end

    window.x, window.y = 100, 100
    window.locked = false

    expanded.quests = {}
    expanded.quests_ts = {}
    expanded.categories = {}
    expanded.categories_ts = {}
end

return M
