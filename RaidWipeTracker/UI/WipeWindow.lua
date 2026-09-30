local addonName, RWT = ...

local WipeWindow = {}
RWT.UI.WipeWindow = WipeWindow

local Util, Widgets = RWT.Util, RWT.UI.Widgets
local STATUS, RESULT = RWT.STATUS, RWT.RESULT

local WIDTH, HEIGHT = 880, 600
local LEFT_W = 300          -- 左栏（团队）宽度
local RIGHT_W = 500         -- 右栏（责任人）内容宽度
local PLAYER_W, PLAYER_H = 132, 22
local TAG_H, TAG_MIN_W, TAG_MAX_W = 20, 48, 300
local ROW_PAD = 8
local ROW_TOP = 28          -- 名字行高度

local frame

------------------------------------------------------------
-- 草稿：state.draft 即当前窗口编辑的数据，随 SavedVariables 落盘，/reload 不丢
------------------------------------------------------------

local function GetDraft()
    return RWT.db.state.draft
end

local function GetTarget()
    local draft = GetDraft()
    if not draft then return nil end
    local session = RWT.Session:Get(draft.sessionID)
    return session, RWT.Session:GetPull(session, draft.pullNumber)
end

local function FindSelected(name)
    local draft = GetDraft()
    for i, p in ipairs(draft.players) do
        if p.name == name then return p, i end
    end
    return nil
end

-- 把输入框里的文字加为临时 tag（与预设同名时等同于选中该预设）
-- 不是预设的会记入本次登录列表，下一把还能直接点
local function CommitText(entry)
    local tag = RWT.Tags.Normalize(entry.pendingText)
    entry.pendingText = nil
    if not tag or RWT.Tags.IndexOf(entry.tags, tag) then return false end
    if #entry.tags >= RWT.MAX_TAGS_PER_PLAYER then
        RWT:Print("每人最多 %d 个 tag。", RWT.MAX_TAGS_PER_PLAYER)
        return false
    end
    table.insert(entry.tags, tag)
    local _, pull = GetTarget()
    local encounterID = pull and pull.encounterID
    if not RWT.Tags:IsPreset(tag, encounterID) then
        RWT.Tags:Remember(tag, encounterID)
    end
    return true
end

-- 保存 / 暂存前把所有输入框中未回车的文字也提交为 tag
local function CommitAllPending(draft)
    for _, entry in ipairs(draft.players) do
        entry.tags = entry.tags or {}
        CommitText(entry)
    end
end

-- 把草稿写回待填写的 Pull 并清空草稿（下一把开始 / 切换到其他 Pull / 关闭窗口时调用）
-- 已记录的 Pull 不会被未保存的修改覆盖
function WipeWindow:StashDraft()
    local draft = GetDraft()
    if not draft then return end
    CommitAllPending(draft)
    local session, pull = GetTarget()
    if pull and pull.status == STATUS.PENDING then
        pull.players = RWT.Session.SanitizePlayers(draft.players)
        pull.note = Util.Trim(draft.note)
    end
    RWT.db.state.draft = nil
    if frame and frame:IsShown() then frame:Hide() end
end

------------------------------------------------------------
-- 创建界面
------------------------------------------------------------

