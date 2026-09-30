local addonName, RWT = ...

-- ESC - 选项 - 插件 中的设置页（Retail Settings API）
local OptionsPanel = RWT:NewModule("OptionsPanel")
RWT.UI.OptionsPanel = OptionsPanel

local Widgets = RWT.UI.Widgets

function OptionsPanel:OnInit()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end

    local canvas = CreateFrame("Frame")
    canvas:Hide()

    local title = Widgets.CreateText(canvas, "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("RaidWipeTracker  |cff888888" .. RWT.version .. "|r")

    local openMain = Widgets.CreateButton(canvas, "打开主面板", 110, 24, function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        RWT.UI.MainWindow:Open()
    end)
    openMain:SetPoint("TOPRIGHT", -16, -14)

    local body = CreateFrame("Frame", nil, canvas)
    body:SetPoint("TOPLEFT", 8, -50)
    body:SetPoint("BOTTOMRIGHT", -8, 8)
    self.view = RWT.UI.SettingsView.New(body)

    canvas:SetScript("OnShow", function() self.view:Refresh() end)

    local category = Settings.RegisterCanvasLayoutCategory(canvas, "RaidWipeTracker")
    Settings.RegisterAddOnCategory(category)
    self.category = category
end

-- 打开 ESC-选项-插件 中的本插件页面
function OptionsPanel:Open()
    if self.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.category:GetID())
    else
        RWT.UI.MainWindow:Open("settings")
    end
end

RWT:RegisterSlash("config", "打开 ESC-选项-插件 中的设置页", function()
    if InCombatLockdown() then
        RWT.UI.MainWindow:Open("settings")
        return
    end
    OptionsPanel:Open()
end)
