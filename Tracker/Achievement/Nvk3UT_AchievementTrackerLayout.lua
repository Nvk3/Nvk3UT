local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local MODULE_TAG = addonName .. ".AchievementTrackerLayout"

local ROW_GAP = 3
local HEADER_TO_ROWS_GAP = 3
local ROW_TEXT_PADDING_Y = 4
local CATEGORY_MIN_HEIGHT = 26
local ACHIEVEMENT_MIN_HEIGHT = 24
local OBJECTIVE_MIN_HEIGHT = 24
local CATEGORY_TOP_PADDING = 0
local OBJECTIVE_TOP_PADDING = 3
local OBJECTIVE_SPACING = 3
local OBJECTIVE_BOTTOM_PADDING = 0
local CATEGORY_BOTTOM_PAD_EXPANDED = 6
local CATEGORY_BOTTOM_PAD_COLLAPSED = 6
local BOTTOM_PIXEL_NUDGE = 3

local function logLoaded()
    local root = rawget(_G, addonName)
    if type(root) ~= "table" then
        return
    end

    local diagnostics = root.Diagnostics
    if diagnostics and type(diagnostics.DebugIfEnabled) == "function" then
        diagnostics:DebugIfEnabled(MODULE_TAG, "Loaded achievement tracker layout module")
    end
end

local function applySpacing(deps)
    if not deps then
        return
    end

    ROW_GAP = deps.VERTICAL_PADDING or ROW_GAP
    HEADER_TO_ROWS_GAP = deps.HEADER_TO_ROWS_GAP or HEADER_TO_ROWS_GAP or ROW_GAP
    ROW_TEXT_PADDING_Y = deps.ROW_TEXT_PADDING_Y or ROW_TEXT_PADDING_Y
    CATEGORY_BOTTOM_PAD_EXPANDED = deps.CATEGORY_BOTTOM_PAD_EXPANDED or CATEGORY_BOTTOM_PAD_EXPANDED
    CATEGORY_BOTTOM_PAD_COLLAPSED = deps.CATEGORY_BOTTOM_PAD_COLLAPSED or CATEGORY_BOTTOM_PAD_COLLAPSED
    CATEGORY_TOP_PADDING = deps.CATEGORY_TOP_PADDING or CATEGORY_TOP_PADDING
    ACHIEVEMENT_MIN_HEIGHT = deps.ACHIEVEMENT_MIN_HEIGHT or ACHIEVEMENT_MIN_HEIGHT
    OBJECTIVE_TOP_PADDING = deps.OBJECTIVE_TOP_PADDING or OBJECTIVE_TOP_PADDING or ROW_GAP
    OBJECTIVE_SPACING = deps.OBJECTIVE_SPACING or OBJECTIVE_SPACING or ROW_GAP
    OBJECTIVE_BOTTOM_PADDING = deps.OBJECTIVE_BOTTOM_PADDING or OBJECTIVE_BOTTOM_PADDING or 0
end

function Layout.UpdateSpacing(deps)
    applySpacing(deps)
end

function Layout.GetVerticalPadding()
    return ROW_GAP
end

function Layout.GetRowTextPaddingY()
    return ROW_TEXT_PADDING_Y
end

function Layout.GetRowGap()
    return ROW_GAP
end

function Layout.GetHeaderToRowsGap()
    return HEADER_TO_ROWS_GAP
end

function Layout.GetCategoryMinHeight()
    return CATEGORY_MIN_HEIGHT
end

function Layout.GetAchievementMinHeight()
    return ACHIEVEMENT_MIN_HEIGHT
end

function Layout.GetObjectiveMinHeight()
    return OBJECTIVE_MIN_HEIGHT
end

function Layout.GetCategoryBottomPadding(isExpanded)
    if isExpanded then
        return CATEGORY_BOTTOM_PAD_EXPANDED
    end

    return CATEGORY_BOTTOM_PAD_COLLAPSED
end

function Layout.GetCategoryTopPadding()
    return CATEGORY_TOP_PADDING
end

function Layout.GetBottomPixelNudge()
    return BOTTOM_PIXEL_NUDGE
end

function Layout.GetRowMinHeight(rowType)
    if rowType == "category" then
        return Layout.GetCategoryMinHeight()
    elseif rowType == "achievement" then
        return Layout.GetAchievementMinHeight()
    elseif rowType == "objective" then
        return Layout.GetObjectiveMinHeight()
    end

    return 0