local function CreateSelectedRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetWidth(RIGHT_W)
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    row:SetBackdropColor(0.1, 0.1, 0.13, 0.9)
    row:SetBackdropBorderColor(0.25, 0.25, 0.3, 1)

    row.nameText = Widgets.CreateText(row, "GameFontNormal")
    row.nameText:SetPoint("TOPLEFT", ROW_PAD, -6)

    row.roleText = Widgets.CreateText(row, "GameFontDisableSmall")
    row.roleText:SetPoint("LEFT", row.nameText, "RIGHT", 8, 0)

    row.removeButton = Widgets.CreateButton(row, "移除", 50, 18, function()
        WipeWindow:TogglePlayer(row.entry)
    end)
    row.removeButton:SetPoint("TOPRIGHT", -6, -4)

    row.tagPool = Widgets.CreatePool(function()
        local b = Widgets.CreateToggle(row, 60, TAG_H)
        b:SetScript("OnClick", function(self, mouseButton)
            WipeWindow:OnTagClicked(row, self, mouseButton)
        end)
        b:SetScript("OnEnter", function(self)
            if self.kind == "preset" then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local _, pull = GetTarget()
            local bossPreset = pull and pull.encounterID
            if self.kind == "session" then
                GameTooltip:SetText("临时 tag（本次登录保留）")
                GameTooltip:AddLine("左键：给该玩家加上或取消", 1, 1, 1)
                GameTooltip:AddLine("右键：从本次登录中删除", 1, 1, 1)
                if bossPreset then
                    GameTooltip:AddLine("Shift+右键：设为该首领的预设 tag", 1, 1, 1)
                else
                    GameTooltip:AddLine("Shift+右键：设为通用预设 tag", 1, 1, 1)
                end
            else
                GameTooltip:SetText("临时 tag")
                GameTooltip:AddLine("左键：移除", 1, 1, 1)
                if bossPreset then
                    GameTooltip:AddLine("右键：设为该首领的预设 tag", 1, 1, 1)
                else
                    GameTooltip:AddLine("右键：设为通用预设 tag", 1, 1, 1)
                end
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        return b
    end)

    row.tagLabel = Widgets.CreateText(row, "GameFontHighlightSmall")
    row.tagLabel:SetText("自定义：")

    row.tagBox = Widgets.CreateEditBox(row, RIGHT_W - 130, RWT.MAX_TAG_LETTERS)
    row.tagBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and row.entry then row.entry.pendingText = self:GetText() end
    end)
    -- 回车添加临时 tag 并保持焦点，方便连续输入
    row.tagBox:SetScript("OnEnterPressed", function() WipeWindow:CommitRowText(row) end)
    row.tagBox:SetScript("OnTabPressed", function()
        WipeWindow:FocusRow(row.index + 1)
    end)
    row.tagAdd = Widgets.CreateButton(row, "添加", 50, 20, function() WipeWindow:CommitRowText(row) end)
    return row
end

local function CreateBanner(parent)
    local banner = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    banner:SetHeight(30)
    banner:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    banner:SetBackdropColor(0.45, 0.35, 0.05, 0.5)
    banner.text = Widgets.CreateText(banner, "GameFontHighlightSmall")
    banner.text:SetPoint("LEFT", 8, 0)
    banner.text:SetPoint("RIGHT", -230, 0)
    banner.text:SetJustifyV("MIDDLE")
    banner.ignore = Widgets.CreateButton(banner, "忽略", 60, 22, function()
        local _, pull = GetTarget()
        if pull then pull.resolveMode = nil end
        WipeWindow:Render()
    end)
    banner.ignore:SetPoint("RIGHT", -6, 0)
    banner.action = Widgets.CreateButton(banner, "", 150, 22, function()
        if banner.actionFn then banner.actionFn() end
    end)
    banner.action:SetPoint("RIGHT", banner.ignore, "LEFT", -6, 0)
    return banner
end

