-- UI/Nvk3UT_ChatAchievementContext.lua
-- TODO(EVENTS_REFACTOR): Move initialization into the future Events bootstrap once available.

Nvk3UT = Nvk3UT or {}

local ChatContext = {}
Nvk3UT.ChatAchievementContext = ChatContext

local function debug(fmt, ...)
    local diag = Nvk3UT and Nvk3UT.Diagnostics
    if diag and diag.Debug then
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
            return result and true or false
        end
    end

    local fav = Nvk3UT and Nvk3UT.FavoritesData
    if fav and type(fav.SetFavorited) == "function" then
        local ok, result = pcall(fav.SetFavorited, achievementId, shouldFavorite, "ChatAchievementContext:Toggle")
        if ok then
            return result and true or false
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

local function addMenuEntry(label, callback)
    if type(label) ~= "string" or label == "" or type(callback) ~= "function" then
        return false
    end

    if LibCustomMenu and type(AddCustomMenuItem) == "function" then
        local optionType = MENU_ADD_OPTION_LABEL or MENU_OPTION_LABEL or 1
        local ok = pcall(AddCustomMenuItem, label, callback, optionType)
        return ok == true
    end

    if type(AddMenuItem) == "function" then
        local ok = pcall(AddMenuItem, label, callback)
        return ok == true
    end

    return false
end

local function appendMenuEntries(achievementId)
    if not achievementId then
        return
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
        local changed = setFavorite(achievementId, not favoriteNow)
        if changed then
            refreshAfterFavoriteChange()
        end
    end) then
        addedAny = true
    end

    if addedAny then
        debug("Appended chat context entries for achievement %d", achievementId)
    end
end

function ChatContext.Init()
    if ChatContext._initialized then
        return
    end
    ChatContext._initialized = true

    ensureStringIds()

    debug("init")

    local function onPopulateLinkContextMenu(link, button, control)
        if not ChatContext._hookFireLogged then
            ChatContext._hookFireLogged = true
            debug("hook fired")
        end

        if button ~= MOUSE_BUTTON_INDEX_RIGHT then
            return
        end

        if type(ZO_LinkHandler_ParseLink) ~= "function" then
            return
        end

        local linkType, data1 = ZO_LinkHandler_ParseLink(link)
        if linkType ~= "achievement" then
            return
        end

        local achievementId = tonumber(data1)
        if not achievementId or achievementId <= 0 then
            return
        end

        if control and type(control.IsHidden) == "function" then
            local ok, hidden = pcall(control.IsHidden, control)
            if ok and hidden then
                return
            end
        end

        appendMenuEntries(achievementId)
    end

    if type(SecurePostHook) == "function" then
        SecurePostHook("ZO_LinkHandler_PopulateLinkContextMenu", onPopulateLinkContextMenu)
    else
        debug("Context menu hook unavailable; right-click integration disabled")
    end
end

return ChatContext
