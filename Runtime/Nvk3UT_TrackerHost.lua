-- Runtime/Nvk3UT_TrackerHost.lua
-- NOTE:
-- ESO event registration (ADD_ON_LOADED, PLAYER_ACTIVATED, HUD visibility,
-- cursor mode, combat state, etc.) is owned by Events/Nvk3UT_EventHandlerBase.lua.
-- TrackerHost is a pure UI container; do not register events here.
local Host = {}

local ADDON_NAME = "Nvk3UT"
local ROOT_CONTROL_NAME = ADDON_NAME .. "_UI_Root"
local HEADER_CONTROL_NAME = ROOT_CONTROL_NAME .. "_Header"
local FOOTER_CONTROL_NAME = ROOT_CONTROL_NAME .. "_Footer"
local SCROLL_CONTAINER_NAME = ROOT_CONTROL_NAME .. "_ScrollContainer"
local SCROLL_CHILD_NAME = SCROLL_CONTAINER_NAME .. "_ScrollChild"

local MIN_WIDTH = 260
local MIN_HEIGHT = 240
local RESIZE_HANDLE_SIZE = 12
local MAX_BAR_HEIGHT = 250

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
    headerHeightPx = 40,
    footerHeightPx = 100,
}

local LEFT_MOUSE_BUTTON = _G.MOUSE_BUTTON_INDEX_LEFT or 1

local function clamp(value, minimum, maximum)
    if type(value) ~= "number" then
        value = minimum
    end

    if maximum then
        if value > maximum then
            value = maximum
        end
    end

    if value < minimum then
        value = minimum
    end

    return value
end

local function round(numberValue)
    if type(numberValue) ~= "number" then
        return nil
    end

    return math.floor(numberValue + 0.5)
end

function Host:Init()
    self.sv = self.sv or nil
    self.windowSettings = nil
    self.windowBarSettings = nil

    self.window = self.window or nil
    self.headerControl = self.headerControl or nil
    self.footerControl = self.footerControl or nil
    self.scrollArea = self.scrollArea or nil
    self.scrollChild = self.scrollChild or nil

    self.locked = self.locked or false
end

function Host:OnPlayerActivated()
    self:EnsureWindow()
    self:ApplySavedSettings()

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHost.OnPlayerActivated() complete")
    end
end

function Host:_EnsureSavedVars()
    if self.sv then
        return self.sv
    end

    local addon = Nvk3UT
    if not (addon and addon.sv) then
        return nil
    end

    local general = addon.sv.General
    if type(general) ~= "table" then
        general = {}
        addon.sv.General = general
    end

    self.sv = general
    return general
end

function Host:_EnsureWindowSettings()
    if self.windowSettings then
        return self.windowSettings
    end

    local general = self:_EnsureSavedVars()
    local window = general and general.window
    if type(window) ~= "table" then
        window = {}
        if general then
            general.window = window
        end
    end

    window.left = tonumber(window.left) or DEFAULT_WINDOW.left
    window.top = tonumber(window.top) or DEFAULT_WINDOW.top
    window.width = tonumber(window.width) or DEFAULT_WINDOW.width
    window.height = tonumber(window.height) or DEFAULT_WINDOW.height
    window.locked = window.locked == true
    if window.visible == nil then
        window.visible = DEFAULT_WINDOW.visible
    else
        window.visible = window.visible ~= false
    end
    if window.clamp == nil then
        window.clamp = DEFAULT_WINDOW.clamp
    else
        window.clamp = window.clamp ~= false
    end
    if window.onTop == nil then
        window.onTop = DEFAULT_WINDOW.onTop
    else
        window.onTop = window.onTop == true
    end

    self.windowSettings = window
    return window
end

