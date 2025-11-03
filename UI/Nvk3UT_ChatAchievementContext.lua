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

local function callMethod(target, methodName, ...)
    if not target or type(methodName) ~= "string" then
        return false
    end

    local method = target[methodName]
    if type(method) ~= "function" then
        return false
    end

    local ok, result = pcall(method, target, ...)
    if not ok then
        return false
    end

    if result == false then
        return false
    end

    return true
end

local function callAny(target, methodNames, ...)
    if not target or type(methodNames) ~= "table" then
        return false
    end

    for i = 1, #methodNames do
        if callMethod(target, methodNames[i], ...) then
            return true
        end
    end

    return false
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

local NAVIGATION_RETRY_MS = 50
local NAVIGATION_MAX_ATTEMPTS = 10

local function selectCategoryForAchievement(achievements, manager, categoryIndex, subCategoryIndex)
    if not categoryIndex then
        return false
    end

    local selectors = {
        "SelectCategoryByIndices",
        "SelectCategoryIndices",
        "SelectCategory",
        "OpenCategory",
        "NavigateToCategory",
    }

    if callAny(achievements, selectors, categoryIndex, subCategoryIndex) then
        return true
    end

    if manager then
        local managerSelectors = {
            "SelectCategoryByIndices",
            "SelectCategoryIndices",
            "SetCategory",
            "NavigateToCategory",
        }

        if callAny(manager, managerSelectors, categoryIndex, subCategoryIndex) then
            return true
        end

        if subCategoryIndex then
            if callAny(manager, managerSelectors, categoryIndex) then
                return true
            end
        end
    end

    return false
end

local function focusAchievementWithSystem(achievements, manager, achievementId)
    if not achievementId then
        return false
    end

    local focused = false

    local achievementSelectors = {
        "ShowAchievement",
        "SelectAchievementById",
        "SelectAchievement",
        "FocusAchievement",
        "TrySelectAchievement",
    }

    if callAny(achievements, achievementSelectors, achievementId) then
        focused = true
    elseif callAny(manager, {
        "ShowAchievement",
        "SelectAchievement",
        "FocusAchievement",
    }, achievementId) then
        focused = true
    end

    if not focused then
        return false
    end

    local scrollers = {
        "ScrollToAchievement",
        "EnsureAchievementVisible",
        "EnsureAchievementIsVisible",
    }

    callAny(achievements, scrollers, achievementId)
    callAny(manager, scrollers, achievementId)

    return true
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

    local achievements = getAchievementsSystem()
    local manager = rawget(_G, "ACHIEVEMENTS_MANAGER")

    if navigation.categoryIndex then
        selectCategoryForAchievement(achievements, manager, navigation.categoryIndex, navigation.subCategoryIndex)
    end

    if focusAchievementWithSystem(achievements, manager, achievementId) then
        return true
    end

    if callAny(manager, {
        "ShowAchievement",
        "SelectAchievement",
        "FocusAchievement",
    }, achievementId) then
        return true
    end

    if callAny(achievements, {
        "ShowAchievement",
        "SelectAchievement",
        "FocusAchievement",
    }, achievementId) then
        return true
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
        local ok, result = pcall(ZO_Achievements_OpenToAchievement, achievementId)
        if ok and result ~= false then
            return true
        end
    end

    local achievements = getAchievementsSystem()
    if achievements and type(achievements.OpenToAchievement) == "function" then
        local ok, result = pcall(achievements.OpenToAchievement, achievements, achievementId)
        if ok and result ~= false then
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
