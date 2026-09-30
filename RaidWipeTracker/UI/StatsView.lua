local addonName, RWT = ...

local Util, Widgets = RWT.Util, RWT.UI.Widgets
local MainWindow = RWT.UI.MainWindow

local StatsView = {}
StatsView.scope = "SESSION"   -- "SESSION" 本 Session / "BOSS" 同 Boss 同难度全部 Session
StatsView.selectedPlayer = nil

local RANK_W = 280
local DETAIL_W = 560
local OVERVIEW_W, OVERVIEW_H = 480, 520

local overview

-- 当前范围下参与统计的 Session 列表
function StatsView:GetScopeSessions()
    local session = MainWindow:GetSelectedSession()
    if not session then return nil, {} end
    if self.scope == "BOSS" then
        return session, RWT.Statistics:SessionsForBoss(session)
    end
    return session, { session }
end

function StatsView:Create(parent)
    local f = CreateFrame("Frame", nil, parent)

    self.header = Widgets.CreateText(f, "GameFontHighlight")
    self.header:SetPoint("TOPLEFT", 4, -4)
    self.header:SetWidth(500)
    self.header:SetSpacing(4)

    self.sendButton = Widgets.CreateButton(f, "发送", 120, 24, function() self:SendReport() end)
    self.sendButton:SetPoint("TOPRIGHT", -4, -2)
    self.overviewButton = Widgets.CreateButton(f, "总览", 70, 24, function() self:ShowOverview() end)
    self.overviewButton:SetPoint("RIGHT", self.sendButton, "LEFT", -6, 0)
    self.scopeButton = Widgets.CreateButton(f, "", 150, 24, function()
        self.scope = (self.scope == "SESSION") and "BOSS" or "SESSION"
        self.selectedPlayer = nil
        self:Refresh()
    end)
    self.scopeButton:SetPoint("RIGHT", self.overviewButton, "LEFT", -6, 0)
    self.pendingButton = Widgets.CreateButton(f, "去填写待处理", 120, 24, function()
        local session = MainWindow:GetSelectedSession()
        local pull = session and RWT.Session:GetPendingPulls(session)[1]
        if pull then RWT.UI.WipeWindow:Open(session.sessionID, pull.pullNumber) end
    end)
    self.pendingButton:SetPoint("TOPRIGHT", self.sendButton, "BOTTOMRIGHT", 0, -4)

    -- 左侧：责任人排行 + 分类排行
    local left = Widgets.CreatePanel(f)
    left:SetPoint("TOPLEFT", 0, -64)
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(RANK_W + 32)

    local rankTitle = Widgets.CreateText(left, "GameFontNormal")
    rankTitle:SetPoint("TOPLEFT", 8, -6)
    rankTitle:SetText("灭团责任次数（点击查看明细）")

    self.rankScroll, self.rankContent = Widgets.CreateScrollArea(left, RANK_W)
    self.rankScroll:SetPoint("TOPLEFT", 4, -24)
    self.rankScroll:SetPoint("BOTTOMRIGHT", -26, 170)
    self.rankPool = Widgets.CreatePool(function()
        local b = Widgets.CreateToggle(self.rankContent, RANK_W, 22, "LEFT")
        b.countText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.countText:SetPoint("RIGHT", -8, 0)
        b.text:SetPoint("RIGHT", -56, 0)
        b:SetScript("OnClick", function(btn)
            self.selectedPlayer = btn.playerName
            self:Refresh()
        end)
        return b
    end)
    self.emptyRank = Widgets.CreateText(self.rankContent, "GameFontDisable")
    self.emptyRank:SetPoint("TOPLEFT", 6, -6)
    self.emptyRank:SetText("还没有责任人记录")

    local catTitle = Widgets.CreateText(left, "GameFontNormal")
    catTitle:SetPoint("BOTTOMLEFT", 8, 150)
    catTitle:SetText("按 tag")
    self.categoryText = Widgets.CreateText(left, "GameFontHighlightSmall")
    self.categoryText:SetPoint("TOPLEFT", catTitle, "BOTTOMLEFT", 0, -4)
    self.categoryText:SetWidth(RANK_W)
    self.categoryText:SetHeight(140)
    self.categoryText:SetSpacing(2)

    -- 右侧：玩家明细
    local right = Widgets.CreatePanel(f)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT")
    self.detailScroll, self.detailContent = Widgets.CreateScrollArea(right, DETAIL_W)
    self.detailScroll:SetPoint("TOPLEFT", 6, -6)
    self.detailScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    self.detailText = Widgets.CreateText(self.detailContent, "GameFontHighlight")
    self.detailText:SetPoint("TOPLEFT", 4, -4)
    self.detailText:SetWidth(DETAIL_W - 8)
    self.detailText:SetSpacing(3)
    return f
