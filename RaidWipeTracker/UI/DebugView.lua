local addonName, RWT = ...

local DebugView = {}
local Widgets = RWT.UI.Widgets
local MainWindow = RWT.UI.MainWindow
local Util = RWT.Util

local ROW_H = 16

local function OnOff(on)
    return on and "|cff40ff40开启|r" or "|cff888888关闭|r"
end

local function FormatSummary(report)
    local head
    if report.group == "solo" then
        head = "当前只有自己"
    elseif report.group == "party" then
        head = string.format("小队 %d 人", report.expected)
    else
        head = string.format("团队 %d 人", report.expected)
    end
    local missing = #report.missing
    local state = missing == 0 and "|cff40ff40全部识别|r" or "|cffff4040有未识别|r"
    local text = string.format("%s    已识别 %d    未识别 %d    %s",
        head, #report.recognized, missing, state)
    if report.fakes then
        text = text .. string.format("\n假团员额外 %d 人，不计入上面", #report.fakes)
    end
    return text
end

local function MemberLine(member, suffix)
    local short = Util.ShortName(member.name)
    local colored = member.class and Util.ColorizeByClass(short, member.class) or ("|cffcccccc" .. short .. "|r")
    local classNote = member.class and "" or "  |cff888888无职业|r"
    local role = RWT.ROLE_LABEL[member.role] or RWT.ROLE_LABEL.NONE
    local unit = member.unit and ("  |cff888888" .. member.unit .. "|r") or ""
    return string.format("%s    |cffaaaaaa%s|r    %s%s%s%s", colored, member.name, role, unit, classNote, suffix or "")
end

function DebugView:Create(parent)
    local f = CreateFrame("Frame", nil, parent)

    self.status = Widgets.CreateText(f, "GameFontHighlight")
    self.status:SetPoint("TOPLEFT", 16, -16)
    self.status:SetWidth(860)
    self.status:SetSpacing(4)

    self.hint = Widgets.CreateText(f, "GameFontDisableSmall")
    self.hint:SetPoint("TOPLEFT", self.status, "BOTTOMLEFT", 0, -12)
    self.hint:SetWidth(860)
    self.hint:SetText("推荐顺序：先开假团员，再模拟开怪，然后模拟灭团或模拟击杀。关闭调试会同时关掉副本检查绕过和假团员。假团员只影响之后开始的 Pull 快照。")

    self.startButton = Widgets.CreateButton(f, "模拟开怪", 120, 26, function()
        RWT.Encounter:DebugStart()
    end)
    self.startButton:SetPoint("TOPLEFT", self.hint, "BOTTOMLEFT", 0, -20)

    self.wipeButton = Widgets.CreateButton(f, "模拟灭团", 120, 26, function()
        RWT.Encounter:DebugEnd(false)
    end)
    self.wipeButton:SetPoint("LEFT", self.startButton, "RIGHT", 8, 0)

    self.killButton = Widgets.CreateButton(f, "模拟击杀", 120, 26, function()
        RWT.Encounter:DebugEnd(true)
    end)
    self.killButton:SetPoint("LEFT", self.wipeButton, "RIGHT", 8, 0)

    self.rosterButton = Widgets.CreateButton(f, "开启假团员", 130, 26, function()
        RWT.Encounter:DebugToggleRoster()
    end)
    self.rosterButton:SetPoint("LEFT", self.killButton, "RIGHT", 8, 0)

    self.offButton = Widgets.CreateButton(f, "关闭调试", 120, 26, function()
        RWT.Encounter:DebugOff()
    end)
    self.offButton:SetPoint("LEFT", self.rosterButton, "RIGHT", 8, 0)

    self.checkTitle = Widgets.CreateText(f, "GameFontNormal")
    self.checkTitle:SetPoint("TOPLEFT", self.startButton, "BOTTOMLEFT", 0, -18)
    self.checkTitle:SetWidth(130)
    self.checkTitle:SetText("当前团队成员")

    self.recheckButton = Widgets.CreateButton(f, "重新检查", 100, 22, function()
        if self.rosterScroll then self.rosterScroll:SetVerticalScroll(0) end
        self:Refresh()
    end)
    self.recheckButton:SetPoint("LEFT", self.checkTitle, "RIGHT", 12, 0)

    self.summary = Widgets.CreateText(f, "GameFontHighlightSmall")
    self.summary:SetPoint("TOPLEFT", self.checkTitle, "BOTTOMLEFT", 0, -8)
    self.summary:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    self.summary:SetSpacing(3)

    self.checkPanel = Widgets.CreatePanel(f)
    self.checkPanel:SetPoint("TOPLEFT", self.summary, "BOTTOMLEFT", -6, -8)
    self.checkPanel:SetPoint("BOTTOMRIGHT", -12, 8)

    self.rosterScroll, self.rosterContent = Widgets.CreateScrollArea(self.checkPanel, 800)
    self.rosterScroll:SetPoint("TOPLEFT", 8, -8)
    self.rosterScroll:SetPoint("BOTTOMRIGHT", -26, 8)

    self.linePool = Widgets.CreatePool(function()
        local fs = Widgets.CreateText(self.rosterContent, "GameFontHighlightSmall")
        fs:SetWidth(780)
        fs:SetWordWrap(false)
        return fs
    end)

    f:SetScript("OnShow", function()
        if self.rosterScroll then self.rosterScroll:SetVerticalScroll(0) end
        self:Refresh()
    end)
    return f
end

function DebugView:RenderRoster()
    local report = RWT.Roster:Inspect()
    self.summary:SetText(FormatSummary(report))

    self.linePool:ReleaseAll()
    local content = self.rosterContent
    local y = 2
    local function AddLine(text)
        local fs = self.linePool:Acquire()
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
        fs:SetText(text)
        y = y + ROW_H
    end
    local function AddHeader(text)
        if y > 2 then y = y + 6 end
        AddLine("|cffffd100" .. text .. "|r")
    end

    if #report.recognized == 0 then
        AddLine("|cff888888没有已识别的团员|r")
    else
        local groups = RWT.Roster.GroupByRole(report.recognized)
        for _, role in ipairs(RWT.ROLE_ORDER) do
            local members = groups[role]
            if #members > 0 then
                AddHeader(string.format("%s（%d）", RWT.ROLE_LABEL[role], #members))
                for _, member in ipairs(members) do
                    AddLine(MemberLine(member))
                end
            end
        end
    end

    if #report.missing > 0 then
        AddHeader(string.format("未识别（%d）", #report.missing))
        for _, member in ipairs(report.missing) do
            AddLine(string.format("|cffff4040%s|r    %s", member.unit, member.reason))
        end
    end

    if report.fakes then
        AddHeader(string.format("假团员（%d）", #report.fakes))
        if #report.fakes == 0 then
            AddLine("|cff888888没有假团员|r")
        end
        for _, member in ipairs(report.fakes) do
            local suffix = "  |cff66ccff假团员|r"
            if member.skipped then
                suffix = suffix .. "  |cff888888（与真实团员重名，快照会跳过）|r"
            end
            AddLine(MemberLine(member, suffix))
        end
    end

    content:SetHeight(math.max(y + 4, 1))
end

function DebugView:Refresh()
    local enc = RWT.Encounter
    local fake = RWT.Roster.fakeMembers ~= nil
    local _, pull = enc:GetActivePull()
    local debugPull = pull and pull.encounterID == RWT.DEBUG_ENCOUNTER_ID and pull or nil

    local pullText
    if debugPull then
        pullText = string.format("|cffffd100Pull #%d|r", debugPull.pullNumber)
    elseif pull then
        pullText = string.format("|cff888888无（当前进行中的是 %s Pull #%d）|r", pull.bossName or "其他战斗", pull.pullNumber)
    else
        pullText = "|cff888888无|r"
    end

    self.status:SetText(string.format("调试绕过：%s    假团员：%s\n进行中的调试战斗：%s",
        OnOff(enc.debugBypass), OnOff(fake), pullText))
    self.rosterButton:SetText(fake and "关闭假团员" or "开启假团员")
    self.wipeButton:SetEnabled(debugPull ~= nil)
    self.killButton:SetEnabled(debugPull ~= nil)
    self:RenderRoster()
end

RWT:On("RWT_ROSTER_CHANGED", function()
    if DebugView.frame and DebugView.frame:IsVisible() then
        DebugView:Refresh()
    end
end)

MainWindow:RegisterView("debug", DebugView)
