local addonName, RWT = ...

-- 纯计算模块：所有统计都从原始 pulls 实时计算，不写数据库，不缓存计数
local Statistics = RWT:NewModule("Statistics")
local STATUS, RESULT = RWT.STATUS, RWT.RESULT

-- 接受单个 session 或 session 数组
local function AsList(sessions)
    if not sessions then return {} end
    if sessions.sessionID then return { sessions } end
    return sessions
end

-- Pull 结果汇总：total / wipes（含未知）/ kills / unknown / pending / recorded / skipped / active
function Statistics:Summarize(sessions)
    local s = { total = 0, wipes = 0, kills = 0, unknown = 0, pending = 0, recorded = 0, skipped = 0, active = 0, sessions = 0 }
    for _, session in ipairs(AsList(sessions)) do
        s.sessions = s.sessions + 1
        for _, pull in ipairs(session.pulls) do
            s.total = s.total + 1
            if pull.result == RESULT.KILL then
                s.kills = s.kills + 1
            elseif pull.result == RESULT.WIPE then
                s.wipes = s.wipes + 1
            elseif pull.result == RESULT.UNKNOWN then
                s.wipes = s.wipes + 1
                s.unknown = s.unknown + 1
            end
            if pull.status == STATUS.PENDING then s.pending = s.pending + 1
            elseif pull.status == STATUS.RECORDED then s.recorded = s.recorded + 1
            elseif pull.status == STATUS.SKIPPED then s.skipped = s.skipped + 1
            elseif pull.status == STATUS.ACTIVE then s.active = s.active + 1 end
        end
    end
    return s
end

-- 遍历所有责任人条目（击杀把不计入）
local function ForEachBlame(sessions, fn)
    for _, session in ipairs(AsList(sessions)) do
        for _, pull in ipairs(session.pulls) do
            if pull.result ~= RESULT.KILL then
                for _, player in ipairs(pull.players) do
                    fn(session, pull, player)
                end
            end
        end
    end
end

-- 把 { [key] = count } 转成按次数降序的数组 { { key, count }, ... }
local function SortCounts(map)
    local list = {}
    for key, count in pairs(map) do table.insert(list, { key = key, count = count }) end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.key < b.key
    end)
    return list
end
Statistics.SortCounts = SortCounts

-- 对一个责任人条目的每个 tag 计数；没有 tag 时记为"无 tag"
local function CountTags(map, player)
    local tags = player.tags
    if not tags or #tags == 0 then
        map[RWT.NO_TAG_LABEL] = (map[RWT.NO_TAG_LABEL] or 0) + 1
        return
    end
    for _, tag in ipairs(tags) do
        map[tag] = (map[tag] or 0) + 1
    end
end

-- 责任人排行：{ { name, class, role, count, tags = {[tag]=n}, entries = {...} }, ... }，次数降序
-- count 为出现的 Pull 数（同一把只算一次），tags 为各 tag 出现次数
function Statistics:PlayerRanking(sessions)
    local byName, total = {}, 0
    ForEachBlame(sessions, function(session, pull, player)
        local rec = byName[player.name]
        if not rec then
            rec = { name = player.name, class = player.class, role = player.role, count = 0, tags = {}, entries = {} }
            byName[player.name] = rec
        end
        rec.class = player.class or rec.class
        rec.count = rec.count + 1
        total = total + 1
        CountTags(rec.tags, player)
        table.insert(rec.entries, {
            sessionID = session.sessionID,
            pullNumber = pull.pullNumber,
            timestamp = pull.timestamp or pull.startTimestamp,
            tags = player.tags or {},
        })
    end)

    local list = {}
    for _, rec in pairs(byName) do
        table.sort(rec.entries, function(a, b) return (a.timestamp or 0) < (b.timestamp or 0) end)
        table.insert(list, rec)
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return list, total
end

-- tag 排行（预设与临时 tag 都计数）：{ { key = "搬球", count = 17 }, ... }
function Statistics:TagRanking(sessions)
    local map = {}
    ForEachBlame(sessions, function(_, _, player) CountTags(map, player) end)
    return SortCounts(map)
end

-- 两个 Session 是否为同一 Boss 同一难度；手动输入名字建立的 Session 没有 encounterID，按名字匹配
function Statistics.IsSameBoss(a, b)
    if a.difficultyID ~= b.difficultyID then return false end
    if a.encounterID and b.encounterID then return a.encounterID == b.encounterID end
    return a.bossName == b.bossName
end

-- 与 reference 同一 Boss 同一难度的所有 Session（按开始时间升序），用于 Boss 维度累计统计
function Statistics:SessionsForBoss(reference)
    local list = {}
    for _, session in pairs(RWT.db.sessions) do
        if Statistics.IsSameBoss(session, reference) then
            table.insert(list, session)
        end
    end
    table.sort(list, function(a, b) return (a.startTimestamp or 0) < (b.startTimestamp or 0) end)
    return list
end
