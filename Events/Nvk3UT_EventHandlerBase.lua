-- Events/Nvk3UT_EventHandlerBase.lua
local EventHandlerBase = {}

-------------------------------------------------
-- Init / lifecycle
-------------------------------------------------

function EventHandlerBase:Init()
    self._eventsRegistered = self._eventsRegistered or false

    self.addon = Nvk3UT
    self.host = Nvk3UT and Nvk3UT.TrackerHost or nil
    self.runtime = Nvk3UT and Nvk3UT.TrackerRuntime or nil

    self:RegisterAllCallbacks()
end

function EventHandlerBase:OnPlayerActivated()
    local addon = self.addon or Nvk3UT
    if addon ~= self.addon then
        self.addon = addon
    end

    local host = addon and addon.TrackerHost or self.host
    if host ~= self.host then
        self.host = host
    end

    local runtime = addon and addon.TrackerRuntime or self.runtime
    if runtime ~= self.runtime then
        self.runtime = runtime
    end

    if host and host.EnsureWindow then
        host:EnsureWindow()
    end

    if host and host.ApplySavedSettings then
        host:ApplySavedSettings()
    end

    self:_ApplySceneVisibility(self:_EvaluateSceneVisibility())

    if addon and addon.Debug then
        addon:Debug("EventHandlerBase.OnPlayerActivated() ensured tracker host visibility")
    end
end

local function isSceneStateVisible(scene)
    if not scene then
        return false
    end

    if scene.GetState then
        local state = scene:GetState()
        if state == SCENE_SHOWING or state == SCENE_SHOWN then
            return true
        end
    end

    local stateValue = scene.state
    if stateValue == SCENE_SHOWING or stateValue == SCENE_SHOWN then
        return true
    end

    return false
end

function EventHandlerBase:_EvaluateSceneVisibility()
    local manager = SCENE_MANAGER
    if not manager then
        return true
    end

    local hudVisible = false

    if isSceneStateVisible(HUD_SCENE) or isSceneStateVisible(HUD_UI_SCENE) then
        hudVisible = true
    end

    if not hudVisible and manager.IsShowing then
        local okHud, showingHud = pcall(manager.IsShowing, manager, "hud")
        if okHud and showingHud then
            hudVisible = true
        end

        if not hudVisible then
            local okHudUi, showingHudUi = pcall(manager.IsShowing, manager, "hudui")
            if okHudUi and showingHudUi then
                hudVisible = true
            end
        end
    end

    return hudVisible
end

function EventHandlerBase:_ApplySceneVisibility(shouldShow)
    local addon = self.addon or Nvk3UT
    if addon ~= self.addon then
        self.addon = addon
    end

    local host = addon and addon.TrackerHost or self.host
    if host ~= self.host then
        self.host = host
    end

    local runtime = addon and addon.TrackerRuntime or self.runtime
    if runtime ~= self.runtime then
        self.runtime = runtime
    end

    local visible = shouldShow and true or false

    if host and host.SetVisible then
        host:SetVisible(visible)
    end

    if runtime and runtime.QueueDirty then
        runtime:QueueDirty("layout")
    end

    if addon and addon.Debug then
        addon:Debug("EventHandlerBase -> HUD visibility " .. tostring(visible))
    end
end

