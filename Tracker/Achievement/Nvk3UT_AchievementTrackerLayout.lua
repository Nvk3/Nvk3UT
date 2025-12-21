local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local MODULE_TAG = addonName .. ".AchievementTrackerLayout"

local VERTICAL_PADDING = 3
local ROW_TEXT_PADDING_Y = 8
local CATEGORY_MIN_HEIGHT = 26
local ACHIEVEMENT_MIN_HEIGHT = 24
local OBJECTIVE_MIN_HEIGHT = 20

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

function Layout.GetVerticalPadding()
    return VERTICAL_PADDING
end

function Layout.GetRowTextPaddingY()
    return ROW_TEXT_PADDING_Y
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

function Layout.ComputeTotalHeight(rowHeights)
    local totalHeight = 0
    if type(rowHeights) ~= "table" then
        return totalHeight
    end

    for index = 1, #rowHeights do
        local rowHeight = normalizeHeight(rowHeights[index])
        totalHeight = totalHeight + rowHeight

        if index > 1 then
            totalHeight = totalHeight + Layout.GetVerticalPadding()
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
