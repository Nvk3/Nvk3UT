-- Runtime/Nvk3UT_TrackerHostLayout.lua
local HostLayout = {}

local DEFAULT_HEADER_HEIGHT = 40
local DEFAULT_FOOTER_HEIGHT = 100
local MAX_BAR_HEIGHT = 250

local function clampHeight(value, defaultValue)
    local numeric = tonumber(value)
    if not numeric then
        numeric = defaultValue
    end

    if numeric < 0 then
        numeric = 0
    elseif numeric > MAX_BAR_HEIGHT then
        numeric = MAX_BAR_HEIGHT
    end

    return numeric
end

local function getTrackerHeight(tracker)
    if tracker and tracker.GetHeight then
        local ok, height = pcall(tracker.GetHeight, tracker)
        if ok then
            return tonumber(height) or 0
        end
    end

    return 0
end

function HostLayout:Init()
    self.host = Nvk3UT and Nvk3UT.TrackerHost or nil
    self._lastHeaderHeight = nil
    self._lastFooterHeight = nil
end

function HostLayout:OnPlayerActivated()
    self:UpdateHeaderFooterSizes()
    self:ApplyLayout()

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHostLayout.OnPlayerActivated() layout applied")
    end
end

function HostLayout:_ResolveHost()
    if not self.host then
        self.host = Nvk3UT and Nvk3UT.TrackerHost or nil
    end

    return self.host
end

function HostLayout:_ResolveWindowBars(host)
    if not host then
        return nil
    end

    if host._EnsureWindowBarSettings then
        return host:_EnsureWindowBarSettings()
    end

    if host.windowBarSettings then
        return host.windowBarSettings
    end

    local sv = host.sv
    if sv and type(sv.WindowBars) == "table" then
        return sv.WindowBars
    end

    return nil
end

function HostLayout:UpdateHeaderFooterSizes()
    local host = self:_ResolveHost()
    if not host then
        if Nvk3UT and Nvk3UT.Debug then
            Nvk3UT:Debug("TrackerHostLayout.UpdateHeaderFooterSizes() skipped - missing host")
        end
        return
    end

    local window = host.GetWindowControl and host:GetWindowControl() or host.window
    local header = host.GetHeaderControl and host:GetHeaderControl() or host.headerControl
    local footer = host.GetFooterControl and host:GetFooterControl() or host.footerControl
    local scroll = host.scrollArea

    if not (window and header and footer and scroll) then
        if Nvk3UT and Nvk3UT.Debug then
            Nvk3UT:Debug("TrackerHostLayout.UpdateHeaderFooterSizes() skipped - controls missing")
        end
        return
    end

    local bars = self:_ResolveWindowBars(host) or {}

    local headerHeight = clampHeight(bars.headerHeightPx, DEFAULT_HEADER_HEIGHT)
    local footerHeight = clampHeight(bars.footerHeightPx, DEFAULT_FOOTER_HEIGHT)

    if self._lastHeaderHeight == headerHeight and self._lastFooterHeight == footerHeight then
        if Nvk3UT and Nvk3UT.Debug then
            Nvk3UT:Debug(string.format(
                "TrackerHostLayout.UpdateHeaderFooterSizes() unchanged header=%d footer=%d",
                headerHeight,
                footerHeight
            ))
        end
        return
    end

    self._lastHeaderHeight = headerHeight
    self._lastFooterHeight = footerHeight

    bars.headerHeightPx = headerHeight
    bars.footerHeightPx = footerHeight

    if header.SetHeight then
        header:SetHeight(headerHeight)
    end

    if header.SetHidden then
        header:SetHidden(headerHeight <= 0)
    end

    if header.SetMouseEnabled then
        header:SetMouseEnabled(headerHeight > 0)
    end

    if footer.SetHeight then
        footer:SetHeight(footerHeight)
    end

    if footer.SetHidden then
        footer:SetHidden(footerHeight <= 0)
    end

    if footer.SetMouseEnabled then
        footer:SetMouseEnabled(footerHeight > 0)
    end

    scroll:ClearAnchors()

    if headerHeight > 0 then
        scroll:SetAnchor(TOPLEFT, header, BOTTOMLEFT, 0, 0)
        scroll:SetAnchor(TOPRIGHT, header, BOTTOMRIGHT, 0, 0)
    else
        scroll:SetAnchor(TOPLEFT, window, TOPLEFT, 0, 0)
        scroll:SetAnchor(TOPRIGHT, window, TOPRIGHT, 0, 0)
    end

    if footerHeight > 0 then
        scroll:SetAnchor(BOTTOMLEFT, footer, TOPLEFT, 0, 0)
        scroll:SetAnchor(BOTTOMRIGHT, footer, TOPRIGHT, 0, 0)
    else
        scroll:SetAnchor(BOTTOMLEFT, window, BOTTOMLEFT, 0, 0)
        scroll:SetAnchor(BOTTOMRIGHT, window, BOTTOMRIGHT, 0, 0)
    end

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug(string.format(
            "TrackerHostLayout.UpdateHeaderFooterSizes() header=%d footer=%d",
            headerHeight,
            footerHeight
        ))
    end
end

local function layoutSection(body, control, tracker, yOffset)
    if not control then
        return yOffset
    end

    control:ClearAnchors()
    control:SetAnchor(TOPLEFT, body, TOPLEFT, 0, yOffset)
    control:SetAnchor(TOPRIGHT, body, TOPRIGHT, 0, yOffset)

    if control.IsHidden and control:IsHidden() then
        return yOffset
    end

    local height = 0
    if control.GetHeight then
        height = control:GetHeight() or 0
    end

    local trackerHeight = getTrackerHeight(tracker)
    if trackerHeight > 0 then
        height = trackerHeight
    end

    if height < 0 then
        height = 0
    end

    return yOffset + height
end

function HostLayout:ApplyLayout()
    local host = self:_ResolveHost()
    if not host then
        if Nvk3UT and Nvk3UT.Debug then
            Nvk3UT:Debug("TrackerHostLayout.ApplyLayout() skipped - missing host")
        end
        return
    end

    local body = host.GetBodyContainer and host:GetBodyContainer() or host.scrollChild
    if not body then
        if Nvk3UT and Nvk3UT.Debug then
            Nvk3UT:Debug("TrackerHostLayout.ApplyLayout() skipped - missing body container")
        end
        return
    end

    local questTracker = Nvk3UT and Nvk3UT.QuestTracker or nil
    local achievementTracker = Nvk3UT and Nvk3UT.AchievementTracker or nil

    local yOffset = 0

    yOffset = layoutSection(body, host.questSectionControl, questTracker, yOffset)
    yOffset = layoutSection(body, host.achievementSectionControl, achievementTracker, yOffset)

    if body.SetHeight then
        body:SetHeight(yOffset)
    end

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHostLayout.ApplyLayout() finalYOffset=" .. tostring(yOffset))
    end
end

local addon = Nvk3UT
if not addon then
    error("Nvk3UT_TrackerHostLayout loaded before Nvk3UT_Core. Load order is wrong.")
end

addon.TrackerHostLayout = HostLayout
addon:RegisterModule("TrackerHostLayout", HostLayout)

return HostLayout
