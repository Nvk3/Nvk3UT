Nvk3UT = Nvk3UT or {}

Nvk3UT.UI = Nvk3UT.UI or {}
local D = Nvk3UT.Diagnostics
local M = {}
Nvk3UT.UI = M

-- Apply toggles (no re-hooking). Only refresh UI/status.
function M.ApplyFeatureToggles()
    -- Update status first and only once
    if Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
        Nvk3UT.UI.UpdateStatus()
    end

    local SM = SCENE_MANAGER
    local ach = (SYSTEMS and SYSTEMS.GetObject and SYSTEMS:GetObject("achievements")) or ACHIEVEMENTS
    local isShowing = SM and SM.IsShowing and SM:IsShowing("achievements")

    if isShowing then
        -- Hard rebuild by briefly closing and re-opening the scene
        SM:Hide("achievements")
        zo_callLater(function() SM:Show("achievements") end, 50)
    else
        -- Soft refresh so the next open is up-to-date
        if ach and ach.refreshGroups then
            ach.refreshGroups:RefreshAll("FullUpdate")
        end
    end
    -- Toggle category tooltips
    if Nvk3UT and Nvk3UT.Tooltips and Nvk3UT.Tooltips.Enable then
        local on = (Nvk3UT.sv and Nvk3UT.sv.features and (Nvk3UT.sv.features.tooltips ~= false))
        Nvk3UT.Tooltips.Enable(on)
    end

end

local TITLE = "Nvk3's Ultimate Tracker"

local function ensureStatusLabel()
    local parent = _G["ZO_CompassFrame"] or _G["ZO_Compass"] or GuiRoot
    if not Nvk3UT._status then
        local ctl = WINDOW_MANAGER:CreateControl("Nvk3UT_Status", parent, CT_LABEL)
        ctl:SetFont("ZoFontGameSmall")
        ctl:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, -18)
        Nvk3UT._status = ctl
    end
    return Nvk3UT._status
end
M.GetStatusLabel = ensureStatusLabel

local function Nvk3UT_UI_ComputeCounts()
    local total, done = 0, 0
    local numCats = GetNumAchievementCategories and GetNumAchievementCategories() or 0
    for top=1, numCats do
        local _, numSub, numAch = GetAchievementCategoryInfo(top)
        if numAch and numAch > 0 then
            for a=1, numAch do
                local id = GetAchievementId(top, nil, a)
                local _,_,_,_,completed = GetAchievementInfo(id)
                total = total + 1
                if completed then done = done + 1 end
            end
        end
        for sub=1,(numSub or 0) do
            local _, numAch2 = GetAchievementSubCategoryInfo(top, sub)
            if numAch2 and numAch2 > 0 then
                for a=1, numAch2 do
                    local id = GetAchievementId(top, sub, a)
                    local _,_,_,_,completed = GetAchievementInfo(id)
                    total = total + 1
                    if completed then done = done + 1 end
                end
            end
        end
    end
    return done, total
