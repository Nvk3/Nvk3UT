local Runtime = {}

function Runtime:Init()
    self.dirtyFlags = {
        quest = false,
        achievement = false,
        layout = false,
    }

    self.isInCombat = false
    self.isCursorMode = false

    self._isUpdateRegistered = false

    self.PROCESS_INTERVAL_MS = 50
end

function Runtime:QueueDirty(kind)
    kind = kind or "layout"

    if self.dirtyFlags[kind] == nil then
        self.dirtyFlags[kind] = false
    end

    self.dirtyFlags[kind] = true

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerRuntime.QueueDirty(" .. tostring(kind) .. ")")
    end
end

function Runtime:SetCombatState(inCombat)
    if self.isInCombat ~= inCombat then
        self.isInCombat = inCombat
        self:QueueDirty("layout")

        if Nvk3UT and Nvk3UT.Debug then
            Nvk3UT:Debug("TrackerRuntime.SetCombatState(" .. tostring(inCombat) .. ")")
        end
    end
end

function Runtime:SetCursorMode(cursorShown)
    if self.isCursorMode ~= cursorShown then
        self.isCursorMode = cursorShown
        self:QueueDirty("layout")

        if Nvk3UT and Nvk3UT.Debug then
            Nvk3UT:Debug("TrackerRuntime.SetCursorMode(" .. tostring(cursorShown) .. ")")
        end
    end
end

function Runtime:_IsAnythingDirty()
    for _, value in pairs(self.dirtyFlags) do
        if value then
            return true
        end
    end

    return false
end

function Runtime:ProcessFrame()
    if not self:_IsAnythingDirty() then
        return
    end

    local questDirty = self.dirtyFlags.quest
    local achievementDirty = self.dirtyFlags.achievement
    local layoutDirty = self.dirtyFlags.layout

    for key in pairs(self.dirtyFlags) do
        self.dirtyFlags[key] = false
    end

    local questViewModel = nil
    local achievementViewModel = nil

    -- if questDirty then
    --     questViewModel = Nvk3UT.QuestTrackerController:BuildViewModel()
    -- end

    -- if achievementDirty then
    --     achievementViewModel = Nvk3UT.AchievementTrackerController:BuildViewModel()
    -- end

    -- if questDirty and Nvk3UT.QuestTracker then
    --     Nvk3UT.QuestTracker:Refresh(questViewModel)
    -- end

    -- if achievementDirty and Nvk3UT.AchievementTracker then
    --     Nvk3UT.AchievementTracker:Refresh(achievementViewModel)
    -- end

    local needLayout = layoutDirty or questDirty or achievementDirty

    if needLayout then
        local layoutModule = Nvk3UT and Nvk3UT.TrackerHostLayout or nil
        if layoutModule and layoutModule.ApplyLayout then
            if Nvk3UT and Nvk3UT.SafeCall then
                Nvk3UT:SafeCall(function()
                    layoutModule:ApplyLayout()
                end)
            else
                layoutModule:ApplyLayout()
            end
        end
    end

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug(string.format(
            "TrackerRuntime.ProcessFrame q=%s a=%s l=%s",
            tostring(questDirty),
            tostring(achievementDirty),
            tostring(needLayout)
        ))
    end
end

function Runtime:OnPlayerActivated()
    if self._isUpdateRegistered then
        return
    end
    self._isUpdateRegistered = true

    local function tick()
        if Nvk3UT and Nvk3UT.SafeCall then
            Nvk3UT:SafeCall(function()
                self:ProcessFrame()
            end)
        else
            self:ProcessFrame()
        end
    end

    EVENT_MANAGER:RegisterForUpdate("Nvk3UT_TrackerRuntime_ProcessFrame", self.PROCESS_INTERVAL_MS, tick)

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerRuntime.OnPlayerActivated() registered update loop")
    end
end

local addon = Nvk3UT
if not addon then
    error("Nvk3UT_TrackerRuntime loaded before Nvk3UT_Core. Load order is wrong.")
end

addon.TrackerRuntime = Runtime
addon:RegisterModule("TrackerRuntime", Runtime)

return Runtime
