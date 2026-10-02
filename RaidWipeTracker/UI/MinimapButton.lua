local addonName, RWT = ...

-- 小地图按钮（自实现，不依赖 LibDBIcon）+ 插件收纳按钮（AddonCompartment）回调
local MinimapButton = RWT:NewModule("MinimapButton")
RWT.UI.MinimapButton = MinimapButton

local ICON = RWT.LOGO
local RADIUS_OFFSET = 10 -- 按钮中心在小地图边缘外侧的距离

local button

local function Settings()
    return RWT.db.settings.minimap
end

-- 根据角度把按钮放到小地图边缘
local function UpdatePosition()
    local angle = math.rad(Settings().angle or 225)
    local radius = (Minimap:GetWidth() / 2) + RADIUS_OFFSET
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- 拖动时按鼠标位置计算角度
local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    Settings().angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdatePosition()
end

-- 左键主面板 / Shift+左键 待填写 / 右键浮空面板
function MinimapButton.HandleClick(mouseButton)
    if mouseButton == "RightButton" then
        RWT.UI.FloatPanel:Toggle()
    elseif IsShiftKeyDown() then
        RWT.UI.WipeWindow:OpenNextPending()
    else
        RWT.UI.MainWindow:Toggle()
    end
end

-- 鼠标提示：当前 Session 与待填写数量
function MinimapButton.ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("RaidWipeTracker")
    local session = RWT.Session:GetCurrent()
    if session then
        GameTooltip:AddLine(string.format("当前：%s（%s）  %d Pull",
            session.bossName or "?", session.difficultyName or "?", #session.pulls), 1, 1, 1)
    else
        GameTooltip:AddLine("当前没有 Session", 0.7, 0.7, 0.7)
    end
    local pending = RWT.Session:CountAllPending()
    if pending > 0 then
        GameTooltip:AddLine(string.format("待填写：%d", pending), 1, 0.6, 0.2)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("左键：主面板", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift+左键：填写下一个待处理", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("右键：浮空快捷面板", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function CreateButton()
    local b = CreateFrame("Button", "RaidWipeTrackerMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, mouseButton) MinimapButton.HandleClick(mouseButton) end)
    b:SetScript("OnEnter", function(self) MinimapButton.ShowTooltip(self) end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    return b
end

-- 根据设置显示 / 隐藏
function MinimapButton:Apply()
    if Settings().hide then
        if button then button:Hide() end
        return
    end
    if not button then button = CreateButton() end
    UpdatePosition()
    button:Show()
end

function MinimapButton:OnInit()
    self:Apply()
end

RWT:On("RWT_SETTINGS_CHANGED", function() MinimapButton:Apply() end)

RWT:RegisterSlash("minimap", "显示 / 隐藏小地图按钮", function()
    Settings().hide = not Settings().hide
    MinimapButton:Apply()
    RWT:Print("小地图按钮：%s", Settings().hide and "已隐藏" or "已显示")
    RWT:NotifyDataChanged()
end)

------------------------------------------------------------
-- 插件收纳按钮（.toc 中的 AddonCompartmentFunc* 要求全局函数）
------------------------------------------------------------

function RaidWipeTracker_OnCompartmentClick(_, mouseButton)
    MinimapButton.HandleClick(mouseButton)
end

function RaidWipeTracker_OnCompartmentEnter(_, menuButtonFrame)
    MinimapButton.ShowTooltip(menuButtonFrame)
end

function RaidWipeTracker_OnCompartmentLeave()
    GameTooltip:Hide()
end