end
function M.BuildLAM()
    local LAM = LibAddonMenu2
    if not LAM then return end

    local panel = {
        type = "panel",
        name = TITLE,
        displayName = "|c66CCFF"..TITLE.."|r",
        author = "Nvk3",
        version = "{VERSION}",
        registerForRefresh = true,
        registerForDefaults = true,
    }
    LAM:RegisterAddonPanel("Nvk3UT_Panel", panel)

    local opts = {
        { type="header", name="Anzeige" },
        {
            type="checkbox",
            name="Status über dem Kompass anzeigen",
            getFunc=function() return Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.showStatus end,
            setFunc=function(v) if Nvk3UT.sv and Nvk3UT.sv.ui then Nvk3UT.sv.ui.showStatus=v end; Nvk3UT.UI.UpdateStatus() end,
            default=true
        },
        { type="header", name="Optionen" },
        { type="dropdown", name="Favoritenspeicherung:", choices={"Account-Weit","Charakter-Weit"},
          getFunc=function()
              local s=(Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.favScope) or "account"
              return (s=="character" and "Charakter-Weit") or "Account-Weit"
          end,
          setFunc=function(label)
                          local old = (Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.favScope) or "account"
            local new = (label=="Charakter-Weit") and "character" or "account"
            if Nvk3UT.sv and Nvk3UT.sv.ui then Nvk3UT.sv.ui.favScope = new end
            if Nvk3UT.FavoritesData and Nvk3UT.FavoritesData.MigrateScope then Nvk3UT.FavoritesData.MigrateScope(old, new) end
            if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then Nvk3UT.UI.UpdateStatus() end
        end,
          tooltip="Speichert und zählt Favoriten account-weit oder charakter-weit."
        },
        { type="dropdown", name="Kürzlich-Zeitraum:", choices={"Alle","7 Tage","30 Tage"},
          getFunc=function()
              local w=(Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.recentWindow) or 0
              return (w==7 and "7 Tage") or (w==30 and "30 Tage") or "Alle"
          end,
          setFunc=function(label)
              local w=(label=="7 Tage" and 7) or (label=="30 Tage" and 30) or 0
              if Nvk3UT.sv and Nvk3UT.sv.ui then Nvk3UT.sv.ui.recentWindow=w end
              if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then Nvk3UT.UI.UpdateStatus() end
          end,
          tooltip="Wähle, welche Zeitspanne für Kürzlich gezählt/angezeigt wird."
        },
        { type="dropdown", name="Kürzlich - Maximum:", choices={"50","100","250"},
          getFunc=function()
              return tostring((Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.recentMax) or 100)
          end,
          setFunc=function(label)
              local v=tonumber(label) or 100
              if Nvk3UT.sv and Nvk3UT.sv.ui then Nvk3UT.sv.ui.recentMax=v end
              if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then Nvk3UT.UI.UpdateStatus() end
          end,
          tooltip="Hardcap für die Anzahl der Kürzlich-Einträge."
        },
        
        
        { type="header", name="Funktionen" },
        {
            type="checkbox", name="Errungenschafts-Tooltips ein",
            getFunc=function() return (Nvk3UT.sv and Nvk3UT.sv.features and (Nvk3UT.sv.features.tooltips ~= false)) end,
            setFunc=function(v)
                if Nvk3UT.sv then Nvk3UT.sv.features = Nvk3UT.sv.features or {}; Nvk3UT.sv.features.tooltips = v end
                if Nvk3UT.Tooltips and Nvk3UT.Tooltips.Enable then Nvk3UT.Tooltips.Enable(v) end
            end,
            default=true
        },

        {
            type="checkbox", name="Abgeschlossen aktiv",
            getFunc=function() return Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features.completed end,
            setFunc=function(v) Nvk3UT.sv.features = Nvk3UT.sv.features or {}; Nvk3UT.sv.features.completed=v; M.ApplyFeatureToggles() end,
            default=true
        },
        {
            type="checkbox", name="Favoriten aktiv",
            getFunc=function() return Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features.favorites end,
            setFunc=function(v) Nvk3UT.sv.features = Nvk3UT.sv.features or {}; Nvk3UT.sv.features.favorites=v; M.ApplyFeatureToggles() end,
            default=true
        },
        {
            type="checkbox", name="Kürzlich aktiv",
            getFunc=function() return Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features.recent end,
            setFunc=function(v) Nvk3UT.sv.features = Nvk3UT.sv.features or {}; Nvk3UT.sv.features.recent=v; M.ApplyFeatureToggles() end,
            default=true
        },
        {
            type="checkbox", name="To-Do-Liste aktiv",
            getFunc=function() return Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features.todo end,
            setFunc=function(v) Nvk3UT.sv.features = Nvk3UT.sv.features or {}; Nvk3UT.sv.features.todo=v; M.ApplyFeatureToggles() end,
            default=true
        },
{ type="header", name="Debug" },
        {
            type="checkbox",
            name="Debug aktivieren",
            getFunc=function() return Nvk3UT.sv and Nvk3UT.sv.debug end,
            setFunc=function(v) if Nvk3UT.sv then Nvk3UT.sv.debug=v end end,
            default=false
        },
        { type="button", name="Self-Test ausführen", func=function()
            if Nvk3UT and Nvk3UT.SelfTest and Nvk3UT.SelfTest.Run then Nvk3UT.SelfTest.Run() end
        end, tooltip="Führt einen kompakten Integritäts-Check aus. Bei aktiviertem Debug erscheinen ausführliche Chat-Logs." },
        { type="button", name="UI neu laden", func=function() ReloadUI() end },

    }
    LAM:RegisterOptionControls("Nvk3UT_Panel", opts)
