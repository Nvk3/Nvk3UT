--[[
    Nvk3UT_QuestTrackerRow.lua

    Defines a lightweight quest-tracker row wrapper that stores
    references to quest row data and the underlying UI control.
    The row exposes helpers so controllers can refresh visuals,
    measure wrapped height, and apply layout immediately without
    introducing throttling or deferred updates.
]]

Nvk3UT = Nvk3UT or {}

local QuestTrackerRow = {}
QuestTrackerRow.__index = QuestTrackerRow

local function isControl(value)
    return type(value) == "userdata"
end

local function safeCall(method, ...)
    if type(method) == "function" then
        return method(...)
    end
end

function QuestTrackerRow:New(params)
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

    return row
end

function QuestTrackerRow:SetRefreshFunction(callback)
    self.refreshFunc = callback
end

function QuestTrackerRow:SetMeasureFunction(callback)
    self.measureFunc = callback
end

function QuestTrackerRow:SetLayoutFunction(callback)
    self.layoutFunc = callback
end

function QuestTrackerRow:SetWidthFunction(callback)
    self.widthFunc = callback
end

function QuestTrackerRow:SetIndent(indent)
    if type(indent) == "number" then
        self.indent = indent
    end
end

function QuestTrackerRow:SetDefaultHeight(height)
    if type(height) == "number" and height >= 0 then
        self.defaultHeight = height
    end
end

function QuestTrackerRow:SetTextPadding(padding)
    if type(padding) == "number" and padding >= 0 then
        self.textPaddingY = padding
    end
end

function QuestTrackerRow:SetContainer(container)
    self.container = container
end

function QuestTrackerRow:GetContainer()
    if self.container then
        return self.container
    end

    if type(self.containerProvider) == "function" then
        return self.containerProvider(self)
    end

    return nil
end

function QuestTrackerRow:GetControl()
    return self.control
end

function QuestTrackerRow:IsControlValid()
    return isControl(self.control)
end

function QuestTrackerRow:IsRenderable()
    return self:IsControlValid()
end

function QuestTrackerRow:IsHidden()
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

    if ok then
        return hidden == true
    end

    return false
end

function QuestTrackerRow:GetIndent()
    return self.indent or 0
end

function QuestTrackerRow:GetDefaultHeight()
    return self.defaultHeight or 0
end

function QuestTrackerRow:GetTextPadding()
    return self.textPaddingY or 0
end

function QuestTrackerRow:SetCachedHeight(height)
    if type(height) == "number" then
        self.cachedHeight = height
    else
        self.cachedHeight = 0
    end
end

function QuestTrackerRow:GetCachedHeight()
    return self.cachedHeight or 0
end

function QuestTrackerRow:RefreshVisual()
    if type(self.refreshFunc) == "function" then
        self.refreshFunc(self)
    end
end

function QuestTrackerRow:MeasureHeight()
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

function QuestTrackerRow:ApplyLayout(yOffset)
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

function QuestTrackerRow:GetWidthContribution()
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

Nvk3UT.QuestTrackerRow = QuestTrackerRow

return QuestTrackerRow