end

local function normalizeHeight(value)
    local numeric = tonumber(value)
    if not numeric then
        return 0
    end

    if numeric ~= numeric then
        return 0
    end

    if numeric < 0 then
        return 0
    end

    return numeric
end

function Layout.ComputeRowHeight(rowType, textHeight)
    local baseTextHeight = normalizeHeight(textHeight)
    local targetHeight = baseTextHeight + Layout.GetRowTextPaddingY()
    local minHeight = Layout.GetRowMinHeight(rowType)

    if minHeight > 0 then
        targetHeight = math.max(minHeight, targetHeight)
    end

    return targetHeight
end

local function normalizeSubrowCandidate(objective)
    if not objective then
        return nil
    end

    if objective.isVisible == false then
        return nil
    end

    if objective.isComplete then
        return nil
    end

    local maxValue = tonumber(objective.max)
    local currentValue = tonumber(objective.current)

    if maxValue and currentValue and maxValue > 0 and currentValue >= maxValue then
        return nil
    end

    local description = objective.description
    if description == nil or description == "" then
        return nil
    end

    return objective
end

function Layout.ComputeEntrySubrowCount(entry)
    if not entry then
        return 0
    end

    local objectives = entry.objectives
    if type(objectives) ~= "table" then
        return 0
    end

    local count = 0
    for index = 1, #objectives do
        if normalizeSubrowCandidate(objectives[index]) then
            count = count + 1
        end
    end

    return count
end

function Layout.ShouldDisplayObjective(objective)
    return normalizeSubrowCandidate(objective) ~= nil
end

local function getSubrowSpacing()
    return OBJECTIVE_SPACING or Layout.GetVerticalPadding()
end

local function getSubrowTopSpacing()
    return OBJECTIVE_TOP_PADDING or getSubrowSpacing()
end

local function computeSubrowHeight(rowType, textHeight)
    return Layout.ComputeRowHeight(rowType, textHeight)
end

function Layout.GetSubrowHeight(rowType, textHeight)
    return computeSubrowHeight(rowType, textHeight)
end

function Layout.GetSubrowSpacing()
    return getSubrowSpacing()
end

function Layout.ComputeEntryHeight(entry, baseRowHeight, subrowHeights)
    local totalHeight = normalizeHeight(baseRowHeight)
    local spacing = getSubrowSpacing()
    local topSpacing = getSubrowTopSpacing()
    local bottomSpacing = OBJECTIVE_BOTTOM_PADDING or 0

    local objectives = entry and entry.objectives
    local hasObjectives = type(objectives) == "table"
    local addedSubrows = 0

    if hasObjectives and type(subrowHeights) == "table" then
        for index = 1, #subrowHeights do
            local subrowHeight = normalizeHeight(subrowHeights[index])
            if subrowHeight > 0 then
                if totalHeight > 0 then
                    if addedSubrows == 0 then
                        totalHeight = totalHeight + topSpacing
                    else
                        totalHeight = totalHeight + spacing
                    end
                end
                totalHeight = totalHeight + subrowHeight
                addedSubrows = addedSubrows + 1
            end
        end
    end

    if addedSubrows > 0 then
        totalHeight = totalHeight + bottomSpacing
    end

    return totalHeight
end

function Layout.ComputeTotalHeight(rowHeights)
    local totalHeight = 0
    if type(rowHeights) ~= "table" then
        return totalHeight
    end

    local verticalPadding = Layout.GetVerticalPadding() or 0
    for index = 1, #rowHeights do
        local rowHeight = normalizeHeight(rowHeights[index])
        totalHeight = totalHeight + rowHeight

        if index > 1 then
            totalHeight = totalHeight + verticalPadding
        end
    end

    return totalHeight
end

function Layout.ComputeHeight(_, currentHeightFallback)
    if currentHeightFallback ~= nil then
        return currentHeightFallback
    end

    return 0
end

function Layout.Apply(_, _, currentHeightFallback)
    if currentHeightFallback ~= nil then
        return currentHeightFallback
    end

    return 0
end

logLoaded()

Nvk3UT.AchievementTrackerLayout = Layout

return Layout