end

-- >>> NVK3UT v0.10.1 Status Builder (injected)
local function __nvk3_IsOn(key)
    local sv = Nvk3UT and Nvk3UT.sv
    return sv and sv.features and sv.features[key] == true
end

local function __nvk3_CountFavorites()
    local Fav = Nvk3UT and Nvk3UT.FavoritesData
    if not Fav or not Fav.Iterate then return 0 end
    local sv = Nvk3UT and Nvk3UT.sv
    local scope = (sv and sv.ui and sv.ui.favScope) or "account"
    local n = 0
    for _ in Fav.Iterate(scope) do n = n + 1 end
    return n
end

local function __nvk3_CountRecent()
    local RD = Nvk3UT and Nvk3UT.RecentData
    if not RD then return 0 end
    if RD.CountConfigured then return RD.CountConfigured() end
    if RD.ListConfigured then local l = RD.ListConfigured(); return type(l)=="table" and #l or 0 end
    return 0
end

local function __nvk3_CountTodo()
    local TD = Nvk3UT and Nvk3UT.TodoData
    if not TD then return 0 end
    -- Prefer a dedicated counter if available
    if TD.CountOpen then return TD.CountOpen() end
    -- Try to fetch all open items with a very high max to avoid truncation
    if TD.ListAllOpen then
        local list = TD.ListAllOpen(999999, false)
        return type(list)=="table" and #list or 0
    end
    return 0
end

local function __nvk3_BuildStatusParts()
    local parts = {}

    -- Abgeschlossen zuerst
    if __nvk3_IsOn("completed") then
        if Nvk3UT_UI_ComputeCounts then
            local done, total = Nvk3UT_UI_ComputeCounts()
            parts[#parts+1] = ("Abgeschlossen %d/%d"):format(done or 0, total or 0)
        end
    end

    if __nvk3_IsOn("favorites") then
        local n = __nvk3_CountFavorites()
        if n > 0 then parts[#parts+1] = ("Favoriten %d"):format(n) end
    end

    if __nvk3_IsOn("recent") then
        local n = __nvk3_CountRecent()
        if n > 0 then parts[#parts+1] = ("Kürzlich %d"):format(n) end
    end

    if __nvk3_IsOn("todo") then
        local n = __nvk3_CountTodo()
        if n > 0 then parts[#parts+1] = ("To-Do-Liste %d"):format(n) end
    end

    return parts
end

-- Patch/define UpdateStatus in module M or Nvk3UT.UI
do
    local ns = Nvk3UT and Nvk3UT.UI
    local function __nvk3_UpdateStatus_impl()
        if not (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui) then return end
        local show = Nvk3UT.sv.ui.showStatus ~= false
        local getLabel = (ns and ns.GetStatusLabel) or (M and M.GetStatusLabel)
        if not getLabel then return end
        local ctl = getLabel()
        if not ctl then return end

        local parts = __nvk3_BuildStatusParts()
        if (not show) or (#parts == 0) then
            ctl:SetHidden(true)
            ctl._nvk3_last = ""
            return
        end

        local header = (TITLE and ("|c66CCFF"..TITLE.."|r  –  ") or "")
        local txt = header .. table.concat(parts, "  •  ")
        if ctl._nvk3_last ~= txt then
            ctl:SetText(txt)
            ctl._nvk3_last = txt
        end
        ctl:SetHidden(false)
    end

    if ns then
        ns.UpdateStatus = __nvk3_UpdateStatus_impl
    elseif M then
        M.UpdateStatus = __nvk3_UpdateStatus_impl
    end
end
-- <<< NVK3UT v0.10.1
