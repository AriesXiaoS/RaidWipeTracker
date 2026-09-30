local addonName, RWT = ...

local Session = RWT:NewModule("Session")
local Util = RWT.Util
local STATUS, RESULT, RESOLVE = RWT.STATUS, RWT.RESULT, RWT.RESOLVE

------------------------------------------------------------
-- 基础访问
------------------------------------------------------------

function Session:Get(sessionID)
    return sessionID and RWT.db.sessions[sessionID] or nil
end

function Session:GetCurrent()
    return self:Get(RWT.db.state.currentSessionID)
end

function Session:SetCurrent(sessionID)
    RWT.db.state.currentSessionID = sessionID
end

-- 所有 Session，按开始时间倒序（最新在前）
function Session:GetSortedList()
    local list = {}
    for _, session in pairs(RWT.db.sessions) do table.insert(list, session) end
    table.sort(list, function(a, b)
        if a.startTimestamp ~= b.startTimestamp then
            return (a.startTimestamp or 0) > (b.startTimestamp or 0)
        end
        return a.sessionID > b.sessionID
    end)
    return list
end

-- 最近一个 Session（优先当前）
function Session:GetCurrentOrLatest()
    return self:GetCurrent() or self:GetSortedList()[1]
end

local function IsSameEncounter(session, encounterID, difficultyID)
    return session.encounterID == encounterID and session.difficultyID == difficultyID
end

------------------------------------------------------------
-- 创建 / 关闭 / 删除
------------------------------------------------------------

local function GenerateID(ts)
    local db = RWT.db
    local seq = db.nextSessionSeq or 1
    db.nextSessionSeq = seq + 1
    return string.format("S%04d-%s", seq, date("%Y%m%d-%H%M%S", ts))
end

-- info = { encounterID, bossName, difficultyID, difficultyName, instanceName, instanceID }
function Session:Create(info)
    local now = Util.Now()
    local id = GenerateID(now)
    local session = {
        sessionID = id,
        bossName = info.bossName,
        encounterID = info.encounterID,
        difficultyID = info.difficultyID,
        difficultyName = info.difficultyName,
        instanceName = info.instanceName,
        instanceID = info.instanceID,
        startTimestamp = now,
        startDateText = Util.FormatDate(now),
        endTimestamp = nil,
        endDateText = nil,
        lastActivity = now,
        pullCount = 0,
        killed = false,
        closed = false,
        closeReason = nil,
        pulls = {},
    }
    RWT.db.sessions[id] = session
    return session
end

-- reason: "KILL" | "MANUAL"
function Session:Close(session, reason)
    local now = Util.Now()
    session.closed = true
    session.closeReason = reason
    session.killed = session.killed or reason == "KILL"
    session.endTimestamp = now
    session.endDateText = Util.FormatDate(now)
    if RWT.db.state.currentSessionID == session.sessionID then
        RWT.db.state.currentSessionID = nil
    end
end

-- 重新打开一个已结束但未击杀的 Session（例如误操作 /rwt end）
function Session:Reopen(session)
    session.closed = false
    session.closeReason = nil
    session.endTimestamp = nil
    session.endDateText = nil
end

function Session:Delete(sessionID)
    local state = RWT.db.state
    RWT.db.sessions[sessionID] = nil
    if state.currentSessionID == sessionID then state.currentSessionID = nil end
    if state.activePull and state.activePull.sessionID == sessionID then state.activePull = nil end
    if state.draft and state.draft.sessionID == sessionID then state.draft = nil end
end

------------------------------------------------------------
-- 续接规则（修改 Session 策略只需要改这里）
------------------------------------------------------------

-- 同 Boss 同难度、未关闭的 Session，按最近活动倒序
function Session:FindUnclosed(encounterID, difficultyID, excludeID)
    local list = {}
    for id, session in pairs(RWT.db.sessions) do
        if id ~= excludeID and not session.closed and IsSameEncounter(session, encounterID, difficultyID) then
            table.insert(list, session)
        end
    end
    table.sort(list, function(a, b) return (a.lastActivity or 0) > (b.lastActivity or 0) end)
    return list
end

-- 为新 Pull 选择 Session，返回 session, resolveMode
function Session:ResolveForEncounter(info)
    local state = RWT.db.state
    if state.forceNewSession then
        state.forceNewSession = false
        local session = self:Create(info)
        self:SetCurrent(session.sessionID)
        return session, RESOLVE.CURRENT -- 用户明确要求新建，不再提示并入
    end

    local current = self:GetCurrent()
    if current and not current.closed and IsSameEncounter(current, info.encounterID, info.difficultyID) then
        return current, RESOLVE.CURRENT
    end

    local windowSec = (RWT.db.settings.resumeWindowHours or 12) * 3600
    local candidate = self:FindUnclosed(info.encounterID, info.difficultyID)[1]
    if candidate and (Util.Now() - (candidate.lastActivity or 0)) <= windowSec then
        self:SetCurrent(candidate.sessionID)
        return candidate, RESOLVE.RESUMED
    end

    local session = self:Create(info)
    self:SetCurrent(session.sessionID)
    return session, RESOLVE.NEW
