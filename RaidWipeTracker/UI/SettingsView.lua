local addonName, RWT = ...

local Widgets = RWT.UI.Widgets
local MainWindow = RWT.UI.MainWindow

-- 设置界面工厂：主面板"设置"标签页和 ESC-选项-插件 页面各创建一个实例，共用同一份设置数据
local SettingsView = {}
RWT.UI.SettingsView = SettingsView

local LEFT_W = 320
local TAG_LIST_W = 500
local TAG_ROW_H = 24
local TAG_SECTION_H = 22
local TAG_ADD_H = 28

local TOPN_OPTIONS = { { 3, "Top 3" }, { 5, "Top 5" } }
local CHANNEL_OPTIONS = { { "RAID", "团队" }, { "GUILD", "公会" }, { "SAY", "白字" } }
local FLAG_STEP = 23

local function S()
    return RWT.db.settings
end

-- 开关定义：get / set 支持嵌套字段
local FLAGS = {
    { label = "灭团后自动弹出记录窗口", get = function() return S().autoPopup end, set = function(v) S().autoPopup = v end },
    { label = "击杀后自动打开统计", get = function() return S().autoOpenStatsOnKill end, set = function(v) S().autoOpenStatsOnKill = v end },
    { label = "首把灭团提示并入 / 拆分", get = function() return S().promptOnFirstWipe end, set = function(v) S().promptOnFirstWipe = v end },
    { label = "地下城 / 场景首领也记录", get = function() return S().trackNonRaid end, set = function(v) S().trackNonRaid = v end },
    { label = "显示小地图按钮", get = function() return not S().minimap.hide end, set = function(v) S().minimap.hide = not v end },
    { label = "显示浮空快捷面板", get = function() return S().floatPanel.enabled end, set = function(v) S().floatPanel.enabled = v end },
    { label = "锁定浮空面板位置", get = function() return S().floatPanel.locked end, set = function(v) S().floatPanel.locked = v end },
}

-- 设置被修改：通知小地图按钮、浮空面板与所有界面
local function Changed()
    RWT:Fire("RWT_SETTINGS_CHANGED")
    RWT:NotifyDataChanged()
end

local Instance = {}
Instance.__index = Instance

local instances = {}

function SettingsView.New(parent)
    local view = setmetatable({}, Instance)
    view.frame = view:Build(parent)
    table.insert(instances, view)
    return view
end

local function SectionTitle(parent, text, x, y)
    local fs = Widgets.CreateText(parent, "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", x, -y)
    fs:SetText(text)
    return fs
end

-- 一组互斥选项按钮
local function CreateChoiceRow(parent, x, y, options, width, onSelect)
    local buttons = {}
    for i, opt in ipairs(options) do
        local b = Widgets.CreateToggle(parent, width, 22)
        b:SetPoint("TOPLEFT", x + (i - 1) * (width + 4), -y)
        b:SetLabel(opt[2])
        b.value = opt[1]
        b:SetScript("OnClick", function() onSelect(opt[1]) end)
        table.insert(buttons, b)
    end
    return buttons
end

------------------------------------------------------------
-- 左栏：报告 / 行为 / 续接
------------------------------------------------------------

local function FormatInterval(n)
    return string.format("%g", tonumber(n) or RWT.CHAT_INTERVAL_DEFAULT)
end

local function ApplyInterval(box, key)
    local n = tonumber(box:GetText())
    if not n or n < RWT.CHAT_INTERVAL_MIN or n > RWT.CHAT_INTERVAL_MAX then
        n = RWT.CHAT_INTERVAL_DEFAULT
    end
    box:SetText(FormatInterval(n))
    if S()[key] == n then return end
    S()[key] = n
    Changed()
end

-- 间隔可以是小数，不能用 SetNumeric
local function CreateIntervalBox(parent, label, key)
    local box = Widgets.CreateEditBox(parent, 50, 4)
    box:SetPoint("LEFT", label, "RIGHT", 8, 0)
    box:SetScript("OnEscapePressed", function(self)
        self.revert = true
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        if self.revert then
            self.revert = nil
            self:SetText(FormatInterval(S()[key]))
            return
        end
        ApplyInterval(self, key)
    end)
    return box
