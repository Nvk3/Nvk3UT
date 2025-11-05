Nvk3UT = Nvk3UT or {}

local Category = {}
Nvk3UT.FavoritesCategory = Category

local Diagnostics = Nvk3UT and Nvk3UT.Diagnostics
local Utils = Nvk3UT and Nvk3UT.Utils
local Data = Nvk3UT and Nvk3UT.FavoritesData

local state = {
    parent = nil,
    host = nil,
    container = nil,
    hasFavorites = false,
}

local tableUnpack = table.unpack or unpack

local function safeCall(func, ...)
    local SafeCall = Nvk3UT and Nvk3UT.SafeCall
    if type(SafeCall) == "function" then
        return SafeCall(func, ...)
    end

    if type(func) ~= "function" then
        return nil
    end

    local results = { pcall(func, ...) }
    if not results[1] then
        return nil
    end

    table.remove(results, 1)
    return tableUnpack(results)
end

local function ensureData()
    if Data and Data.InitSavedVars then
        safeCall(Data.InitSavedVars)
    end
end

local function logShim(action)
    if Diagnostics and Diagnostics.Debug then
        Diagnostics.Debug("Favorites SHIM -> %s", tostring(action))
    end
end

local function isDebugEnabled()
    return Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and Utils and Utils.d
end

local function gatherChainIds(achievementId)
    local ids = {}
    if type(achievementId) ~= "number" then
        return ids
    end

    local normalize = Utils and Utils.NormalizeAchievementId
    local baseId = normalize and normalize(achievementId) or achievementId
    local seen = {}

    local function push(id)
        if type(id) == "number" and id ~= 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end

    push(baseId)

    local current = baseId
    while type(GetNextAchievementInLine) == "function" do
        local okNext, nextId = pcall(GetNextAchievementInLine, current)
        if not okNext or type(nextId) ~= "number" or nextId == 0 or seen[nextId] then
            break
        end
        push(nextId)
        current = nextId
    end

    if baseId ~= achievementId then
        push(achievementId)
    end

    return ids
end

local function resolveContainer()
    if state.container then
        return state.container
    end

    local host = state.host
    if not host or type(host) ~= "userdata" then
        return nil
    end

    local wm = WINDOW_MANAGER
    if not wm then
        return nil
    end

    local control = wm:CreateControl(nil, host, CT_CONTROL)
    control:SetHidden(true)
    control:SetResizeToFitDescendents(true)
    control:SetAnchor(TOPLEFT, host, TOPLEFT, 0, 0)
    control:SetAnchor(TOPRIGHT, host, TOPRIGHT, 0, 0)

    state.container = control
    return control
end

---Initialize the favorites category container.
---@param parentOrContainer Control|any
---@return any
function Category:Init(parentOrContainer)
    state.parent = parentOrContainer
    state.host = nil
    state.container = nil
    state.hasFavorites = false

    if type(parentOrContainer) == "userdata" then
        state.host = parentOrContainer
        state.container = parentOrContainer
    elseif parentOrContainer and type(parentOrContainer.GetControl) == "function" then
        local ok, control = pcall(parentOrContainer.GetControl, parentOrContainer)
        if ok and type(control) == "userdata" then
            state.host = control
            state.container = control
        end
    end

    if not state.host and parentOrContainer and type(parentOrContainer.GetNamedChild) == "function" then
        state.host = parentOrContainer
    end

    if not state.container then
        state.container = resolveContainer()
    end

    return state.container or state.host or parentOrContainer
end

