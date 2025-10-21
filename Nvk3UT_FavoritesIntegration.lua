Nvk3UT = Nvk3UT or {}
local function _nvk3ut_is_enabled(key)
  return (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features[key]) and true or false
end
local Fav = Nvk3UT.FavoritesData
local U = Nvk3UT.Utils
local favProvide_lastTs, favProvide_lastCount = 0, -1

local NVK3_FAVORITES_KEY = "Nvk3UT_Favorites"

local SUMMARY_ICONS = {
    "esoui/art/market/keyboard/giftmessageicon_up.dds",
    "esoui/art/market/keyboard/giftmessageicon_down.dds",
    "esoui/art/market/keyboard/giftmessageicon_over.dds"
}

local function AddFavoritesTopCategory(AchievementsClass)
    local orgAddTopLevelCategory = AchievementsClass.AddTopLevelCategory
    function AchievementsClass.AddTopLevelCategory(...)
                if not _nvk3ut_is_enabled("favorites") then return orgAddTopLevelCategory(...) end
        if not _nvk3ut_is_enabled("favorites") then return (
            select(1, ...)).AddTopLevelCategory and select(1, ...).AddTopLevelCategory(...) end
        local self, name = ...
        if name then return orgAddTopLevelCategory(...) end
        local result = orgAddTopLevelCategory(...)
        local lookup, tree, hidesUnearned = self.nodeLookupData, self.categoryTree, false
        local normalIcon, pressedIcon, mouseoverIcon = unpack(SUMMARY_ICONS)
        local parentNode = self:AddCategory(lookup, tree, "ZO_IconChildlessHeader", nil, NVK3_FAVORITES_KEY, "Favoriten", hidesUnearned, normalIcon, pressedIcon, mouseoverIcon, true, true)
        local _row = parentNode and parentNode.GetData and parentNode:GetData()
        if _row then _row.isNvkFavorites = true end
        local row = parentNode:GetData(); row.isNvk3Fav = true
        if self.refreshGroups then self.refreshGroups:RefreshAll("FullUpdate") end
        return result
    end
end

local function OverrideOnCategorySelected(AchievementsClass)
    local org = AchievementsClass.OnCategorySelected
    function AchievementsClass.OnCategorySelected(...)
                if not _nvk3ut_is_enabled("favorites") then return org(...) end
        local ACH, data, saveExpanded = ...
        if data.categoryIndex == NVK3_FAVORITES_KEY then
            ACH:HideSummary()
            ACH.UpdateCategoryLabels(...)
        else
            return org(...)
        end
    end
end

local function OverrideGetCategoryInfoFromData(AchievementsClass)
    local org = AchievementsClass.GetCategoryInfoFromData
    function AchievementsClass.GetCategoryInfoFromData(...)
                if not _nvk3ut_is_enabled("favorites") then return org(...) end
        local ACH, data, parentData = ...
        if data.categoryIndex == NVK3_FAVORITES_KEY then
            local num, earned, total = 0, 0, 0
            local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.favScope) or "account"; for id in Fav.Iterate(__scope) do
                num = num + 1
                local _, _, points, _, completed = GetAchievementInfo(id)
                total = total + (points or 0)
                if completed then earned = earned + (points or 0) end
            end
            local hidesPoints = total == 0
            return num, earned, total, hidesPoints
        else
            return org(...)
        end
    end
end

local function OverrideOnAchievementUpdated(AchievementsClass)
    local org = AchievementsClass.OnAchievementUpdated
    function AchievementsClass.OnAchievementUpdated(...)
        local ACH, id = ...
        local data = ACH.categoryTree:GetSelectedData()
        if _nvk3ut_is_enabled("favorites") and data and data.categoryIndex == NVK3_FAVORITES_KEY then
            if Fav.IsFavorite(id) and ZO_ShouldShowAchievement(ACH.categoryFilter.filterType, id) then
                ACH:UpdateCategoryLabels(data, true, false)
            end
        else
            return org(...)
        end
    end
end

