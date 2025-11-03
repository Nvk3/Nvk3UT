-- UI/Nvk3UT_ChatAchievementContext.lua
-- TODO(EVENTS_REFACTOR): Move initialization into the future Events bootstrap once available.

Nvk3UT = Nvk3UT or {}

local ChatContext = {}
Nvk3UT.ChatAchievementContext = ChatContext

local function debug(fmt, ...)
    local diag = Nvk3UT and Nvk3UT.Diagnostics
    if diag and type(diag.Debug) == "function" then
        diag.Debug("[ChatAchievementContext] " .. tostring(fmt), ...)
    end
end

local function registerString(id, text)
    if type(id) ~= "string" or id == "" then
        return
    end
    if _G[id] == nil then
        ZO_CreateStringId(id, text)
    end
    SafeAddString(_G[id], text, 1)
end

local function ensureStringIds()
    registerString("SI_NVK3UT_CTX_OPEN_ACHIEVEMENT", "In Errungenschaften öffnen")
    registerString("SI_NVK3UT_CTX_FAVORITE_ADD", "Zu Favoriten hinzufügen")
    registerString("SI_NVK3UT_CTX_FAVORITE_REMOVE", "Von Favoriten entfernen")
end

local function getAchievementsSystem()
    if SYSTEMS and type(SYSTEMS.GetObject) == "function" then
        local ok, result = pcall(SYSTEMS.GetObject, SYSTEMS, "achievements")
        if ok and result then
            return result
        end
    end

    return ACHIEVEMENTS
end

local function getCategoryIndicesForAchievement(achievementId)
    local numeric = tonumber(achievementId)
    if not numeric or numeric <= 0 then
        return nil, nil
    end

    local candidates = {
        _G.GetAchievementCategoryInfoFromAchievementId,
        _G.GetCategoryInfoFromAchievementId,
    }

    for index = 1, #candidates do
        local fn = candidates[index]
        if type(fn) == "function" then
            local ok, categoryIndex, subCategoryIndex = pcall(fn, numeric)
            if ok and categoryIndex then
                return categoryIndex, subCategoryIndex
            end
        end
    end

    return nil, nil
end

local function scrollIntoView(container, control)
    if not container or not control then
        return
    end

    if type(ZO_Scroll_ScrollIntoView) == "function" then
        ZO_Scroll_ScrollIntoView(container, control, 20)
    elseif type(ZO_Scroll_ScrollControlIntoCentralView) == "function" then
        ZO_Scroll_ScrollControlIntoCentralView(container, control)
    end
end

local function resolveContentContainer(achievements)
    if not achievements then
        return nil
    end

    return achievements.contentListScroll or achievements.contentList or achievements.listControl or achievements.scroll
end

local NAVIGATION_RETRY_MS = 50
local NAVIGATION_MAX_ATTEMPTS = 10

local function focusAchievementEntry(achievements, achievementId)
    if not achievements then
        return false
    end

    local numeric = tonumber(achievementId)
    if not numeric or numeric <= 0 then
        return false
    end

    if type(achievements.FocusAchievement) == "function" then
        local ok = pcall(achievements.FocusAchievement, achievements, numeric)
        if ok then
            return true
        end
    end

    local byId = achievements.achievementsById
    if type(byId) == "table" then
        local entry = byId[achievementId] or byId[numeric] or byId[tostring(achievementId)]
        if entry then
            if type(entry.Expand) == "function" then
                pcall(entry.Expand, entry)
            end
            if type(entry.Select) == "function" then
                local ok, result = pcall(entry.Select, entry)
                if ok and result ~= false then
                    if type(entry.GetControl) == "function" then
                        local control = entry:GetControl()
                        if control then
                            scrollIntoView(resolveContentContainer(achievements), control)
                        end
                    end
                    return true
                end
            end
            if type(entry.Show) == "function" then
                local ok = pcall(entry.Show, entry)
                if ok then
                    return true
                end
            end
        end
    end

    local tree = achievements.categoryTree
    if not tree then
        return false
    end

    local lookupSources = {
        tree.nodeLookupData,
        achievements.nodeLookupData,
    }
    for _, lookup in ipairs(lookupSources) do
        if type(lookup) == "table" then
            local node = lookup[achievementId] or lookup[numeric] or lookup[tostring(achievementId)]
            if node then
                if type(tree.SelectNode) == "function" then
                    local ok, result = pcall(tree.SelectNode, tree, node)
                    if ok and result ~= false then
                        return true
                    end
                end
                if type(node.Select) == "function" then
                    local ok = pcall(node.Select, node)
                    if ok then
                        return true
                    end
                end
            end
        end
    end

    local visited = {}
    local function visit(node)
        if not node or visited[node] then
            return nil
        end
        visited[node] = true

        local data = node.data
        if data then
            local dataId = data.achievementId or data.id
            if dataId == achievementId or dataId == numeric then
                return node
            end
        end

        local children = node.children
        if type(children) == "table" then
            for i = 1, #children do
                local found = visit(children[i])
                if found then
                    return found
                end
            end
        end

        return nil
    end

    local root
    if type(tree.GetRootNode) == "function" then
        local ok, result = pcall(tree.GetRootNode, tree)
        if ok then
            root = result
        end
    end
    root = root or tree.rootNode

    local target = visit(root)
    if target then
        if type(tree.SelectNode) == "function" then
            local ok, result = pcall(tree.SelectNode, tree, target)
            if ok and result ~= false then
                return true
            end
        end
        if type(target.Select) == "function" then
            local ok = pcall(target.Select, target)
            if ok then
                return true
            end
        end
    end

    return false
