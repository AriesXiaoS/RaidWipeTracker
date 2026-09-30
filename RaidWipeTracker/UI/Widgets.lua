local addonName, RWT = ...

local Widgets = {}
RWT.UI.Widgets = Widgets

local WHITE = "Interface\\Buttons\\WHITE8X8"

local WINDOW_BACKDROP = {
    bgFile = WHITE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local FLAT_BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

-- 可拖动、ESC 可关闭的基础窗口（非安全框架）
function Widgets.CreateWindow(globalName, width, height, strata)
    local f = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata(strata or "HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop(WINDOW_BACKDROP)
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
    f:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetJustifyH("LEFT")

    f.closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.closeButton:SetPoint("TOPRIGHT", -3, -3)

    if globalName then table.insert(UISpecialFrames, globalName) end
    f:Hide()
    return f
end

-- 标准按钮
function Widgets.CreateButton(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, height or 22)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- 可选中的扁平按钮（玩家、分类、列表项）
function Widgets.CreateToggle(parent, width, height, justify)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height)
    b:SetBackdrop(FLAT_BACKDROP)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 5, 0)
    b.text:SetPoint("RIGHT", -5, 0)
    b.text:SetJustifyH(justify or "CENTER")
    b.text:SetWordWrap(false)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    function b:SetSelected(selected)
        self.selected = selected
        if selected then
            self:SetBackdropColor(0.15, 0.4, 0.85, 0.6)
            self:SetBackdropBorderColor(0.45, 0.75, 1, 1)
        else
            self:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
            self:SetBackdropBorderColor(0.28, 0.28, 0.32, 1)
        end
    end

    function b:SetLabel(text, r, g, bl)
        self.text:SetText(text)
        self.text:SetTextColor(r or 1, g or 1, bl or 1)
    end

    b:SetSelected(false)
    return b
end

-- 单行输入框：回车 / ESC 取消焦点
function Widgets.CreateEditBox(parent, width, maxLetters)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(maxLetters or RWT.MAX_REASON_LETTERS)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
end

-- 文本
function Widgets.CreateText(parent, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("TOP")
    return fs
end

-- 滚动区域：调用方负责定位 scroll（右侧需预留约 24px 给滚动条），并设置 content 高度
function Widgets.CreateScrollArea(parent, contentWidth)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    if not ok or not scroll then
        scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    end
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(contentWidth, 1)
    scroll:SetScrollChild(content)
    scroll.content = content
    return scroll, content
end

-- 面板背景（分栏用）
function Widgets.CreatePanel(parent)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p:SetBackdrop(FLAT_BACKDROP)
    p:SetBackdropColor(0, 0, 0, 0.25)
    p:SetBackdropBorderColor(0.25, 0.25, 0.3, 1)
    return p
end

-- 简单对象池：Acquire 复用已创建对象，ReleaseAll 全部隐藏
function Widgets.CreatePool(createFn)
    local pool = { items = {}, active = 0 }
    function pool:Acquire()
        self.active = self.active + 1
        local item = self.items[self.active]
        if not item then
            item = createFn()
            self.items[self.active] = item
        end
        item:ClearAllPoints()
        item:Show()
        return item
    end
    function pool:ReleaseAll()
        for _, item in ipairs(self.items) do
            item:Hide()
            item:ClearAllPoints()
        end
        self.active = 0
    end
    return pool
end

-- 确认对话框
StaticPopupDialogs["RWT_CONFIRM"] = {
    text = "%s",
    button1 = YES or "是",
    button2 = NO or "否",
    OnAccept = function(_, data)
        if data and data.fn then data.fn() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Widgets.Confirm(text, fn)
    StaticPopup_Show("RWT_CONFIRM", text, nil, { fn = fn })
end

-- 按文字宽度调整按钮宽度
function Widgets.SizeToText(button, minW, maxW)
    local w = math.ceil(button.text:GetStringWidth()) + 14
    button:SetWidth(math.min(math.max(w, minW or 0), maxW or w))
end

-- 流式布局：按钮宽度各不相同，放不下时换行；返回最后一行底部的 y（正数，相对 parent 顶部）
function Widgets.FlowLayout(buttons, parent, x, y, maxW, h, gap)
    if #buttons == 0 then return y end
    local cx, cy = x, y
    for _, b in ipairs(buttons) do
        local w = b:GetWidth()
        if cx > x and cx + w > x + maxW then
            cx = x
            cy = cy + h + gap
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, -cy)
        cx = cx + w + gap
    end
    return cy + h
end

-- 在列表中按"每行 perRow 个"的网格布局放置按钮，返回占用的行数
function Widgets.LayoutGrid(buttons, parent, x, y, cellW, cellH, gap, perRow)
    for i, b in ipairs(buttons) do
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + col * (cellW + gap), -(y + row * (cellH + gap)))
    end
    return math.ceil(#buttons / perRow)
end
