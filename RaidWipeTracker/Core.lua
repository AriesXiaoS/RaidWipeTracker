local addonName, RWT = ...

RWT.name = addonName
RWT.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "dev"
RWT.UI = RWT.UI or {}

local errorHandler = function(err) return geterrorhandler()(err) end

-- 带参数的保护调用：单个监听者报错不影响其他监听者
local function SafeCall(fn, ...)
    if securecallfunction then
        return securecallfunction(fn, ...)
    end
    local n, args = select("#", ...), { ... }
    return xpcall(function() return fn(unpack(args, 1, n)) end, errorHandler)
end

------------------------------------------------------------
-- 输出
------------------------------------------------------------

function RWT:Print(msg, ...)
    if select("#", ...) > 0 then msg = string.format(msg, ...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[RWT]|r " .. tostring(msg))
end

------------------------------------------------------------
-- 模块注册：按文件加载顺序在 ADDON_LOADED 时调用 OnInit
------------------------------------------------------------

local modules = {}

-- 创建并注册模块，模块挂在 RWT[name] 上
function RWT:NewModule(name)
    local module = RWT[name] or {}
    RWT[name] = module
    table.insert(modules, module)
    return module
end

------------------------------------------------------------
-- 游戏事件分发（同一事件可以有多个监听者）
------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function RWT:RegisterEvent(event, callback)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(eventHandlers[event], callback)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        SafeCall(list[i], event, ...)
    end
end)

------------------------------------------------------------
-- 插件内部消息（数据变化时通知 UI 刷新）
------------------------------------------------------------

local callbacks = {}

function RWT:On(message, callback)
    callbacks[message] = callbacks[message] or {}
    table.insert(callbacks[message], callback)
end

function RWT:Fire(message, ...)
    local list = callbacks[message]
    if not list then return end
    for i = 1, #list do
        SafeCall(list[i], ...)
    end
end

-- 通知所有界面数据已改变
function RWT:NotifyDataChanged()
    self:Fire("RWT_DATA_CHANGED")
end

------------------------------------------------------------
-- 脱战后执行（UI 弹窗统一走这里，避免在战斗中操作界面）
------------------------------------------------------------

local combatQueue = {}

function RWT:RunAfterCombat(fn)
    if InCombatLockdown() then
        table.insert(combatQueue, fn)
    else
        xpcall(fn, errorHandler)
    end
end

RWT:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    local queue = combatQueue
    combatQueue = {}
    for _, fn in ipairs(queue) do
        xpcall(fn, errorHandler)
    end
end)

------------------------------------------------------------
-- 初始化
------------------------------------------------------------

RWT:RegisterEvent("ADDON_LOADED", function(_, loadedName)
    if loadedName ~= addonName then return end
    for _, module in ipairs(modules) do
        if module.OnInit then module:OnInit() end
    end
    RWT.initialized = true
end)

------------------------------------------------------------
-- 斜杠命令
------------------------------------------------------------

local slashCommands = {}

-- 注册子命令：/rwt <name> <rest>
function RWT:RegisterSlash(name, help, fn)
    slashCommands[name] = { help = help, fn = fn }
end

local function PrintHelp()
    RWT:Print("RaidWipeTracker %s 命令：", RWT.version)
    DEFAULT_CHAT_FRAME:AddMessage("  /rwt  - 打开/关闭主窗口")
    local names = {}
    for name in pairs(slashCommands) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  /rwt %s  - %s", name, slashCommands[name].help))
    end
end

SLASH_RAIDWIPETRACKER1 = "/rwt"
SLASH_RAIDWIPETRACKER2 = "/raidwipetracker"
SlashCmdList["RAIDWIPETRACKER"] = function(input)
    if not RWT.initialized then return end
    input = RWT.Util.Trim(input or "")
    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower()
    if not cmd then
        if RWT.UI.MainWindow then RWT.UI.MainWindow:Toggle() end
        return
    end
    local entry = slashCommands[cmd]
    if entry then
        entry.fn(rest)
    else
        PrintHelp()
    end
end

RWT:RegisterSlash("help", "显示帮助", PrintHelp)