function EventHandlerBase:RegisterAllCallbacks()
    if self._eventsRegistered then
        return
    end
    self._eventsRegistered = true

    local addon = self.addon or Nvk3UT
    if addon ~= self.addon then
        self.addon = addon
    end

    self.host = addon and addon.TrackerHost or self.host
    self.runtime = addon and addon.TrackerRuntime or self.runtime

    -------------------------------------------------
    -- ADD_ON_LOADED / PLAYER_ACTIVATED
    -------------------------------------------------
    local function OnAddOnLoaded(_, loadedName)
        local addonTable = self.addon or Nvk3UT
        if addonTable ~= self.addon then
            self.addon = addonTable
        end

        local expectedName = (addonTable and (addonTable.addonName or addonTable.name)) or "Nvk3UT"
        if loadedName ~= expectedName then
            return
        end

        EVENT_MANAGER:UnregisterForEvent("Nvk3UT_EventHandlerBase_ADDON_LOADED", EVENT_ADD_ON_LOADED)

        local function initializeSavedVariables()
            local stateInit = addonTable and addonTable.StateInit or Nvk3UT_StateInit
            if addonTable and stateInit and addonTable.StateInit ~= stateInit then
                addonTable.StateInit = stateInit
            end
            if stateInit and stateInit.BootstrapSavedVariables then
                stateInit.BootstrapSavedVariables(addonTable)
            elseif stateInit and stateInit.InitSavedVariables then
                stateInit.InitSavedVariables(stateInit, addonTable)
            elseif addonTable and addonTable.InitSavedVariables then
                addonTable:InitSavedVariables()
            end
        end

        local function ensureTrackerWindow()
            local hostModule = addonTable and addonTable.TrackerHost
            if hostModule and hostModule.EnsureWindow then
                hostModule:EnsureWindow()
            end
            self.host = hostModule or self.host
        end

        local function forwardAddonLoaded()
            if addonTable and addonTable.OnAddonLoaded then
                addonTable:OnAddonLoaded(loadedName)
            end
        end

        if addonTable and addonTable.SafeCall then
            addonTable:SafeCall(function()
                initializeSavedVariables()
                ensureTrackerWindow()
                forwardAddonLoaded()
            end)
        else
            initializeSavedVariables()
            ensureTrackerWindow()
            forwardAddonLoaded()
        end

        self.runtime = addonTable and addonTable.TrackerRuntime or self.runtime

        if addonTable and addonTable.Debug then
            addonTable:Debug("EventHandlerBase -> OnAddOnLoaded bootstrap complete")
        end

        local shouldShow = self:_EvaluateSceneVisibility()
        self:_ApplySceneVisibility(shouldShow)
    end

    EVENT_MANAGER:RegisterForEvent(
        "Nvk3UT_EventHandlerBase_ADDON_LOADED",
        EVENT_ADD_ON_LOADED,
        function(eventCode, loadedName)
            local addonTable = self.addon or Nvk3UT
            if addonTable and addonTable.SafeCall then
                addonTable:SafeCall(function()
                    OnAddOnLoaded(eventCode, loadedName)
                end)
            else
                OnAddOnLoaded(eventCode, loadedName)
            end
        end
    )

    local function OnPlayerActivated()
        EVENT_MANAGER:UnregisterForEvent("Nvk3UT_EventHandlerBase_PLAYER_ACTIVATED", EVENT_PLAYER_ACTIVATED)

        local addonTable = self.addon or Nvk3UT
        if addonTable ~= self.addon then
            self.addon = addonTable
        end

        local function forwardPlayerActivated()
            if addonTable and addonTable.OnPlayerActivated then
                addonTable:OnPlayerActivated()
            end
        end

        if addonTable and addonTable.SafeCall then
            addonTable:SafeCall(function()
                forwardPlayerActivated()
            end)
        else
            forwardPlayerActivated()
        end

        self.host = addonTable and addonTable.TrackerHost or self.host
        self.runtime = addonTable and addonTable.TrackerRuntime or self.runtime

        if addonTable and addonTable.Debug then
            addonTable:Debug("EventHandlerBase -> PLAYER_ACTIVATED complete, runtime live")
        end
    end

    EVENT_MANAGER:RegisterForEvent(
        "Nvk3UT_EventHandlerBase_PLAYER_ACTIVATED",
        EVENT_PLAYER_ACTIVATED,
        function(eventCode)
            local addonTable = self.addon or Nvk3UT
            if addonTable and addonTable.SafeCall then
                addonTable:SafeCall(function()
                    OnPlayerActivated(eventCode)
                end)
            else
                OnPlayerActivated(eventCode)
            end
        end
    )

    -------------------------------------------------
    -- HUD / Scene visibility handling
    -------------------------------------------------
    local hudSceneNames = {
        hud = true,
        hudui = true,
    }

    local function EvaluateTrackerVisibilityForScene(scene, oldState, newState)
        local validState =
            newState == SCENE_SHOWING or newState == SCENE_SHOWN or newState == SCENE_HIDING or newState == SCENE_HIDDEN
        if not validState then
            return self:_EvaluateSceneVisibility()
        end

        local isShowing = newState == SCENE_SHOWING or newState == SCENE_SHOWN
        local isHiding = newState == SCENE_HIDING or newState == SCENE_HIDDEN

        local isHudScene = false
        if scene then
            if scene == HUD_SCENE or scene == HUD_UI_SCENE then
                isHudScene = true
            else
                local sceneName = scene.GetName and scene:GetName()
                if sceneName then
                    local lowered
                    if zo_strlower then
                        lowered = zo_strlower(sceneName)
                    else
                        lowered = string.lower(sceneName)
                    end
                    if lowered and hudSceneNames[lowered] then
                        isHudScene = true
                    end
                end
            end
        end

        if isHudScene then
            if isShowing then
                return true
            end

            if isHiding then
                return self:_EvaluateSceneVisibility()
            end

            return self:_EvaluateSceneVisibility()
        end

        if isShowing then
            return false
        end

        if isHiding then
            return self:_EvaluateSceneVisibility()
        end

        return self:_EvaluateSceneVisibility()
    end

    local function OnSceneStateChanged(scene, oldState, newState)
        local shouldShow = EvaluateTrackerVisibilityForScene(scene, oldState, newState)
        self:_ApplySceneVisibility(shouldShow)
    end

    if SCENE_MANAGER and SCENE_MANAGER.RegisterCallback then
        SCENE_MANAGER:RegisterCallback("SceneStateChanged", function(scene, oldState, newState)
            if addon and addon.SafeCall then
                addon:SafeCall(function()
                    OnSceneStateChanged(scene, oldState, newState)
                end)
            else
                OnSceneStateChanged(scene, oldState, newState)
            end
        end)
    end

    -------------------------------------------------
    -- Cursor mode / reticle handling
    -------------------------------------------------
    local function OnReticleHidden(_, isHidden)
        local addonTable = self.addon or Nvk3UT
        if addonTable ~= self.addon then
            self.addon = addonTable
        end

        local runtime = addonTable and addonTable.TrackerRuntime or self.runtime
        if runtime ~= self.runtime then
            self.runtime = runtime
        end

        local cursorShown = isHidden == true

        if runtime and runtime.SetCursorMode then
            runtime:SetCursorMode(cursorShown)
        end

        if runtime and runtime.QueueDirty then
            runtime:QueueDirty("layout")
        end

        if addonTable and addonTable.Debug then
            addonTable:Debug("EventHandlerBase -> CursorMode " .. tostring(cursorShown))
        end
    end

    EVENT_MANAGER:RegisterForEvent(
        "Nvk3UT_EventHandlerBase_RETICLE",
        EVENT_RETICLE_HIDDEN_UPDATE,
        function(eventCode, isHidden)
            local addonTable = self.addon or Nvk3UT
            if addonTable and addonTable.SafeCall then
                addonTable:SafeCall(function()
                    OnReticleHidden(eventCode, isHidden)
                end)
            else
                OnReticleHidden(eventCode, isHidden)
            end
        end
    )

    -------------------------------------------------
    -- Combat state handling
    -------------------------------------------------
    local function OnCombatState(_, inCombat)
        local addonTable = self.addon or Nvk3UT
        if addonTable ~= self.addon then
            self.addon = addonTable
        end

        local runtime = addonTable and addonTable.TrackerRuntime or self.runtime
        if runtime ~= self.runtime then
            self.runtime = runtime
        end

        if runtime and runtime.SetCombatState then
            runtime:SetCombatState(inCombat == true)
        end

        if runtime and runtime.QueueDirty then
            runtime:QueueDirty("layout")
        end

        if addonTable and addonTable.Debug then
            addonTable:Debug("EventHandlerBase -> CombatState " .. tostring(inCombat))
        end
    end

    EVENT_MANAGER:RegisterForEvent(
        "Nvk3UT_EventHandlerBase_COMBAT",
        EVENT_PLAYER_COMBAT_STATE,
        function(eventCode, inCombat)
            local addonTable = self.addon or Nvk3UT
            if addonTable and addonTable.SafeCall then
                addonTable:SafeCall(function()
                    OnCombatState(eventCode, inCombat)
                end)
            else
                OnCombatState(eventCode, inCombat)
            end
        end
    )

    if addon and addon.Debug then
        addon:Debug("EventHandlerBase:RegisterAllCallbacks() complete")
    end

    -- Apply initial visibility state to match the active scene when we boot.
    local initialVisibility = self:_EvaluateSceneVisibility()
    self:_ApplySceneVisibility(initialVisibility)
end

local addon = Nvk3UT
if not addon then
    error("Nvk3UT_EventHandlerBase loaded before Nvk3UT_Core. Load order is wrong.")
end

addon.EventHandlerBase = EventHandlerBase
addon:RegisterModule("EventHandlerBase", EventHandlerBase)

return EventHandlerBase
