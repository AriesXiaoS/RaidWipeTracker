local addonName, RWT = ...

-- Boss 选择对话框：当前版本团队副本（冒险指南）+ 脚下副本 + 历史 Boss + 手动输入 + 难度
local BossPicker = {}
RWT.UI.BossPicker = BossPicker

local Util, Widgets = RWT.Util, RWT.UI.Widgets

local WIDTH, HEIGHT = 380, 520
local LIST_W = 320
local DIFFICULTIES = { 14, 15, 16, 17 } -- 普通 / 英雄 / 史诗 / 随机
local MAX_HISTORY = 20

local frame

------------------------------------------------------------
-- 数据来源
------------------------------------------------------------

-- 当前副本信息
local function CurrentInstance()
    local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    return {
        inInstance = instanceType == "raid" or instanceType == "party" or instanceType == "scenario",
        instanceName = Util.SafeString(name, nil),
        instanceID = instanceID,
        difficultyID = difficultyID,
    }
end

-- 手册数据按需加载；没加载时 EJ_* 经常返回空
local function EnsureJournal()
    local addons = C_AddOns
    if not (addons and addons.LoadAddOn) then return end
    if addons.IsAddOnLoaded and addons.IsAddOnLoaded("Blizzard_EncounterJournal") then return end
    addons.LoadAddOn("Blizzard_EncounterJournal")
end

-- 记住玩家正在看的手册页，读完再选回去
local function CaptureJournalSelection()
    local ej = _G.EncounterJournal
    if not ej then return nil end
    local tier = ej.selectedTier
    local select = ej.instanceSelect
    if not tier and select then
        tier = select.selectedTier
        local dropdown = select.tierDropDown or select.TierDropDown
        if not tier and dropdown and UIDropDownMenu_GetSelectedValue then
            tier = UIDropDownMenu_GetSelectedValue(dropdown)
        end
    end
    return { tier = tier, instanceID = ej.instanceID, encounterID = ej.encounterID }
end

local function RestoreJournalSelection(saved)
    if not saved then return end
    if saved.tier and EJ_SelectTier then EJ_SelectTier(saved.tier) end
    if saved.instanceID and saved.instanceID ~= 0 and EJ_SelectInstance then
        EJ_SelectInstance(saved.instanceID)
    end
    if saved.encounterID and saved.encounterID ~= 0 and EJ_SelectEncounter then
        EJ_SelectEncounter(saved.encounterID)
    end
end

-- 某个手册副本的首领。第 7 个返回值是 dungeonEncounterID，和开怪事件一致
local function BossesOf(journalInstanceID, instanceName)
    local list = {}
    if not journalInstanceID or journalInstanceID == 0 or not EJ_GetEncounterInfoByIndex then return list end
    if EJ_SelectInstance then EJ_SelectInstance(journalInstanceID) end
    for i = 1, 30 do
        local name, _, _, _, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(i, journalInstanceID)
        if not name or name == "" then break end
        table.insert(list, {
            bossName = name,
            encounterID = dungeonEncounterID,
            instanceName = instanceName,
            journalInstanceID = journalInstanceID,
        })
    end
    return list
end