function Host:_EnsureWindowBarSettings()
    if self.windowBarSettings then
        return self.windowBarSettings
    end

    local general = self:_EnsureSavedVars()
    local bars = general and general.WindowBars
    if type(bars) ~= "table" then
        bars = {}
        if general then
            general.WindowBars = bars
        end
    end

    local header = round(bars.headerHeightPx)
    if not header then
        header = DEFAULT_WINDOW_BARS.headerHeightPx
    end
    bars.headerHeightPx = clamp(header, 0, MAX_BAR_HEIGHT)

    local footer = round(bars.footerHeightPx)
    if not footer then
        footer = DEFAULT_WINDOW_BARS.footerHeightPx
    end
    bars.footerHeightPx = clamp(footer, 0, MAX_BAR_HEIGHT)

    self.windowBarSettings = bars
    return bars
end

function Host:_StartWindowMove()
    if not self.window or self:IsLocked() then
        return
    end

    self.window:StartMoving()
end

function Host:_StopWindowMove()
    if not self.window then
        return
    end

    self.window:StopMovingOrResizing()
    self:SaveWindowPosition()
end

function Host:EnsureWindow()
    if self.window and self.scrollChild then
        return
    end

    local wm = WINDOW_MANAGER
    if not wm then
        return
    end

    local window = self.window
    if not window then
        window = wm:CreateTopLevelWindow(ROOT_CONTROL_NAME)
        if not window then
            return
        end

        window:SetHidden(true)
        window:SetMouseEnabled(true)
        window:SetMovable(true)
        window:SetClampedToScreen(true)
        window:SetResizeHandleSize(RESIZE_HANDLE_SIZE)
        window:SetDimensionConstraints(MIN_WIDTH, MIN_HEIGHT)
        window:SetDrawLayer(DL_BACKGROUND)
        window:SetDrawTier(DT_LOW)
        window:SetDrawLevel(0)

        window:SetHandler("OnMouseDown", function(_, button)
            if button ~= LEFT_MOUSE_BUTTON then
                return
            end

            local header = self.headerControl
            if header and header.SetHidden then
                local isHidden = header:IsHidden()
                local height = header:GetHeight() or 0
                if not isHidden and height > 0 then
                    return
                end
            end

            self:_StartWindowMove()
        end)

        window:SetHandler("OnMouseUp", function(_, button)
            if button == LEFT_MOUSE_BUTTON then
                self:_StopWindowMove()
            end
        end)

        window:SetHandler("OnMoveStop", function()
            self:SaveWindowPosition()
        end)

        window:SetHandler("OnResizeStop", function()
            self:SaveWindowSize()
        end)

        self.window = window
    end

    local header = self.headerControl
    if not header then
        header = wm:CreateControl(HEADER_CONTROL_NAME, window, CT_CONTROL)
        header:SetAnchor(TOPLEFT, window, TOPLEFT, 0, 0)
        header:SetAnchor(TOPRIGHT, window, TOPRIGHT, 0, 0)
        header:SetHeight(DEFAULT_WINDOW_BARS.headerHeightPx)
        header:SetMouseEnabled(true)
        header:SetHandler("OnMouseDown", function(_, button)
            if button == LEFT_MOUSE_BUTTON then
                self:_StartWindowMove()
            end
        end)
        header:SetHandler("OnMouseUp", function(_, button)
            if button == LEFT_MOUSE_BUTTON then
                self:_StopWindowMove()
            end
        end)
        self.headerControl = header
    end

    local footer = self.footerControl
    if not footer then
        footer = wm:CreateControl(FOOTER_CONTROL_NAME, window, CT_CONTROL)
        footer:SetAnchor(BOTTOMLEFT, window, BOTTOMLEFT, 0, 0)
        footer:SetAnchor(BOTTOMRIGHT, window, BOTTOMRIGHT, 0, 0)
        footer:SetHeight(DEFAULT_WINDOW_BARS.footerHeightPx)
        footer:SetMouseEnabled(true)
        self.footerControl = footer
    end

    local scroll = self.scrollArea
    if not scroll then
        scroll = wm:CreateControlFromVirtual(SCROLL_CONTAINER_NAME, window, "ZO_ScrollContainer")
        if not scroll then
            scroll = wm:CreateControl(SCROLL_CONTAINER_NAME, window, CT_SCROLL)
        end
        if not scroll then
            return
        end
    end

    scroll:SetParent(window)
    scroll:ClearAnchors()
    scroll:SetAnchor(TOPLEFT, header, BOTTOMLEFT, 0, 0)
    scroll:SetAnchor(TOPRIGHT, header, BOTTOMRIGHT, 0, 0)
    scroll:SetAnchor(BOTTOMLEFT, footer, TOPLEFT, 0, 0)
    scroll:SetAnchor(BOTTOMRIGHT, footer, TOPRIGHT, 0, 0)
    scroll:SetMouseEnabled(true)
    scroll:SetClampedToScreen(false)
    self.scrollArea = scroll

    local scrollChild = self.scrollChild
    if not scrollChild then
        scrollChild = scroll:GetNamedChild("ScrollChild")
        if not scrollChild then
            scrollChild = wm:CreateControl(SCROLL_CHILD_NAME, scroll, CT_CONTROL)
            if scroll.SetScrollChild then
                scroll:SetScrollChild(scrollChild)
            end
        else
            if scrollChild.SetName then
                scrollChild:SetName(SCROLL_CHILD_NAME)
            end
        end
    end

    scrollChild:SetParent(scroll)
    scrollChild:ClearAnchors()
    scrollChild:SetAnchor(TOPLEFT, scroll, TOPLEFT, 0, 0)
    scrollChild:SetAnchor(TOPRIGHT, scroll, TOPRIGHT, 0, 0)
    if scrollChild.SetResizeToFitDescendents then
        scrollChild:SetResizeToFitDescendents(true)
    end
    scrollChild:SetMouseEnabled(false)
    self.scrollChild = scrollChild