local function CreateFrameOnce()
    if frame then return frame end
    frame = Widgets.CreateWindow("RaidWipeTrackerWipeWindow", WIDTH, HEIGHT, "HIGH")
    frame:SetPoint("CENTER", 0, 40)

    frame.subtitle = Widgets.CreateText(frame, "GameFontHighlight")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)

    frame.pendingButton = Widgets.CreateButton(frame, "", 130, 22, function()
        local draft = GetDraft()
        local session, pull = RWT.Session:FindNextPending(draft and draft.sessionID, draft and draft.pullNumber)
        if session then WipeWindow:Open(session.sessionID, pull.pullNumber) end
    end)
    frame.pendingButton:SetPoint("TOPRIGHT", -36, -12)

    frame.banner = CreateBanner(frame)
    frame.banner:SetPoint("TOPLEFT", 12, -56)
    frame.banner:SetPoint("TOPRIGHT", -12, -56)

    -- 左栏：团队
    local leftPanel = Widgets.CreatePanel(frame)
    leftPanel:SetPoint("TOPLEFT", 12, -92)
    leftPanel:SetPoint("BOTTOMLEFT", 12, 76)
    leftPanel:SetWidth(LEFT_W + 8)
    frame.leftScroll, frame.leftContent = Widgets.CreateScrollArea(leftPanel, LEFT_W - 20)
    frame.leftScroll:SetPoint("TOPLEFT", 6, -6)
    frame.leftScroll:SetPoint("BOTTOMRIGHT", -26, 34)
    frame.headerPool = Widgets.CreatePool(function() return Widgets.CreateText(frame.leftContent, "GameFontNormal") end)
    frame.playerPool = Widgets.CreatePool(function()
        local b = Widgets.CreateToggle(frame.leftContent, PLAYER_W, PLAYER_H, "LEFT")
        b:SetScript("OnClick", function(self) WipeWindow:TogglePlayer(self.member) end)
        return b
    end)

    frame.manualBox = Widgets.CreateEditBox(leftPanel, LEFT_W - 90, 60)
    frame.manualBox:SetPoint("BOTTOMLEFT", 12, 8)
    frame.manualBox:SetScript("OnEnterPressed", function() WipeWindow:AddManual() end)
    local addButton = Widgets.CreateButton(leftPanel, "手动添加", 72, 22, function() WipeWindow:AddManual() end)
    addButton:SetPoint("LEFT", frame.manualBox, "RIGHT", 6, 0)

    -- 右栏：已选责任人
    local rightPanel = Widgets.CreatePanel(frame)
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 8, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", -12, 76)
    frame.rightScroll, frame.rightContent = Widgets.CreateScrollArea(rightPanel, RIGHT_W)
    frame.rightScroll:SetPoint("TOPLEFT", 6, -6)
    frame.rightScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    frame.rowPool = Widgets.CreatePool(function() return CreateSelectedRow(frame.rightContent) end)
    frame.emptyHint = Widgets.CreateText(frame.rightContent, "GameFontDisable")
    frame.emptyHint:SetPoint("TOPLEFT", 8, -8)
    frame.emptyHint:SetWidth(RIGHT_W - 16)
    frame.emptyHint:SetText("点击左侧玩家选中责任人（可多选，再次点击取消）。\n每个人可以多选预设 tag（通用在前，当前首领在后），也可以输入自定义 tag（回车添加）。\n没有责任人时直接保存或跳过即可。")

    -- 底部：备注与按钮
    local noteLabel = Widgets.CreateText(frame, "GameFontNormal")
    noteLabel:SetPoint("BOTTOMLEFT", 16, 50)
    noteLabel:SetText("备注：")
    frame.noteBox = Widgets.CreateEditBox(frame, WIDTH - 100, 200)
    frame.noteBox:SetPoint("LEFT", noteLabel, "RIGHT", 10, 0)
    frame.noteBox:SetScript("OnTextChanged", function(self, userInput)
        local draft = GetDraft()
        if userInput and draft then draft.note = self:GetText() end
    end)

    local cancel = Widgets.CreateButton(frame, "取消", 90, 26, function() WipeWindow:Cancel() end)
    cancel:SetPoint("BOTTOMRIGHT", -16, 14)
    local skip = Widgets.CreateButton(frame, "跳过", 90, 26, function() WipeWindow:Skip() end)
    skip:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
    local save = Widgets.CreateButton(frame, "保存", 110, 26, function() WipeWindow:Save() end)
    save:SetPoint("RIGHT", skip, "LEFT", -8, 0)
    frame.hint = Widgets.CreateText(frame, "GameFontDisableSmall")
    frame.hint:SetPoint("BOTTOMLEFT", 16, 20)
    frame.hint:SetText("关闭窗口 = 暂存为待填写；取消 = 放弃本次修改；跳过 = 无责任人")

    -- 关闭（X / ESC）时暂存到待填写的 Pull，不丢数据
    frame:SetScript("OnHide", function() WipeWindow:StashDraft() end)
    return frame
end

------------------------------------------------------------
-- 渲染
------------------------------------------------------------