end

local function selectCategoryForAchievement(achievements, categoryIndex, subCategoryIndex)
    if not achievements or not categoryIndex then
        return false
    end

    local selectors = {
        "SelectCategoryByIndices",
        "SelectCategoryIndices",
        "SelectCategory",
        "OpenCategory",
        "NavigateToCategory",
    }

    for i = 1, #selectors do
        local method = achievements[selectors[i]]
        if type(method) == "function" then
            local ok = pcall(method, achievements, categoryIndex, subCategoryIndex)
            if ok then
                return true
            end
        end
    end

    local manager = rawget(_G, "ACHIEVEMENTS_MANAGER")
    if manager then
        local managerSelectors = {
            "SelectCategoryByIndices",
            "SetCategory",
        }

        for i = 1, #managerSelectors do
            local method = manager[managerSelectors[i]]
            if type(method) == "function" then
                local ok = pcall(method, manager, categoryIndex, subCategoryIndex)
                if ok then
                    return true
                end
            end
        end
    end

    local tree = achievements.categoryTree
    if tree and type(tree.SelectNode) == "function" then
        local root
        if type(tree.GetRootNode) == "function" then
            local ok, result = pcall(tree.GetRootNode, tree)
            if ok then
                root = result
            end
        end
        root = root or tree.rootNode

        local function selectNode(node)
            if not node then
                return false
            end
            local ok = pcall(tree.SelectNode, tree, node)
            if ok then
                return true
            end
            if type(node.Select) == "function" then
                local nodeOk = pcall(node.Select, node)
                if nodeOk then
                    return true
                end
            end
            return false
        end

        if root and type(root.children) == "table" then
            local categoryNode = root.children[categoryIndex]
            if categoryNode then
                if subCategoryIndex and type(categoryNode.children) == "table" then
                    local subNode = categoryNode.children[subCategoryIndex]
                    if selectNode(subNode) then
                        return true
                    end
                end
                if selectNode(categoryNode) then
                    return true
                end
            end
        end
    end

    return false
end

local function showAchievementsScene()
    local sceneManager = SCENE_MANAGER
    if sceneManager and type(sceneManager.Show) == "function" then
        sceneManager:Show("achievements")
        return true
    end

    if MAIN_MENU_KEYBOARD and type(MAIN_MENU_KEYBOARD.ShowScene) == "function" then
        MAIN_MENU_KEYBOARD:ShowScene("achievements")
        return true
    end

    return false
end

local function doNavigateToAchievement(navigation)
    if type(navigation) ~= "table" then
        return false
    end

    local achievementId = navigation.id
    if not achievementId then
        return false
    end

    local manager = rawget(_G, "ACHIEVEMENTS_MANAGER")
    if manager and type(manager.ShowAchievement) == "function" then
        local ok, result = pcall(manager.ShowAchievement, manager, achievementId)
        if ok and result ~= false then
            return true
        end
    end

    local achievements = getAchievementsSystem()
    if not achievements then
        return false
    end

    if type(achievements.OpenToAchievement) == "function" then
        local ok = pcall(achievements.OpenToAchievement, achievements, achievementId)
        if ok then
            return true
        end
    end

    if navigation.categoryIndex then
        selectCategoryForAchievement(achievements, navigation.categoryIndex, navigation.subCategoryIndex)
    end

    if focusAchievementEntry(achievements, achievementId) then
        return true
    end

    if type(achievements.SelectAchievement) == "function" then
        local ok, result = pcall(achievements.SelectAchievement, achievements, achievementId)
        if ok and result ~= false then
            return true
        end
    end

    if manager and type(manager.SelectAchievement) == "function" then
        local ok, result = pcall(manager.SelectAchievement, manager, achievementId)
        if ok and result ~= false then
            return true
        end
    end

    return false