end

function Host:RestoreWindowPositionFromSV(windowSettings)
    local settings = windowSettings or self:_EnsureWindowSettings()
    if not (self.window and settings) then
        return
    end

    local left = round(settings.left) or DEFAULT_WINDOW.left
    local top = round(settings.top) or DEFAULT_WINDOW.top

    self.window:ClearAnchors()
    if GuiRoot then
        self.window:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, left, top)
    else
        self.window:SetAnchor(TOPLEFT, nil, TOPLEFT, left, top)
    end
end

function Host:RestoreWindowSizeFromSV(windowSettings)
    local settings = windowSettings or self:_EnsureWindowSettings()
    if not (self.window and settings) then
        return
    end

    local width = clamp(tonumber(settings.width) or DEFAULT_WINDOW.width, MIN_WIDTH)
    local height = clamp(tonumber(settings.height) or DEFAULT_WINDOW.height, MIN_HEIGHT)

    self.window:SetDimensions(width, height)
end

function Host:UpdateHeaderFooterSizeFromSV(windowBars)
    local bars = windowBars or self:_EnsureWindowBarSettings()
    if not (self.headerControl and self.footerControl and self.scrollArea) then
        return
    end

    local headerHeight = clamp(tonumber(bars.headerHeightPx) or DEFAULT_WINDOW_BARS.headerHeightPx, 0, MAX_BAR_HEIGHT)
    local footerHeight = clamp(tonumber(bars.footerHeightPx) or DEFAULT_WINDOW_BARS.footerHeightPx, 0, MAX_BAR_HEIGHT)

    self.headerControl:SetHeight(headerHeight)
    self.headerControl:SetHidden(headerHeight <= 0)
    self.headerControl:SetMouseEnabled(headerHeight > 0)

    self.footerControl:SetHeight(footerHeight)
    self.footerControl:SetHidden(footerHeight <= 0)
    self.footerControl:SetMouseEnabled(footerHeight > 0)

    self.scrollArea:ClearAnchors()
    if headerHeight > 0 then
        self.scrollArea:SetAnchor(TOPLEFT, self.headerControl, BOTTOMLEFT, 0, 0)
        self.scrollArea:SetAnchor(TOPRIGHT, self.headerControl, BOTTOMRIGHT, 0, 0)
    else
        self.scrollArea:SetAnchor(TOPLEFT, self.window, TOPLEFT, 0, 0)
        self.scrollArea:SetAnchor(TOPRIGHT, self.window, TOPRIGHT, 0, 0)
    end

    if footerHeight > 0 then
        self.scrollArea:SetAnchor(BOTTOMLEFT, self.footerControl, TOPLEFT, 0, 0)
        self.scrollArea:SetAnchor(BOTTOMRIGHT, self.footerControl, TOPRIGHT, 0, 0)
    else
        self.scrollArea:SetAnchor(BOTTOMLEFT, self.window, BOTTOMLEFT, 0, 0)
        self.scrollArea:SetAnchor(BOTTOMRIGHT, self.window, BOTTOMRIGHT, 0, 0)
    end
