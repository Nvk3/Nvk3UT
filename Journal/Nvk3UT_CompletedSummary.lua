Nvk3UT = Nvk3UT or {}

local Summary = {}
Nvk3UT.CompletedSummary = Summary

local state = {
    parent = nil,
}

---Initialize the completed summary placeholder.
---@param parentOrContainer any
---@return any
function Summary:Init(parentOrContainer)
    state.parent = parentOrContainer
    return parentOrContainer
end

---Refresh the completed summary placeholder.
---@return any
function Summary:Refresh()
    return state.parent
end

---Set the visibility of the completed summary placeholder.
---@param _isVisible boolean
function Summary:SetVisible(_isVisible)
    -- No completed summary UI is rendered today.
end

---Get the measured height of the completed summary placeholder.
---@return number
function Summary:GetHeight()
    return 0
end

return Summary
