local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local DEFAULT_VERTICAL_PADDING = 3

local function GetContainerWidth(parent)
    if not parent or not parent.GetWidth then
        return 0
    end

    local width = parent:GetWidth()
    if not width or width <= 0 then
        return 0
    end

    return width
end

local function ApplyRowMetrics(control, layoutCtx, rowData)
    if not control or not control.label then
        return
    end

    rowData = rowData or {}

    local indent = rowData.indent or 0
    local toggleWidth = rowData.toggleWidth or 0
    local leftPadding = rowData.leftPadding or 0
    local rightPadding = rowData.rightPadding or 0
    local minHeight = rowData.minHeight

    local containerWidth = GetContainerWidth(layoutCtx and layoutCtx.parent)
    local availableWidth = containerWidth - indent - toggleWidth - leftPadding - rightPadding
    if availableWidth < 0 then
        availableWidth = 0
    end

    control.label:SetWidth(availableWidth)

    local textHeight = control.label:GetTextHeight() or 0
    local targetHeight = textHeight + (rowData.textPaddingY or 0)
    if minHeight then
        targetHeight = math.max(minHeight, targetHeight)
    end

    control:SetHeight(targetHeight)
end

local function RefreshControlMetrics(control, layoutCtx)
    if not control or not control.label then
        return
    end

    local indent = control.currentIndent or 0
    local rowData = control.layoutRowData or {}
    rowData.indent = indent

    ApplyRowMetrics(control, layoutCtx, rowData)
end

local function AnchorControl(control, layoutCtx, indentX)
    if not control or not layoutCtx then
        return
    end

    indentX = indentX or 0
    control:ClearAnchors()

    if layoutCtx.lastAnchoredControl then
        local previousIndent = layoutCtx.lastAnchoredControl.currentIndent or 0
        local offsetX = indentX - previousIndent
        control:SetAnchor(TOPLEFT, layoutCtx.lastAnchoredControl, BOTTOMLEFT, offsetX, layoutCtx.verticalPadding)
        control:SetAnchor(TOPRIGHT, layoutCtx.lastAnchoredControl, BOTTOMRIGHT, 0, layoutCtx.verticalPadding)
    else
        control:SetAnchor(TOPLEFT, layoutCtx.parent, TOPLEFT, indentX, 0)
        control:SetAnchor(TOPRIGHT, layoutCtx.parent, TOPRIGHT, 0, 0)
    end

    layoutCtx.lastAnchoredControl = control
    layoutCtx.orderedControls[#layoutCtx.orderedControls + 1] = control
    control.currentIndent = indentX
end

function Layout:Init()
end

function Layout:BeginLayout(parent, opts)
    local layoutCtx = {}
    layoutCtx.parent = parent
    layoutCtx.verticalPadding = (opts and opts.verticalPadding) or DEFAULT_VERTICAL_PADDING
    layoutCtx.orderedControls = {}
    layoutCtx.lastAnchoredControl = nil
    layoutCtx.textPaddingY = opts and opts.textPaddingY or 0

    return layoutCtx
end

function Layout:ApplyRowLayout(control, rowType, rowData, layoutCtx)
    if not control or not layoutCtx then
        return
    end

    rowData = rowData or {}
    rowData.textPaddingY = rowData.textPaddingY or layoutCtx.textPaddingY or 0
    control.layoutRowData = rowData

    ApplyRowMetrics(control, layoutCtx, rowData)

    if control.SetHidden then
        control:SetHidden(false)
    end

    AnchorControl(control, layoutCtx, rowData.indent or 0)
end

function Layout:FinishLayout(layoutCtx)
    if not layoutCtx then
        return 0, 0
    end

    local maxWidth = 0
    local totalHeight = 0
    local visibleCount = 0

    for index = 1, #layoutCtx.orderedControls do
        local control = layoutCtx.orderedControls[index]
        if control then
            RefreshControlMetrics(control, layoutCtx)
        end
        if control and not control:IsHidden() then
            visibleCount = visibleCount + 1
            local width = (control:GetWidth() or 0) + (control.currentIndent or 0)
            if width > maxWidth then
                maxWidth = width
            end
            totalHeight = totalHeight + (control:GetHeight() or 0)
            if visibleCount > 1 then
                totalHeight = totalHeight + layoutCtx.verticalPadding
            end
        end
    end

    return maxWidth, totalHeight
end

Nvk3UT.AchievementTrackerLayout = Layout

return Layout
