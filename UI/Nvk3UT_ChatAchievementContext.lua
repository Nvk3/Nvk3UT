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
    registerString("SI_NVK3UT_CTX_OPEN_ACHIEVEMENT", "Open achievement")
    registerString("SI_NVK3UT_CTX_FAVORITE_ADD", "Add to favorites")
    registerString("SI_NVK3UT_CTX_FAVORITE_REMOVE", "Remove from favorites")
end

local function openAchievement(achievementId)
    if type(ZO_Achievements_OpenToAchievement) == "function" then
        local ok = pcall(ZO_Achievements_OpenToAchievement, achievementId)
        if ok then
            return true
        end
    end

    local achievements = (SYSTEMS and SYSTEMS.GetObject and SYSTEMS:GetObject("achievements")) or ACHIEVEMENTS
    if achievements and type(achievements.OpenToAchievement) == "function" then
        local ok = pcall(achievements.OpenToAchievement, achievements, achievementId)
        if ok then
            return true
        end
    end

    return false
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
    local ok, err = pcall(AddCustomMenuItem, label, callback, optionType)
    if not ok then
        if type(err) == "string" then
            debug("AddCustomMenuItem failed: %s", err)
        end
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

    if addedAny then
        debug("appended items for achievement %d", achievementId)
    end

    return addedAny
end

local function resolveAchievementId(link, linkType, data1)
    if linkType ~= "achievement" then
        if type(ZO_LinkHandler_ParseLink) == "function" and type(link) == "string" then
            local parsedType, parsedData1 = ZO_LinkHandler_ParseLink(link)
            linkType, data1 = parsedType, parsedData1
        end
    end

    if linkType ~= "achievement" then
        return nil
    end

    local numericId = tonumber(data1)
    if not numericId or numericId <= 0 then
        return nil
    end

    return numericId
end

local function OnLinkMouseUpContext(link, button, text, linkStyle, linkType, data1, ...)
    if button ~= MOUSE_BUTTON_INDEX_RIGHT then
        return
    end

    local achievementId = resolveAchievementId(link, linkType, data1)
    if not achievementId then
        return
    end

    if appendMenuEntries(achievementId) and type(ShowMenu) == "function" then
        ShowMenu()
    end
end

function ChatContext.Init()
    if ChatContext._initialized then
        return
    end
    ChatContext._initialized = true

    ensureStringIds()

    if not hasLibCustomMenu() then
        debug("LibCustomMenu unavailable; chat context disabled")
        return
    end

    local handler = rawget(_G, "LINK_HANDLER")
    if type(handler) ~= "table" or type(handler.RegisterCallback) ~= "function" or handler.LINK_MOUSE_UP_EVENT == nil then
        debug("LINK_HANDLER unavailable; chat context disabled")
        return
    end

    if ChatContext._callbackRegistered then
        return
    end

    handler:RegisterCallback(handler.LINK_MOUSE_UP_EVENT, OnLinkMouseUpContext)
    ChatContext._callbackRegistered = true
    debug("LCM link-context registered")
end

return ChatContext
