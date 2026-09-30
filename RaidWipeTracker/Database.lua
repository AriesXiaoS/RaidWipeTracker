local addonName, RWT = ...

local Database = RWT:NewModule("Database")
local Util = RWT.Util

-- 迁移函数表：migrations[N] 负责把 v(N-1) 升级到 vN。
Database.migrations = {}

-- v1 的 category + reason 转为 tags 数组
local function ConvertPlayerToTags(player)
    if type(player) ~= "table" or type(player.tags) == "table" then return end
    local tags = {}
    if type(player.category) == "string" and player.category ~= "" then
        table.insert(tags, player.category)
    end
    local reason = Util.Trim(player.reason)
    if reason ~= "" and reason ~= player.category then
        table.insert(tags, reason)
    end
    player.tags = tags
    player.category = nil
    player.reason = nil
end

-- 改默认预设之前的出厂列表。只有存档仍是这份时才换成新默认，用户自己改过的不覆盖。
local PREVIOUS_DEFAULT_TAGS = {
    "搬球", "点名", "站位", "漏断", "个人死亡", "踩圈",
    "机制错误", "坦克机制", "治疗机制", "DPS机制", "其他",
}

local function SameTagList(a, b)
    if type(a) ~= "table" or #a ~= #b then return false end
    for i = 1, #b do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- v1 -> v2：原因统一为 tag；settings.categories 改名为 settings.tags
Database.migrations[2] = function(db)
    for _, session in pairs(db.sessions or {}) do
        for _, pull in ipairs(type(session) == "table" and session.pulls or {}) do
            for _, player in ipairs(pull.players or {}) do ConvertPlayerToTags(player) end
        end
    end
    local draft = db.state and db.state.draft
    if draft and type(draft.players) == "table" then
        for _, player in ipairs(draft.players) do ConvertPlayerToTags(player) end
    end
    local settings = db.settings
    if settings and type(settings.categories) == "table" then
        if #settings.categories > 0 then settings.tags = settings.categories end
        settings.categories = nil
    end
end

-- v3 的出厂预设。只有存档仍是这份时才补上「蠢死」，用户自己改过的不覆盖。
local V3_DEFAULT_TAGS = { "吃地板", "漏断", "站位" }

-- v2 -> v3：出厂预设 tag 收成「吃地板 / 漏断 / 站位」
Database.migrations[3] = function(db)
    local settings = db.settings
    if settings and SameTagList(settings.tags, PREVIOUS_DEFAULT_TAGS) then
        settings.tags = Util.DeepCopy(V3_DEFAULT_TAGS)
    end
end

-- v4 曾把「蠢死」加在末尾。只有存档仍是这份时才把「蠢死」挪到最前。
local V4_DEFAULT_TAGS = { "吃地板", "漏断", "站位", "蠢死" }

-- v3 -> v4：出厂预设 tag 增加「蠢死」
Database.migrations[4] = function(db)
    local settings = db.settings
    if settings and SameTagList(settings.tags, V3_DEFAULT_TAGS) then
        settings.tags = Util.DeepCopy(RWT.DEFAULT_TAGS)
    end
end

-- v4 -> v5：出厂预设里「蠢死」放到第一位
Database.migrations[5] = function(db)
    local settings = db.settings
    if settings and SameTagList(settings.tags, V4_DEFAULT_TAGS) then
        settings.tags = Util.DeepCopy(RWT.DEFAULT_TAGS)
    end
end

local function IsArray(t)
    return type(t) == "table" and t[1] ~= nil
end

-- 只补齐缺失字段，不覆盖已有值；数组（如分类列表）整体视为一个值
local function MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = Util.DeepCopy(v)
        elseif type(v) == "table" and not IsArray(v) and type(target[k]) == "table" then
            MergeDefaults(target[k], v)
        end
    end
end

local function BuildDefaults()
    return {
        version = RWT.DB_VERSION,
        nextSessionSeq = 1,
        sessions = {},
        state = {
            forceNewSession = false,
        },
        settings = RWT.DEFAULT_SETTINGS,
    }
end

-- 依次执行从 db.version+1 到 DB_VERSION 的迁移
local function RunMigrations(db)
    local from = db.version or 1
    for v = from + 1, RWT.DB_VERSION do
        local migrate = Database.migrations[v]
        if migrate then
            migrate(db)
            RWT:Print("数据库已从 v%d 升级到 v%d", v - 1, v)
        end
        db.version = v
    end
end

local VALID_CHANNEL = { RAID = true, GUILD = true, SAY = true }

-- LOCAL 以及其它非法值回到团队，避免旧的「仅本地」突然变成白字发言
local function SanitizeChannel(value)
    if VALID_CHANNEL[value] then return value end
    return "RAID"
end

local function SanitizeInterval(value)
    local n = tonumber(value)
    if not n or n < RWT.CHAT_INTERVAL_MIN or n > RWT.CHAT_INTERVAL_MAX then
        return RWT.CHAT_INTERVAL_DEFAULT
    end
    return n
end