end

local function runPendingNavigation()
    local navigation = ChatContext._pendingNavigation
    if not navigation then
        return
    end

    navigation.attempts = (navigation.attempts or 0) + 1

    if doNavigateToAchievement(navigation) then
        ChatContext._pendingNavigation = nil
        return
    end

    if navigation.attempts >= NAVIGATION_MAX_ATTEMPTS then
        ChatContext._pendingNavigation = nil
        return
    end

    if type(zo_callLater) == "function" then
        zo_callLater(runPendingNavigation, NAVIGATION_RETRY_MS)
    end
end

local function registerSceneNavigationCallback()
    local sceneManager = SCENE_MANAGER
    local scene

    if sceneManager and type(sceneManager.GetScene) == "function" then
        local ok, result = pcall(sceneManager.GetScene, sceneManager, "achievements")
        if ok then
            scene = result
        end
    end

    if not scene and type(ACHIEVEMENTS_SCENE) == "table" then
        scene = ACHIEVEMENTS_SCENE
    end

    if not scene or type(scene.RegisterCallback) ~= "function" or type(scene.UnregisterCallback) ~= "function" then
        return false
    end

    local function onStateChange(oldState, newState)
        if newState == SCENE_SHOWN then
            scene:UnregisterCallback("StateChange", onStateChange)
            ChatContext._sceneCallback = nil
            if type(zo_callLater) == "function" then
                zo_callLater(runPendingNavigation, 0)
            else
                runPendingNavigation()
            end
        elseif newState == SCENE_HIDDEN then
            scene:UnregisterCallback("StateChange", onStateChange)
            ChatContext._sceneCallback = nil
            ChatContext._pendingNavigation = nil
        end
    end

    ChatContext._sceneCallback = onStateChange
    scene:RegisterCallback("StateChange", onStateChange)

    if type(scene.GetState) == "function" then
        local ok, state = pcall(scene.GetState, scene)
        if ok and state == SCENE_SHOWN then
            if type(zo_callLater) == "function" then
                zo_callLater(runPendingNavigation, 0)
            else
                runPendingNavigation()
            end
        end
    end

    return true
end

local function openAchievementFallback(achievementId)
    local numeric = tonumber(achievementId)
    if not numeric or numeric <= 0 then
        return false
    end

    local categoryIndex, subCategoryIndex = getCategoryIndicesForAchievement(numeric)

    ChatContext._pendingNavigation = {
        id = numeric,
        categoryIndex = categoryIndex,
        subCategoryIndex = subCategoryIndex,
        attempts = 0,
    }

    if not ChatContext._sceneCallback then
        registerSceneNavigationCallback()
    end

    showAchievementsScene()

    if not ChatContext._sceneCallback then
        if type(zo_callLater) == "function" then
            zo_callLater(runPendingNavigation, 0)
        else
            runPendingNavigation()
        end
    end

    debug("open fallback used for %d (cat=%s sub=%s)", numeric, tostring(categoryIndex), tostring(subCategoryIndex))

    return true
end

local function openAchievement(achievementId)
    if type(ZO_Achievements_OpenToAchievement) == "function" then
        local ok = pcall(ZO_Achievements_OpenToAchievement, achievementId)
        if ok then
            return true
        end
    end

    local achievements = getAchievementsSystem()
    if achievements and type(achievements.OpenToAchievement) == "function" then
        local ok = pcall(achievements.OpenToAchievement, achievements, achievementId)
        if ok then
            return true
        end
    end

    return openAchievementFallback(achievementId)
end

local function isFavorite(achievementId)
    local state = Nvk3UT and Nvk3UT.AchievementState
    if state and type(state.IsFavorited) == "function" then
        local ok, result = pcall(state.IsFavorited, achievementId)
        if ok then
            return result and true or false
        end
    end

    local fav = Nvk3UT and Nvk3UT.FavoritesData
    if fav and type(fav.IsFavorited) == "function" then
        local ok, result = pcall(fav.IsFavorited, achievementId)
        if ok then
            return result and true or false
        end
    end

    return false
end

