Nvk3UT = Nvk3UT or {}
local function _nvk3ut_is_enabled(key)
  return (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features[key]) and true or false
end
local Fav = Nvk3UT.FavoritesData
local U = Nvk3UT.Utils
local favProvide_lastTs, favProvide_lastCount = 0, -1

local NVK3_FAVORITES_KEY = "Nvk3UT_Favorites"
local ICON_PATH_FAVORITES = "/esoui/art/guild/guild_rankicon_leader_large.dds"
local FAVORITES_LOOKUP_KEY = "NVK3UT_FAVORITES_ROOT"

local function sanitizePlainName(name)
  if U and U.StripLeadingIconTag then
    name = U.StripLeadingIconTag(name)
  end
  return name
end

local function _countFavorites()
    if not (Fav and Fav.Iterate) then
        return 0
    end
    local scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.General and Nvk3UT.sv.General.favScope) or "account"
    local ok, iterator, state, key = pcall(Fav.Iterate, scope)
    if not ok or type(iterator) ~= "function" then
        return 0
    end
    local count = 0
    local current = key
    while true do
        local id, flagged = iterator(state, current)
        current = id
        if id == nil then
            break
        end
        if flagged then
            count = count + 1
        end
    end
    return count
end

local function _updateFavoritesTooltip(ach)
    if not ach then
        return
    end
    local node = ach._nvkFavoritesNode
    local data
    if node and node.GetData then
        data = node:GetData()
    end
    data = data or ach._nvkFavoritesData
    if not data then
        return
    end

    local count = _countFavorites()
    local name = data.name or data.text or (data.categoryData and data.categoryData.name) or "Favoriten"
    local label = zo_strformat("<<1>>", name)
    local iconTag = (U and U.GetIconTagForTexture and U.GetIconTagForTexture(ICON_PATH_FAVORITES)) or ""
    local displayLabel = (iconTag ~= "" and (iconTag .. label)) or label
    local line = string.format("%s - %s", displayLabel, ZO_CommaDelimitNumber(count or 0))
    data.isNvkFavorites = true
    data.nvkSummaryTooltipText = line
    ach._nvkFavoritesData = data
end

local function AddFavoritesTopCategory(AchievementsClass)
    local orgAddTopLevelCategory = AchievementsClass.AddTopLevelCategory
    function AchievementsClass:AddTopLevelCategory(...)
        local result = orgAddTopLevelCategory(self, ...)
        if not _nvk3ut_is_enabled("favorites") then
            return result
        end

        local lookup, tree = self.nodeLookupData, self.categoryTree
        if not (lookup and tree) then
            return result
        end

        if lookup[FAVORITES_LOOKUP_KEY] then
            local node = lookup[FAVORITES_LOOKUP_KEY]
            if node and not self._nvkFavoritesNode then
                self._nvkFavoritesNode = node
            end
            return result
        end

        local parentNode =
            self:AddCategory(lookup, tree, "ZO_IconChildlessHeader", nil, NVK3_FAVORITES_KEY, "Favoriten", false, nil, nil, nil, true, true)
        if not parentNode then
            return result
        end

        lookup[FAVORITES_LOOKUP_KEY] = parentNode
        self._nvkFavoritesNode = parentNode
        local row = parentNode.GetData and parentNode:GetData()
        if row then
            row.isNvkFavorites = true
            row.nvkSummaryTooltipText = nil
            row.isNvk3Fav = true
            local plain = row.name or row.text or "Favoriten"
            row.nvkPlainName = row.nvkPlainName or sanitizePlainName(plain)
            self._nvkFavoritesData = row
        end

        _updateFavoritesTooltip(self)
        if self.refreshGroups then
            self.refreshGroups:RefreshAll("FullUpdate")
        end

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
            _updateFavoritesTooltip(ACH)
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
            local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.General and Nvk3UT.sv.General.favScope) or "account"; for id in Fav.Iterate(__scope) do
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
                _updateFavoritesTooltip(ACH)
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
                local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.General and Nvk3UT.sv.General.favScope) or "account"; for id in Fav.Iterate(__scope) do
                    local cIdx, scIdx, aIdx = GetCategoryInfoFromAchievementId(id)
                    local r = searchResults[cIdx]
                    if r then r = r[scIdx or ZO_ACHIEVEMENTS_ROOT_SUBCATEGORY]; if r and r[aIdx] then result[#result+1]=id end end
                end
            else
                local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.General and Nvk3UT.sv.General.favScope) or "account"; for id in Fav.Iterate(__scope) do result[#result+1] = id end
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
                        local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.General and Nvk3UT.sv.General.favScope) or "account";
                        local isFav = Fav.IsFavorite(id, __scope) or Fav.IsFavorite(self:GetId(), __scope)
                        local U = Nvk3UT and Nvk3UT.Utils; if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then U.d("[Nvk3UT][Favorites][Menu] open", "data={id:", id, ", isFav:", tostring(isFav), "}") end
                        if isFav then
                            AddCustomMenuItem("Von Favoriten entfernen", function() 
                                -- remove entire line of series
                                local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.General and Nvk3UT.sv.General.favScope) or "account"; while id ~= 0 do Fav.Remove(id, __scope); id = GetNextAchievementInLine(id) end; local U = Nvk3UT and Nvk3UT.Utils; if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then U.d("[Nvk3UT][Favorites][Toggle] remove", "data={rootId:", ACHIEVEMENTS:GetBaseAchievementId(self:GetId()), "}") end
                                if ACHIEVEMENTS and ACHIEVEMENTS.refreshGroups then ACHIEVEMENTS.refreshGroups:RefreshAll("FullUpdate") end
                                Nvk3UT.RebuildSelected(ACHIEVEMENTS)
                                _updateFavoritesTooltip(ACHIEVEMENTS)
                                if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then Nvk3UT.UI.UpdateStatus() end
                            end)
                        else
                            AddCustomMenuItem("Zu Favoriten hinzufügen", function()
                                local __scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.General and Nvk3UT.sv.General.favScope) or "account"; Fav.Add(id, __scope)
                                local U = Nvk3UT and Nvk3UT.Utils; if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then U.d("[Nvk3UT][Favorites][Toggle] add", "data={id:", id, ", scope:account}") end
                                Nvk3UT.RebuildSelected(ACHIEVEMENTS)
                                _updateFavoritesTooltip(ACHIEVEMENTS)
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