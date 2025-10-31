Nvk3UT = Nvk3UT or {}

local Summary = {}
Nvk3UT.TodoSummary = Summary

local state = {
    parent = nil,
}

---Initialize the to-do summary placeholder.
---@param parentOrContainer any
---@return any
function Summary:Init(parentOrContainer)
    state.parent = parentOrContainer
    return parentOrContainer
end

---Refresh the to-do summary placeholder.
---@return any
function Summary:Refresh()
    return state.parent
end

---Set the visibility of the to-do summary placeholder.
---@param _isVisible boolean
function Summary:SetVisible(_isVisible)
    -- Intentionally left blank. The summary does not render any controls today.
end

---Get the measured height of the to-do summary placeholder.
---@return number
function Summary:GetHeight()
    return 0
end

return Summary