local function debugLog(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local diagnostics = Nvk3UT and Nvk3UT.Diagnostics
    local message
    local ok, formatted = pcall(string.format, fmt, ...)
    if ok then
        message = formatted
    else
        message = tostring(fmt)
    end

    if diagnostics and diagnostics.Debug then
        diagnostics.Debug("FavoritesCategory %s", message)
    elseif Utils and Utils.d then
        Utils.d(string.format("[Favorites][Category] %s", message))
    end
end

local function toggleContainerHidden(isVisible)
    local container = state.container or state.host
    if container and container.SetHidden then
        container:SetHidden(isVisible == false)
    end
end

local function getFavoritesScope()
    if Data and type(Data.GetFavoritesScope) == "function" then
        local scope = safeCall(Data.GetFavoritesScope)
        if type(scope) == "string" and scope ~= "" then
            return scope
        end
    end

    local general = Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.General
    return (general and general.favScope) or "account"
end

local function hasFavoritesInScope(scope)
    if not (Data and Data.GetAllFavorites) then
        return false
    end

    local iterator, iterState, key = safeCall(Data.GetAllFavorites, scope)
    if type(iterator) ~= "function" then
        return false
    end

    for _, flagged in iterator, iterState, key do
        if flagged then
            return true
        end
    end

    return false
end

local function isFavoritesCategoryActive()
    local achievements = ACHIEVEMENTS
    if not achievements then
        return false
    end

    local tree = achievements.categoryTree
    if tree and tree.GetSelectedData then
        local selected = tree:GetSelectedData()
        if type(selected) == "table" then
            if selected.isNvkFavorites then
                return true
            end

            if selected.categoryIndex == "Nvk3UT_Favorites" then
                return true
            end
        end
    end

    return false
end

---Refresh the favorites category view.
---@return any
function Category:Refresh()
    local container = state.container or resolveContainer()
    if not container then
        return nil
    end

    -- The current journal shim still delegates rendering to the base UI
    -- integrations. For now, simply ensure the container's visibility reflects
    -- whether we have any favorites so later passes can flesh out the layout.
    local previousHasFavorites = state.hasFavorites == true

    ensureData()

    local scope = getFavoritesScope()
    local hasFavorites = hasFavoritesInScope(scope)

    local otherScopeHasFavorites = false
    if not hasFavorites then
        local alternate = scope == "account" and "character" or (scope == "character" and "account" or nil)
        if alternate then
            otherScopeHasFavorites = hasFavoritesInScope(alternate)
        end
    end

    state.hasFavorites = hasFavorites

    toggleContainerHidden(not hasFavorites)

    local shouldRefreshJournal = false
    if hasFavorites ~= previousHasFavorites and isFavoritesCategoryActive() then
        shouldRefreshJournal = true
    elseif not hasFavorites and otherScopeHasFavorites and isFavoritesCategoryActive() then
        shouldRefreshJournal = true
    end

    if shouldRefreshJournal then
        local achievements = ACHIEVEMENTS
        local refreshGroups = achievements and achievements.refreshGroups
        if refreshGroups and refreshGroups.RefreshAll then
            refreshGroups:RefreshAll("FullUpdate")
        end
    end

    return container
end

---Set the visibility of the favorites category container.
---@param isVisible boolean
function Category:SetVisible(isVisible)
    toggleContainerHidden(not isVisible)
end

---Get the measured height of the favorites container.
---@return number
function Category:GetHeight()
    local container = state.container or state.host
    if container and container.GetHeight then
        return container:GetHeight()
    end
    return 0
end

---Remove an achievement (and its chain siblings) from the favorites lists.
---@param achievementId number
---@return boolean removed
function Category:Remove(achievementId)
    ensureData()
    if type(achievementId) ~= "number" or not Data then
        return false
    end

    if not (Data.SetFavorited and Data.IsFavorited) then
        return false
    end

    local scopes = { "account", "character" }
    local removedAny = false
    local chainIds = gatherChainIds(achievementId)

    for _, candidateId in ipairs(chainIds) do
        for _, scope in ipairs(scopes) do
            if Data.IsFavorited(candidateId, scope) then
                Data.SetFavorited(candidateId, false, "Favorites:Remove", scope)
                removedAny = true
            end
        end
    end

    if removedAny then
        debugLog("Removed completed achievement %d", achievementId)
        local ui = Nvk3UT and Nvk3UT.UI
        if ui and ui.RefreshAchievements then
            safeCall(ui.RefreshAchievements)
        end
        if ui and ui.UpdateStatus then
            safeCall(ui.UpdateStatus)
        end
    end

    return removedAny
end

local Shim = {}
Nvk3UT.Favorites = Shim

function Shim.Init(...)
    logShim("Init")
    if type(Category.Init) ~= "function" then
        return nil
    end
    return safeCall(Category.Init, Category, ...)
end

function Shim.Refresh(...)
    logShim("Refresh")
    if type(Category.Refresh) ~= "function" then
        return nil
    end
    return safeCall(Category.Refresh, Category, ...)
end

function Shim.SetVisible(...)
    logShim("SetVisible")
    if type(Category.SetVisible) ~= "function" then
        return nil
    end
    return safeCall(Category.SetVisible, Category, ...)
end

function Shim.GetHeight(...)
    if type(Category.GetHeight) ~= "function" then
        return 0
    end
    local height = safeCall(Category.GetHeight, Category, ...)
    return tonumber(height) or 0
end

function Shim.Remove(...)
    logShim("Remove")
    if type(Category.Remove) ~= "function" then
        return false
    end
    local result = safeCall(Category.Remove, Category, ...)
    return result and true or false
end

return Category
