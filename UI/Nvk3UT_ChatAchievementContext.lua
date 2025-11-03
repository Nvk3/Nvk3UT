-- UI/Nvk3UT_ChatAchievementContext.lua
-- TODO(EVENTS_REFACTOR): Move initialization into the future Events bootstrap once available.

Nvk3UT = Nvk3UT or {}

local ChatContext = {}
Nvk3UT.ChatAchievementContext = ChatContext

local Diagnostics = Nvk3UT.Diagnostics

local function debug(fmt, ...)
    if Diagnostics and Diagnostics.Debug then
        Diagnostics.Debug("[ChatAchievementContext] " .. tostring(fmt), ...)
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

local pendingContext = nil
local menuOptionType = MENU_ADD_OPTION_LABEL or MENU_OPTION_LABEL
if not menuOptionType then
    menuOptionType = MENU_OPTION_LABEL or MENU_ADD_OPTION_LABEL or 1
end

local function isChatControl(control)
    if not control then
        return false
    end

    local current = control
    local depth = 0
    while current and depth < 6 do
        if type(current.GetName) == "function" then
            local ok, name = pcall(current.GetName, current)
            if ok and type(name) == "string" and name ~= "" then
                if name:find("ZO_Chat", 1, true) or name:find("ChatWindow", 1, true) then
                    return true
                end
            end
        end

        if type(current.GetParent) ~= "function" then
            break
        end
        current = current:GetParent()
        depth = depth + 1
    end

    return false
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

local function addMenuEntry(label, callback)
    if type(label) ~= "string" or label == "" or type(callback) ~= "function" then
        return false
    end

    local added = false

    if LibCustomMenu and type(AddCustomMenuItem) == "function" then
        local ok = pcall(AddCustomMenuItem, label, callback, menuOptionType)
        if ok then
            added = true
        end
    elseif type(AddCustomMenuItem) == "function" then
        local ok = pcall(AddCustomMenuItem, label, callback, menuOptionType)
        if ok then
            added = true
        end
    elseif type(AddMenuItem) == "function" then
        local ok = pcall(AddMenuItem, label, callback, menuOptionType)
        if ok then
            added = true
        end
    end

    return added
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
        setFavorite(achievementId, not favoriteNow)
    end) then
        addedAny = true
    end

    if addedAny then
        debug("Appended chat context entries for achievement %d", achievementId)
    end
end

local function parseAchievementLink(link)
    if type(ZO_LinkHandler_ParseLink) ~= "function" then
        return nil
    end

    local linkType, data1 = ZO_LinkHandler_ParseLink(link)
    if linkType ~= "achievement" then
        return nil
    end

    local achievementId = tonumber(data1)
    if not achievementId or achievementId <= 0 then
        return nil
    end

    return achievementId
end

local function resetPending()
    pendingContext = nil
end

local function onLinkMouseUp(link, button, text, color, control, ...)
    resetPending()

    if button ~= MOUSE_BUTTON_INDEX_RIGHT then
        return false
    end

    if not isChatControl(control) then
        return false
    end

    local achievementId = parseAchievementLink(link)
    if not achievementId then
        return false
    end

    pendingContext = {
        achievementId = achievementId,
        link = link,
    }

    return false
end

local function onPopulateContextMenu(link, ...)
    if not pendingContext or pendingContext.link ~= link then
        resetPending()
        return
    end

    local achievementId = pendingContext.achievementId
    resetPending()

    if achievementId then
        appendMenuEntries(achievementId)
    end
end

function ChatContext.Init()
    if ChatContext._initialized then
        return
    end
    ChatContext._initialized = true

    ensureStringIds()

    if type(ZO_PreHook) ~= "function" then
        return
    end

    if type(ZO_LinkHandler_OnLinkMouseUp) ~= "function" then
        return
    end

    ZO_PreHook("ZO_LinkHandler_OnLinkMouseUp", onLinkMouseUp)

    local hookFunction = function(...)
        onPopulateContextMenu(...)
    end

    if type(SecurePostHook) == "function" then
        SecurePostHook("ZO_LinkHandler_PopulateLinkContextMenu", hookFunction)
    elseif type(ZO_PostHook) == "function" then
        ZO_PostHook("ZO_LinkHandler_PopulateLinkContextMenu", hookFunction)
    else
        -- Fallback: without a post-hook we cannot safely append menu items.
        debug("Context menu hook unavailable; right-click integration disabled")
    end
end

return ChatContext