local function Override_ZO_GetAchievementIds()
    local org = ZO_GetAchievementIds
    local idToName = {}
    local gender = GetUnitGender("player")
    local function nameOf(id)
        local name = GetAchievementInfo(id)
        name = zo_strformat(name, gender)
        idToName[id] = name
        return name
    end
    local function sortByName(a,b) return (idToName[a] or nameOf(a)) < (idToName[b] or nameOf(b)) end
    function ZO_GetAchievementIds(...)
        local categoryIndex, subcategoryIndex, numAchievements, considerSearchResults = ...
        if categoryIndex == NVK3_FAVORITES_KEY then
            local result = {}
            local searchResults = considerSearchResults and ACHIEVEMENTS_MANAGER:GetSearchResults()
            if searchResults then
                local GetCategoryInfoFromAchievementId = GetCategoryInfoFromAchievementId
                local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.favScope) or "account"; for id in Fav.Iterate(__scope) do
                    local cIdx, scIdx, aIdx = GetCategoryInfoFromAchievementId(id)
                    local r = searchResults[cIdx]
                    if r then r = r[scIdx or ZO_ACHIEVEMENTS_ROOT_SUBCATEGORY]; if r and r[aIdx] then result[#result+1]=id end end
                end
            else
                local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.favScope) or "account"; for id in Fav.Iterate(__scope) do result[#result+1] = id end
            end
            table.sort(result, sortByName)
            local U = Nvk3UT and Nvk3UT.Utils; local __now = (U and U.now and U.now() or 0); if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and ((__now - favProvide_lastTs) > 0.5 or #result ~= favProvide_lastCount) then favProvide_lastTs = __now; favProvide_lastCount = #result; U.d("[Nvk3UT][Favorites][Provide] list", "data={count:", #result, ", searchFiltered:", tostring(considerSearchResults and true or false), "}") end
            return result
        else
            return org(...)
        end
    end
end

local function HookAchievementContext()
    local AchClass
    local function HookAchClass(class)
        if AchClass then return end
        AchClass = class
        local orgOnClicked = AchClass.OnClicked
        function AchClass:OnClicked(...)
            local button = ...
            if button == MOUSE_BUTTON_INDEX_LEFT then
                return orgOnClicked(self, ...)
            elseif button == MOUSE_BUTTON_INDEX_RIGHT and IsChatSystemAvailableForCurrentPlatform() then
                local orgShowMenu = ShowMenu
                function ShowMenu(...)
                    ShowMenu = orgShowMenu
                    if not ACHIEVEMENTS.control:IsHidden() then
                        local id = ACHIEVEMENTS:GetBaseAchievementId(self:GetId())
                        local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.favScope) or "account";
                        local isFav = Fav.IsFavorite(id, __scope) or Fav.IsFavorite(self:GetId(), __scope)
                        local U = Nvk3UT and Nvk3UT.Utils; if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then U.d("[Nvk3UT][Favorites][Menu] open", "data={id:", id, ", isFav:", tostring(isFav), "}") end
                        if isFav then
                            AddCustomMenuItem("Von Favoriten entfernen", function() 
                                -- remove entire line of series
                                local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.favScope) or "account"; while id ~= 0 do Fav.Remove(id, __scope); id = GetNextAchievementInLine(id) end; local U = Nvk3UT and Nvk3UT.Utils; if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then U.d("[Nvk3UT][Favorites][Toggle] remove", "data={rootId:", ACHIEVEMENTS:GetBaseAchievementId(self:GetId()), "}") end
                                if ACHIEVEMENTS and ACHIEVEMENTS.refreshGroups then ACHIEVEMENTS.refreshGroups:RefreshAll("FullUpdate") end
                                Nvk3UT.RebuildSelected(ACHIEVEMENTS)
                                if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then Nvk3UT.UI.UpdateStatus() end
                            end)
                        else
                            AddCustomMenuItem("Zu Favoriten hinzufügen", function()
                                local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.favScope) or "account"; Fav.Add(id, __scope)
                                local U = Nvk3UT and Nvk3UT.Utils; if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then U.d("[Nvk3UT][Favorites][Toggle] add", "data={id:", id, ", scope:account}") end
                                Nvk3UT.RebuildSelected(ACHIEVEMENTS)
                                if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then Nvk3UT.UI.UpdateStatus() end
                            end)
                        end
                    end
                    return ShowMenu(...)
                end
                return orgOnClicked(self, ...)
            end
        end
    end
    local orgFactory = ACHIEVEMENTS.achievementPool.m_Factory
    ACHIEVEMENTS.achievementPool.m_Factory = function(...)
        local ach = orgFactory(...)
        if ach and not AchClass then HookAchClass(getmetatable(ach).__index) end
        return ach
    end
end

function Nvk3UT_EnableFavorites()
    local AchievementsClass = getmetatable(ACHIEVEMENTS).__index
    AddFavoritesTopCategory(AchievementsClass)
    OverrideOnCategorySelected(AchievementsClass)
    OverrideGetCategoryInfoFromData(AchievementsClass)
    OverrideOnAchievementUpdated(AchievementsClass)
    Override_ZO_GetAchievementIds()
    HookAchievementContext()
end