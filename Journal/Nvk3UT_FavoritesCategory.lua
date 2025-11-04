Nvk3UT = Nvk3UT or {}

local Category = {}
Nvk3UT.FavoritesCategory = Category

local Diagnostics = Nvk3UT and Nvk3UT.Diagnostics
local Utils = Nvk3UT and Nvk3UT.Utils
local Data = Nvk3UT and Nvk3UT.FavoritesData

local state = {
    parent = nil,
    host = nil,
    scrollList = nil,
    container = nil,
    dataTypeRegistered = false,
    visible = true,
    hasEntries = false,
}

local ROW_TYPE_ID = 1
local SCROLL_LIST_CONTROL_NAME = "Nvk3UT_FavoritesList"

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

local function resolveFavoritesScope()
    local root = Nvk3UT and Nvk3UT.sv
    local general = root and root.General
    local scope = general and general.favScope
    if type(scope) == "string" and scope ~= "" then
        return scope
    end
    return "account"
end

local function normalizeAchievementId(id)
    local normalized = safeCall(Utils and Utils.NormalizeAchievementId, id)
    if type(normalized) ~= "number" or normalized <= 0 then
        normalized = safeCall(Data and Data.NormalizeId, id)
    end
    if type(normalized) ~= "number" or normalized <= 0 then
        local numeric = tonumber(id)
        if numeric and numeric > 0 then
            normalized = math.floor(numeric)
        end
    end
    if type(normalized) ~= "number" or normalized <= 0 then
        return nil
    end
    return normalized
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

local function resolveHostControl(target)
    if type(target) == "userdata" then
        return target
    end

    if target and type(target.GetControl) == "function" then
        local ok, control = pcall(target.GetControl, target)
        if ok and type(control) == "userdata" then
            return control
        end
    end

    if target and type(target.GetNamedChild) == "function" then
        local ok, control = pcall(target.GetNamedChild, target, "Contents")
        if ok and type(control) == "userdata" then
            return control
        end
    end

    return nil
end

local function ensureScrollList()
    if state.scrollList and type(state.scrollList) == "userdata" then
        return state.scrollList
    end

    local host = state.host or resolveHostControl(state.parent)
    if not host or type(host) ~= "userdata" then
        return nil
    end

    if type(host.GetNamedChild) == "function" then
        local ok, existing = pcall(host.GetNamedChild, host, SCROLL_LIST_CONTROL_NAME)
        if ok and existing then
            state.scrollList = existing
            state.container = existing
            return existing
        end
    end

    local wm = WINDOW_MANAGER
    if not (wm and type(wm.CreateControlFromVirtual) == "function") then
        return nil
    end

    local control = wm:CreateControlFromVirtual(SCROLL_LIST_CONTROL_NAME, host, "ZO_ScrollList")
    if not control then
        return nil
    end

    control:ClearAnchors()
    control:SetAnchor(TOPLEFT, host, TOPLEFT, 0, 0)
    control:SetAnchor(BOTTOMRIGHT, host, BOTTOMRIGHT, 0, 0)
    control:SetHidden(true)

    state.scrollList = control
    state.container = control

    return control
end

local function goToAchievement(achievementId)
    if type(achievementId) ~= "number" then
        return
    end

    local achievements = (SYSTEMS and SYSTEMS:GetObject("achievements")) or ACHIEVEMENTS
    if not achievements then
        return
    end

    local categoryIndex, subCategoryIndex = GetCategoryInfoFromAchievementId(achievementId)
    if not achievements:OpenCategory(categoryIndex, subCategoryIndex) then
        if achievements.contentSearchEditBox and achievements.contentSearchEditBox:GetText() ~= "" then
            achievements.contentSearchEditBox:SetText("")
            ACHIEVEMENTS_MANAGER:ClearSearch(true)
        end
    end
    if achievements:OpenCategory(categoryIndex, subCategoryIndex) then
        if not achievements.achievementsById then
            return
        end
        local parentAchievementIndex = achievements:GetBaseAchievementId(achievementId)
        if not achievements.achievementsById[parentAchievementIndex] then
            achievements:ResetFilters()
        end
        if achievements.achievementsById[parentAchievementIndex] then
            achievements.achievementsById[parentAchievementIndex]:Expand()
            ZO_Scroll_ScrollControlIntoCentralView(
                achievements.contentList,
                achievements.achievementsById[parentAchievementIndex]:GetControl()
            )
        end
    end
end

