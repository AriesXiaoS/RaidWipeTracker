local addonName, RWT = ...

local Util, Widgets = RWT.Util, RWT.UI.Widgets
local MainWindow = RWT.UI.MainWindow
local STATUS, RESULT = RWT.STATUS, RWT.RESULT

local STATUS_COLOR = {
    ACTIVE = "ff40c0ff",
    PENDING = "ffff9930",
    RECORDED = "ff80ff80",
    SKIPPED = "ffa0a0a0",
}

local RESULT_COLOR = {
    WIPE = "ffff5050",
    KILL = "ff40ff40",
    UNKNOWN = "ffc0c0c0",
}

local function Colored(color, text)
    return "|c" .. color .. text .. "|r"
end

-- Session 状态文字
local function SessionStateText(session)
    if session.killed then return Colored("ff40ff40", "已击杀") end
    if session.closed then return Colored("ffa0a0a0", "已结束") end
    if RWT.db.state.currentSessionID == session.sessionID then return Colored("ffffd100", "进行中") end
    return Colored("ffc0c0c0", "未结束")
end

-- 一条 Pull 的多行描述（历史列表使用）
local function FormatPull(pull)
    local lines = {}
    table.insert(lines, string.format("|cffffd100Pull #%d|r   %s   %s   %s   %s%s",
        pull.pullNumber, Util.FormatTime(pull.timestamp or pull.startTimestamp),
        Colored(RESULT_COLOR[pull.result] or "ffffffff", RWT.RESULT_LABEL[pull.result] or "进行中"),
        Util.FormatDuration(pull.duration),
        Colored(STATUS_COLOR[pull.status] or "ffffffff", RWT.STATUS_LABEL[pull.status] or "?"),
        pull.manual and "   |cff888888手动|r" or ""))
    for _, p in ipairs(pull.players) do
        table.insert(lines, string.format("    %s  %s",
            Util.ColorizeByClass(Util.ShortName(p.name), p.class),
            RWT.Tags:Format(p.tags, "|cff888888" .. RWT.NO_TAG_LABEL .. "|r")))
    end
    if #pull.players == 0 and (pull.status == STATUS.RECORDED or pull.status == STATUS.SKIPPED)
        and pull.result ~= RESULT.KILL then
        table.insert(lines, "    |cff888888（无责任人）|r")
    end
    if pull.note and pull.note ~= "" then
        table.insert(lines, "    |cffaaaaaa备注：|r" .. Util.EscapeChat(pull.note))
    end
    return table.concat(lines, "\n")
end

------------------------------------------------------------
-- 当前 Session 视图
------------------------------------------------------------

local CurrentView = {}

function CurrentView:Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.info = Widgets.CreateText(f, "GameFontHighlight")
    self.info:SetPoint("TOPLEFT", 8, -8)
    self.info:SetWidth(880)
    self.info:SetSpacing(4)

    local buttons = {
        { "填写下一个待处理", function() RWT.UI.WipeWindow:OpenNextPending() end },
        { "查看统计", function()
            local s = RWT.Session:GetCurrentOrLatest()
            if s then MainWindow:ShowStats(s.sessionID) end
        end },
        { "结束当前 Session", function()
            local s = RWT.Session:GetCurrent()
            if s then Widgets.Confirm("结束当前 Session？（未击杀，之后可以在历史中重新设为当前）", function()
                RWT.Session:Close(s, "MANUAL")
                RWT:NotifyDataChanged()
            end) end
        end },
        { "下一把新建 Session", function()
            RWT.db.state.forceNewSession = not RWT.db.state.forceNewSession
            RWT:NotifyDataChanged()
        end },
    }
    local first
    local prev
    for _, def in ipairs(buttons) do
        local b = Widgets.CreateButton(f, def[1], 150, 26, def[2])
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("BOTTOMLEFT", 8, 8) end
        first = first or b
        prev = b
    end

    local sessionButtons = {
        { "新建 Boss", function() RWT.UI.FloatPanel:NewBoss() end },
        { "新建 Session", function() RWT.UI.FloatPanel:NewSession() end },
    }
    prev = nil
    for _, def in ipairs(sessionButtons) do
        local b = Widgets.CreateButton(f, def[1], 150, 26, def[2])
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("BOTTOMLEFT", first, "TOPLEFT", 0, 6) end
        prev = b
    end
    return f
end