local function setFavorite(achievementId, shouldFavorite)
    local state = Nvk3UT and Nvk3UT.AchievementState
    if state and type(state.SetFavorited) == "function" then
        local ok, result = pcall(state.SetFavorited, achievementId, shouldFavorite, "ChatAchievementContext:Toggle")
        if ok then
            return result
        end
    end

    local fav = Nvk3UT and Nvk3UT.FavoritesData
    if fav and type(fav.SetFavorited) == "function" then
        local ok, result = pcall(fav.SetFavorited, achievementId, shouldFavorite, "ChatAchievementContext:Toggle")
        if ok then
            return result
        end
    end

    return false
end

local function refreshAfterFavoriteChange()
    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and type(runtime.QueueDirty) == "function" then
        pcall(runtime.QueueDirty, runtime, "achievement")
    end

    local rebuild = Nvk3UT and Nvk3UT.Rebuild
    if rebuild and type(rebuild.ForceAchievementRefresh) == "function" then
        pcall(rebuild.ForceAchievementRefresh, "ChatAchievementContext:ToggleFavorite")
    end

    local ui = Nvk3UT and Nvk3UT.UI
    if ui and type(ui.UpdateStatus) == "function" then
        pcall(ui.UpdateStatus)
    end
end

local function hasLibCustomMenu()
    if type(AddCustomMenuItem) == "function" then
        return true
    end

    local lib = rawget(_G, "LibCustomMenu")
    if type(lib) == "table" and type(lib.AddCustomMenuItem) == "function" then
        return true
    end

    if type(LibStub) == "function" then
        local ok, instance = pcall(LibStub, "LibCustomMenu", true)
        if ok and type(instance) == "table" and type(instance.AddCustomMenuItem) == "function" then
            return true
        end
    end

    return false
end

local function addMenuEntry(label, callback)
    if type(label) ~= "string" or label == "" or type(callback) ~= "function" then
        return false
    end

    if type(AddCustomMenuItem) ~= "function" then
        return false
    end

    local optionType = MENU_ADD_OPTION_LABEL or MENU_OPTION_LABEL or 1
    local ok = pcall(AddCustomMenuItem, label, callback, optionType)
    if not ok then
        return false
    end

    return true
end

local function appendMenuEntries(achievementId)
    if not achievementId then
        return false
    end

    local addedAny = false

    if addMenuEntry(GetString(SI_NVK3UT_CTX_OPEN_ACHIEVEMENT), function()
        openAchievement(achievementId)
    end) then
        addedAny = true
    end

    local favoriteNow = isFavorite(achievementId)
    local toggleLabelId = favoriteNow and SI_NVK3UT_CTX_FAVORITE_REMOVE or SI_NVK3UT_CTX_FAVORITE_ADD
    if addMenuEntry(GetString(toggleLabelId), function()
        local desired = not favoriteNow
        local changed = setFavorite(achievementId, desired)
        if changed ~= false then
            refreshAfterFavoriteChange()
        end
    end) then
        addedAny = true
    end

    return addedAny
end

local function OnLinkMouseUpContext(link, button, text, linkStyle, linkType, data1, ...)
    if button ~= MOUSE_BUTTON_INDEX_RIGHT or linkType ~= "achievement" then
        ChatContext._pendingId = nil
        return
    end

    local numericId = tonumber(data1)
    if numericId and numericId > 0 then
        ChatContext._pendingId = numericId
    else
        ChatContext._pendingId = nil
    end
end

local function OnShowMenuPreHook(control)
    local achievementId = ChatContext._pendingId
    if not achievementId then
        return false
    end

    ChatContext._pendingId = nil

    appendMenuEntries(achievementId)

    return false
end

function ChatContext.Init()
    if ChatContext._initialized then
        return
    end
    ChatContext._initialized = true

    ensureStringIds()

    if not hasLibCustomMenu() then
        return
    end

    local handler = rawget(_G, "LINK_HANDLER")
    if type(handler) ~= "table" or type(handler.RegisterCallback) ~= "function" or handler.LINK_MOUSE_UP_EVENT == nil then
        return
    end

    if ChatContext._callbackRegistered then
        return
    end

    handler:RegisterCallback(handler.LINK_MOUSE_UP_EVENT, OnLinkMouseUpContext)

    if not ChatContext._showMenuHooked then
        ZO_PreHook("ShowMenu", OnShowMenuPreHook)
        ChatContext._showMenuHooked = true
    end

    ChatContext._callbackRegistered = true
end

return ChatContext