end

function Host:ApplySavedSettings()
    if not self.window then
        return
    end

    self.windowSettings = nil
    self.windowBarSettings = nil

    local windowSettings = self:_EnsureWindowSettings()
    local windowBars = self:_EnsureWindowBarSettings()

    self.locked = windowSettings.locked == true
    self.window:SetMovable(not self.locked)
    self.window:SetResizeHandleSize(self.locked and 0 or RESIZE_HANDLE_SIZE)
    self.window:SetMouseEnabled(true)
    self.window:SetClampedToScreen(windowSettings.clamp ~= false)
    self.window:SetDrawTier(windowSettings.onTop and DT_HIGH or DT_LOW)

    self:RestoreWindowSizeFromSV(windowSettings)
    self:RestoreWindowPositionFromSV(windowSettings)
    if Nvk3UT and Nvk3UT.TrackerHostLayout and Nvk3UT.TrackerHostLayout.UpdateHeaderFooterSizes then
        Nvk3UT.TrackerHostLayout:UpdateHeaderFooterSizes()
    else
        self:UpdateHeaderFooterSizeFromSV(windowBars)
    end

    local visible = windowSettings.visible ~= false
    self.window:SetHidden(not visible)

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHost.ApplySavedSettings() lock=" .. tostring(self.locked))
    end
end

function Host:SaveWindowPosition()
    local windowSettings = self:_EnsureWindowSettings()
    if not (self.window and windowSettings) then
        return
    end

    local left = round(self.window:GetLeft())
    local top = round(self.window:GetTop())
    if left then
        windowSettings.left = left
    end
    if top then
        windowSettings.top = top
    end
end

function Host:SaveWindowSize()
    local windowSettings = self:_EnsureWindowSettings()
    if not (self.window and windowSettings) then
        return
    end

    local width = round(self.window:GetWidth())
    local height = round(self.window:GetHeight())
    if width then
        windowSettings.width = clamp(width, MIN_WIDTH)
    end
    if height then
        windowSettings.height = clamp(height, MIN_HEIGHT)
    end
end

function Host:SetVisible(isVisible)
    local windowSettings = self:_EnsureWindowSettings()
    local shouldShow = isVisible and true or false

    if self.window then
        self.window:SetHidden(not shouldShow)
    end

    windowSettings.visible = shouldShow

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHost.SetVisible(" .. tostring(shouldShow) .. ")")
    end
end

function Host:IsVisible()
    if self.window then
        return not self.window:IsHidden()
    end

    local settings = self.windowSettings or self:_EnsureWindowSettings()
    return settings and settings.visible ~= false
end

function Host:SetLocked(isLocked)
    local locked = isLocked and true or false
    local windowSettings = self:_EnsureWindowSettings()

    self.locked = locked
    windowSettings.locked = locked

    if self.window then
        self.window:SetMovable(not locked)
        self.window:SetResizeHandleSize(locked and 0 or RESIZE_HANDLE_SIZE)
    end

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHost.SetLocked(" .. tostring(locked) .. ")")
    end
end

function Host:IsLocked()
    return self.locked == true
end

function Host:GetBodyContainer()
    return self.scrollChild
end

function Host:GetHeaderControl()
    return self.headerControl
end

function Host:GetFooterControl()
    return self.footerControl
end

function Host:GetWindowControl()
    return self.window
end

local addon = Nvk3UT
if not addon then
    error("Nvk3UT_TrackerHost loaded before Nvk3UT_Core. Load order is wrong.")
end

addon.TrackerHost = Host
addon:RegisterModule("TrackerHost", Host)

return Host