local function setupDataRow(rowControl, rowData)
    if not (rowControl and rowData and rowData.achievementId) then
        return
    end

    local label = rowControl.GetNamedChild and rowControl:GetNamedChild("Text") or rowControl
    if label and label.SetText then
        local okName, name = pcall(GetAchievementInfo, rowData.achievementId)
        if okName and name then
            label:SetText(zo_strformat("<<1>>", name))
        else
            label:SetText(tostring(rowData.achievementId))
        end
    end

    local function openAchievement()
        goToAchievement(rowData.achievementId)
    end

    rowControl:SetHandler("OnMouseDoubleClick", function()
        openAchievement()
    end)

    rowControl:SetHandler("OnMouseUp", function(control, button, upInside)
        if button == MOUSE_BUTTON_INDEX_RIGHT and upInside then
            ClearMenu()
            AddCustomMenuItem(GetString(SI_ITEM_ACTION_LINK_TO_CHAT), function()
                local link = ZO_LinkHandler_CreateChatLink(GetAchievementLink, rowData.achievementId)
                ZO_LinkHandler_InsertLink(link)
            end)
            AddCustomMenuItem(GetString(SI_ITEM_ACTION_OPEN), function()
                openAchievement()
            end)
            AddCustomMenuItem("Aus Favoriten entfernen", function()
                local scope = resolveFavoritesScope()
                local removed = false
                if Data and Data.SetFavorited then
                    local ok, changed = pcall(Data.SetFavorited, rowData.achievementId, false, "FavoritesCategory:ContextRemove", scope)
                    removed = ok and changed ~= false
                end
                if removed then
                    local journal = Nvk3UT and Nvk3UT.Journal
                    if journal and type(journal.RefreshFavoritesIfVisible) == "function" then
                        pcall(journal.RefreshFavoritesIfVisible, journal, "FavoritesCategory:ContextRemove")
                    end
                end
            end)
            ShowMenu(control)
        end
    end)
end

local function setupScrollList()
    local scrollList = ensureScrollList()
    if not scrollList then
        return nil
    end

    if not state.dataTypeRegistered then
        ZO_ScrollList_AddDataType(scrollList, ROW_TYPE_ID, "ZO_SelectableLabel", 24, setupDataRow)
        state.dataTypeRegistered = true
    end

    return scrollList
end

local function collectFavoriteIds()
    ensureData()

    if not (Data and Data.GetAllFavorites) then
        return {}
    end

    local scope = resolveFavoritesScope()
    local iterator, iterState, key = safeCall(Data.GetAllFavorites, scope)
    if type(iterator) ~= "function" then
        return {}
    end

    local ids = {}
    for rawId, flagged in iterator, iterState, key do
        if flagged then
            local normalized = normalizeAchievementId(rawId)
            if normalized then
                local okInfo, _ = pcall(GetAchievementInfo, normalized)
                if okInfo then
                    ids[#ids + 1] = normalized
                end
            end
        end
    end

    table.sort(ids)

    return ids
end

local function applyVisibility()
    local scrollList = state.scrollList
    if not (scrollList and scrollList.SetHidden) then
        return
    end

    local shouldShow = (state.visible ~= false) and state.hasEntries
    scrollList:SetHidden(not shouldShow)
end

local function updateScrollList()
    local scrollList = setupScrollList()
    if not scrollList then
        state.hasEntries = false
        return nil, 0
    end

    local dataList = ZO_ScrollList_GetDataList(scrollList)
    if not dataList then
        state.hasEntries = false
        return scrollList, 0
    end

    ZO_ScrollList_Clear(scrollList)

    local ids = collectFavoriteIds()
    for index = 1, #ids do
        local achievementId = ids[index]
        dataList[#dataList + 1] = ZO_ScrollList_CreateDataEntry(ROW_TYPE_ID, { achievementId = achievementId }, 1)
    end

    ZO_ScrollList_Commit(scrollList)

    state.hasEntries = #ids > 0
    applyVisibility()

    return scrollList, #ids
end

---Initialize the favorites category container.
---@param parentOrContainer Control|any
---@return any
function Category:Init(parentOrContainer)
    state.parent = parentOrContainer

    local resolvedHost = resolveHostControl(parentOrContainer)
    if resolvedHost and resolvedHost ~= state.host then
        state.host = resolvedHost
        state.scrollList = nil
        state.container = nil
        state.dataTypeRegistered = false
    elseif not state.host then
        state.host = resolvedHost
    end

    local scrollList, count = updateScrollList()

    if scrollList then
        debugLog("Initialized favorites list (entries=%d)", count)
    end

    return scrollList or state.host or parentOrContainer
end

---Refresh the favorites category view.
---@return any
function Category:Refresh()
    local scrollList, count = updateScrollList()

    if scrollList then
        debugLog("Refresh completed (entries=%d)", count)
    end

    return scrollList
end

---Set the visibility of the favorites category container.
---@param isVisible boolean
function Category:SetVisible(isVisible)
    state.visible = isVisible ~= false
    applyVisibility()
end

---Get the measured height of the favorites container.
---@return number
function Category:GetHeight()
    local container = state.container or state.scrollList or state.host
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