function CurrentView:Refresh()
    local state = RWT.db.state
    local session = RWT.Session:GetCurrent()
    local lines = {}
    if session then
        local summary = RWT.Statistics:Summarize(session)
        table.insert(lines, string.format("|cffffd100%s|r（%s）   %s", session.bossName or "?", session.difficultyName or "?", SessionStateText(session)))
        table.insert(lines, string.format("副本：%s", session.instanceName or "?"))
        table.insert(lines, string.format("开始：%s    最近活动：%s", session.startDateText or "-", Util.FormatDate(session.lastActivity)))
        table.insert(lines, string.format("Pull：%d    灭团：%d    击杀：%d    待填写：%s",
            summary.total, summary.wipes, summary.kills,
            summary.pending > 0 and Colored("ffff9930", tostring(summary.pending)) or "0"))
    else
        table.insert(lines, "当前没有 Session。开怪（ENCOUNTER_START）后自动创建或续接。")
    end

    table.insert(lines, "")
    local _, activePull = RWT.Encounter:GetActivePull()
    if activePull then
        table.insert(lines, string.format("状态：|cff40c0ff战斗中|r  %s Pull #%d（%s 开始）",
            activePull.bossName or "?", activePull.pullNumber, Util.FormatTime(activePull.startTimestamp)))
    else
        table.insert(lines, "状态：空闲")
    end
    local allPending = RWT.Session:CountAllPending()
    table.insert(lines, string.format("所有 Session 待填写：%s", allPending > 0 and Colored("ffff9930", tostring(allPending)) or "0"))
    table.insert(lines, string.format("下一次开怪：%s", state.forceNewSession and "|cffffd100强制新建 Session|r"
        or string.format("同 Boss 同难度 %d 小时内自动续接", RWT.db.settings.resumeWindowHours or 12)))
    self.info:SetText(table.concat(lines, "\n"))
end

MainWindow:RegisterView("current", CurrentView)

------------------------------------------------------------
-- 历史视图：左侧 Session 列表，右侧 Pull 列表
------------------------------------------------------------

local HistoryView = {}
local LIST_W = 260
local PULL_CONTENT_W = 580

