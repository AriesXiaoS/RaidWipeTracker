local addonName, RWT = ...

-- 浮空快捷面板：全手动操作入口，自动事件失效时也能完整记录
local FloatPanel = RWT:NewModule("FloatPanel")
RWT.UI.FloatPanel = FloatPanel

local Widgets = RWT.UI.Widgets
local RESULT = RWT.RESULT

local WIDTH = 228
local BTN_W, BTN_H = 102, 22

local frame

local function Settings()
    return RWT.db.settings.floatPanel
end

------------------------------------------------------------
-- 操作
------------------------------------------------------------

-- 有进行中的自动记录时不允许手动记录，避免编号冲突
local function BlockedByActivePull()
    if RWT.db.state.activePull then
        RWT:Print("首领战记录进行中，结束后再手动记录（卡住时 /reload 会自动对账）。")
        return true
    end
    return false
end

-- 确保有当前 Session；没有时先弹出 Boss 选择框
local function WithCurrentSession(title, fn)
    local session = RWT.Session:GetCurrent()
    if session then
        fn(session)
        return
    end
    RWT.UI.BossPicker:Open(title, function(info)
        fn(RWT.Session:CreateManual(info))
    end)
end

function FloatPanel:ManualWipe()
    if BlockedByActivePull() then return end
    WithCurrentSession("手动记录：选择 Boss", function(session)
        local pull = RWT.Session:AddManualPull(session, RESULT.WIPE)
        RWT:Print("已手动记录 %s Pull #%d（灭团）。", session.bossName or "?", pull.pullNumber)
        RWT:NotifyDataChanged()
        RWT.UI.WipeWindow:Open(session.sessionID, pull.pullNumber)
    end)
end

function FloatPanel:NewBoss()
    RWT.UI.BossPicker:Open("新建 Boss 记录", function(info)
        local session = RWT.Session:CreateManual(info)
        RWT:Print("已新建并设为当前：%s", RWT.Session.Describe(session))
        RWT:NotifyDataChanged()
    end)
end

function FloatPanel:NewSession()
    local base = RWT.Session:GetCurrentOrLatest()
    if not base then
        self:NewBoss()
        return
    end
    Widgets.Confirm(string.format("为 %s（%s）新建一个 Session 并设为当前？", base.bossName or "?", base.difficultyName or "?"), function()
        local session = RWT.Session:CreateManual(base)
        RWT:Print("已新建并设为当前：%s", RWT.Session.Describe(session))
        RWT:NotifyDataChanged()
    end)
end

local ACTIONS = {
    { key = "wipe", label = "手动记录一把", fn = function() FloatPanel:ManualWipe() end },
    { key = "main", label = "主面板", fn = function() RWT.UI.MainWindow:Toggle() end },
}

------------------------------------------------------------
-- 界面
------------------------------------------------------------

local function SavePosition()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    Settings().point = { point, relativePoint, x, y }
end

local function RestorePosition()
    frame:ClearAllPoints()
    local p = Settings().point
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
    end
end

local function CreateFrameOnce()
    if frame then return frame end
    frame = CreateFrame("Frame", "RaidWipeTrackerFloatPanel", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not Settings().locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.85)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)

    frame.title = Widgets.CreateText(frame, "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 8, -7)
    frame.title:SetText("RaidWipeTracker")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() FloatPanel:SetEnabled(false) end)

    frame.lock = Widgets.CreateButton(frame, "", 40, 18, function()
        Settings().locked = not Settings().locked
        FloatPanel:Refresh()
        RWT:NotifyDataChanged()
    end)
    frame.lock:SetPoint("RIGHT", close, "LEFT", -2, 0)

    frame.status = Widgets.CreateText(frame, "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", 8, -26)
    frame.status:SetWidth(WIDTH - 16)
    frame.status:SetSpacing(2)

    frame.buttons = {}
    local top = 60
    for i, action in ipairs(ACTIONS) do
        local b = Widgets.CreateButton(frame, action.label, BTN_W, BTN_H, action.fn)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", 8 + col * (BTN_W + 4), -(top + row * (BTN_H + 4)))
        frame.buttons[action.key] = b
    end
    local rows = math.ceil(#ACTIONS / 2)
    frame:SetSize(WIDTH, top + rows * (BTN_H + 4) + 6)

    RestorePosition()
    return frame
end

-- 刷新状态行与按钮可用性
function FloatPanel:Refresh()
    if not frame or not frame:IsShown() then return end
    local session = RWT.Session:GetCurrent()
    local _, activePull = RWT.Encounter:GetActivePull()
    local pending = RWT.Session:CountAllPending()

    local line1 = session
        and string.format("|cffffd100%s|r（%s）  Pull %d", session.bossName or "?", session.difficultyName or "?", #session.pulls)
        or "|cff888888没有当前 Session|r"
    local line2 = activePull and "|cff40c0ff首领战进行中|r" or "空闲"
    if pending > 0 then line2 = line2 .. string.format("   |cffff9930待填写 %d|r", pending) end
    frame.status:SetText(line1 .. "\n" .. line2)

    frame.lock:SetText(Settings().locked and "解锁" or "锁定")
    frame.buttons.wipe:SetEnabled(activePull == nil)
end

-- 根据设置显示 / 隐藏
function FloatPanel:Apply()
    if Settings().enabled then
        CreateFrameOnce()
        frame:Show()
        self:Refresh()
    elseif frame then
        frame:Hide()
    end
end

function FloatPanel:SetEnabled(enabled)
    Settings().enabled = enabled and true or false
    self:Apply()
    RWT:NotifyDataChanged()
end

function FloatPanel:Toggle()
    self:SetEnabled(not Settings().enabled)
end

function FloatPanel:OnInit()
    self:Apply()
end

RWT:On("RWT_SETTINGS_CHANGED", function() FloatPanel:Apply() end)
RWT:On("RWT_DATA_CHANGED", function() FloatPanel:Refresh() end)

RWT:RegisterSlash("panel", "显示 / 隐藏浮空快捷面板", function() FloatPanel:Toggle() end)