end

function Instance:BuildLeft(f)
    local x = 8
    self.realmButton = Widgets.CreateToggle(f, LEFT_W - 16, 22, "LEFT")
    self.realmButton:SetPoint("TOPLEFT", x + 8, -2)
    self.realmButton:SetScript("OnClick", function()
        S().reportShowRealm = not S().reportShowRealm
        Changed()
    end)

    SectionTitle(f, "统计报告", x, 28)
    self.topNButtons = CreateChoiceRow(f, x + 8, 50, TOPN_OPTIONS, 70, function(v)
        S().reportTopN = v
        Changed()
    end)
    self.channelButtons = CreateChoiceRow(f, x + 8, 74, CHANNEL_OPTIONS, 90, function(v)
        S().reportChannel = v
        Changed()
    end)
    local reportIntervalLabel = Widgets.CreateText(f, "GameFontHighlight")
    reportIntervalLabel:SetPoint("TOPLEFT", x + 8, -102)
    reportIntervalLabel:SetText("发送间隔（秒）：")
    self.reportIntervalBox = CreateIntervalBox(f, reportIntervalLabel, "reportInterval")

    SectionTitle(f, "单次记录汇报", x, 130)
    self.recordButton = Widgets.CreateToggle(f, LEFT_W - 16, 22, "LEFT")
    self.recordButton:SetPoint("TOPLEFT", x + 8, -152)
    self.recordButton:SetScript("OnClick", function()
        S().recordChat = not S().recordChat
        Changed()
    end)
    self.recordChannelButtons = CreateChoiceRow(f, x + 8, 178, CHANNEL_OPTIONS, 90, function(v)
        S().recordChannel = v
        Changed()
    end)
    local recordIntervalLabel = Widgets.CreateText(f, "GameFontHighlight")
    recordIntervalLabel:SetPoint("TOPLEFT", x + 8, -206)
    recordIntervalLabel:SetText("发送间隔（秒）：")
    self.recordIntervalBox = CreateIntervalBox(f, recordIntervalLabel, "recordInterval")

    local behaviorY = 234
    SectionTitle(f, "行为", x, behaviorY)
    self.flagButtons = {}
    local flagY = behaviorY + 22
    for i, def in ipairs(FLAGS) do
        local b = Widgets.CreateToggle(f, LEFT_W - 16, 22, "LEFT")
        b:SetPoint("TOPLEFT", x + 8, -(flagY + (i - 1) * FLAG_STEP))
        b.def = def
        b:SetScript("OnClick", function()
            def.set(not def.get())
            Changed()
        end)
        table.insert(self.flagButtons, b)
    end

    local y = flagY + #FLAGS * FLAG_STEP + 4
    local resumeLabel = Widgets.CreateText(f, "GameFontHighlight")
    resumeLabel:SetPoint("TOPLEFT", x + 8, -y)
    resumeLabel:SetText("自动续接窗口（小时）：")
    self.resumeBox = Widgets.CreateEditBox(f, 50, 4)
    self.resumeBox:SetPoint("LEFT", resumeLabel, "RIGHT", 10, 0)
    self.resumeBox:SetNumeric(true)
    local apply = Widgets.CreateButton(f, "应用", 56, 22, function()
        local hours = tonumber(self.resumeBox:GetText())
        if hours and hours >= 0 then S().resumeWindowHours = hours end
        self.resumeBox:ClearFocus()
        Changed()
    end)
    apply:SetPoint("LEFT", self.resumeBox, "RIGHT", 6, 0)
    local hint = Widgets.CreateText(f, "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", x + 8, -(y + 24))
    hint:SetWidth(LEFT_W - 16)
    hint:SetText("同 Boss 同难度、未击杀的 Session，距上次活动不超过该时长时自动续接；0 = 总是新建。")

    local reset = Widgets.CreateButton(f, "恢复默认设置", 120, 22, function()
        Widgets.Confirm("恢复默认设置？（记录和预设 tag 都会保留）", function()
            RWT.Database:ResetSettings()
            Changed()
        end)
    end)
    reset:SetPoint("TOPLEFT", x + 8, -(y + 52))
end