end

function StatsView:RenderHeader(session, sessions)
    local s = RWT.Statistics:Summarize(sessions)
    local lines = {}
    if self.scope == "BOSS" then
        table.insert(lines, string.format("|cffffd100%s|r（%s）  全部 %d 个 Session 累计", session.bossName or "?", session.difficultyName or "?", s.sessions))
    else
        table.insert(lines, string.format("|cffffd100%s|r（%s）  Progress Session  |cff888888%s%s|r",
            session.bossName or "?", session.difficultyName or "?", session.startDateText or "-",
            session.endDateText and (" ~ " .. session.endDateText) or ""))
    end
    local unknownText = s.unknown > 0 and string.format("（含未知 %d）", s.unknown) or ""
    table.insert(lines, string.format("总 Pull：%d    Wipe：%d%s    Kill：%d", s.total, s.wipes, unknownText, s.kills))
    if s.pending > 0 then
        table.insert(lines, string.format("|cffff9930注意：有 %d 把待填写，统计可能不完整。|r", s.pending))
    end
    self.header:SetText(table.concat(lines, "\n"))
    self.pendingButton:SetShown(self.scope == "SESSION" and s.pending > 0)
end

function StatsView:RenderRanking(ranking, total)
    self.rankPool:ReleaseAll()
    local y = 0
    local found = false
    for i, rec in ipairs(ranking) do
        local b = self.rankPool:Acquire()
        b.playerName = rec.name
        b:SetPoint("TOPLEFT", self.rankContent, "TOPLEFT", 0, -y)
        b:SetLabel(string.format("%d. %s", i, Util.ColorizeByClass(Util.ShortName(rec.name), rec.class)))
        b.countText:SetText(rec.count .. " 次")
        b:SetSelected(rec.name == self.selectedPlayer)
        if rec.name == self.selectedPlayer then found = true end
        y = y + 24
    end
    if not found then self.selectedPlayer = nil end
    self.emptyRank:SetShown(#ranking == 0)
    self.rankContent:SetHeight(math.max(y, 1))
end

function StatsView:RenderCategories(sessions)
    local lines = {}
    for i, item in ipairs(RWT.Statistics:TagRanking(sessions)) do
        if i > 10 then
            table.insert(lines, "…")
            break
        end
        table.insert(lines, string.format("%s  %d 次", RWT.Tags:FormatOne(item.key), item.count))
    end
    self.categoryText:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff888888无|r")
end

function StatsView:RenderDetail(ranking)
    local rec
    for _, r in ipairs(ranking) do
        if r.name == self.selectedPlayer then rec = r break end
    end
    if not rec then
        self.detailText:SetText("|cff888888在左侧点击玩家查看其全部记录。|r")
        self.detailContent:SetHeight(40)
        return
    end

    local lines = {}
    table.insert(lines, string.format("%s   |cffffd100共 %d 次|r", Util.ColorizeByClass(rec.name, rec.class), rec.count))
    table.insert(lines, "")
    for _, item in ipairs(RWT.Statistics.SortCounts(rec.tags)) do
        table.insert(lines, string.format("%s ×%d", RWT.Tags:FormatOne(item.key), item.count))
    end
    table.insert(lines, "")
    local fmt = self.scope == "BOSS" and Util.FormatDate or Util.FormatTime
    for _, e in ipairs(rec.entries) do
        table.insert(lines, string.format("|cffffd100Pull %d|r   %s   %s",
            e.pullNumber, fmt(e.timestamp), RWT.Tags:Format(e.tags, "|cff888888" .. RWT.NO_TAG_LABEL .. "|r")))
    end
    self.detailText:SetText(table.concat(lines, "\n"))
    self.detailContent:SetHeight(self.detailText:GetStringHeight() + 12)
end

function StatsView:Refresh()
    local session, sessions = self:GetScopeSessions()
    self.scopeButton:SetText(self.scope == "BOSS" and "范围：该 Boss 全部" or "范围：本 Session")
    local topN = RWT.db.settings.reportTopN == 3 and 3 or 5
    self.sendButton:SetText(string.format("发送 Top %d", topN))
    self.sendButton:SetEnabled(session ~= nil and not Util.InCombatOrEncounter())
    self.overviewButton:SetEnabled(session ~= nil)
    self.scopeButton:SetEnabled(session ~= nil)

    if not session then
        self.header:SetText("还没有任何 Session。")
        self.pendingButton:Hide()
        self:RenderRanking({}, 0)
        self.categoryText:SetText("")
        self:RenderDetail({})
        self:RefreshOverview()
        return
    end

    local ranking, total = RWT.Statistics:PlayerRanking(sessions)
    self:RenderHeader(session, sessions)
    self:RenderRanking(ranking, total)
    self:RenderCategories(sessions)
    self:RenderDetail(ranking)
    self:RefreshOverview()
end

local function EnsureOverview()
    if overview then return overview end
    overview = Widgets.CreateWindow("RaidWipeTrackerOverview", OVERVIEW_W, OVERVIEW_H, "HIGH")
    overview.title:SetText("总览")
    local scroll, content = Widgets.CreateScrollArea(overview, OVERVIEW_W - 56)
    scroll:SetPoint("TOPLEFT", 12, -40)
    scroll:SetPoint("BOTTOMRIGHT", -28, 12)
    local text = Widgets.CreateText(content, "GameFontHighlight")
    text:SetPoint("TOPLEFT", 4, -4)
    text:SetWidth(OVERVIEW_W - 64)
    text:SetSpacing(3)
    text:SetWordWrap(true)
    overview.text = text
    overview.content = content
    return overview
end

function StatsView:ShowOverview()
    local win = EnsureOverview()
    win:Show()
    self:RefreshOverview()
end

function StatsView:RefreshOverview()
    if not overview or not overview:IsShown() then return end
    local session, sessions = self:GetScopeSessions()
    local lines = session and RWT.ChatReport:BuildOverviewLines(sessions) or { "还没有任何 Session。" }
    overview.text:SetText(table.concat(lines, "\n"))
    overview.content:SetHeight(math.max(overview.text:GetStringHeight() + 12, 1))
end

-- 由外部指定统计范围（"SESSION" / "BOSS"）
function StatsView:SetScope(scope)
    if scope == "SESSION" or scope == "BOSS" then
        if scope ~= self.scope then self.selectedPlayer = nil end
        self.scope = scope
    end
end

function StatsView:SendReport()
    local session, sessions = self:GetScopeSessions()
    if not session then return end
    RWT.ChatReport:Send(sessions, self.scope == "BOSS")
end

MainWindow:RegisterView("stats", StatsView)
RWT.UI.StatsView = StatsView

-- 战斗状态变化时刷新发送按钮
RWT:RegisterEvent("PLAYER_REGEN_ENABLED", function() if StatsView.frame then MainWindow:Refresh() end end)
RWT:RegisterEvent("PLAYER_REGEN_DISABLED", function() if StatsView.frame then MainWindow:Refresh() end end)
