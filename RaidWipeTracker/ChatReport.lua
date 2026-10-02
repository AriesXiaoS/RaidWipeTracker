local addonName, RWT = ...

local ChatReport = RWT:NewModule("ChatReport")
local Util = RWT.Util

local PARTY_HOME = LE_PARTY_CATEGORY_HOME or 1
local PARTY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE or 2

-- 统计报告和记录通报共用一条队列，避免两套发言叠在一起
local queue = {}
local pumping = false

------------------------------------------------------------
-- 兼容封装
------------------------------------------------------------

local function SendChat(msg, channel)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, channel)
    else
        SendChatMessage(msg, channel)
    end
end

-- 12.x 在首领战等场景会锁定插件聊天发送；API 不存在时视为未锁定
local function InChatLockdown()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

function ChatReport:CanSend()
    return not Util.InCombatOrEncounter() and not InChatLockdown()
end

------------------------------------------------------------
-- 文本生成
------------------------------------------------------------

local function ShowRealm()
    return RWT.db.settings.reportShowRealm and true or false
end

-- 1.名字 5次（吃地板×3 漏断×2），原因按次数从高到低。
-- forChat 时转义管道符，人名保持纯文本：频道消息里的颜色码会被服务器丢弃整行。
local function FormatPlayer(index, rec, showRealm, forChat)
    local function Safe(text)
        text = text or ""
        if forChat then return Util.EscapeChat(text) end
        return text
    end
    local parts = {}
    for _, item in ipairs(RWT.Statistics.SortCounts(rec.tags)) do
        table.insert(parts, string.format("%s×%d", Safe(item.key), item.count))
    end
    local tags = #parts > 0 and ("（" .. table.concat(parts, " ") .. "）") or ""
    local name = Safe(Util.ReportName(rec.name, showRealm))
    if not forChat then name = Util.ColorizeByClass(name, rec.class) end
    return string.format("%d.%s %d次%s", index, name, rec.count, tags)
end

local function FormatHeader(session, wipes, forChat)
    local boss = session.bossName or "?"
    local difficulty = session.difficultyName or "?"
    if forChat then
        boss = Util.EscapeChat(boss)
        difficulty = Util.EscapeChat(difficulty)
    end
    return string.format("[灭团统计] %s（%s）%d Wipes", boss, difficulty, wipes)
end

