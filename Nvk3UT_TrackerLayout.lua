--[[
    Nvk3UT_TrackerLayout.lua

    Shared layout helpers that stack tracker rows vertically and
    compute size metrics for tracker containers. The layout module
    does not create controls or own tracker state – controllers pass
    their row state so the helpers can position controls immediately
    without introducing batching, throttling, or pooling.
]]

Nvk3UT = Nvk3UT or {}

local TrackerLayout = {}
TrackerLayout.__index = TrackerLayout

local function isControl(value)
    return type(value) == "userdata"
end

local function canAnchor(control)
    return isControl(control)
        and type(control.ClearAnchors) == "function"
        and type(control.SetAnchor) == "function"
end

local function isVisibleControl(control)
    return isControl(control) and type(control.IsHidden) == "function"
end

local function getWidth(control)
    if not isControl(control) then
        return 0
    end

    if type(control.GetWidth) == "function" then
        local width = control:GetWidth()
        if type(width) == "number" and width > 0 then
            return width
        end
    end

    if type(control.minWidth) == "number" then
        return control.minWidth
    end

    return 0
end

local function getHeight(control, defaultHeight)
    if not isControl(control) then
        return defaultHeight or 0
    end

    if type(control.GetHeight) == "function" then
        local height = control:GetHeight()
        if type(height) == "number" and height > 0 then
            return height
        end
    end

    if type(control.GetDesiredHeight) == "function" then
        local desired = control:GetDesiredHeight()
        if type(desired) == "number" and desired > 0 then
            return desired
        end
    end

    if type(control.minHeight) == "number" then
        return control.minHeight
    end

    if type(defaultHeight) == "number" then
        return defaultHeight
    end

    return 0
end

local function applyAnchors(layoutState, container, control, indentX, verticalPadding)
    if not (layoutState and canAnchor(control) and isControl(container)) then
        return
    end

    indentX = indentX or 0
    verticalPadding = verticalPadding or 0

    control:ClearAnchors()

    local lastControl = layoutState.lastAnchoredControl
    if not canAnchor(lastControl) then
        lastControl = nil
        layoutState.lastAnchoredControl = nil
    end

    if lastControl then
        local previousIndent = lastControl.currentIndent or 0
        local offsetX = indentX - previousIndent
        control:SetAnchor(TOPLEFT, lastControl, BOTTOMLEFT, offsetX, verticalPadding)
        control:SetAnchor(TOPRIGHT, lastControl, BOTTOMRIGHT, 0, verticalPadding)
    else
        control:SetAnchor(TOPLEFT, container, TOPLEFT, indentX, 0)
        control:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, 0)
    end

    layoutState.lastAnchoredControl = control
    layoutState.orderedControls[#layoutState.orderedControls + 1] = control
    control.currentIndent = indentX
end

local function computeMetrics(layoutState, verticalPadding, refreshMetrics)
    verticalPadding = verticalPadding or 0

    local maxWidth = 0
    local totalHeight = 0
    local visibleCount = 0
    local defaultHeight = layoutState and layoutState.defaultHeight

    for index = 1, #layoutState.orderedControls do
        local control = layoutState.orderedControls[index]
        if isVisibleControl(control) then
            if type(refreshMetrics) == "function" then
                refreshMetrics(control)
            end

            local isHidden = true
            local ok, hidden = pcall(control.IsHidden, control)
            if ok then
                isHidden = hidden
            end

            if not isHidden then
                visibleCount = visibleCount + 1

                local width = getWidth(control) + (control.currentIndent or 0)
                if width > maxWidth then
                    maxWidth = width
                end

                totalHeight = totalHeight + getHeight(control, defaultHeight)
                if visibleCount > 1 then
                    totalHeight = totalHeight + verticalPadding
                end
            end
        end
    end

    layoutState.contentWidth = maxWidth
    layoutState.contentHeight = totalHeight

    return maxWidth, totalHeight
end

local function resetLayout(layoutState)
    if not layoutState then
        return
    end

    layoutState.orderedControls = {}
    layoutState.lastAnchoredControl = nil
end

function TrackerLayout.ResetQuestLayout(state)
    resetLayout(state)
end

function TrackerLayout.ResetAchievementLayout(state)
    resetLayout(state)
end

function TrackerLayout.AnchorQuestRow(state, container, control, indentX, verticalPadding)
    applyAnchors(state, container, control, indentX, verticalPadding)
end

function TrackerLayout.AnchorAchievementRow(state, container, control, indentX, verticalPadding)
    applyAnchors(state, container, control, indentX, verticalPadding)
end

local function layoutRows(container, rows, options)
    local verticalPadding = options and options.verticalPadding or 0
    local refreshMetrics = options and options.refreshMetrics
    local defaultHeight = options and options.defaultHeight

    if not isControl(container) then
        return 0, 0
    end

    local tempState = {
        orderedControls = {},
        lastAnchoredControl = nil,
        contentWidth = 0,
        contentHeight = 0,
        defaultHeight = defaultHeight,
    }

    for index = 1, #(rows or {}) do
        local control = rows[index]
        if canAnchor(control) then
            local indent = control.currentIndent or 0
            applyAnchors(tempState, container, control, indent, verticalPadding)
        end
    end

    computeMetrics(tempState, verticalPadding, refreshMetrics)
    return tempState.contentWidth or 0, tempState.contentHeight or 0
end

function TrackerLayout.LayoutQuestTrackerRows(container, rows, options)
    return layoutRows(container, rows, options)
end

function TrackerLayout.LayoutAchievementTrackerRows(container, rows, options)
    return layoutRows(container, rows, options)
end

function TrackerLayout.UpdateQuestContentSize(state, verticalPadding, refreshMetrics)
    return computeMetrics(state, verticalPadding, refreshMetrics)
end

function TrackerLayout.UpdateAchievementContentSize(state, verticalPadding, refreshMetrics)
    return computeMetrics(state, verticalPadding, refreshMetrics)
end

Nvk3UT.TrackerLayout = TrackerLayout

return TrackerLayout