end

------------------------------------------------------------
-- Pull 操作
------------------------------------------------------------

function Session:GetPull(session, pullNumber)
    if not session then return nil end
    for i, pull in ipairs(session.pulls) do
        if pull.pullNumber == pullNumber then return pull, i end
    end
    return nil
end

-- 开始新 Pull：编号 = pullCount + 1，状态 ACTIVE
function Session:NewPull(session, info, roster)
    local now = Util.Now()
    session.pullCount = (session.pullCount or 0) + 1
    session.lastActivity = now
    session.bossName = info.bossName or session.bossName
    local pull = {
        pullNumber = session.pullCount,
        encounterID = info.encounterID,
        bossName = info.bossName,
        difficultyID = info.difficultyID,
        groupSize = info.groupSize,
        startTimestamp = now,
        timestamp = nil,
        dateText = nil,
        duration = nil,
        result = nil,
        status = STATUS.ACTIVE,
        roster = roster or {},
        players = {},
        note = "",
    }
    table.insert(session.pulls, pull)
    return pull
end

-- 结束 Pull：写入结束时间与结果
function Session:FinishPull(session, pull, result)
    local now = Util.Now()
    pull.result = result
    pull.timestamp = now
    pull.dateText = Util.FormatDate(now)
    pull.duration = now - (pull.startTimestamp or now)
    pull.status = result == RESULT.KILL and STATUS.RECORDED or STATUS.PENDING
    session.lastActivity = now
    if result == RESULT.KILL then
        session.killed = true
        self:Close(session, "KILL")
    end
end

------------------------------------------------------------
-- 手动操作（自动事件失效时使用）
------------------------------------------------------------

-- 手动新建 Session 并设为当前；info 可以是 BossPicker 的结果，也可以是已有 Session（复制 Boss 与难度）
function Session:CreateManual(info)
    local session = self:Create(info)
    session.manual = info.encounterID == nil or nil
    self:SetCurrent(session.sessionID)
    RWT.db.state.forceNewSession = false
    return session
end

-- 手动记录一把（result 为 WIPE 或 KILL），写入当前团队快照，返回 pull
function Session:AddManualPull(session, result)
    local info = {
        encounterID = session.encounterID,
        bossName = session.bossName,
        difficultyID = session.difficultyID,
        groupSize = GetNumGroupMembers(),
    }
    local pull = self:NewPull(session, info, RWT.Roster:Snapshot())
    pull.manual = true
    self:FinishPull(session, pull, result)
    return pull
end

-- 清洗责任人列表：玩家去重、去空名，tag 去重、截断、限量
function Session.SanitizePlayers(players)
    local out, seen = {}, {}
    for _, p in ipairs(players or {}) do
        local name = Util.Trim(p.name)
        if name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(out, {
                name = name,
                class = p.class,
                role = p.role or "NONE",
                tags = RWT.Tags.SanitizeList(p.tags),
            })
        end
    end
    return out
end

-- 保存一条 Pull 记录（新建与编辑共用）
function Session:SavePullRecord(session, pull, players, note, status)
    pull.players = Session.SanitizePlayers(players)
    pull.note = Util.Trim(note)
    if pull.result ~= RESULT.KILL then
        pull.status = status
    end
    pull.resolveMode = nil
    pull.editedAt = Util.Now()
end

function Session:DeletePull(session, pullNumber)
    local pull, index = self:GetPull(session, pullNumber)
    if not index then return end
    table.remove(session.pulls, index)
    local state = RWT.db.state
    if state.draft and state.draft.sessionID == session.sessionID and state.draft.pullNumber == pullNumber then
        state.draft = nil
    end
    if state.activePull and state.activePull.sessionID == session.sessionID and state.activePull.pullNumber == pullNumber then
        state.activePull = nil
    end
    if pull.result == RESULT.KILL then self:ClearKillIfNone(session) end
end

-- 击杀把被删除或移走后：Session 里没有其他击杀把时取消击杀标记，因击杀而结束的重新打开
function Session:ClearKillIfNone(session)
    if Util.Find(session.pulls, function(p) return p.result == RESULT.KILL end) then return end
    session.killed = false
    if session.closeReason == "KILL" then self:Reopen(session) end
end

