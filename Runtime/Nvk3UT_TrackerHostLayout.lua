Nvk3UT = Nvk3UT or {}

local HostLayout = Nvk3UT.TrackerHostLayout or {}
Nvk3UT.TrackerHostLayout = HostLayout

local DEFAULT_SECTION_ORDER = { "quest", "achievement", "endeavor" }

local function ensureInitialized(self)
    if self._inited then
        return
    end

    self._inited = true
    self.paddingLeft = self.paddingLeft or 0
    self.paddingTop = self.paddingTop or 0
    self.paddingRight = self.paddingRight or 0
    self.paddingBottom = self.paddingBottom or 0
    self.sectionGap = self.sectionGap or 0
    self.order = self.order or DEFAULT_SECTION_ORDER
    self._cache = self._cache or {
        anchors = {},
        sizes = {},
        totalHeight = 0,
    }
    self._headerH = self._headerH or 0
    self._footerH = self._footerH or 0
    self._hadZeroMeasure = self._hadZeroMeasure or false
end

function HostLayout:Init()
    ensureInitialized(self)
end

local function getTrackerModuleForKind(kind)
    if kind == "quest" then
        return Nvk3UT and Nvk3UT.QuestTracker
    elseif kind == "achievement" then
        return Nvk3UT and Nvk3UT.AchievementTracker
    elseif kind == "endeavor" then
        return Nvk3UT and Nvk3UT.EndeavorTracker
    end
    return nil
end

local function safeTrackerContentSize(tracker)
    if type(tracker) ~= "table" then
        return 0, 0
    end

    local getContentSize = tracker.GetContentSize
    if type(getContentSize) ~= "function" then
        return 0, 0
    end

    local safeCall = Nvk3UT and Nvk3UT.SafeCall
    if type(safeCall) == "function" then
        local result = safeCall(function()
            local width, height = getContentSize(tracker)
            return { width = width, height = height }
        end)
        if type(result) == "table" then
            local width = tonumber(result.width) or 0
            local height = tonumber(result.height) or 0
            return width, height
        end

        return 0, 0
    end

    local ok, width, height = pcall(getContentSize, tracker)
    if ok then
        return tonumber(width) or 0, tonumber(height) or 0
    end

    return 0, 0
end

local function measureSection(self, kind, container)
    if not container then
        return 0, 0
    end

    if container.IsHidden and container:IsHidden() then
        return 0, 0
    end

    local width, height = 0, 0

    local tracker = getTrackerModuleForKind(kind)
    local trackerWidth, trackerHeight = safeTrackerContentSize(tracker)
    width = math.max(width, trackerWidth)
    height = math.max(height, trackerHeight)

    if width <= 0 or height <= 0 then
        local holder = container.holder
        if holder then
            if holder.GetWidth then
                local holderWidth = tonumber(holder:GetWidth()) or 0
                width = math.max(width, holderWidth)
            end
            if holder.GetHeight then
                local holderHeight = tonumber(holder:GetHeight()) or 0
                height = math.max(height, holderHeight)
            end
        end
    end

    if width <= 0 or height <= 0 then
        if container.GetWidth then
            local containerWidth = tonumber(container:GetWidth()) or 0
            width = math.max(width, containerWidth)
        end
        if container.GetHeight then
            local containerHeight = tonumber(container:GetHeight()) or 0
            height = math.max(height, containerHeight)
        end
    end

    if height <= 0 then
        local cache = self._cache and self._cache.sizes or nil
        local last = cache and cache[kind]
        if last and last > 0 then
            height = last
            self._hadZeroMeasure = true
        else
            height = last or 0
        end
    end

    if width < 0 then
        width = 0
    end

    if height < 0 then
        height = 0
    end

    return width, height
end

function HostLayout:UpdateHeaderFooterSizes()
    ensureInitialized(self)

    self._headerH = self._headerH or 0
    self._footerH = self._footerH or 0
end

local function anchorSection(self, kind, container, offsetX, offsetY, paddingRight)
    if not (container and container.ClearAnchors and container.SetAnchor) then
        return
    end

    local parent = container.GetParent and container:GetParent()
    if not parent then
        return
    end

    local anchors = self._cache and self._cache.anchors or nil
    if not anchors then
        return
    end

    local cached = anchors[kind]
    local target = {
        parent = parent,
        left = offsetX,
        top = offsetY,
        right = paddingRight,
    }

    local changed = false
    if not cached then
        changed = true
    else
        if cached.parent ~= target.parent then
            changed = true
        elseif cached.left ~= target.left or cached.top ~= target.top or cached.right ~= target.right then
            changed = true
        end
    end

    if not changed then
        return
    end

    container:ClearAnchors()
    container:SetAnchor(TOPLEFT, parent, TOPLEFT, offsetX, offsetY)
    container:SetAnchor(TOPRIGHT, parent, TOPRIGHT, -(paddingRight or 0), offsetY)

    anchors[kind] = target
end

function HostLayout:ApplyLayout()
    ensureInitialized(self)

    local host = Nvk3UT and Nvk3UT.TrackerHost
    if not (host and host.GetRoot and host.GetSectionContainer) then
        return
    end

    local root = host:GetRoot()
    if not (root and root.GetWidth and root.GetHeight) then
        return
    end

    self._hadZeroMeasure = false
    self:UpdateHeaderFooterSizes()

    local paddingLeft = self.paddingLeft or 0
    local paddingTop = self.paddingTop or 0
    local paddingRight = self.paddingRight or 0
    local paddingBottom = self.paddingBottom or 0
    local sectionGap = self.sectionGap or 0
    local order = self.order or DEFAULT_SECTION_ORDER

    local anchors = self._cache.anchors
    local sizes = self._cache.sizes
    local cursorY = paddingTop + (self._headerH or 0)
    local baseline = cursorY
    local usedSections = 0
    local maxWidth = 0

    for index = 1, #order do
        local kind = order[index]
        if type(kind) == "string" and kind ~= "" then
            local container = host:GetSectionContainer(kind)
            if container and container.ClearAnchors and container.SetAnchor then
                local width, height = measureSection(self, kind, container)
                anchorSection(self, kind, container, paddingLeft, cursorY, paddingRight)

                if sizes then
                    sizes[kind] = height
                end

                maxWidth = math.max(maxWidth, width)

                if height > 0 then
                    cursorY = cursorY + height + sectionGap
                    usedSections = usedSections + 1
                end
            end
        end
    end

    if usedSections > 0 and sectionGap > 0 then
        cursorY = cursorY - sectionGap
    end

    local contentHeight = math.max(0, cursorY - baseline)
    local totalHeight = paddingTop + contentHeight + paddingBottom + (self._headerH or 0) + (self._footerH or 0)

    if self._cache then
        self._cache.totalHeight = totalHeight
        self._cache.contentWidth = math.max(0, maxWidth)
    end

    if type(Nvk3UT.Debug) == "function" then
        Nvk3UT.Debug(
            "TrackerHostLayout: ApplyLayout (sections=%d, totalHeight=%.1f)",
            usedSections,
            totalHeight
        )
    end

    if self._hadZeroMeasure then
        self._hadZeroMeasure = false
        local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
        if runtime and runtime.QueueDirty then
            runtime:QueueDirty("layout")
        end
    end
end

HostLayout:Init()

return HostLayout
