-- Core/Nvk3UT_Diagnostics.lua
-- Centralized logging / diagnostics for Nvk3UT.
-- Loads before Core, so it cannot assume that the global addon table exists
-- at file scope. All access to Nvk3UT therefore happens via guarded helpers.
--
-- TODO: Once the refactor introduces a finalized Core bootstrap, make sure
-- Core/Nvk3UT_Core.lua calls Nvk3UT_Diagnostics.AttachToRoot(Nvk3UT) during
-- OnAddonLoaded so the Diagnostics module is reachable via Nvk3UT.Diagnostics.

Nvk3UT_Diagnostics = Nvk3UT_Diagnostics or {}

local Diagnostics = Nvk3UT_Diagnostics

local function coerceToBoolean(value)
    if value == nil then
        return nil
    end

    return value and true or false
end

local initialDebugState = false
if type(Nvk3UT) == "table" and type(Nvk3UT.IsDebugEnabled) == "function" then
    local ok, enabled = pcall(Nvk3UT.IsDebugEnabled, Nvk3UT)
    if ok and enabled ~= nil then
        initialDebugState = enabled and true or false
    end
end

Diagnostics.debugEnabled = (Diagnostics.debugEnabled ~= nil) and Diagnostics.debugEnabled or initialDebugState

local isAttachedToRoot = false

local function ensureRoot()
    if isAttachedToRoot then
        return
    end

    local root = rawget(_G, "Nvk3UT")
    if type(root) == "table" then
        root.Diagnostics = root.Diagnostics or Diagnostics
        isAttachedToRoot = true
    end
end

function Diagnostics.AttachToRoot(root)
    if type(root) ~= "table" then
        return
    end

    root.Diagnostics = root.Diagnostics or Diagnostics
    isAttachedToRoot = true
end

local function _fmt(fmt, ...)
    if fmt == nil then
        return ""
    end

    return string.format(tostring(fmt), ...)
end

local function _print(level, msg)
    local output = string.format("[%s] %s", level, msg)

    if d then
        d(output)
    else
        print(output)
    end
end

local LOCAL_COALESCE_WINDOW_MS = 700
local DEFAULT_COALESCE_WINDOW_MS = 500
local DEFAULT_RATE_LIMIT_MS = 2000

local coalesceBuckets = {}
local achStageFallbackState = {}
local todoListOpenState = {}

local function getTimeMilliseconds()
    if type(GetFrameTimeMilliseconds) == "function" then
        return GetFrameTimeMilliseconds()
    end

    if type(GetGameTimeMilliseconds) == "function" then
        return GetGameTimeMilliseconds()
    end

    if type(GetFrameTimeSeconds) == "function" then
        local seconds = GetFrameTimeSeconds()
        if type(seconds) == "number" then
            return seconds * 1000
        end
    end

    if type(GetTimeStamp) == "function" then
        local seconds = GetTimeStamp()
        if type(seconds) == "number" then
            return seconds * 1000
        end
    end

    return nil
end

function Diagnostics.SetDebugEnabled(enabled)
    Diagnostics.debugEnabled = not not enabled
end

function Diagnostics.IsDebugEnabled()
    return Diagnostics.debugEnabled == true
end

function Diagnostics.SyncFromSavedVariables(sv)
    if type(sv) ~= "table" then
        return
    end

    local flag = nil
    if sv.debug ~= nil then
        flag = coerceToBoolean(sv.debug)
    elseif sv.debugEnabled ~= nil then
        flag = coerceToBoolean(sv.debugEnabled)
    end

    if flag ~= nil then
        Diagnostics.SetDebugEnabled(flag)
    end

    -- TODO: wire additional diagnostics verbosity flags once SavedVariables schema is finalized.
end

function Diagnostics.Debug(fmt, ...)
    if not Diagnostics.debugEnabled then
        return
    end

    ensureRoot()
    _print("Nvk3UT DEBUG", _fmt(fmt, ...))
