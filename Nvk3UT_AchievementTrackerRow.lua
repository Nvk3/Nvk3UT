--[[
    Nvk3UT_AchievementTrackerRow.lua

    Row wrapper used by the achievement tracker so controllers can
    work with row objects instead of raw controls while preserving
    the immediate, synchronous refresh behaviour from the stable
    branch.
]]

Nvk3UT = Nvk3UT or {}

local AchievementTrackerRow = {}
AchievementTrackerRow.__index = AchievementTrackerRow

local function isControl(value)
    return type(value) == "userdata"
end

local function computeControlWidth(control)
    if not isControl(control) then
        return 0
    end

    if type(control.GetWidth) == "function" then
        local width = control:GetWidth()
        if type(width) == "number" and width > 0 then
            return width
        end
    end

    if type(control.GetDesiredWidth) == "function" then
        local desired = control:GetDesiredWidth()
        if type(desired) == "number" and desired > 0 then
            return desired
        end
    end

    if type(control.minWidth) == "number" and control.minWidth > 0 then
        return control.minWidth
    end

    return 0
end

local function applyDefaultLayout(row, yOffset)
    local control = row:GetControl()
    local container = row:GetContainer()

    if not (isControl(control) and isControl(container)) then
        return row:GetCachedHeight()
    end

    if type(control.ClearAnchors) == "function" then
        control:ClearAnchors()
    end

    local indent = row:GetIndent()

    if type(control.SetAnchor) == "function" then
        control:SetAnchor(TOPLEFT, container, TOPLEFT, indent, yOffset)
        control:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, yOffset)
    end

    control.currentIndent = indent

    local height = row:GetCachedHeight()
    if height <= 0 and type(control.GetHeight) == "function" then
        height = control:GetHeight() or 0
    end

    return height
end

function AchievementTrackerRow:New(params)
    params = params or {}

    local row = setmetatable({}, self)
    row.rowType = params.rowType
    row.key = params.key
    row.data = params.data
    row.control = params.control
    row.indent = params.indent or 0
    row.leftPadding = params.leftPadding or 0
    row.rightPadding = params.rightPadding or 0
    row.defaultHeight = params.defaultHeight or 0
    row.textPaddingY = params.textPaddingY or 0
    row.refreshFunc = params.refreshFunc
    row.measureFunc = params.measureFunc
    row.layoutFunc = params.layoutFunc
    row.widthFunc = params.widthFunc
    row.containerProvider = params.containerProvider
    row.container = params.container
    row.cachedHeight = 0
    row.explicitHidden = nil

    return row
end

function AchievementTrackerRow:SetRefreshFunction(callback)
    self.refreshFunc = callback
end

function AchievementTrackerRow:SetMeasureFunction(callback)
    self.measureFunc = callback
end

function AchievementTrackerRow:SetLayoutFunction(callback)
    self.layoutFunc = callback
end

function AchievementTrackerRow:SetWidthFunction(callback)
    self.widthFunc = callback
end

function AchievementTrackerRow:SetIndent(indent)
    if type(indent) == "number" then
        self.indent = indent
    end
end

function AchievementTrackerRow:SetDefaultHeight(height)
    if type(height) == "number" and height >= 0 then
        self.defaultHeight = height
    end
end

function AchievementTrackerRow:SetTextPadding(padding)
    if type(padding) == "number" and padding >= 0 then
        self.textPaddingY = padding
    end
end

function AchievementTrackerRow:SetContainer(container)
    self.container = container
end

function AchievementTrackerRow:GetContainer()
    if self.container then
        return self.container
    end

    if type(self.containerProvider) == "function" then
        return self.containerProvider(self)
    end

    return nil
end

function AchievementTrackerRow:GetControl()
    return self.control
end

function AchievementTrackerRow:IsControlValid()
    return isControl(self.control)
end

function AchievementTrackerRow:IsRenderable()
    return self:IsControlValid()
end

function AchievementTrackerRow:IsHidden()
    if self.explicitHidden ~= nil then
        return self.explicitHidden
    end

    local control = self.control
    if not isControl(control) then
        return true
    end

    local ok, hidden = pcall(function()
        if type(control.IsHidden) == "function" then
            return control:IsHidden()
        end
        return false
    end)

    if ok and hidden then
        local container = self:GetContainer()
        if isControl(container) and type(container.IsHidden) == "function" then
            local containerOk, containerHidden = pcall(container.IsHidden, container)
            if containerOk and containerHidden then
                return false
            end
        end
        return true
    end

    return false
end

function AchievementTrackerRow:GetIndent()
    return self.indent or 0
end

function AchievementTrackerRow:GetDefaultHeight()
    return self.defaultHeight or 0
end

function AchievementTrackerRow:GetTextPadding()
    return self.textPaddingY or 0
end

function AchievementTrackerRow:SetCachedHeight(height)
    if type(height) == "number" then
        self.cachedHeight = height
    else
        self.cachedHeight = 0
    end
end

function AchievementTrackerRow:GetCachedHeight()
    return self.cachedHeight or 0
end

function AchievementTrackerRow:RefreshVisual()
    if type(self.refreshFunc) == "function" then
        self.refreshFunc(self)
    end
end

function AchievementTrackerRow:SetHidden(hidden)
    local normalized = hidden == true
    self.explicitHidden = normalized

    local control = self.control
    if isControl(control) and type(control.SetHidden) == "function" then
        control:SetHidden(normalized)
    end
end

function AchievementTrackerRow:IsExplicitlyHidden()
    return self.explicitHidden
end

function AchievementTrackerRow:MeasureHeight()
    local height

    if type(self.measureFunc) == "function" then
        height = self.measureFunc(self)
    end

    if type(height) ~= "number" then
        local control = self.control
        if isControl(control) and type(control.GetHeight) == "function" then
            height = control:GetHeight()
        else
            height = self:GetDefaultHeight()
        end
    end

    if type(height) ~= "number" then
        height = 0
    end

    if height < 0 then
        height = 0
    end

    self.cachedHeight = height
    return height
end

function AchievementTrackerRow:ApplyLayout(yOffset)
    local height

    if type(self.layoutFunc) == "function" then
        height = self.layoutFunc(self, yOffset)
    end

    if type(height) ~= "number" then
        height = applyDefaultLayout(self, yOffset)
    end

    if type(height) ~= "number" then
        height = self:GetCachedHeight()
    end

    if type(height) ~= "number" or height < 0 then
        height = 0
    end

    self.cachedHeight = height
    return height
end

function AchievementTrackerRow:GetWidthContribution()
    local width

    if type(self.widthFunc) == "function" then
        width = self.widthFunc(self)
    end

    if type(width) ~= "number" then
        width = computeControlWidth(self.control) + self:GetIndent()
    end

    if width < 0 then
        width = 0
    end

    return width
end

Nvk3UT.AchievementTrackerRow = AchievementTrackerRow

return AchievementTrackerRow