local function CurrentJournalInstanceID()
    if not (EJ_GetInstanceForMap and C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    local journalInstanceID = mapID and EJ_GetInstanceForMap(mapID)
    if not journalInstanceID or journalInstanceID == 0 then return nil end
    return journalInstanceID
end

local function JournalInstanceName(journalInstanceID, fallback)
    if EJ_SelectInstance then EJ_SelectInstance(journalInstanceID) end
    local name = EJ_GetInstanceInfo and EJ_GetInstanceInfo()
    return Util.SafeString(name, fallback)
end

-- 当前资料片的团队副本（不含 5 人本、不含旧资料片）
local function CurrentTierRaids()
    local raids = {}
    if not (EJ_GetCurrentTier and EJ_SelectTier and EJ_GetInstanceByIndex) then return raids end
    local tier = EJ_GetCurrentTier()
    if not tier then return raids end
    EJ_SelectTier(tier)
    for i = 1, 40 do
        local journalInstanceID, name = EJ_GetInstanceByIndex(i, true)
        if not journalInstanceID then break end
        local bosses = BossesOf(journalInstanceID, name)
        if #bosses > 0 then
            table.insert(raids, {
                title = name,
                journalInstanceID = journalInstanceID,
                bosses = bosses,
            })
        end
    end
    return raids
end

-- 当前版本团本及其首领。会暂时改动手册选中页，读完还原。失败时返回空表
function BossPicker:GetCurrentTierRaids()
    EnsureJournal()
    local saved = CaptureJournalSelection()
    local ok, raids = pcall(CurrentTierRaids)
    RestoreJournalSelection(saved)
    if not ok or type(raids) ~= "table" then return {} end
    return raids
end

-- 区块：脚下副本（有才出现，且若已在团本列表中则只置顶一次）+ 当前版本各团本。同时给出扁平首领表供默认匹配
local function LoadJournalSections(instance)
    EnsureJournal()
    local saved = CaptureJournalSelection()
    local sections, flat = {}, {}
    local ok = pcall(function()
        local hereID = CurrentJournalInstanceID()
        local raids = CurrentTierRaids()
        local hereSection
        local rest = {}
        for _, raid in ipairs(raids) do
            if hereID and raid.journalInstanceID == hereID then
                raid.title = "当前副本：" .. (raid.title or "?")
                hereSection = raid
            else
                table.insert(rest, raid)
            end
        end
        if hereID and not hereSection and instance.inInstance then
            local name = JournalInstanceName(hereID, instance.instanceName)
            local bosses = BossesOf(hereID, name)
            if #bosses > 0 then
                hereSection = {
                    title = "当前副本：" .. (name or "?"),
                    journalInstanceID = hereID,
                    bosses = bosses,
                }
            end
        end
        if hereSection then table.insert(sections, hereSection) end
        for _, raid in ipairs(rest) do table.insert(sections, raid) end
        if hereID and instance.inInstance then
            for _, section in ipairs(sections) do
                if section.journalInstanceID == hereID then
                    for _, boss in ipairs(section.bosses) do
                        boss.instanceID = instance.instanceID
                    end
                end
            end
        end
        for _, section in ipairs(sections) do
            for _, boss in ipairs(section.bosses) do table.insert(flat, boss) end
        end
    end)
    RestoreJournalSelection(saved)
    if not ok then return {}, {} end
    return sections, flat
end

-- 历史 Session 中出现过的 Boss（按最近活动排序、去重）。调试首领不进选择框
local function GetHistoryBosses()
    local list, seen = {}, {}
    for _, session in ipairs(RWT.Session:GetSortedList()) do
        if session.encounterID ~= RWT.DEBUG_ENCOUNTER_ID then
            local key = tostring(session.encounterID or "") .. "|" .. tostring(session.bossName)
            if not seen[key] then
                seen[key] = true
                table.insert(list, {
                    bossName = session.bossName,
                    encounterID = session.encounterID,
                    instanceName = session.instanceName,
                    instanceID = session.instanceID,
                    difficultyID = session.difficultyID,
                })
                if #list >= MAX_HISTORY then break end
            end
        end
    end
    return list
end

local function DifficultyName(id)
    local name = GetDifficultyInfo and GetDifficultyInfo(id)
    return Util.SafeString(name, tostring(id))
end

------------------------------------------------------------
-- 界面
------------------------------------------------------------

local function CreateFrameOnce()
    if frame then return frame end
    frame = Widgets.CreateWindow("RaidWipeTrackerBossPicker", WIDTH, HEIGHT, "DIALOG")

    local panel = Widgets.CreatePanel(frame)
    panel:SetPoint("TOPLEFT", 12, -40)
    panel:SetSize(LIST_W + 32, 280)
    frame.scroll, frame.content = Widgets.CreateScrollArea(panel, LIST_W)
    frame.scroll:SetPoint("TOPLEFT", 4, -4)
    frame.scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    frame.headerPool = Widgets.CreatePool(function() return Widgets.CreateText(frame.content, "GameFontNormal") end)
    frame.bossPool = Widgets.CreatePool(function()
        local b = Widgets.CreateToggle(frame.content, LIST_W, 22, "LEFT")
        b:SetScript("OnClick", function(self) BossPicker:Select(self.boss) end)
        return b
    end)

    local nameLabel = Widgets.CreateText(frame, "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 2, -12)
    nameLabel:SetText("或手动输入 Boss 名称：")
    frame.nameBox = Widgets.CreateEditBox(frame, LIST_W, 60)
    frame.nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -6)
    frame.nameBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and Util.Trim(self:GetText()) ~= "" then
            BossPicker.selected = nil
            BossPicker:RefreshList()
        end
    end)
    frame.nameBox:SetScript("OnEnterPressed", function() BossPicker:Confirm() end)

    local diffLabel = Widgets.CreateText(frame, "GameFontHighlight")
    diffLabel:SetPoint("TOPLEFT", frame.nameBox, "BOTTOMLEFT", -6, -14)
    diffLabel:SetText("难度：")
    frame.diffButtons = {}
    for i = 1, #DIFFICULTIES + 1 do
        local b = Widgets.CreateToggle(frame, 62, 22)
        b:SetPoint("TOPLEFT", diffLabel, "BOTTOMLEFT", (i - 1) * 66, -6)
        b:SetScript("OnClick", function(self)
            BossPicker.difficultyID = self.difficultyID
            BossPicker.userPickedDifficulty = true
            BossPicker:RefreshDifficulty()
        end)
        frame.diffButtons[i] = b
    end

    local cancel = Widgets.CreateButton(frame, "取消", 90, 24, function() frame:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT", -14, 12)
    local ok = Widgets.CreateButton(frame, "确定", 90, 24, function() BossPicker:Confirm() end)
    ok:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
    return frame
end

function BossPicker:Select(boss)
    self.selected = boss
    frame.nameBox:SetText("")
    frame.nameBox:ClearFocus()
    if boss.difficultyID and not self.userPickedDifficulty then
        self.difficultyID = boss.difficultyID
        self:RefreshDifficulty()
    end
    self:RefreshList()
end

function BossPicker:RefreshList()
    frame.headerPool:ReleaseAll()
    frame.bossPool:ReleaseAll()
    local y = 4
    local function Section(title, bosses, showInstance)
        if #bosses == 0 then return end
        local header = frame.headerPool:Acquire()
        header:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 2, -y)
        header:SetText(title)
        y = y + 20
        for _, boss in ipairs(bosses) do
            local b = frame.bossPool:Acquire()
            b.boss = boss
            b:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
            local suffix = showInstance and boss.instanceName and ("  |cff888888" .. boss.instanceName .. "|r") or ""
            b:SetLabel(boss.bossName .. suffix)
            local sel = self.selected
            b:SetSelected(sel ~= nil and sel.bossName == boss.bossName and sel.encounterID == boss.encounterID)
            y = y + 24
        end
        y = y + 6
    end
    local anyJournal = false
    for _, section in ipairs(self.sections or {}) do
        Section(section.title, section.bosses, false)
        if #section.bosses > 0 then anyJournal = true end
    end
    Section("历史 Boss", self.historyBosses, true)
    if not anyJournal and #self.historyBosses == 0 then
        local header = frame.headerPool:Acquire()
        header:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 2, -y)
        header:SetText("|cff888888读不到首领列表，请在下方手动输入。|r")
        y = y + 20
    end
    frame.content:SetHeight(math.max(y, 1))
