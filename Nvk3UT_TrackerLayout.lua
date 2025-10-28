--[[
    Nvk3UT_TrackerLayout.lua

    Shared layout helpers that operate on tracker row objects.
    Controllers build ordered row lists and pass them here so the
    layout can stack controls synchronously without throttling or
    deferred processing.
]]

Nvk3UT = Nvk3UT or {}

local TrackerLayout = {}
TrackerLayout.__index = TrackerLayout

local function isControl(value)
    return type(value) == "userdata"
end

local function isRow(value)
    return type(value) == "table"
        and type(value.MeasureHeight) == "function"
        and type(value.ApplyLayout) == "function"
        and type(value.GetWidthContribution) == "function"
end

local function setRowContainer(row, container)
    if not isRow(row) then
        return
    end

    if type(row.SetContainer) == "function" then
        row:SetContainer(container)
    end
end

local function getRowHiddenState(row)
    if not isRow(row) then
        return true
    end

    if type(row.IsHidden) == "function" then
        local ok, hidden = pcall(row.IsHidden, row)
        if ok then
            return hidden == true
        end
    end

    return false
end

local function getRowWidth(row)
    if not isRow(row) then
        return 0
    end

    local ok, width = pcall(row.GetWidthContribution, row)
    if ok and type(width) == "number" and width > 0 then
        return width
    end

    return 0
end

local function applyLayout(container, rows, options)
    local verticalPadding = (options and options.verticalPadding) or 0
    local maxWidth = 0
    local currentY = 0
    local visibleCount = 0

    if type(rows) ~= "table" then
        rows = {}
    end

    for index = 1, #rows do
        local row = rows[index]
        if isRow(row) and row:IsRenderable() then
            setRowContainer(row, container)

            local ok, height = pcall(row.MeasureHeight, row)
            if not ok or type(height) ~= "number" or height < 0 then
                height = 0
            end

            if not getRowHiddenState(row) and height > 0 then
                if visibleCount > 0 then
                    currentY = currentY + verticalPadding
                end

                local appliedHeight
                ok, appliedHeight = pcall(row.ApplyLayout, row, currentY)
                if ok and type(appliedHeight) == "number" and appliedHeight >= 0 then
                    height = appliedHeight
                end

                currentY = currentY + height
                visibleCount = visibleCount + 1

                local width = getRowWidth(row)
                if width > maxWidth then
                    maxWidth = width
                end
            end
        end
    end

    if isControl(container) and type(container.SetHeight) == "function" then
        container:SetHeight(currentY)
    end

    return maxWidth, currentY, visibleCount
end

function TrackerLayout.LayoutQuestTrackerRows(container, rows, options)
    local width, height = applyLayout(container, rows, options)
    return width, height
end

function TrackerLayout.LayoutAchievementTrackerRows(container, rows, options)
    local width, height = applyLayout(container, rows, options)
    return width, height
end

-- Backward compatibility: some legacy callers still reset layout state
-- objects that store ordered controls. The new row-based pipeline does
-- not require explicit reset helpers, but we keep these functions so
-- existing callers that invoke them continue to succeed harmlessly.
function TrackerLayout.ResetQuestLayout(state)
    if type(state) == "table" then
        state.rows = {}
        state.orderedControls = {}
    end
end

function TrackerLayout.ResetAchievementLayout(state)
    if type(state) == "table" then
        state.rows = {}
        state.orderedControls = {}
    end
end

Nvk3UT.TrackerLayout = TrackerLayout

return TrackerLayout
