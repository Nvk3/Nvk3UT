local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".QuestTrackerRows"

local function getAddon()
    return rawget(_G, addonName)
end

local function safeDebug(message, ...)
    local addon = getAddon()
    local debugFn = addon and addon.Debug

    if type(debugFn) ~= "function" then
        return
    end

    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, message, ...)
        if ok then
            debugFn(formatted)
        else
            debugFn(message)
        end
    else
        debugFn(message)
    end
end

function Rows:Init(parentContainer)
    self.parent = parentContainer
    self.rows = {}

    safeDebug("%s: Init with parent %s", MODULE_TAG, tostring(parentContainer))
end

function Rows:Reset()
    if self.rows then
        for index, control in ipairs(self.rows) do
            if control and control.SetHidden then
                control:SetHidden(true)
            end

            if control and control.ClearAnchors then
                control:ClearAnchors()
            end

            self.rows[index] = nil
        end
    end

    self.rows = {}
    self.viewModel = nil

    safeDebug("%s: Reset rows", MODULE_TAG)
end

function Rows:BuildOrRebuildRows(viewModel)
    self:Reset()

    self.viewModel = viewModel
    if type(viewModel) ~= "table" then
        safeDebug("%s: BuildOrRebuildRows called with missing viewModel", MODULE_TAG)
        return self.rows
    end

    local rows = self.rows
    local rowList = viewModel.rows or viewModel
    if type(rowList) ~= "table" then
        return rows
    end

    for _, entry in ipairs(rowList) do
        local control = entry and entry.control
        if control then
            table.insert(rows, control)
        end
    end

    safeDebug("%s: BuildOrRebuildRows completed with %d row(s)", MODULE_TAG, #rows)

    return rows
end

function Rows:GetRowControls()
    return self.rows or {}
end

Nvk3UT.QuestTrackerRows = Rows

return Rows
