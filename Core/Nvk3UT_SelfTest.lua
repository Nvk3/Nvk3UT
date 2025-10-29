
Nvk3UT = Nvk3UT or {}
local U = Nvk3UT.Utils
local M = {}
Nvk3UT.SelfTest = M

local function printLine(tag, text)
    local prefix = "[Nvk3UT]["..tag.."] "
    if d then d(prefix .. text) end
end

local function stamp()
    if GetGameTimeMilliseconds then return GetGameTimeMilliseconds() end
    if GetFrameTimeMilliseconds then return GetFrameTimeMilliseconds() end
    return 0
end

local function runTest(tag, name, fn, verbose, totals)
    local t0 = stamp()
    local ok, err = pcall(fn)
    local dt = stamp() - t0
    if ok == true or (ok and err == nil) then
        totals.passes = totals.passes + 1
        if verbose then printLine(tag, "✔ "..name.." ("..dt.." ms)") end
    else
        totals.fails = totals.fails + 1
        local msg = tostring(err)
        if verbose then printLine(tag, "✖ "..name.." ("..dt.." ms) – "..msg) end
    end
end

-- Individual checks (keep them lightweight; no side effects)
local function testEnvironment()
    assert(EVENT_MANAGER ~= nil, "EVENT_MANAGER fehlt")
    assert(ZO_SavedVars ~= nil, "SavedVars-API fehlt")
    return true
end

local function testSV_Favorites()
    -- ensure structures exist after Init (non-destructive)
    local Fav = Nvk3UT.FavoritesData
    assert(Fav ~= nil, "FavoritesData fehlt")
    Fav.InitSavedVars()
    assert(Nvk3UT_Data_Favorites_Account ~= nil, "Account-Favoriten-SV fehlt")
    assert(Nvk3UT_Data_Favorites_Characters ~= nil, "Char-Favoriten-SV fehlt")
    return true
end

local function testSV_Recent()
    local RD = Nvk3UT.RecentData
    assert(RD ~= nil, "RecentData fehlt")
    RD.InitSavedVars()
    local raw = _G["Nvk3UT_Data_Recent"]
    local acct = GetDisplayName and GetDisplayName() or nil
    local ok = raw and raw["Default"] and acct and raw["Default"][acct] and raw["Default"][acct]["$AccountWide"]
    assert(ok, "Recent nicht accountweit initialisiert")
    return true
end

local function testHooks_Recent()
    -- If feature is hidden, skip quietly
    local sv = Nvk3UT.sv
    if not (sv and sv.General and sv.General.showRecent ~= false) then return true end
    assert(EVENT_ACHIEVEMENT_UPDATED ~= nil and EVENT_ACHIEVEMENT_AWARDED ~= nil, "Events undefiniert")
    -- We cannot introspect registrations safely here; assume RecentData.RegisterEvents was called on load in Core
    return true
end

local function testUI_Status()
    -- just ensure our status function exists
    local UI = Nvk3UT.UI
    assert(UI and UI.UpdateStatus, "UI.UpdateStatus fehlt")
    return true
end

local function testCounts()
    -- mild consistency: if APIs present, CountConfigured equals list length
    local RD = Nvk3UT.RecentData
    if RD and RD.CountConfigured and RD.ListConfigured then
        local c = RD.CountConfigured()
        local l = RD.ListConfigured()
        assert(type(l)=="table", "Recent.ListConfigured kein table")
        assert(c == #l, "Recent Count != List length ("..tostring(c).." vs "..tostring(#l)..")")
    end
    return true
end

function M.Run()
    local tag = "SelfTest#" .. string.format("%03X", math.random(0, 4095))
    local verbose = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug) and true or false

    local totals = {passes=0, warns=0, fails=0}
    local t0 = stamp()
    if verbose then printLine(tag, "Starte…") end

    runTest(tag, "Environment", testEnvironment, verbose, totals)
    runTest(tag, "SV/Favorites", testSV_Favorites, verbose, totals)
    runTest(tag, "SV/Recent", testSV_Recent, verbose, totals)
    runTest(tag, "Hooks/Recent", testHooks_Recent, verbose, totals)
    runTest(tag, "UI/Status", testUI_Status, verbose, totals)
    runTest(tag, "Zähler/Recent", testCounts, verbose, totals)

    local dt = stamp() - t0
    if verbose then
        printLine(tag, "Alle Tests abgeschlossen. Zusammenfassung: OK:"..totals.passes.." · Warn:"..totals.warns.." · Fail:"..totals.fails.." · "..dt.." ms")
    else
        printLine("SelfTest", "OK ("..totals.passes.."/"..(totals.passes+totals.warns+totals.fails)..") · Warnungen: "..totals.warns.." · Fehler: "..totals.fails.." · "..dt.." ms")
    end
end