-- 标题一条，之后每人一条。单条仍不超过 CHAT_MAX_BYTES。
function ChatReport:BuildMessages(sessions, isBossScope, topN)
    local first = sessions[1]
    local s = RWT.Statistics:Summarize(sessions)
    local ranking = RWT.Statistics:PlayerRanking(sessions)
    local maxBytes = RWT.CHAT_MAX_BYTES

    local messages = { Util.Utf8Truncate(FormatHeader(first, s.wipes, true), maxBytes) }

    local limit = (topN == 3) and 3 or 5
    local count = math.min(limit, #ranking)
    if count == 0 then
        table.insert(messages, "暂无记录")
        return messages
    end

    local showRealm = ShowRealm()
    for i = 1, count do
        table.insert(messages, Util.Utf8Truncate(FormatPlayer(i, ranking[i], showRealm, true), maxBytes))
    end
    return messages
end

-- 总览面板：标题加全部排行，不转义、不截断、不限制人数。
function ChatReport:BuildOverviewLines(sessions)
    local first = sessions and sessions[1]
    if not first then return { "暂无记录" } end
    local s = RWT.Statistics:Summarize(sessions)
    local ranking = RWT.Statistics:PlayerRanking(sessions)
    local lines = { FormatHeader(first, s.wipes, false) }
    if #ranking == 0 then
        table.insert(lines, "暂无记录")
        return lines
    end
    local showRealm = ShowRealm()
    for i, rec in ipairs(ranking) do
        table.insert(lines, FormatPlayer(i, rec, showRealm, false))
    end
    return lines
end

-- [记录] 名字 : 吃地板  走位失误 ；没有 tag 时只发名字
function ChatReport:BuildRecordMessages(players)
    local showRealm = ShowRealm()
    local maxBytes = RWT.CHAT_MAX_BYTES
    local messages = {}
    for _, player in ipairs(players or {}) do
        local name = Util.EscapeChat(Util.ReportName(player.name, showRealm))
        local parts = {}
        for _, tag in ipairs(player.tags or {}) do
            local text = Util.EscapeChat(tag)
            if text ~= "" then table.insert(parts, text) end
        end
        local line = #parts > 0 and string.format("[记录] %s : %s", name, table.concat(parts, "  "))
            or string.format("[记录] %s", name)
        table.insert(messages, Util.Utf8Truncate(line, maxBytes))
    end
    return messages
end

------------------------------------------------------------
-- 频道与发送
------------------------------------------------------------

-- 根据偏好与当前队伍状态选择频道；nil 表示这个频道发不出去，只打印到本地
function ChatReport:ResolveChannel(pref)
    if pref == "SAY" then return "SAY" end
    if pref == "GUILD" then
        return IsInGuild() and "GUILD" or nil
    end
    if IsInRaid(PARTY_HOME) then return "RAID" end
    if IsInGroup(PARTY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInGroup(PARTY_HOME) then return "PARTY" end
    return nil
end

local function PrintLocal(messages)
    for _, msg in ipairs(messages) do
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[RWT]|r " .. msg)
    end
end

local function Pump()
    if pumping then return end
    local item = queue[1]
    if not item then return end
    if not ChatReport:CanSend() then
        local left = #queue
        queue = {}
        RWT:Print("进入战斗，通报发送已中断（剩余 %d 条未发送）。", left)
        return
    end
    pumping = true
    table.remove(queue, 1)
    SendChat(item.msg, item.channel)
    if #queue == 0 then
        pumping = false
        return
    end
    C_Timer.After(item.interval, function()
        pumping = false
        Pump()
    end)
end

-- 按间隔逐条发送。频道发不出去时整批改在本地聊天框显示。
function ChatReport:Enqueue(messages, channelPref, interval)
    if not messages or #messages == 0 then return end
    local channel = self:ResolveChannel(channelPref)
    if not channel then
        if channelPref == "GUILD" then
            RWT:Print("不在公会中，通报只显示在本地：")
        else
            RWT:Print("不在队伍中，通报只显示在本地：")
        end
        PrintLocal(messages)
        return
    end
    local delay = tonumber(interval) or RWT.CHAT_INTERVAL_DEFAULT
    if delay < RWT.CHAT_INTERVAL_MIN or delay > RWT.CHAT_INTERVAL_MAX then
        delay = RWT.CHAT_INTERVAL_DEFAULT
    end
    for _, msg in ipairs(messages) do
        table.insert(queue, { msg = msg, channel = channel, interval = delay })
    end
    Pump()
end

-- 发送统计报告。战斗中不发送。
function ChatReport:Send(sessions, isBossScope)
    if not sessions or #sessions == 0 then return end
    if not self:CanSend() then
        RWT:Print("战斗或首领战中无法发送报告，请脱战后再试。")
        return
    end
    local settings = RWT.db.settings
    local messages = self:BuildMessages(sessions, isBossScope, settings.reportTopN)
    self:Enqueue(messages, settings.reportChannel, settings.reportInterval)
end

-- 保存记录后按人通报。文本在调用时生成；战斗或聊天锁定中则脱战后再发。
function ChatReport:SendRecord(players)
    local settings = RWT.db.settings
    if not settings.recordChat then return end
    local messages = self:BuildRecordMessages(players)
    if #messages == 0 then return end
    local channelPref = settings.recordChannel
    local interval = settings.recordInterval
    local tries = 0
    local function Go()
        if self:CanSend() then
            self:Enqueue(messages, channelPref, interval)
            return
        end
        tries = tries + 1
        if tries > 40 then
            RWT:Print("仍在战斗或聊天锁定中，这次单次记录汇报未发送。")
            return
        end
        if InCombatLockdown() then
            RWT:RunAfterCombat(Go)
        else
            C_Timer.After(0.5, Go)
        end
    end
    Go()
end

RWT:RegisterSlash("report", "发送当前（或最近）Session 的统计", function()
    local session = RWT.Session:GetCurrentOrLatest()
    if not session then
        RWT:Print("没有可报告的 Session。")
        return
    end
    ChatReport:Send({ session }, false)
end)