------------------------------------------------------------
-- 右栏：预设 tag 管理（通用 + 当前版本每个首领）
------------------------------------------------------------

function Instance:CreateTagRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(TAG_LIST_W, TAG_ROW_H)
    row.text = Widgets.CreateText(row, "GameFontHighlight")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetPoint("RIGHT", -110, 0)
    row.text:SetJustifyV("MIDDLE")
    row.text:SetWordWrap(false)
    local function Act(fn)
        return function()
            local ok, err = fn(row.tag)
            if not ok and err then RWT:Print(err) end
            Changed()
        end
    end
    row.delete = Widgets.CreateButton(row, "删", 34, 20, Act(function(tag)
        if row.encounterID then return RWT.Tags:RemoveBoss(row.encounterID, tag) end
        return RWT.Tags:Remove(tag)
    end))
    row.delete:SetPoint("RIGHT", -2, 0)
    row.down = Widgets.CreateButton(row, "下", 34, 20, Act(function(tag)
        if row.encounterID then return RWT.Tags:MoveBoss(row.encounterID, tag, 1) end
        return RWT.Tags:Move(tag, 1)
    end))
    row.down:SetPoint("RIGHT", row.delete, "LEFT", -2, 0)
    row.up = Widgets.CreateButton(row, "上", 34, 20, Act(function(tag)
        if row.encounterID then return RWT.Tags:MoveBoss(row.encounterID, tag, -1) end
        return RWT.Tags:Move(tag, -1)
    end))
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    return row
end

function Instance:CreateSectionHeader(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TAG_LIST_W, TAG_SECTION_H)
    b.text = Widgets.CreateText(b, "GameFontHighlight")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyV("MIDDLE")
    b.text:SetWordWrap(false)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b:SetScript("OnClick", function(self)
        if not self.expandKey then return end
        self.owner.expanded[self.expandKey] = not self.owner.expanded[self.expandKey]
        self.owner:RefreshTags()
    end)
    return b
end

function Instance:CreateAddRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(TAG_LIST_W, TAG_ADD_H)
    row.box = Widgets.CreateEditBox(row, TAG_LIST_W - 70, RWT.MAX_TAG_LETTERS)
    row.box:SetPoint("LEFT", 4, 0)
    row.box:SetScript("OnTextChanged", function(box, userInput)
        if not userInput then return end
        self.draftText[row.sectionKey or "general"] = box:GetText()
    end)
    row.box:SetScript("OnEnterPressed", function() self:AddFromRow(row) end)
    row.add = Widgets.CreateButton(row, "添加", 60, 22, function() self:AddFromRow(row) end)
    row.add:SetPoint("RIGHT", -2, 0)
    return row
end

function Instance:AddFromRow(row)
    local key = row.sectionKey or "general"
    local ok, err
    if row.encounterID then
        ok, err = RWT.Tags:AddBoss(row.encounterID, row.box:GetText())
    else
        ok, err = RWT.Tags:Add(row.box:GetText())
    end
    if ok then
        self.draftText[key] = ""
        row.box:SetText("")
    elseif err then
        RWT:Print(err)
    end
    Changed()
end

function Instance:BuildRight(f)
    local x = LEFT_W + 16
    SectionTitle(f, "预设 tag", x, 6)
    local hint = Widgets.CreateText(f, "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", x, -30)
    hint:SetPoint("TOPRIGHT", -16, -30)
    hint:SetWordWrap(true)
    hint:SetText("通用 tag 对所有首领显示。点团本名展开首领，再点首领名管理它的专属 tag。删除不影响已保存的记录。")

    local reset = Widgets.CreateButton(f, "恢复默认 tag", 110, 22, function()
        Widgets.Confirm("把通用 tag 恢复为默认列表？（首领专属 tag 和已保存的记录不受影响）", function()
            RWT.Tags:ResetDefaults()
            Changed()
        end)
    end)
    reset:SetPoint("BOTTOMLEFT", x, 12)

    local panel = Widgets.CreatePanel(f)
    panel:SetPoint("TOPLEFT", x, -62)
    panel:SetPoint("BOTTOMRIGHT", -12, 40)
    self.tagScroll, self.tagContent = Widgets.CreateScrollArea(panel, TAG_LIST_W)
    self.tagScroll:SetPoint("TOPLEFT", 4, -4)
    self.tagScroll:SetPoint("BOTTOMRIGHT", -26, 4)
    self.tagScroll:SetScript("OnSizeChanged", function(_, w)
        w = math.floor((w or 0) + 0.5)
        if w < 80 or w == self.laidWidth or self.refreshingTags then return end
        self:RefreshTags()
    end)
    self.expanded = {}
    self.draftText = {}
    self.tagPool = Widgets.CreatePool(function() return self:CreateTagRow(self.tagContent) end)
    self.headerPool = Widgets.CreatePool(function()
        local header = self:CreateSectionHeader(self.tagContent)
        header.owner = self
        return header
    end)
    self.addPool = Widgets.CreatePool(function() return self:CreateAddRow(self.tagContent) end)
