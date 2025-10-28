--[[
    Nvk3UT_TrackerLayout.lua

    Shared layout helpers that stack tracker rows vertically and
    compute size metrics for tracker containers. The layout module
    does not create controls or own tracker state – controllers pass
    their row state so the helpers can position controls immediately
    without introducing batching, throttling, or pooling.
]]

local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local TrackerLayout = {}
TrackerLayout.__index = TrackerLayout

local function applyAnchors(layoutState, container, control, indentX, verticalPadding)
    if not (layoutState and container and control) then
        return
    end

    indentX = indentX or 0
    verticalPadding = verticalPadding or 0

    control:ClearAnchors()

    local lastControl = layoutState.lastAnchoredControl
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

    for index = 1, #layoutState.orderedControls do
        local control = layoutState.orderedControls[index]
        if control and type(refreshMetrics) == "function" then
            refreshMetrics(control)
        end
        if control and not control:IsHidden() then
            visibleCount = visibleCount + 1
            local width = (control:GetWidth() or 0) + (control.currentIndent or 0)
            if width > maxWidth then
                maxWidth = width
            end
            totalHeight = totalHeight + (control:GetHeight() or 0)
            if visibleCount > 1 then
                totalHeight = totalHeight + verticalPadding
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
    local tempState = {
        orderedControls = {},
        lastAnchoredControl = nil,
        contentWidth = 0,
        contentHeight = 0,
    }

    for index = 1, #(rows or {}) do
        local control = rows[index]
        if control then
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
