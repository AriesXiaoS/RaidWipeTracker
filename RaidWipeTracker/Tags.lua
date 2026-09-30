local addonName, RWT = ...

-- 通用预设在 settings.tags；首领专属在 settings.bossTags[encounterID]
-- 两边都不在的 tag 即为临时 tag
-- sessionTemps 只活在本次登录：/reload 或小退后清空，不写入存档
local Tags = RWT:NewModule("Tags")
local Util = RWT.Util

local SESSION_TEMP_LIMIT = 20
local sessionTemps = {}

local function Presets()
    return RWT.db.settings.tags
end

local function BossKey(encounterID)
    if type(encounterID) ~= "number" and type(encounterID) ~= "string" then return nil end
    local key = tostring(encounterID)
    if key == "" or key == "0" then return nil end
    return key
end

local function BossMap()
    local settings = RWT.db.settings
    if type(settings.bossTags) ~= "table" then
        settings.bossTags = {}
    end
    return settings.bossTags
end

-- 不创建空列表。返回实际数组与字符串键
local function FindBossList(encounterID)
    local key = BossKey(encounterID)
    if not key then return nil, nil end
    local list = BossMap()[key]
    if type(list) ~= "table" then return nil, key end
    return list, key
end

local function IndexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
    return nil
end
Tags.IndexOf = IndexOf

local function InsertPreset(list, tag)
    if IndexOf(list, tag) then return false, "tag 已存在" end
    if #list >= RWT.MAX_PRESET_TAGS then return false, "预设 tag 数量已达上限" end
    table.insert(list, tag)
    return true
end

local function MoveIn(list, tag, delta)
    local index = IndexOf(list, tag)
    if not index then return false end
    local target = index + delta
    if target < 1 or target > #list then return false end
    list[index], list[target] = list[target], list[index]
    return true
end

-- 清洗用户输入：去首尾空白、合并连续空白、按 UTF-8 截断；空串返回 nil
function Tags.Normalize(text)
    if type(text) ~= "string" then return nil end
    -- 去掉 "|"，避免破坏界面里的颜色转义
    text = Util.Trim((text:gsub("|", ""))):gsub("%s+", " ")
    if text == "" then return nil end
    return Util.Utf8Truncate(text, RWT.MAX_TAG_BYTES)
end

function Tags:GetPresets()
    return Presets()
end

function Tags:GetBossTags(encounterID)
    return FindBossList(encounterID) or {}
end

-- 记录页用：通用在前，该首领在后；与通用同名的不重复
function Tags:GetForEncounter(encounterID)
    local out, seen = {}, {}
    for _, tag in ipairs(Presets()) do
        if not seen[tag] then
            seen[tag] = true
            table.insert(out, tag)
        end
    end
    for _, tag in ipairs(self:GetBossTags(encounterID)) do
        if not seen[tag] then
            seen[tag] = true
            table.insert(out, tag)
        end
    end
    return out
end

-- 不传 encounterID：任一预设列表都算（历史着色）。
-- 传了（包括 nil）：只认通用和该首领；没有首领 id 时只认通用。
function Tags:IsPreset(tag, ...)
    if IndexOf(Presets(), tag) then return true end
    if select("#", ...) == 0 then
        for _, list in pairs(BossMap()) do
            if type(list) == "table" and IndexOf(list, tag) then return true end
        end
        return false
    end
    return IndexOf(self:GetBossTags(...), tag) ~= nil
end

-- 添加通用预设 tag，成功返回 true
function Tags:Add(text)
    local tag = Tags.Normalize(text)
    if not tag then return false, "tag 不能为空" end
    return InsertPreset(Presets(), tag)
end

function Tags:AddBoss(encounterID, text)
    local key = BossKey(encounterID)
    if not key then return false, "无法识别首领" end
    local tag = Tags.Normalize(text)
    if not tag then return false, "tag 不能为空" end
    if IndexOf(Presets(), tag) then return false, "已在通用 tag 中" end
    local map = BossMap()
    local list = map[key]
    if type(list) ~= "table" then
        list = {}
        map[key] = list
    end
    return InsertPreset(list, tag)
