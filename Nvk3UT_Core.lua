Nvk3UT = Nvk3UT or {}
local UI = Nvk3UT.UI
local defaults={version=3,debug=false,ui={showStatus=true,favScope='account',recentWindow=0,recentMax=100},features={completed=true,favorites=true,recent=true,todo=true}}
local function OnLoaded(e,name)
    if name~="Nvk3UT" then return end
    Nvk3UT._rebuild_lock=false
    Nvk3UT.sv = ZO_SavedVars:NewAccountWide("Nvk3UT_SV", 2, nil, defaults)
    Nvk3UT.sv.features = Nvk3UT.sv.features or {}
    if Nvk3UT.sv.features.tooltips == nil then Nvk3UT.sv.features.tooltips = true end
    local U = Nvk3UT and Nvk3UT.Utils; if U and U.d then U.d("[Nvk3UT][Core][Init] loaded", "data={version:\"{VERSION}\"}") end
    if Nvk3UT.FavoritesData and Nvk3UT.FavoritesData.InitSavedVars then Nvk3UT.FavoritesData.InitSavedVars() end
    if Nvk3UT.RecentData and Nvk3UT.RecentData.InitSavedVars then Nvk3UT.RecentData.InitSavedVars() end
    if Nvk3UT.RecentData and Nvk3UT.RecentData.RegisterEvents then Nvk3UT.RecentData.RegisterEvents() end
    -- Global status refresh on achievement changes
    if EVENT_MANAGER and Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
        local function _nvk3ut_status_refresh_on_ach_event(...)
            -- keep it light: just refresh the text, counts are computed inside UpdateStatus
            Nvk3UT.UI.UpdateStatus()
        end
        EVENT_MANAGER:RegisterForEvent("Nvk3UT_Status_AchUpdated", EVENT_ACHIEVEMENT_UPDATED, _nvk3ut_status_refresh_on_ach_event)
        EVENT_MANAGER:RegisterForEvent("Nvk3UT_Status_Awarded", EVENT_ACHIEVEMENT_AWARDED, _nvk3ut_status_refresh_on_ach_event)
    end

    if Nvk3UT.UI then Nvk3UT.UI.BuildLAM(); Nvk3UT.UI.UpdateStatus() end
    -- Enable integrations when ACHIEVEMENTS exists
    local function TryEnable(attempt)
        attempt=attempt or 1
        if ACHIEVEMENTS then
            if not Nvk3UT.__integrated then
                Nvk3UT.__integrated=true
                local U = Nvk3UT and Nvk3UT.Utils; if U and U.d then U.d("[Nvk3UT][Core][Integrations] enabled", "data={favorites:", tostring(Nvk3UT_EnableFavorites and true or false), ", recent:", tostring(Nvk3UT_EnableRecentCategory and true or false), ", completed:", tostring(Nvk3UT_EnableCompletedCategory and true or false), "}") end
                if Nvk3UT_EnableFavorites then Nvk3UT_EnableFavorites() end
                if Nvk3UT_EnableRecentCategory then Nvk3UT_EnableRecentCategory() end
                if Nvk3UT_EnableTodoCategory then Nvk3UT_EnableTodoCategory() end
            end
            return
        end
        if attempt<15 then zo_callLater(function() TryEnable(attempt+1) end, 500) end
    end
    TryEnable(1)
    if Nvk3UT.Tooltips and Nvk3UT.Tooltips.Init then Nvk3UT.Tooltips.Init() end
    EVENT_MANAGER:UnregisterForEvent("Nvk3UT_Load", EVENT_ADD_ON_LOADED)
end
EVENT_MANAGER:RegisterForEvent("Nvk3UT_Load", EVENT_ADD_ON_LOADED, OnLoaded)
SLASH_COMMANDS["/nvk3test"]=function() if Nvk3UT.Diagnostics then Nvk3UT.Diagnostics.SelfTest(); Nvk3UT.Diagnostics.SystemTest() end end


-- Enable Completed category
if Nvk3UT_EnableCompletedCategory then Nvk3UT_EnableCompletedCategory() end