end

function BossPicker:RefreshDifficulty()
    local ids = {}
    for _, id in ipairs(DIFFICULTIES) do table.insert(ids, id) end
    local current = self.instance.difficultyID
    if current and current ~= 0 and not tContains(ids, current) then table.insert(ids, current) end
    for i, b in ipairs(frame.diffButtons) do
        local id = ids[i]
        if id then
            b.difficultyID = id
            b:SetLabel(DifficultyName(id))
            b:SetSelected(id == self.difficultyID)
            b:Show()
        else
            b:Hide()
        end
    end
end

-- 默认选中：当前目标名匹配的首领 > 当前 / 最近 Session 的 Boss；否则把非玩家目标名填入输入框
function BossPicker:ChooseDefault()
    local targetName = UnitExists("target") and not UnitIsPlayer("target") and Util.SafeString(UnitName("target"), nil)
    local recent = RWT.Session:GetCurrentOrLatest()
    local function Find(list, name)
        for _, boss in ipairs(list) do
            if boss.bossName == name then return boss end
        end
    end
    local boss = targetName and (Find(self.journalBosses, targetName) or Find(self.historyBosses, targetName))
    if not boss and recent then
        boss = Find(self.journalBosses, recent.bossName) or Find(self.historyBosses, recent.bossName)
    end
    if boss then
        self.selected = boss
        if not self.instance.inInstance and boss.difficultyID then self.difficultyID = boss.difficultyID end
    elseif targetName then
        frame.nameBox:SetText(targetName)
    end
end

function BossPicker:Confirm()
    local typed = Util.Trim(frame.nameBox:GetText())
    local boss = self.selected
    local instance = self.instance
    local info
    if typed ~= "" then
        info = { bossName = typed, encounterID = nil, manual = true }
    elseif boss then
        info = { bossName = boss.bossName, encounterID = boss.encounterID }
    else
        RWT:Print("请选择或输入一个 Boss。")
        return
    end
    info.difficultyID = self.difficultyID
    info.difficultyName = DifficultyName(self.difficultyID)
    if boss and typed == "" and boss.instanceName then
        info.instanceName, info.instanceID = boss.instanceName, boss.instanceID
    else
        info.instanceName = instance.inInstance and instance.instanceName or "手动"
        info.instanceID = instance.inInstance and instance.instanceID or nil
    end
    frame:Hide()
    if self.onPick then self.onPick(info) end
end

-- 打开选择框；onPick(info) 收到 { bossName, encounterID, difficultyID, difficultyName, instanceName, instanceID, manual }
function BossPicker:Open(title, onPick)
    CreateFrameOnce()
    self.onPick = onPick
    self.selected = nil
    self.userPickedDifficulty = false
    self.instance = CurrentInstance()
    self.sections, self.journalBosses = LoadJournalSections(self.instance)
    self.historyBosses = GetHistoryBosses()
    local current = self.instance.difficultyID
    self.difficultyID = (current and current ~= 0) and current or 16

    frame.title:SetText(title or "选择 Boss")
    frame.nameBox:SetText("")
    self:ChooseDefault()
    frame:Show()
    self:RefreshDifficulty()
    self:RefreshList()
    if frame.scroll.SetVerticalScroll then frame.scroll:SetVerticalScroll(0) end
end
