-- Runtime/Nvk3UT_TrackerHost.lua
local Host = {}

--[[
TEMPORARY EVENT HANDLERS NOTICE
================================
This file currently self-registers scene / cursor / combat events in _TempRegisterEvents().

This is ONLY a stopgap until we introduce Events/Nvk3UT_EventHandlerBase.lua
and the rest of the Events/* modules (Migration Tokens: EVENTS_001_CREATE_EventHandlerBase_lua
and following). Once those exist, ALL ESO event registration and SCENE_MANAGER callbacks
MUST be removed from Runtime/Nvk3UT_TrackerHost.lua.

At that point:
- Events/* will own HUD visibility, cursor mode, combat state, quest/achievement change hooks.
- Events/* will call Nvk3UT.TrackerHost:SetVisible(), Nvk3UT.TrackerRuntime:SetCursorMode(),
  Nvk3UT.TrackerRuntime:SetCombatState(), and Nvk3UT.TrackerRuntime:QueueDirty() as needed.

If you are working on the Events migration, DELETE:
- Host:_TempRegisterEvents()
- Any SCENE_MANAGER:RegisterCallback(...) and EVENT_MANAGER:RegisterForEvent(...) in this file
- The OnPlayerActivated() call to self:_TempRegisterEvents()

Do not forget to also remove the corresponding TODO comments.
]]

local WINDOW_NAME = "Nvk3UT_TrackerHost_Window"
local HEADER_NAME = WINDOW_NAME .. "_Header"
local FOOTER_NAME = WINDOW_NAME .. "_Footer"
local SCROLL_NAME = WINDOW_NAME .. "_Scroll"
local SCROLL_CHILD_NAME = SCROLL_NAME .. "ScrollChild"
local DEFAULT_HEADER_HEIGHT = 40
local DEFAULT_FOOTER_HEIGHT = 100
local MIN_WIDTH = 260
local MIN_HEIGHT = 240
local MAX_BAR_HEIGHT = 250
local LEFT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_LEFT or 1

local DEFAULT_WINDOW = {
    left = 200,
    top = 200,
    width = 360,
    height = 640,
    locked = false,
    visible = true,
    clamp = true,
    onTop = false,
}

local DEFAULT_WINDOW_BARS = {
    headerHeightPx = DEFAULT_HEADER_HEIGHT,
    footerHeightPx = DEFAULT_FOOTER_HEIGHT,
}

local DEFAULT_TRACKER_COLORS = {
    questTracker = {
        colors = {
            categoryTitle = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            objectiveText = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            entryTitle = { r = 1, g = 1, b = 0, a = 1 },
            activeTitle = { r = 1, g = 1, b = 1, a = 1 },
        },
    },
    achievementTracker = {
        colors = {
            categoryTitle = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            objectiveText = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            entryTitle = { r = 1, g = 1, b = 0, a = 1 },
            activeTitle = { r = 1, g = 1, b = 1, a = 1 },
        },
    },
}

local function clamp(value, minimum, maximum)
    if value == nil then
        return minimum
    end

    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end

local function copyColor(color)
    if type(color) ~= "table" then
        return nil
    end

    return { r = color.r, g = color.g, b = color.b, a = color.a }
end

local function resolveSavedVars(self)
    if self.sv then
        return self.sv
    end

    local addon = Nvk3UT
    if not addon then
        return nil
    end

    if type(addon.db) == "table" and type(addon.db.tracker) == "table" then
        self.sv = addon.db.tracker
    else
        self.sv = addon.sv
    end

    return self.sv
end

local function ensureGeneral(self)
    local sv = resolveSavedVars(self)
    if type(sv) ~= "table" then
        return nil
    end

    sv.General = sv.General or {}
    sv.General.window = sv.General.window or {}
    sv.General.WindowBars = sv.General.WindowBars or {}
    sv.appearance = sv.appearance or {}

    sv.appearance.questTracker = sv.appearance.questTracker or {}
    sv.appearance.questTracker.colors = sv.appearance.questTracker.colors or {}
    sv.appearance.achievementTracker = sv.appearance.achievementTracker or {}
    sv.appearance.achievementTracker.colors = sv.appearance.achievementTracker.colors or {}

    return sv.General
end

local function normalizeWindow(settings)
    if type(settings) ~= "table" then
        settings = {}
    end

    settings.left = tonumber(settings.left) or DEFAULT_WINDOW.left
    settings.top = tonumber(settings.top) or DEFAULT_WINDOW.top
    settings.width = tonumber(settings.width) or DEFAULT_WINDOW.width
    settings.height = tonumber(settings.height) or DEFAULT_WINDOW.height
    settings.locked = settings.locked == true
    settings.visible = settings.visible ~= false
    settings.clamp = settings.clamp ~= false
    settings.onTop = settings.onTop == true

    return settings
end

local function normalizeWindowBars(bars)
    if type(bars) ~= "table" then
        bars = {}
    end

    local header = clamp(math.floor(tonumber(bars.headerHeightPx) or DEFAULT_WINDOW_BARS.headerHeightPx + 0.5), 0, MAX_BAR_HEIGHT)
    local footer = clamp(math.floor(tonumber(bars.footerHeightPx) or DEFAULT_WINDOW_BARS.footerHeightPx + 0.5), 0, MAX_BAR_HEIGHT)

    bars.headerHeightPx = header
    bars.footerHeightPx = footer

    return bars
end

local queueLayout

local function ensureWindow(self)
    if self.window and self.scrollChild then
        return self.window
    end

    local wm = WINDOW_MANAGER
    if not wm then
        return nil
    end

    local window = self.window or _G[WINDOW_NAME]
    if not window then
        window = wm:CreateTopLevelWindow(WINDOW_NAME)
        window:SetClampedToScreen(true)
        window:SetMouseEnabled(true)
        window:SetMovable(true)
        if window.SetResizeHandleSize then
            window:SetResizeHandleSize(12)
        end
        if window.SetDimensionConstraints then
            window:SetDimensionConstraints(MIN_WIDTH, MIN_HEIGHT)
        end
        window:SetDrawLayer(DL_BACKGROUND)
        window:SetDrawTier(DT_LOW)
        window:SetDrawLevel(0)
        window:SetHidden(true)
        window:SetHandler("OnMoveStop", function()
            Host.SaveWindowPosition(self)
        end)
        window:SetHandler("OnResizeStop", function()
            Host.SaveWindowDimensions(self)
        end)
        window:SetHandler("OnMouseDown", function(_, button)
            Host._BeginDrag(self, button)
        end)
        window:SetHandler("OnMouseUp", function(_, button)
            Host._EndDrag(self, button)
        end)
    end
    self.window = window

    local header = self.headerControl or _G[HEADER_NAME]
    if not header then
        header = wm:CreateControl(HEADER_NAME, window, CT_CONTROL)
        header:SetAnchor(TOPLEFT, window, TOPLEFT, 0, 0)
        header:SetAnchor(TOPRIGHT, window, TOPRIGHT, 0, 0)
        header:SetHeight(DEFAULT_HEADER_HEIGHT)
        header:SetMouseEnabled(true)
        header:SetHandler("OnMouseDown", function(_, button)
            Host._BeginDrag(self, button)
        end)
        header:SetHandler("OnMouseUp", function(_, button)
            Host._EndDrag(self, button)
        end)
    end
    self.headerControl = header

    local footer = self.footerControl or _G[FOOTER_NAME]
    if not footer then
        footer = wm:CreateControl(FOOTER_NAME, window, CT_CONTROL)
        footer:SetAnchor(BOTTOMLEFT, window, BOTTOMLEFT, 0, 0)
        footer:SetAnchor(BOTTOMRIGHT, window, BOTTOMRIGHT, 0, 0)
        footer:SetHeight(DEFAULT_FOOTER_HEIGHT)
        footer:SetMouseEnabled(true)
        footer:SetHandler("OnMouseDown", function(_, button)
            Host._BeginDrag(self, button)
        end)
        footer:SetHandler("OnMouseUp", function(_, button)
            Host._EndDrag(self, button)
        end)
    end
    self.footerControl = footer

    local scroll = self.scrollArea or _G[SCROLL_NAME]
    if not scroll then
        scroll = wm:CreateControlFromVirtual(SCROLL_NAME, window, "ZO_ScrollContainer")
    end
    scroll:ClearAnchors()
    scroll:SetAnchor(TOPLEFT, header, BOTTOMLEFT, 0, 0)
    scroll:SetAnchor(BOTTOMRIGHT, footer, TOPRIGHT, 0, 0)
    self.scrollArea = scroll

    local scrollChild = scroll:GetNamedChild("ScrollChild")
    if not scrollChild and scroll.SetScrollChild then
        scrollChild = wm:CreateControl(SCROLL_CHILD_NAME, scroll, CT_CONTROL)
        scroll:SetScrollChild(scrollChild)
    end
    if scrollChild and scrollChild.ClearAnchors then
        scrollChild:ClearAnchors()
        scrollChild:SetAnchor(TOPLEFT, scroll, TOPLEFT, 0, 0)
        scrollChild:SetAnchor(TOPRIGHT, scroll, TOPRIGHT, 0, 0)
    end

    if scrollChild and scrollChild.SetResizeToFitDescendents then
        scrollChild:SetResizeToFitDescendents(true)
    end
    self.scrollChild = scrollChild

    return window
end

function Host.EnsureWindow(self)
    self = self or Host
    return ensureWindow(self)
end

function Host._BeginDrag(self, button)
    self = self or Host
    if button ~= LEFT_MOUSE_BUTTON then
        return
    end

    if self.locked then
        return
    end

    if self.window and self.window.StartMoving then
        self.window:StartMoving()
        self._isDragging = true
    end
end

function Host._EndDrag(self, button)
    self = self or Host
    if button and button ~= LEFT_MOUSE_BUTTON then
        return
    end

    if not self.window then
        return
    end

    if self._isDragging and self.window.StopMovingOrResizing then
        self.window:StopMovingOrResizing()
        self._isDragging = false
        Host.SaveWindowPosition(self)
    end
end

function Host.Init(self)
    self = self or Host

    self.sv = self.sv or resolveSavedVars(self)
    self.window = self.window or nil
    self.headerControl = self.headerControl or nil
    self.footerControl = self.footerControl or nil
    self.scrollArea = self.scrollArea or nil
    self.scrollChild = self.scrollChild or nil
    self.locked = self.locked or false
    self._isDragging = false
    self._tempEventsRegistered = self._tempEventsRegistered or false
    self._tempSceneCallbacks = self._tempSceneCallbacks or {}
    self._hudSceneVisible = self._hudSceneVisible
    if self._hudSceneVisible == nil then
        self._hudSceneVisible = true
    end
    self._hudUiSceneVisible = self._hudUiSceneVisible
    if self._hudUiSceneVisible == nil then
        self._hudUiSceneVisible = true
    end
    self._sceneShouldShow = self._sceneShouldShow
    if self._sceneShouldShow == nil then
        self._sceneShouldShow = true
    end
    self._userDesiredVisible = self._userDesiredVisible
    if self._userDesiredVisible == nil then
        self._userDesiredVisible = true
    end
end

function Host.OnPlayerActivated(self)
    self = self or Host

    ensureWindow(self)
    Host.ApplySavedSettings(self)

    -- TEMPORARY: register in-file event listeners until Events/ modules take over.
    -- TODO [EventMigration]: remove this call once Events/ modules own all ESO events.
    self:_TempRegisterEvents()

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug(
            "TrackerHost.OnPlayerActivated() complete tempEvents=" .. tostring(self._tempEventsRegistered)
        )
    end
end

function Host.ApplySavedSettings(self)
    self = self or Host

    local window = ensureWindow(self)
    if not window then
        return
    end

    local general = ensureGeneral(self)
    if not general then
        return
    end

    local windowSettings = normalizeWindow(general.window)
    general.window = windowSettings

    window:ClearAnchors()
    window:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, windowSettings.left, windowSettings.top)
    window:SetDimensions(windowSettings.width, windowSettings.height)
    window:SetClampedToScreen(windowSettings.clamp)
    if window.SetDrawTier then
        window:SetDrawTier(windowSettings.onTop and DT_HIGH or DT_LOW)
    end

    self.locked = windowSettings.locked
    window:SetMovable(not self.locked)
    window:SetMouseEnabled(true)

    Host.UpdateHeaderFooterSizeFromSV(self, true)
    Host.SetVisible(self, windowSettings.visible, true)

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug(string.format("TrackerHost.ApplySavedSettings() lock=%s", tostring(self.locked)))
    end
end

Host.ApplySettings = Host.ApplySavedSettings

function Host.UpdateHeaderFooterSizeFromSV(self, suppressSave)
    self = self or Host

    if not (self.headerControl and self.footerControl and self.scrollArea) then
        return
    end

    local general = ensureGeneral(self)
    if not general then
        return
    end

    local bars = normalizeWindowBars(general.WindowBars)
    general.WindowBars = bars

    self.headerControl:SetHeight(bars.headerHeightPx)
    self.footerControl:SetHeight(bars.footerHeightPx)

    self.scrollArea:ClearAnchors()
    self.scrollArea:SetAnchor(TOPLEFT, self.headerControl, BOTTOMLEFT, 0, 0)
    self.scrollArea:SetAnchor(BOTTOMRIGHT, self.footerControl, TOPRIGHT, 0, 0)

    if not suppressSave and self.sv then
        self.sv.General.WindowBars = bars
    end
end

function Host.ApplyWindowBars(self)
    Host.UpdateHeaderFooterSizeFromSV(self, false)
end

function Host.RestoreWindowPositionFromSV(self)
    self = self or Host

    if not self.window then
        return
    end

    local general = ensureGeneral(self)
    if not general then
        return
    end

    local windowSettings = normalizeWindow(general.window)
    self.window:ClearAnchors()
    self.window:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, windowSettings.left, windowSettings.top)
    self.window:SetDimensions(windowSettings.width, windowSettings.height)
end

function Host.SaveWindowPosition(self)
    self = self or Host

    if not (self.window and self.window.GetLeft and self.window.GetTop) then
        return
    end

    local general = ensureGeneral(self)
    if not general then
        return
    end

    general.window.left = math.floor(self.window:GetLeft() + 0.5)
    general.window.top = math.floor(self.window:GetTop() + 0.5)
end

function Host.SaveWindowDimensions(self)
    self = self or Host

    if not (self.window and self.window.GetWidth and self.window.GetHeight) then
        return
    end

    local general = ensureGeneral(self)
    if not general then
        return
    end

    general.window.width = math.floor(self.window:GetWidth() + 0.5)
    general.window.height = math.floor(self.window:GetHeight() + 0.5)
end

function Host.SetVisible(self, isVisible, suppressSave, fromScene)
    self = self or Host

    local general
    if fromScene then
        self._sceneShouldShow = isVisible and true or false
    else
        self._userDesiredVisible = isVisible and true or false
        general = ensureGeneral(self)
        if general and not suppressSave then
            general.window.visible = self._userDesiredVisible
        end
    end

    local window = self.window
    local previousVisible = window and not window:IsHidden()
    local shouldShow = (self._userDesiredVisible ~= false) and (self._sceneShouldShow ~= false)
    if window then
        window:SetHidden(not shouldShow)
    end

    if window and previousVisible ~= shouldShow then
        if queueLayout then
            queueLayout()
        end
    end

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug(string.format(
            "TrackerHost.SetVisible(request=%s, fromScene=%s, final=%s)",
            tostring(isVisible),
            tostring(fromScene == true),
            tostring(shouldShow)
        ))
    end
end

function Host.IsVisible(self)
    self = self or Host
    if not self.window then
        return false
    end

    return not self.window:IsHidden()
end

function Host.SetLocked(self, isLocked)
    self = self or Host

    self.locked = isLocked and true or false
    if self.window then
        self.window:SetMovable(not self.locked)
    end

    local general = ensureGeneral(self)
    if general then
        general.window.locked = self.locked
    end

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHost.SetLocked(" .. tostring(self.locked) .. ")")
    end
end

function Host.IsLocked(self)
    self = self or Host
    return self.locked == true
end

function Host.GetBodyContainer(self)
    self = self or Host
    return self.scrollChild
end

function Host.GetHeaderControl(self)
    self = self or Host
    return self.headerControl
end

function Host.GetFooterControl(self)
    self = self or Host
    return self.footerControl
end

function Host.GetWindowControl(self)
    self = self or Host
    return self.window
end

function Host:_TempRegisterEvents()
    if self._tempEventsRegistered then
        return
    end
    self._tempEventsRegistered = true

    local sceneCallbacks = self._tempSceneCallbacks or {}
    self._tempSceneCallbacks = sceneCallbacks

    -------------------------------------------------
    -- Scene / HUD visibility handling
    -------------------------------------------------
    local function handleSceneState(sceneKey)
        local function stateChanged(_, newState)
            if newState ~= SCENE_SHOWING and newState ~= SCENE_SHOWN and newState ~= SCENE_HIDING and newState ~= SCENE_HIDDEN then
                return
            end

            local isShowing = newState == SCENE_SHOWING or newState == SCENE_SHOWN
            if sceneKey == "hudui" then
                self._hudUiSceneVisible = isShowing and true or false
            else
                self._hudSceneVisible = isShowing and true or false
            end

            local shouldShow = (self._hudSceneVisible ~= false) or (self._hudUiSceneVisible ~= false)
            self:SetVisible(shouldShow, true, true)
        end

        return stateChanged
    end

    local function registerScene(scene, key)
        if not (scene and scene.RegisterCallback) then
            return
        end

        key = key or (scene.GetName and scene:GetName()) or tostring(scene)
        if sceneCallbacks[key] then
            return
        end

        local callback = handleSceneState(key)
        local ok = pcall(scene.RegisterCallback, scene, "StateChange", callback)
        if ok then
            sceneCallbacks[key] = callback
            local isShowing = scene.IsShowing and scene:IsShowing()
            if isShowing ~= nil then
                if key == "hudui" or key == "HUD_UI_SCENE" then
                    self._hudUiSceneVisible = isShowing and true or false
                else
                    self._hudSceneVisible = isShowing and true or false
                end
            end
        end
    end

    registerScene(HUD_SCENE, "hud")
    registerScene(HUD_UI_SCENE, "hudui")

    if SCENE_MANAGER and SCENE_MANAGER.GetScene then
        registerScene(SCENE_MANAGER:GetScene("hud"), "hud")
        registerScene(SCENE_MANAGER:GetScene("hudui"), "hudui")
    end

    local hudShowing = self._hudSceneVisible ~= false
    local hudUiShowing = self._hudUiSceneVisible ~= false
    self:SetVisible(hudShowing or hudUiShowing, true, true)

    -------------------------------------------------
    -- Cursor mode / reticle handling
    -------------------------------------------------
    if EVENT_MANAGER and EVENT_MANAGER.RegisterForEvent then
        local function onReticleHidden(_, isHidden)
            local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
            if runtime and runtime.SetCursorMode then
                runtime:SetCursorMode(isHidden == true)
            end
        end

        EVENT_MANAGER:RegisterForEvent(
            "Nvk3UT_TrackerHost_Reticle",
            EVENT_RETICLE_HIDDEN_UPDATE,
            onReticleHidden
        )

        -------------------------------------------------
        -- Combat state handling
        -------------------------------------------------
        local function onCombatState(_, inCombat)
            local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
            if runtime and runtime.SetCombatState then
                runtime:SetCombatState(inCombat == true)
            end
        end

        EVENT_MANAGER:RegisterForEvent(
            "Nvk3UT_TrackerHost_Combat",
            EVENT_PLAYER_COMBAT_STATE,
            onCombatState
        )
    end

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug(
            "TrackerHost._TempRegisterEvents() registered temporary scene/cursor/combat listeners"
        )
    end
end

queueLayout = function()
    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and runtime.QueueDirty then
        runtime:QueueDirty("layout")
    end
end

function Host.Refresh(self)
    self = self or Host
    queueLayout()
end

function Host.RefreshScroll(self)
    self = self or Host
    queueLayout()
end

function Host.NotifyContentChanged(self)
    self = self or Host
    queueLayout()
end

function Host.ScrollControlIntoView(self, control)
    self = self or Host
    if not (self.scrollArea and control) then
        return
    end

    if type(ZO_Scroll_ScrollControlIntoView) == "function" then
        ZO_Scroll_ScrollControlIntoView(self.scrollArea, control)
    end
end

function Host.EnsureVisible(self)
    self = self or Host
    ensureWindow(self)
    Host.SetVisible(self, true)
end

function Host.EnsureAppearanceDefaults(self)
    self = self or Host

    local sv = resolveSavedVars(self)
    if type(sv) ~= "table" then
        return
    end

    sv.appearance = sv.appearance or {}
    for trackerType, trackerDefaults in pairs(DEFAULT_TRACKER_COLORS) do
        local tracker = sv.appearance[trackerType]
        if type(tracker) ~= "table" then
            tracker = {}
            sv.appearance[trackerType] = tracker
        end

        tracker.colors = tracker.colors or {}
        for role, color in pairs(trackerDefaults.colors) do
            if type(tracker.colors[role]) ~= "table" then
                tracker.colors[role] = copyColor(color)
            end
        end
    end
end

function Host.GetDefaultTrackerColor(self, trackerType, role)
    self = self or Host

    local trackerDefaults = DEFAULT_TRACKER_COLORS[trackerType]
    local colors = trackerDefaults and trackerDefaults.colors
    local color = colors and colors[role]
    if color then
        return color.r, color.g, color.b, color.a
    end

    return 1, 1, 1, 1
end

function Host.GetTrackerColor(self, trackerType, role)
    self = self or Host

    Host.EnsureAppearanceDefaults(self)

    local sv = resolveSavedVars(self)
    if type(sv) ~= "table" then
        return Host.GetDefaultTrackerColor(self, trackerType, role)
    end

    local tracker = sv.appearance and sv.appearance[trackerType]
    local colors = tracker and tracker.colors
    local color = colors and colors[role]
    if color then
        return color.r, color.g, color.b, color.a
    end

    return Host.GetDefaultTrackerColor(self, trackerType, role)
end

function Host.SetTrackerColor(self, trackerType, role, r, g, b, a)
    self = self or Host

    Host.EnsureAppearanceDefaults(self)

    local sv = resolveSavedVars(self)
    if type(sv) ~= "table" then
        return
    end

    sv.appearance[trackerType].colors[role] = {
        r = r,
        g = g,
        b = b,
        a = a,
    }

    Host.ApplyAppearance(self)
end

function Host.ApplyAppearance(self)
    queueLayout()
end

function Host.OnLamPanelOpened(self)
    self = self or Host
    self._lamPanelOpen = true
end

function Host.OnLamPanelClosed(self)
    self = self or Host
    self._lamPanelOpen = false
end

local addon = Nvk3UT
if not addon then
    error("Nvk3UT_TrackerHost loaded before Nvk3UT_Core. Load order is wrong.")
end

addon.TrackerHost = Host
addon:RegisterModule("TrackerHost", Host)

return Host