end

local function buildCoalescedMessage(makeLineFn, count, lastArgs)
    if type(makeLineFn) ~= "function" then
        return nil, "makeLineFn missing"
    end

    local ok, line = pcall(makeLineFn, count, lastArgs)
    if ok then
        return line
    end

    return nil, line
end

function Diagnostics:DebugCoalesced(key, windowMs, makeLineFn, lastArgsTable)
    if not self.debugEnabled then
        return
    end

    if type(key) ~= "string" or key == "" then
        return
    end

    local bucket = coalesceBuckets[key]
    if not bucket then
        bucket = {
            count = 0,
        }
        coalesceBuckets[key] = bucket
    end

    bucket.count = (bucket.count or 0) + 1
    bucket.lastArgs = lastArgsTable

    if bucket.timerActive then
        return
    end

    bucket.timerActive = true

    local delay = tonumber(windowMs) or DEFAULT_COALESCE_WINDOW_MS
    if delay < 0 then
        delay = DEFAULT_COALESCE_WINDOW_MS
    end

    local function flush()
        local count = bucket.count or 0
        local args = bucket.lastArgs

        coalesceBuckets[key] = nil

        bucket.timerActive = nil
        bucket.count = 0
        bucket.lastArgs = nil

        if not Diagnostics.debugEnabled then
            return
        end

        local line, err = buildCoalescedMessage(makeLineFn, count, args)
        if not line or line == "" then
            if err and Diagnostics.debugEnabled then
                Diagnostics.Debug("DebugCoalesced build failed for %s: %s", tostring(key), tostring(err))
            end
            return
        end

        Diagnostics.Debug(line)
    end

    if type(zo_callLater) == "function" and delay > 0 then
        zo_callLater(function()
            flush()
        end, delay)
    else
        flush()
    end
end

function Diagnostics:WarnOnce(key, msg)
    if type(key) ~= "string" or key == "" then
        return false
    end

    self._once = self._once or {}
    if self._once[key] then
        return false
    end

    self._once[key] = true

    if not self:IsDebugEnabled() then
        return false
    end

    if msg == nil then
        return false
    end

    ensureRoot()
    _print("Nvk3UT WARN", tostring(msg))

    return true
end

function Diagnostics:DebugRateLimited(key, intervalMs, msgBuilderFn)
    if not self:IsDebugEnabled() then
        return false
    end

    if type(key) ~= "string" or key == "" then
        return false
    end

    if type(msgBuilderFn) ~= "function" then
        return false
    end

    self._rate = self._rate or {}

    local interval = tonumber(intervalMs) or DEFAULT_RATE_LIMIT_MS
    if interval < 0 then
        interval = DEFAULT_RATE_LIMIT_MS
    end

    local now = getTimeMilliseconds()
    local last = self._rate[key]

    if type(now) == "number" and type(last) == "number" then
        if (now - last) < interval then
            return false
        end
    elseif last ~= nil and now == nil then
        if interval > 0 then
            return false
        end
    end

    local ok, line = pcall(msgBuilderFn)
    if not ok then
        Diagnostics.Debug("DebugRateLimited build failed for %s: %s", tostring(key), tostring(line))
        return false
    end

    if line == nil or line == "" then
        return false
    end

    Diagnostics.Debug("%s", tostring(line))

    if type(now) == "number" then
        self._rate[key] = now
    else
        self._rate[key] = (type(last) == "number" and last or 0) + interval
    end

    return true
end

local function toNumberOrZero(value)
    return tonumber(value) or 0
end

local function toStringOrNone(value)
    if value == nil then
        return "nil"
    end
    return tostring(value)
end

