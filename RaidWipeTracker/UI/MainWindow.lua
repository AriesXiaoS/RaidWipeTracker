local addonName, RWT = ...

local MainWindow = {}
RWT.UI.MainWindow = MainWindow

local Widgets = RWT.UI.Widgets

local WIDTH, HEIGHT = 940, 620

local TABS = {
    { key = "current", label = "当前" },
    { key = "history", label = "历史" },
    { key = "stats", label = "统计" },
    { key = "settings", label = "设置" },
    { key = "debug", label = "调试" },
}

local frame
local views = {}       -- key -> view：{ Create(self, parent) -> frame, Refresh(self) }
MainWindow.activeTab = "current"
MainWindow.selectedSessionID = nil

-- 视图模块在各自文件中注册
function MainWindow:RegisterView(key, view)
    views[key] = view
end

local function CreateFrameOnce()
    if frame then return frame end
    frame = Widgets.CreateWindow("RaidWipeTrackerMainWindow", WIDTH, HEIGHT, "MEDIUM")
    frame.title:SetText("RaidWipeTracker  |cff888888" .. RWT.version .. "|r")

    frame.tabButtons = {}
    local prev
    for _, tab in ipairs(TABS) do
        local b = Widgets.CreateButton(frame, tab.label, 90, 24, function() MainWindow:ShowTab(tab.key) end)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            b:SetPoint("TOPLEFT", 14, -40)
        end
        frame.tabButtons[tab.key] = b
        prev = b
    end

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", 12, -72)
    frame.body:SetPoint("BOTTOMRIGHT", -12, 12)

    for _, tab in ipairs(TABS) do
        local view = views[tab.key]
        if view then
            view.frame = view:Create(frame.body)
            view.frame:SetAllPoints(frame.body)
            view.frame:Hide()
        end
    end

    frame:SetScript("OnShow", function() MainWindow:Refresh() end)
    return frame
end

-- 切换标签页
function MainWindow:ShowTab(key)
    CreateFrameOnce()
    self.activeTab = key
    for tabKey, b in pairs(frame.tabButtons) do
        if tabKey == key then b:LockHighlight() else b:UnlockHighlight() end
        local view = views[tabKey]
        if view and view.frame then view.frame:SetShown(tabKey == key) end
    end
    self:Refresh()
end

-- 刷新当前可见的视图
function MainWindow:Refresh()
    if not frame or not frame:IsShown() then return end
    local view = views[self.activeTab]
    if view and view.Refresh then view:Refresh() end
end

function MainWindow:Open(tab)
    CreateFrameOnce()
    frame:Show()
    self:ShowTab(tab or self.activeTab)
end

function MainWindow:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        self:Open()
    end
end

-- 历史 / 统计共用的"选中 Session"，没有选择时回退到当前或最近的 Session
function MainWindow:GetSelectedSession()
    local session = RWT.Session:Get(self.selectedSessionID)
    if not session then
        session = RWT.Session:GetCurrentOrLatest()
        self.selectedSessionID = session and session.sessionID
    end
    return session
end

function MainWindow:SelectSession(sessionID)
    self.selectedSessionID = sessionID
    self:Refresh()
end

-- 打开某个 Session 的统计页（击杀后自动调用）；scope 为 "SESSION" 或 "BOSS"，省略时保持当前范围
function MainWindow:ShowStats(sessionID, scope)
    self.selectedSessionID = sessionID
    if scope and RWT.UI.StatsView then RWT.UI.StatsView:SetScope(scope) end
    self:Open("stats")
end

-- 打开历史页并选中某个 Session
function MainWindow:ShowHistory(sessionID)
    if sessionID then self.selectedSessionID = sessionID end
    self:Open("history")
end

RWT:On("RWT_DATA_CHANGED", function()
    MainWindow:Refresh()
end)

RWT:RegisterSlash("stats", "打开统计页", function() MainWindow:Open("stats") end)
RWT:RegisterSlash("history", "打开历史记录", function() MainWindow:Open("history") end)
RWT:RegisterSlash("settings", "打开设置", function() MainWindow:Open("settings") end)
