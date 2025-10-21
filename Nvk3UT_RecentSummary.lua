Nvk3UT = Nvk3UT or {}
local RD = Nvk3UT.RecentData

local ROW_TYPE_ID = 1

local function GoToAchievement(rowControl)
    if not rowControl then return end
    local rowData = ZO_ScrollList_GetData(rowControl)
    if not rowData then return end
    local achievements = SYSTEMS and SYSTEMS:GetObject("achievements") or ACHIEVEMENTS
    if not achievements then return end
    local achievementId = rowData.achievementId
    local categoryIndex, subCategoryIndex = GetCategoryInfoFromAchievementId(achievementId)
    if not achievements:OpenCategory(categoryIndex, subCategoryIndex) then
        if achievements.contentSearchEditBox and achievements.contentSearchEditBox:GetText() ~= "" then
            achievements.contentSearchEditBox:SetText("")
            ACHIEVEMENTS_MANAGER:ClearSearch(true)
        end
    end
    if achievements:OpenCategory(categoryIndex, subCategoryIndex) then
        if not achievements.achievementsById then return end
        local parentAchievementIndex = achievements:GetBaseAchievementId(achievementId)
        if not achievements.achievementsById[parentAchievementIndex] then achievements:ResetFilters() end
        if achievements.achievementsById[parentAchievementIndex] then
            achievements.achievementsById[parentAchievementIndex]:Expand()
            ZO_Scroll_ScrollControlIntoCentralView(achievements.contentList, achievements.achievementsById[parentAchievementIndex]:GetControl())
        end
    end
end

local function setupDataRow(rowControl, rowData, scrollList)
    local label = rowControl:GetNamedChild("Text") or rowControl
    local name = GetAchievementInfo(rowData.achievementId)
    label:SetText(zo_strformat("<<1>>", name))
    rowControl:SetHandler("OnMouseDoubleClick", function() GoToAchievement(rowControl) end)
    rowControl:SetHandler("OnMouseUp", function(control, button, upInside)
        if button == MOUSE_BUTTON_INDEX_RIGHT and upInside then
            ClearMenu()
            AddCustomMenuItem(GetString(SI_ITEM_ACTION_LINK_TO_CHAT), function()
                ZO_LinkHandler_InsertLink(ZO_LinkHandler_CreateChatLink(GetAchievementLink, rowData.achievementId))
            end)
            AddCustomMenuItem("Öffnen", function() GoToAchievement(rowControl) end)
            ShowMenu(rowControl)
        end
    end)
end

local function InitScrollList(self)
    ZO_ScrollList_AddDataType(self.RecentScrollList, ROW_TYPE_ID, "ZO_SelectableLabel", 24, setupDataRow)
end

local function UpdateScrollList(self)
    local scrollList = self.RecentScrollList
    if not scrollList then return end
    local dataList = ZO_ScrollList_GetDataList(scrollList)
    ZO_ScrollList_Clear(scrollList)
    local ids = RD.List(15)
    for i=1,#ids do
        local rowData = { achievementId = ids[i] }
        dataList[#dataList+1] = ZO_ScrollList_CreateDataEntry(ROW_TYPE_ID, rowData, 1)
    end
    ZO_ScrollList_Commit(scrollList)
end

local function RegisterAchievementEvents(self)
    local em = GetEventManager()
    local function AchievementsUpdated(eventCode) if not SCENE_MANAGER:IsShowing("achievements") then return end UpdateScrollList(self) end
    local function AchievementUpdated(eventCode,id) RD.Touch(id) end
    local function AchievementAwarded(eventCode,name,points,id) RD.Clear(id) end
    em:RegisterForEvent("Nvk3UT_RecentSummary", EVENT_ACHIEVEMENTS_UPDATED, AchievementsUpdated)
    em:RegisterForEvent("Nvk3UT_RecentSummary", EVENT_ACHIEVEMENT_UPDATED, AchievementUpdated)
    em:RegisterForEvent("Nvk3UT_RecentSummary", EVENT_ACHIEVEMENT_AWARDED, AchievementAwarded)
end

function Nvk3UT_EnableRecentSummary()
    RD.InitSavedVars()
    RD.BuildInitial()
    RD.RegisterEvents()

    local SummaryInset = ZO_AchievementsContents and ZO_AchievementsContents:GetNamedChild("SummaryInset")
    if not SummaryInset then return end
    local ProgressBars = SummaryInset:GetNamedChild("ProgressBars")
    local parent = ProgressBars and ProgressBars:GetNamedChild("ScrollChild") or SummaryInset

    local topAnchor = parent:GetNamedChild("Total") or parent
    local bottomAnchor = SummaryInset:GetNamedChild("Recent") or SummaryInset

    local list = WINDOW_MANAGER:CreateControlFromVirtual("Nvk3UT_RecentList", SummaryInset, "ZO_ScrollList")
    list:SetWidth(542)
    list:SetAnchor(TOPLEFT, topAnchor, BOTTOMLEFT, 0, 10)
    list:SetAnchor(BOTTOMLEFT, bottomAnchor, TOPLEFT, 0, -10)

    local self = { RecentScrollList = list }
    InitScrollList(self)
    UpdateScrollList(self)

    local scene = SCENE_MANAGER and SCENE_MANAGER:GetScene("achievements")
    if scene then
        scene:RegisterCallback("StateChange", function(oldState, newState)
            if newState == SCENE_SHOWING then UpdateScrollList(self) end
        end)
    end

    RegisterAchievementEvents(self)
end