function Diagnostics.Debug_AchStagePending(id, stageId, index)
    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and type(runtime.RecordAchievementStagePending) == "function" then
        runtime:RecordAchievementStagePending(id, stageId, index)
        return
    end

    achStageFallbackState.count = (achStageFallbackState.count or 0) + 1
    achStageFallbackState.lastId = tonumber(id) or id
    achStageFallbackState.lastStageId = tonumber(stageId) or stageId
    achStageFallbackState.lastIndex = tonumber(index) or index

    local emitted = Diagnostics:DebugRateLimited("achv-stage", DEFAULT_RATE_LIMIT_MS, function()
        return string.format(
            "Achievement stage pending: collapsed %d updates (last id=%d stage=%d index=%d)",
            toNumberOrZero(achStageFallbackState.count),
            toNumberOrZero(achStageFallbackState.lastId),
            toNumberOrZero(achStageFallbackState.lastStageId),
            toNumberOrZero(achStageFallbackState.lastIndex)
        )
    end)

    if emitted then
        achStageFallbackState.count = 0
        achStageFallbackState.lastId = nil
        achStageFallbackState.lastStageId = nil
        achStageFallbackState.lastIndex = nil
    end
end

function Diagnostics.Debug_Todo_ListOpenForTop(topIndex, count, phase)
    todoListOpenState.count = (todoListOpenState.count or 0) + 1
    todoListOpenState.lastTop = tonumber(topIndex) or topIndex
    todoListOpenState.lastCount = tonumber(count) or count
    todoListOpenState.lastPhase = phase

    local emitted = Diagnostics:DebugRateLimited("todo-openfortop", DEFAULT_RATE_LIMIT_MS, function()
        return string.format(
            "[TodoData] ListOpenForTop: collapsed %d calls (last phase=%s top=%d count=%d)",
            toNumberOrZero(todoListOpenState.count),
            toStringOrNone(todoListOpenState.lastPhase),
            toNumberOrZero(todoListOpenState.lastTop),
            toNumberOrZero(todoListOpenState.lastCount)
        )
    end)

    if emitted then
        todoListOpenState.count = 0
        todoListOpenState.lastTop = nil
        todoListOpenState.lastCount = nil
        todoListOpenState.lastPhase = nil
    end
end

function Diagnostics.Warn(fmt, ...)
    ensureRoot()
    _print("Nvk3UT WARN", _fmt(fmt, ...))
end

function Diagnostics.Error(fmt, ...)
    ensureRoot()
    _print("Nvk3UT ERROR", _fmt(fmt, ...))
end

function Diagnostics.SelfTest()
    ensureRoot()
    _print("Nvk3UT DEBUG", _fmt("SelfTest: ZO_Achievements available = %s", tostring(ZO_Achievements ~= nil)))
    _print("Nvk3UT DEBUG", _fmt("SelfTest: categoryTree available = %s", tostring(ZO_Achievements and ZO_Achievements.categoryTree ~= nil)))
    _print("Nvk3UT DEBUG", _fmt("SelfTest: LibAddonMenu2 available = %s", tostring(LibAddonMenu2 ~= nil)))
end

function Diagnostics.SystemTest()
    ensureRoot()

    local ach = SYSTEMS and SYSTEMS.GetObject and SYSTEMS:GetObject("achievements")
    _print("Nvk3UT DEBUG", _fmt("SystemTest: SYSTEMS achievements available = %s", tostring(ach ~= nil)))

    if ach then
        _print("Nvk3UT DEBUG", _fmt("SystemTest: ach.categoryTree available = %s", tostring(ach.categoryTree ~= nil)))
        _print("Nvk3UT DEBUG", _fmt("SystemTest: ach.control available = %s", tostring(ach.control ~= nil)))
    end
end

-- Backward compatibility -------------------------------------------------------
if type(Nvk3UT) == "table" then
    Nvk3UT.Diagnostics = Nvk3UT.Diagnostics or Diagnostics
end

if Debug == nil then
    function Debug(fmt, ...)
        return Diagnostics.Debug(fmt, ...)
    end
end

if LogError == nil then
    function LogError(fmt, ...)
        return Diagnostics.Error(fmt, ...)
    end
end

return Diagnostics