function HistoryView:Create(parent)
    local f = CreateFrame("Frame", nil, parent)

    local left = Widgets.CreatePanel(f)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LIST_W + 32)
    self.listScroll, self.listContent = Widgets.CreateScrollArea(left, LIST_W)
    self.listScroll:SetPoint("TOPLEFT", 4, -4)
    self.listScroll:SetPoint("BOTTOMRIGHT", -26, 4)
    self.sessionPool = Widgets.CreatePool(function()
        local b = Widgets.CreateToggle(self.listContent, LIST_W, 38, "LEFT")
        b.text:SetWordWrap(true)
        b:SetScript("OnClick", function(btn) MainWindow:SelectSession(btn.sessionID) end)
        return b
    end)
    self.emptyList = Widgets.CreateText(self.listContent, "GameFontDisable")
    self.emptyList:SetPoint("TOPLEFT", 6, -6)
    self.emptyList:SetText("暂无记录")

    local right = Widgets.CreatePanel(f)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT")

    self.header = Widgets.CreateText(right, "GameFontHighlight")
    self.header:SetPoint("TOPLEFT", 8, -8)
    self.header:SetWidth(PULL_CONTENT_W)
    self.header:SetSpacing(3)

    local actions = {
        { "统计", function(s) MainWindow:ShowStats(s.sessionID) end },
        { "设为当前", function(s)
            if s.killed then return end
            if s.closed then RWT.Session:Reopen(s) end
            RWT.Session:SetCurrent(s.sessionID)
            RWT.db.state.forceNewSession = false
            RWT:NotifyDataChanged()
        end },
        { "结束", function(s)
            if s.closed then return end
            RWT.Session:Close(s, "MANUAL")
            RWT:NotifyDataChanged()
        end },
        { "删除 Session", function(s)
            Widgets.Confirm(string.format("删除 Session「%s」及其全部 %d 条 Pull 记录？此操作不可撤销。",
                RWT.Session.Describe(s), #s.pulls), function()
                RWT.Session:Delete(s.sessionID)
                MainWindow.selectedSessionID = nil
                RWT:NotifyDataChanged()
            end)
        end },
    }
    self.actionButtons = {}
    local prev
    for _, def in ipairs(actions) do
        local b = Widgets.CreateButton(right, def[1], 96, 22, function()
            local s = MainWindow:GetSelectedSession()
            if s then def[2](s) end
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 8, -52) end
        self.actionButtons[def[1]] = b
        prev = b
    end

    self.pullScroll, self.pullContent = Widgets.CreateScrollArea(right, PULL_CONTENT_W)
    self.pullScroll:SetPoint("TOPLEFT", 4, -82)
    self.pullScroll:SetPoint("BOTTOMRIGHT", -26, 4)
    self.pullPool = Widgets.CreatePool(function() return self:CreatePullRow() end)
    return f
end

function HistoryView:CreatePullRow()
    local row = CreateFrame("Frame", nil, self.pullContent, "BackdropTemplate")
    row:SetWidth(PULL_CONTENT_W)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    row:SetBackdropColor(1, 1, 1, 0.03)
    row.text = Widgets.CreateText(row, "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", 6, -5)
    row.text:SetWidth(PULL_CONTENT_W - 140)
    row.text:SetSpacing(2)
    row.deleteButton = Widgets.CreateButton(row, "删除", 56, 20, function()
        local session, pull = row.session, row.pull
        Widgets.Confirm(string.format("删除 Pull #%d 的记录？统计会随之更新。", pull.pullNumber), function()
            RWT.Session:DeletePull(session, pull.pullNumber)
            RWT:NotifyDataChanged()
        end)
    end)
    row.deleteButton:SetPoint("TOPRIGHT", -4, -4)
    row.editButton = Widgets.CreateButton(row, "编辑", 56, 20, function()
        RWT.UI.WipeWindow:Open(row.session.sessionID, row.pull.pullNumber)
    end)
    row.editButton:SetPoint("RIGHT", row.deleteButton, "LEFT", -4, 0)
    return row
end

function HistoryView:RefreshList(selected)
    self.sessionPool:ReleaseAll()
    local y = 0
    local list = RWT.Session:GetSortedList()
    for _, session in ipairs(list) do
        local b = self.sessionPool:Acquire()
        b.sessionID = session.sessionID
        b:SetPoint("TOPLEFT", self.listContent, "TOPLEFT", 0, -y)
        b:SetLabel(string.format("|cffffffff%s|r（%s）\n|cffaaaaaa%s  %d Pull|r  %s",
            session.bossName or "?", session.difficultyName or "?",
            Util.FormatShortDate(session.startTimestamp), #session.pulls, SessionStateText(session)))
        b:SetSelected(selected and selected.sessionID == session.sessionID)
        y = y + 42
    end
    self.emptyList:SetShown(#list == 0)
    self.listContent:SetHeight(math.max(y, 1))
end

function HistoryView:RefreshPulls(session)
    self.pullPool:ReleaseAll()
    for _, b in pairs(self.actionButtons) do b:SetEnabled(session ~= nil) end
    if not session then
        self.header:SetText("没有选中的 Session")
        self.pullContent:SetHeight(1)
        return
    end
    self.actionButtons["设为当前"]:SetEnabled(not session.killed and RWT.db.state.currentSessionID ~= session.sessionID)
    self.actionButtons["结束"]:SetEnabled(not session.closed)

    local summary = RWT.Statistics:Summarize(session)
    self.header:SetText(string.format("|cffffd100%s|r（%s） %s   %s\n%s 开始%s    %d Pull / %d 灭团 / %d 击杀    待填写 %d",
        session.bossName or "?", session.difficultyName or "?", session.instanceName or "", SessionStateText(session),
        session.startDateText or "-", session.endDateText and ("，" .. session.endDateText .. " 结束") or "",
        summary.total, summary.wipes, summary.kills, summary.pending))

    local y = 0
    for i = #session.pulls, 1, -1 do -- 最新在上
        local pull = session.pulls[i]
        local row = self.pullPool:Acquire()
        row.session, row.pull = session, pull
        row.text:SetText(FormatPull(pull))
        row.editButton:SetEnabled(pull.status ~= STATUS.ACTIVE)
        row.deleteButton:SetEnabled(pull.status ~= STATUS.ACTIVE)
        local h = math.max(row.text:GetStringHeight() + 12, 30)
        row:SetHeight(h)
        row:SetPoint("TOPLEFT", self.pullContent, "TOPLEFT", 0, -y)
        y = y + h + 4
    end
    self.pullContent:SetHeight(math.max(y, 1))
end

function HistoryView:Refresh()
    local session = MainWindow:GetSelectedSession()
    self:RefreshList(session)
    self:RefreshPulls(session)
end

MainWindow:RegisterView("history", HistoryView)