-- encounterID -> tag 数组。键统一成字符串；空列表丢掉；单条去重、截断、限数量
local function SanitizeBossTags(map)
    if type(map) ~= "table" then return {} end
    if not (RWT.Tags and RWT.Tags.Normalize) then return map end
    local out = {}
    for key, list in pairs(map) do
        if type(list) == "table" and (type(key) == "string" or type(key) == "number") then
            local id = tostring(key)
            if id ~= "" then
                local tags = out[id] or {}
                local seen = {}
                for _, existing in ipairs(tags) do seen[existing] = true end
                for _, raw in ipairs(list) do
                    local tag = RWT.Tags.Normalize(raw)
                    if tag and not seen[tag] and #tags < RWT.MAX_PRESET_TAGS then
                        seen[tag] = true
                        table.insert(tags, tag)
                    end
                end
                if #tags > 0 then out[id] = tags end
            end
        end
    end
    return out
end

-- 修复损坏或手动编辑过的数据，保证后续代码可以放心访问
local function Sanitize(db)
    for id, session in pairs(db.sessions) do
        if type(session) ~= "table" then
            db.sessions[id] = nil
        else
            session.sessionID = id
            session.pulls = type(session.pulls) == "table" and session.pulls or {}
            session.pullCount = session.pullCount or #session.pulls
            for _, pull in ipairs(session.pulls) do
                pull.players = type(pull.players) == "table" and pull.players or {}
                for _, player in ipairs(pull.players) do
                    player.tags = type(player.tags) == "table" and player.tags or {}
                end
                pull.roster = type(pull.roster) == "table" and pull.roster or {}
                pull.note = pull.note or ""
            end
        end
    end
    local state = db.state
    if state.currentSessionID and not db.sessions[state.currentSessionID] then
        state.currentSessionID = nil
    end
    local draft = state.draft
    if draft then
        local session = db.sessions[draft.sessionID or ""]
        local exists = session and Util.Find(session.pulls, function(p) return p.pullNumber == draft.pullNumber end)
        if not exists or type(draft.players) ~= "table" then
            state.draft = nil
        else
            for _, player in ipairs(draft.players) do
                player.tags = type(player.tags) == "table" and player.tags or {}
            end
        end
    end
    if type(db.settings.tags) ~= "table" or #db.settings.tags == 0 then
        db.settings.tags = Util.DeepCopy(RWT.DEFAULT_TAGS)
    end
    db.settings.bossTags = SanitizeBossTags(db.settings.bossTags)
    if db.settings.reportTopN ~= 3 and db.settings.reportTopN ~= 5 then
        db.settings.reportTopN = 5
    end
    local settings = db.settings
    settings.reportChannel = SanitizeChannel(settings.reportChannel)
    settings.recordChannel = SanitizeChannel(settings.recordChannel)
    settings.reportInterval = SanitizeInterval(settings.reportInterval)
    settings.recordInterval = SanitizeInterval(settings.recordInterval)
    settings.recordChat = settings.recordChat and true or false
end

-- 在 ADDON_LOADED 时调用，此时 SavedVariables 已经载入
function Database:OnInit()
    local db = RaidWipeTrackerDB
    if type(db) ~= "table" then
        db = {}
        RaidWipeTrackerDB = db
    end
    if db.version == nil then
        db.version = RWT.DB_VERSION
    elseif type(db.version) ~= "number" then
        -- 损坏的版本号从头迁移；每个迁移都会先检查数据形态，重复执行无害
        db.version = tonumber(db.version) or 1
    end
    if db.version > RWT.DB_VERSION then
        RWT:Print("|cffff4040警告：数据库版本 v%d 高于插件支持的 v%d，请更新插件。新版本的数据可能无法完整识别。|r", db.version, RWT.DB_VERSION)
    end

    MergeDefaults(db, BuildDefaults())
    if db.version < RWT.DB_VERSION then
        RunMigrations(db)
        MergeDefaults(db, BuildDefaults())
    end
    Sanitize(db)

    RWT.db = db
end

function Database:GetSettings()
    return RWT.db.settings
end

function Database:GetState()
    return RWT.db.state
end

-- 恢复默认设置（不影响记录数据；通用 tag、首领专属 tag 和小地图位置保留）
function Database:ResetSettings()
    local old = RWT.db.settings
    local settings = Util.DeepCopy(RWT.DEFAULT_SETTINGS)
    settings.tags = old.tags or settings.tags
    settings.bossTags = old.bossTags or settings.bossTags
    settings.minimap.angle = old.minimap and old.minimap.angle or settings.minimap.angle
    RWT.db.settings = settings
end

RWT:RegisterSlash("status", "打印数据库状态", function()
    local db = RWT.db
    local count, pulls = 0, 0
    for _, session in pairs(db.sessions) do
        count = count + 1
        pulls = pulls + #session.pulls
    end
    RWT:Print("数据库 v%d：%d 个 Session，%d 条 Pull 记录。当前 Session：%s",
        db.version, count, pulls, tostring(db.state.currentSessionID or "无"))
end)