function WipeWindow:RenderHeader(session, pull)
    frame.title:SetText(string.format("%s（%s）", pull.bossName or session.bossName or "?", session.difficultyName or "?"))
    local extra = pull.result == RESULT.KILL and "   |cff888888击杀把不计入责任统计|r" or ""
    frame.subtitle:SetText(string.format("Pull |cffffd100#%d|r    %s    %s    用时 %s    %s%s",
        pull.pullNumber, pull.dateText or "-", RWT.RESULT_LABEL[pull.result] or "?",
        Util.FormatDuration(pull.duration), RWT.STATUS_LABEL[pull.status] or "", extra))

    local others = RWT.Session:CountAllPending() - (pull.status == STATUS.PENDING and 1 or 0)
    frame.pendingButton:SetText(string.format("其他待填写：%d", others))
    frame.pendingButton:SetEnabled(others > 0)
end

function WipeWindow:RenderBanner(session, pull)
    local banner = frame.banner
    local suggestion = RWT.Session:GetResolveSuggestion(session, pull)
    if not suggestion then
        banner:Hide()
        return
    end
    banner:Show()
    if suggestion.kind == "MERGE" then
        local target = suggestion.target
        banner.text:SetText("检测到未结束的同 Boss Session：" .. RWT.Session.Describe(target) .. "。本把要并入吗？")
        banner.action:SetText("并入该 Session")
        banner.actionFn = function()
            RWT.Session:MovePull(session, pull.pullNumber, target)
            RWT:NotifyDataChanged()
        end
    else
        local previous = session.pulls[#session.pulls - 1]
        banner.text:SetText(string.format("本把已自动续接到 %s 开始的 Session（上一把 %s）。如果是新一轮开荒可以拆分。",
            Util.FormatShortDate(session.startTimestamp), Util.FormatShortDate(previous and previous.timestamp)))
        banner.action:SetText("拆分为新 Session")
        banner.actionFn = function()
            RWT.Session:SplitPullToNew(session, pull.pullNumber)
            RWT:NotifyDataChanged()
        end
    end
end

-- 左栏：开怪时的团队快照 + 开怪后加入的当前成员，按职责分组
function WipeWindow:RenderRoster(pull)
    frame.headerPool:ReleaseAll()
    frame.playerPool:ReleaseAll()

    local main = pull.roster or {}
    local inMain = {}
    for _, m in ipairs(main) do inMain[m.name] = true end
    local extras = {}
    for _, m in ipairs(RWT.Roster:Snapshot()) do
        if not inMain[m.name] then table.insert(extras, m) end
    end
    if #main == 0 then main, extras = extras, {} end

    local content = frame.leftContent
    local y = 4
    local function AddSection(title, members)
        if #members == 0 then return end
        local header = frame.headerPool:Acquire()
        header:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
        header:SetText(string.format("%s（%d）", title, #members))
        y = y + 18
        local buttons = {}
        for _, m in ipairs(members) do
            local b = frame.playerPool:Acquire()
            b.member = m
            b:SetLabel(Util.ShortName(m.name), Util.ClassColor(m.class))
            b:SetSelected(FindSelected(m.name) ~= nil)
            table.insert(buttons, b)
        end
        local rows = Widgets.LayoutGrid(buttons, content, 2, y, PLAYER_W, PLAYER_H, 4, 2)
        y = y + rows * (PLAYER_H + 4) + 8
    end

    local groups = RWT.Roster.GroupByRole(main)
    for _, role in ipairs(RWT.ROLE_ORDER) do
        AddSection(RWT.ROLE_LABEL[role], groups[role])
    end
    AddSection("当前团队（不在开怪快照中）", RWT.Roster.SortEntries(extras))
    content:SetHeight(math.max(y, 1))
end

-- 右栏的一行：玩家 + 预设 tag（多选）+ 临时 tag + 自定义输入框
function WipeWindow:BindRow(row, entry, index)
    row.entry, row.index = entry, index
    entry.tags = entry.tags or {}
    row.nameText:SetText(Util.ColorizeByClass(Util.ShortName(entry.name), entry.class))
    row.roleText:SetText(RWT.ROLE_LABEL[entry.role] or RWT.ROLE_LABEL.NONE)

    row.tagPool:ReleaseAll()
    local buttons = {}
    local function AddButton(tag, kind)
        local b = row.tagPool:Acquire()
        b.tag, b.kind = tag, kind
        local selected = RWT.Tags.IndexOf(entry.tags, tag) ~= nil
        if kind == "preset" then
            b:SetLabel(tag)
            b:SetSelected(selected)
        elseif kind == "session" then
            b:SetLabel(tag, 0.45, 0.85, 1)
            b:SetSelected(selected)
            if selected then
                b:SetBackdropColor(0.1, 0.35, 0.55, 0.85)
                b:SetBackdropBorderColor(0.4, 0.8, 1, 1)
            else
                b:SetBackdropColor(0.08, 0.18, 0.28, 0.9)
                b:SetBackdropBorderColor(0.35, 0.65, 0.85, 1)
            end
        else
            b:SetLabel(tag .. "  ×", 0.45, 0.85, 1)
            b:SetSelected(false)
            b:SetBackdropColor(0.1, 0.3, 0.45, 0.7)
            b:SetBackdropBorderColor(0.4, 0.8, 1, 1)
        end
        Widgets.SizeToText(b, TAG_MIN_W, TAG_MAX_W)
        table.insert(buttons, b)
    end
    local _, pull = GetTarget()
    local encounterID = pull and pull.encounterID
    for _, tag in ipairs(RWT.Tags:GetForEncounter(encounterID)) do AddButton(tag, "preset") end
    local inSession = {}
    for _, tag in ipairs(RWT.Tags:GetSession()) do
        if not RWT.Tags:IsPreset(tag, encounterID) then
            inSession[tag] = true
            AddButton(tag, "session")
        end
    end
    for _, tag in ipairs(entry.tags) do
        if not RWT.Tags:IsPreset(tag, encounterID) and not inSession[tag] then
            AddButton(tag, "once")
        end
    end

    local bottom = Widgets.FlowLayout(buttons, row, ROW_PAD, ROW_TOP, RIGHT_W - ROW_PAD * 2, TAG_H, 4)
    local inputY = bottom + 6
    row.tagLabel:ClearAllPoints()
    row.tagLabel:SetPoint("TOPLEFT", ROW_PAD, -(inputY + 4))
    row.tagBox:ClearAllPoints()
    row.tagBox:SetPoint("TOPLEFT", ROW_PAD + 56, -inputY)
    row.tagAdd:ClearAllPoints()
    row.tagAdd:SetPoint("LEFT", row.tagBox, "RIGHT", 6, 0)
    if row.tagBox:GetText() ~= (entry.pendingText or "") then
        row.tagBox:SetText(entry.pendingText or "")
    end
    row:SetHeight(inputY + 30)
end

local function PromoteTag(tag, encounterID)
    local ok, err = RWT.Tags:Promote(tag, encounterID)
    if not ok then RWT:Print(err or "无法设为预设 tag") end
    RWT:NotifyDataChanged()
end

-- 预设与登录临时 tag：左键切换该玩家是否带上
local function TogglePlayerTag(entry, tag)
    if not RWT.Tags.IndexOf(entry.tags, tag) and #entry.tags >= RWT.MAX_TAGS_PER_PLAYER then
        RWT:Print("每人最多 %d 个 tag。", RWT.MAX_TAGS_PER_PLAYER)
        return
    end
    RWT.Tags.Toggle(entry.tags, tag)
end

-- 预设：左键切换。登录临时 tag：左键切换，右键从本次登录删除，Shift+右键设为预设。
-- 仅本条记录的临时 tag：左键移除，右键设为预设
function WipeWindow:OnTagClicked(row, button, mouseButton)
    local entry = row.entry
    if not entry then return end
    local _, pull = GetTarget()
    local encounterID = pull and pull.encounterID
    if button.kind == "preset" then
        TogglePlayerTag(entry, button.tag)
    elseif button.kind == "session" then
        if mouseButton == "RightButton" then
            if IsShiftKeyDown() then
                PromoteTag(button.tag, encounterID)
                return
            end
            RWT.Tags:Forget(button.tag)
        else
            TogglePlayerTag(entry, button.tag)
        end
    elseif mouseButton == "RightButton" then
        PromoteTag(button.tag, encounterID)
        return
    else
        local i = RWT.Tags.IndexOf(entry.tags, button.tag)
        if i then table.remove(entry.tags, i) end
    end
    self:RenderSelected()
end

function WipeWindow:CommitRowText(row)
    if not row.entry then return end
    CommitText(row.entry)
    row.tagBox:SetText("")
    self:RenderSelected()
    self:FocusRow(row.index)
end

function WipeWindow:RenderSelected()
    frame.rowPool:ReleaseAll()
    local draft = GetDraft()
    local content = frame.rightContent
    local y = 0
    for i, entry in ipairs(draft.players) do
        local row = frame.rowPool:Acquire()
        self:BindRow(row, entry, i)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + row:GetHeight() + 6
    end
    frame.emptyHint:SetShown(#draft.players == 0)
    content:SetHeight(math.max(y, 60))
end

function WipeWindow:Render()
    if not frame or not frame:IsShown() then return end
    local session, pull = GetTarget()
    if not pull then
        RWT.db.state.draft = nil
        frame:Hide()
        return
    end
    self:RenderHeader(session, pull)
    self:RenderBanner(session, pull)
    self:RenderRoster(pull)
    self:RenderSelected()
    local draft = GetDraft()
    if frame.noteBox:GetText() ~= (draft.note or "") then frame.noteBox:SetText(draft.note or "") end

    if self.focusName then
        local _, index = FindSelected(self.focusName)
        self.focusName = nil
        if index then self:FocusRow(index, true) end
    end
end

-- 让第 index 行的原因输入框获得焦点
function WipeWindow:FocusRow(index, scrollIntoView)
    local row = frame.rowPool.items[index]
    if not row or not row:IsShown() then return end
    row.tagBox:SetFocus()
    if scrollIntoView then
        C_Timer.After(0, function()
            local top = select(5, row:GetPoint(1)) or 0
            local scroll = frame.rightScroll
            local range = scroll:GetVerticalScrollRange()
            scroll:SetVerticalScroll(math.min(math.max(-top - 10, 0), range))
        end)
    end
end

------------------------------------------------------------
-- 交互
------------------------------------------------------------

-- 选中 / 取消选中玩家（同一把同一玩家只会出现一次）
function WipeWindow:TogglePlayer(member)
    local draft = GetDraft()
    if not draft or not member then return end
    local _, index = FindSelected(member.name)
    if index then
        table.remove(draft.players, index)
    else
        table.insert(draft.players, {
            name = member.name,
            class = member.class,
            role = member.role or "NONE",
            tags = {},
        })
        self.focusName = member.name
    end
    self:Render()
end

-- 在开怪快照和当前团队里找输入的名字（忽略大小写）。先比完整「名字-服务器」，没带服务器时再只比角色名
local function FindKnownMember(pull, text)
    local candidates = {}
    for _, m in ipairs(pull.roster or {}) do table.insert(candidates, m) end
    for _, m in ipairs(RWT.Roster:Snapshot()) do table.insert(candidates, m) end
    local full = Util.NormalizeName(text)
    full = full and full:lower()
    for _, m in ipairs(candidates) do
        if m.name:lower() == full then return m end
    end
    if text:find("-", 1, true) then return nil end
    local short = text:lower()
    for _, m in ipairs(candidates) do
        if (m.name:match("^[^%-]+") or ""):lower() == short then return m end
    end
    return nil
end

-- 手动输入名字：团队里有这个人时用团队里的写法和职业，否则按输入记录
function WipeWindow:AddManual()
    local text = Util.Trim(frame.manualBox:GetText())
    frame.manualBox:SetText("")
    frame.manualBox:ClearFocus()
    if text == "" then return end
    local _, pull = GetTarget()
    local member = pull and FindKnownMember(pull, text)
    if not member then
        local name = Util.NormalizeName(text)
        if not name then return end
        member = { name = name, role = "NONE" }
    end
    if FindSelected(member.name) then return end
    self:TogglePlayer(member)
end

function WipeWindow:Save()
    local session, pull = GetTarget()
    if not pull then return end
    local draft = GetDraft()
    CommitAllPending(draft)
    RWT.Session:SavePullRecord(session, pull, draft.players, draft.note, STATUS.RECORDED)
    RWT.db.state.draft = nil
    frame:Hide()
    RWT:Print("已保存 Pull #%d：%d 名责任人。", pull.pullNumber, #pull.players)
    RWT.ChatReport:SendRecord(pull.players)
    RWT:NotifyDataChanged()
end

function WipeWindow:Skip()
    local draft = GetDraft()
    local function DoSkip()
        local session, pull = GetTarget()
        if not pull then return end
        RWT.Session:SavePullRecord(session, pull, {}, GetDraft().note, STATUS.SKIPPED)
        RWT.db.state.draft = nil
        frame:Hide()
        RWT:Print("Pull #%d 已跳过（无责任人）。", pull.pullNumber)
        RWT:NotifyDataChanged()
    end
    if draft and #draft.players > 0 then
        Widgets.Confirm("跳过会清空已选择的责任人，确定吗？", DoSkip)
    else
        DoSkip()
    end
end

-- 放弃本次修改，Pull 保持原状态（待填写的仍可以在历史中补填）
function WipeWindow:Cancel()
    RWT.db.state.draft = nil
    frame:Hide()
end

------------------------------------------------------------
-- 对外接口
------------------------------------------------------------

-- 打开某个 Pull 的记录窗口（新记录与历史编辑共用）
function WipeWindow:Open(sessionID, pullNumber)
    if InCombatLockdown() then
        RWT:Print("战斗中，脱战后自动打开记录窗口。")
        RWT:RunAfterCombat(function() self:Open(sessionID, pullNumber) end)
        return
    end
    local session = RWT.Session:Get(sessionID)
    local pull = RWT.Session:GetPull(session, pullNumber)
    if not pull then
        local draft = GetDraft()
        if draft and draft.sessionID == sessionID and draft.pullNumber == pullNumber then
            RWT.db.state.draft = nil
        end
        RWT:Print("找不到该 Pull 记录。")
        return
    end
    if pull.status == STATUS.ACTIVE then
        RWT:Print("该 Pull 仍在战斗中，结束后才能记录。")
        return
    end

    local draft = GetDraft()
    if draft and (draft.sessionID ~= sessionID or draft.pullNumber ~= pullNumber) then
        self:StashDraft()
    end
    if not GetDraft() then
        RWT.db.state.draft = {
            sessionID = sessionID,
            pullNumber = pullNumber,
            players = Util.DeepCopy(pull.players),
            note = pull.note or "",
        }
    end

    CreateFrameOnce()
    frame.noteBox:SetText("")
    frame:Show()
    self:Render()
end

function WipeWindow:IsShown()
    return frame and frame:IsShown()
end

-- 打开下一个待填写的 Pull
function WipeWindow:OpenNextPending()
    local session, pull = RWT.Session:FindNextPending()
    if not session then
        RWT:Print("没有待填写的 Pull。")
        return
    end
    self:Open(session.sessionID, pull.pullNumber)
end

RWT:On("RWT_PULL_STARTING", function()
    WipeWindow:StashDraft()
end)

RWT:On("RWT_DATA_CHANGED", function()
    WipeWindow:Render()
end)

RWT:On("RWT_ROSTER_CHANGED", function()
    if WipeWindow:IsShown() then
        local _, pull = GetTarget()
        if pull then WipeWindow:RenderRoster(pull) end
    end
end)

-- 重载 / 重新登录后恢复未保存的草稿
RWT:On("RWT_WORLD_READY", function()
    local draft = GetDraft()
    if draft and not InCombatLockdown() and not RWT.db.state.activePull and not WipeWindow:IsShown() then
        WipeWindow:Open(draft.sessionID, draft.pullNumber)
    end
end)

RWT:RegisterSlash("pending", "打开下一个待填写的 Pull", function()
    WipeWindow:OpenNextPending()
end)
