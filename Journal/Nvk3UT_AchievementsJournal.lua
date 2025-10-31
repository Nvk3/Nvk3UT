Nvk3UT = Nvk3UT or {}

local Journal = {}
Nvk3UT.AchievementsJournal = Journal

local Utils = Nvk3UT and Nvk3UT.Utils

local state = {
    parent = nil,
}

local function isDebugEnabled()
    return Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and Utils and Utils.d
end

local function buildCriteriaSnapshot(achievementId)
    if type(GetAchievementNumCriteria) ~= "function" or type(GetAchievementCriterion) ~= "function" then
        return nil
    end

    local okCount, total = pcall(GetAchievementNumCriteria, achievementId)
    if not okCount or type(total) ~= "number" or total < 0 then
        return nil
    end

    if total == 0 then
        return { total = 0, completed = 0, allComplete = false }
    end

    local completed = 0
    for index = 1, total do
        local okCrit, _, numCompleted, numRequired = pcall(GetAchievementCriterion, achievementId, index)
        if okCrit then
            local completedValue = tonumber(numCompleted) or 0
            local requiredValue = tonumber(numRequired) or 0
            local achieved
            if requiredValue > 0 then
                achieved = completedValue >= requiredValue
            else
                achieved = completedValue > 0
            end
            if achieved then
                completed = completed + 1
            end
        else
            return { total = total, completed = completed, allComplete = false }
        end
    end

    return {
        total = total,
        completed = completed,
        allComplete = (completed >= total and total > 0),
    }
end

local function ensureCompletionFromInfo(achievementId)
    if type(GetAchievementInfo) ~= "function" then
        return false
    end
    local okInfo, _, _, _, completed = pcall(GetAchievementInfo, achievementId)
    if not okInfo then
        return false
    end
    return completed == true
end

---Initialize the journal view host reference.
---@param parentOrSceneFragment any
function Journal:Init(parentOrSceneFragment)
    state.parent = parentOrSceneFragment
    return parentOrSceneFragment
end

---Refresh the journal view.
---@return any
function Journal:Refresh()
    return state.parent
end

---Determine whether an achievement is fully complete, including multi-stage chains.
---@param achievementId number
---@return boolean
function Journal.IsComplete(achievementId)
    if type(achievementId) ~= "number" then
        return false
    end

    local helper = _G.Nvk3UT_MultiStage
    local helperResult
    if helper and type(helper.IsMultiStageComplete) == "function" then
        local okHelper, result = pcall(helper.IsMultiStageComplete, achievementId, false)
        if okHelper then
            helperResult = result
        end
    end

    local snapshot = buildCriteriaSnapshot(achievementId)
    local resolved

    if type(helperResult) == "boolean" then
        resolved = helperResult
    elseif helper and type(helper.GetMultiStageProgress) == "function" then
        local okProgress, progress = pcall(helper.GetMultiStageProgress, achievementId)
        if okProgress and type(progress) == "table" then
            local total = tonumber(progress.total) or tonumber(progress.totalStages)
            local done = tonumber(progress.completed) or tonumber(progress.completedStages)
            if total and done and total > 0 then
                snapshot = snapshot or { total = total, completed = done }
                snapshot.total = total
                snapshot.completed = done
                snapshot.allComplete = done >= total
                resolved = snapshot.allComplete
            end
        end
    end

    if resolved == nil then
        if snapshot and snapshot.total > 0 then
            resolved = snapshot.allComplete == true
        else
            resolved = ensureCompletionFromInfo(achievementId)
        end
    end

    if snapshot and snapshot.total == 0 then
        snapshot.completed = resolved and 1 or 0
    end

    if isDebugEnabled() then
        local total = snapshot and snapshot.total or 0
        local completed = snapshot and snapshot.completed or (resolved and total) or 0
        Utils.d(string.format("[Ach] %d complete=%s (stages %d/%d)", achievementId, tostring(resolved == true), completed, total))
    end

    return resolved == true
end

return Journal