end

function Instance:Build(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    self:BuildLeft(f)
    self:BuildRight(f)

    f:SetScript("OnShow", function()
        self.raidCache = nil
        self:Refresh()
    end)
    return f
end

function Instance:ListWidth()
    local width = self.tagScroll:GetWidth()
    if not width or width < 80 then return TAG_LIST_W end
    return width
end

function Instance:PlaceTagRows(list, encounterID, x, y, width)
    for i, tag in ipairs(list) do
        local row = self.tagPool:Acquire()
        row.tag = tag
        row.encounterID = encounterID
        row:SetWidth(width)
        row.text:SetText(RWT.Tags:FormatOne(tag))
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #list)
        row.delete:SetEnabled(encounterID ~= nil or #list > 1)
        row:SetPoint("TOPLEFT", self.tagContent, "TOPLEFT", x, -y)
        y = y + TAG_ROW_H
    end
    return y
end

function Instance:PlaceAddRow(encounterID, sectionKey, x, y, width)
    local row = self.addPool:Acquire()
    row.encounterID = encounterID
    row.sectionKey = sectionKey
    row:SetWidth(width)
    row.box:SetWidth(math.max(width - 80, 80))
    local draft = self.draftText[sectionKey] or ""
    if row.box:GetText() ~= draft then row.box:SetText(draft) end
    row:SetPoint("TOPLEFT", self.tagContent, "TOPLEFT", x, -y)
    return y + TAG_ADD_H
end

function Instance:PlaceHeader(kind, expandKey, text, x, y, width)
    local header = self.headerPool:Acquire()
    header.kind = kind
    header.expandKey = expandKey
    header.owner = self
    header:SetWidth(math.max(width - x, 80))
    header.text:SetText(text)
    header:EnableMouse(expandKey ~= nil)
    header:SetPoint("TOPLEFT", self.tagContent, "TOPLEFT", x, -y)
    return y + TAG_SECTION_H
end

function Instance:GetRaids()
    if not self.raidCache then
        self.raidCache = RWT.UI.BossPicker:GetCurrentTierRaids()
    end
    return self.raidCache
end

function Instance:RefreshTags()
    if self.refreshingTags then return end
    self.refreshingTags = true
    self.expanded = self.expanded or {}
    self.draftText = self.draftText or {}
    self.tagPool:ReleaseAll()
    self.headerPool:ReleaseAll()
    self.addPool:ReleaseAll()

    local width = self:ListWidth()
    self.laidWidth = math.floor(width + 0.5)
    self.tagContent:SetWidth(width)
    local y = 0

    y = self:PlaceHeader("label", nil, "|cffffd100通用|r", 0, y, width)
    y = self:PlaceTagRows(RWT.Tags:GetPresets(), nil, 0, y, width)
    y = self:PlaceAddRow(nil, "general", 0, y, width) + 8

    local raids = self:GetRaids()
    if #raids == 0 then
        y = self:PlaceHeader("label", nil, "|cff888888冒险指南未加载，暂时无法列出首领|r", 0, y, width)
    else
        local bossX, tagX = 16, 32
        for _, raid in ipairs(raids) do
            local bosses = raid.bosses or {}
            local tagCount = 0
            for _, boss in ipairs(bosses) do
                local id = boss.encounterID
                if id and tostring(id) ~= "" and tostring(id) ~= "0" then
                    tagCount = tagCount + #RWT.Tags:GetBossTags(id)
                end
            end
            local raidKey = "raid:" .. tostring(raid.journalInstanceID or raid.title or "?")
            local raidOpen = self.expanded[raidKey] and true or false
            local raidArrow = raidOpen and "▼" or "▶"
            local raidTitle = string.format("%s |cffffd100%s|r |cff888888（%d 首领，%d tag）|r",
                raidArrow, raid.title or "?", #bosses, tagCount)
            y = self:PlaceHeader("raid", raidKey, raidTitle, 0, y, width)
            if raidOpen then
                for _, boss in ipairs(bosses) do
                    local id = boss.encounterID
                    local key = id and tostring(id) or nil
                    if not key or key == "" or key == "0" then
                        y = self:PlaceHeader("label", nil, "|cff888888" .. (boss.bossName or "?") .. "|r", bossX, y, width)
                    else
                        local tags = RWT.Tags:GetBossTags(id)
                        local bossKey = "boss:" .. key
                        local open = self.expanded[bossKey] and true or false
                        local arrow = open and "▼" or "▶"
                        local title = string.format("%s %s|cff888888（%d）|r", arrow, boss.bossName or "?", #tags)
                        y = self:PlaceHeader("boss", bossKey, title, bossX, y, width)
                        if open then
                            y = self:PlaceTagRows(tags, id, tagX, y, width - tagX)
                            y = self:PlaceAddRow(id, key, tagX, y, width - tagX)
                        end
                    end
                end
            end
            y = y + 4
        end
    end
    self.tagContent:SetHeight(math.max(y, 1))
    self.refreshingTags = false
    if self.tagWidthRetry then return end
    local actual = math.floor((self.tagScroll:GetWidth() or 0) + 0.5)
    if actual >= 80 and actual ~= self.laidWidth then
        self.tagWidthRetry = true
        self:RefreshTags()
        self.tagWidthRetry = false
    end
end

function Instance:Refresh()
    local s = S()
    if s.reportTopN ~= 3 and s.reportTopN ~= 5 then s.reportTopN = 5 end
    for _, b in ipairs(self.topNButtons) do b:SetSelected(b.value == s.reportTopN) end
    for _, b in ipairs(self.channelButtons) do b:SetSelected(b.value == s.reportChannel) end
    if not self.reportIntervalBox:HasFocus() then
        self.reportIntervalBox:SetText(FormatInterval(s.reportInterval))
    end
    local showRealm = s.reportShowRealm and true or false
    self.realmButton:SetLabel((showRealm and "|cff40ff40[开]|r " or "|cff888888[关]|r ") .. "汇报人名带服务器")
    self.realmButton:SetSelected(showRealm)
    local recordOn = s.recordChat and true or false
    self.recordButton:SetLabel((recordOn and "|cff40ff40[开]|r " or "|cff888888[关]|r ") .. "保存后按人发送到聊天框")
    self.recordButton:SetSelected(recordOn)
    for _, b in ipairs(self.recordChannelButtons) do b:SetSelected(b.value == s.recordChannel) end
    if not self.recordIntervalBox:HasFocus() then
        self.recordIntervalBox:SetText(FormatInterval(s.recordInterval))
    end
    for _, b in ipairs(self.flagButtons) do
        local on = b.def.get() and true or false
        b:SetLabel((on and "|cff40ff40[开]|r " or "|cff888888[关]|r ") .. b.def.label)
        b:SetSelected(on)
    end
    if not self.resumeBox:HasFocus() then
        self.resumeBox:SetText(tostring(s.resumeWindowHours or 12))
    end
    self:RefreshTags()
end

-- 数据或设置变化时刷新所有可见实例
RWT:On("RWT_DATA_CHANGED", function()
    for _, view in ipairs(instances) do
        if view.frame:IsVisible() then view:Refresh() end
    end
end)

------------------------------------------------------------
-- 主面板"设置"标签页
------------------------------------------------------------

local TabView = {}

function TabView:Create(parent)
    self.inner = SettingsView.New(parent)
    return self.inner.frame
end

function TabView:Refresh()
    if self.inner then self.inner:Refresh() end
end

MainWindow:RegisterView("settings", TabView)