end

-- 本次登录内手动输入过的临时 tag，按加入顺序
function Tags:GetSession()
    return sessionTemps
end

-- 记下临时 tag。已在列表里则忽略；当前窗口会显示的预设不记。满了返回 false
function Tags:Remember(tag, encounterID)
    tag = Tags.Normalize(tag)
    if not tag then return false end
    if self:IsPreset(tag, encounterID) then return false end
    if IndexOf(sessionTemps, tag) then return true end
    if #sessionTemps >= SESSION_TEMP_LIMIT then
        RWT:Print("本次登录的临时 tag 已满（%d），请先删掉不用的。", SESSION_TEMP_LIMIT)
        return false
    end
    table.insert(sessionTemps, tag)
    return true
end

-- 从登录列表移除。已经写在玩家身上的 tag 不改
function Tags:Forget(tag)
    tag = Tags.Normalize(tag)
    if not tag then return false end
    local index = IndexOf(sessionTemps, tag)
    if not index then return false end
    table.remove(sessionTemps, index)
    return true
end

-- 临时 tag 转为预设：有首领 id 时写入该首领，否则写入通用
function Tags:Promote(tag, encounterID)
    local ok, err
    if BossKey(encounterID) then
        ok, err = self:AddBoss(encounterID, tag)
    else
        ok, err = self:Add(tag)
    end
    if ok then self:Forget(tag) end
    return ok, err
end

function Tags:Remove(tag)
    local list = Presets()
    local index = IndexOf(list, tag)
    if not index then return false end
    if #list <= 1 then return false, "至少保留一个预设 tag" end
    table.remove(list, index)
    return true
end

function Tags:RemoveBoss(encounterID, tag)
    local list, key = FindBossList(encounterID)
    if not list then return false end
    local index = IndexOf(list, tag)
    if not index then return false end
    table.remove(list, index)
    if #list == 0 then BossMap()[key] = nil end
    return true
end

-- 上移（delta=-1）/ 下移（delta=1）
function Tags:Move(tag, delta)
    return MoveIn(Presets(), tag, delta)
end

function Tags:MoveBoss(encounterID, tag, delta)
    local list = FindBossList(encounterID)
    if not list then return false end
    return MoveIn(list, tag, delta)
end

function Tags:ResetDefaults()
    RWT.db.settings.tags = Util.DeepCopy(RWT.DEFAULT_TAGS)
end

-- 在一个 tag 数组中切换某个 tag，返回切换后是否包含
function Tags.Toggle(list, tag)
    local index = IndexOf(list, tag)
    if index then
        table.remove(list, index)
        return false
    end
    if #list >= RWT.MAX_TAGS_PER_PLAYER then return false end
    table.insert(list, tag)
    return true
end

-- 带颜色的单个 tag："[搬球]"；预设为金色，临时为浅蓝
function Tags:FormatOne(tag)
    local color = self:IsPreset(tag) and RWT.TAG_COLOR_PRESET or RWT.TAG_COLOR_TEMP
    return "|c" .. color .. "[" .. tag .. "]|r"
end

-- 带颜色的一组 tag，空时返回 emptyText
function Tags:Format(tags, emptyText)
    if not tags or #tags == 0 then return emptyText or "" end
    local parts = {}
    for _, tag in ipairs(tags) do table.insert(parts, self:FormatOne(tag)) end
    return table.concat(parts, " ")
end

-- 清洗一组 tag：去重、截断、限制数量
function Tags.SanitizeList(tags)
    local out, seen = {}, {}
    for _, t in ipairs(type(tags) == "table" and tags or {}) do
        local tag = Tags.Normalize(t)
        if tag and not seen[tag] and #out < RWT.MAX_TAGS_PER_PLAYER then
            seen[tag] = true
            table.insert(out, tag)
        end
    end
    return out
end