-- 把一个 Pull 移动到另一个 Session（并入 / 拆分），返回新的 pullNumber
function Session:MovePull(fromSession, pullNumber, toSession)
    local pull, index = self:GetPull(fromSession, pullNumber)
    if not pull then return nil end
    table.remove(fromSession.pulls, index)

    toSession.pullCount = (toSession.pullCount or 0) + 1
    pull.pullNumber = toSession.pullCount
    pull.resolveMode = nil
    table.insert(toSession.pulls, pull)
    toSession.lastActivity = math.max(toSession.lastActivity or 0, pull.timestamp or pull.startTimestamp or 0)

    local state = RWT.db.state
    local function Retarget(ref)
        if ref and ref.sessionID == fromSession.sessionID and ref.pullNumber == pullNumber then
            ref.sessionID = toSession.sessionID
            ref.pullNumber = pull.pullNumber
        end
    end
    Retarget(state.activePull)
    Retarget(state.draft)

    if pull.result == RESULT.KILL then
        self:ClearKillIfNone(fromSession)
        toSession.killed = true
        self:Close(toSession, "KILL")
    elseif state.currentSessionID == fromSession.sessionID then
        self:SetCurrent(toSession.sessionID)
    end

    if #fromSession.pulls == 0 then
        self:Delete(fromSession.sessionID)
    end
    return pull.pullNumber
end

-- 把 Pull 拆分到一个新的 Session
function Session:SplitPullToNew(session, pullNumber)
    local newSession = self:Create(session)
    newSession.startTimestamp = Util.Now()
    newSession.startDateText = Util.FormatDate(newSession.startTimestamp)
    local isCurrent = RWT.db.state.currentSessionID == session.sessionID
    local newNumber = self:MovePull(session, pullNumber, newSession)
    if isCurrent and not newSession.closed then self:SetCurrent(newSession.sessionID) end
    return newSession, newNumber
end

-- 首次灭团时的并入/拆分建议：返回 { kind = "MERGE"|"SPLIT", target = session } 或 nil
function Session:GetResolveSuggestion(session, pull)
    if not session or not pull or not RWT.db.settings.promptOnFirstWipe then return nil end
    if pull.resolveMode == RESOLVE.NEW and #session.pulls == 1 then
        local target = self:FindUnclosed(session.encounterID, session.difficultyID, session.sessionID)[1]
        if target then return { kind = "MERGE", target = target } end
    elseif pull.resolveMode == RESOLVE.RESUMED and #session.pulls > 1
        and session.pulls[#session.pulls] == pull then
        return { kind = "SPLIT" }
    end
    return nil
end

-- 待填写的 Pull（按编号升序）
function Session:GetPendingPulls(session)
    local list = {}
    if not session then return list end
    for _, pull in ipairs(session.pulls) do
        if pull.status == STATUS.PENDING then table.insert(list, pull) end
    end
    return list
end

-- 找到下一个待填写的 Pull：优先当前 Session，其次最近的 Session
function Session:FindNextPending(excludeSessionID, excludePullNumber)
    local ordered = self:GetSortedList()
    local current = self:GetCurrent()
    if current then table.insert(ordered, 1, current) end
    for _, session in ipairs(ordered) do
        for _, pull in ipairs(self:GetPendingPulls(session)) do
            if not (session.sessionID == excludeSessionID and pull.pullNumber == excludePullNumber) then
                return session, pull
            end
        end
    end
    return nil
end

-- 统计所有 Session 中待填写的数量
function Session:CountAllPending()
    local n = 0
    for _, session in pairs(RWT.db.sessions) do
        n = n + #self:GetPendingPulls(session)
    end
    return n
end

------------------------------------------------------------
-- 斜杠命令
------------------------------------------------------------

local function DescribeSession(session)
    return string.format("%s（%s）%s 开始，%d Pull",
        session.bossName or "?", session.difficultyName or "?",
        Util.FormatShortDate(session.startTimestamp), #session.pulls)
end
Session.Describe = DescribeSession

RWT:RegisterSlash("new", "下一次开怪强制新建 Session", function()
    RWT.db.state.forceNewSession = true
    RWT:Print("下一次开怪将新建 Session。")
    RWT:NotifyDataChanged()
end)

RWT:RegisterSlash("resume", "把最近一个未结束的 Session 设为当前", function()
    local best
    for _, session in pairs(RWT.db.sessions) do
        if not session.closed and (not best or (session.lastActivity or 0) > (best.lastActivity or 0)) then
            best = session
        end
    end
    if not best then
        RWT:Print("没有未结束的 Session。")
        return
    end
    RWT.db.state.forceNewSession = false
    Session:SetCurrent(best.sessionID)
    RWT:Print("已续接：%s", DescribeSession(best))
    RWT:NotifyDataChanged()
end)

RWT:RegisterSlash("end", "手动结束当前 Session", function()
    local session = Session:GetCurrent()
    if not session then
        RWT:Print("当前没有 Session。")
        return
    end
    Session:Close(session, "MANUAL")
    RWT:Print("已结束：%s", DescribeSession(session))
    RWT:NotifyDataChanged()
end)
