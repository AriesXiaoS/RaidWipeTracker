local addonName, RWT = ...

local Util = {}
RWT.Util = Util

local strbyte, strsub, format = string.byte, string.sub, string.format

-- 当前 Unix 时间戳（秒）
function Util.Now()
    return time()
end

-- "2026-09-29 19:25:52"
function Util.FormatDate(ts)
    return ts and date("%Y-%m-%d %H:%M:%S", ts) or "-"
end

-- "19:25:52"
function Util.FormatTime(ts)
    return ts and date("%H:%M:%S", ts) or "-"
end

-- "09-29 19:25"
function Util.FormatShortDate(ts)
    return ts and date("%m-%d %H:%M", ts) or "-"
end

-- 秒数 -> "m:ss"
function Util.FormatDuration(sec)
    if not sec or sec < 0 then return "-" end
    return format("%d:%02d", math.floor(sec / 60), sec % 60)
end

function Util.DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = Util.DeepCopy(v)
    end
    return copy
end

function Util.Trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 12.x 的 secret value 防护：旧客户端没有 issecretvalue 时恒为 false
function Util.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- 返回可用的普通字符串，否则返回 fallback
function Util.SafeString(value, fallback)
    if Util.IsSecret(value) or type(value) ~= "string" or value == "" then
        return fallback
    end
    return value
end

-- 当前角色所在服务器（无空格、无连字符的规范化名称）
function Util.PlayerRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName() or ""):gsub("[%s%-]", "")
    end
    return realm
end

-- 统一成 "Name-Realm"
function Util.NormalizeName(name, realm)
    name = Util.SafeString(name, nil)
    if not name then return nil end
    if name:find("-", 1, true) then return name end
    realm = Util.SafeString(realm, nil) or Util.PlayerRealm()
    return name .. "-" .. realm
end

-- 读取单位的 "Name-Realm"，读不到或为 secret 时返回 nil
function Util.UnitFullName(unit)
    if not UnitExists(unit) then return nil end
    local name, realm = UnitFullName(unit)
    name = Util.SafeString(name, nil)
    if not name or name == UNKNOWNOBJECT then return nil end
    return Util.NormalizeName(name, realm)
end

-- 显示用名字：同服去掉服务器后缀，跨服保留
function Util.ShortName(fullName)
    if not fullName then return "?" end
    if Ambiguate then return Ambiguate(fullName, "none") end
    local realm = "-" .. Util.PlayerRealm()
    if fullName:sub(-#realm) == realm then
        return fullName:sub(1, #fullName - #realm)
    end
    return fullName
end

-- 汇报用名字。showRealm 为真时保留「名字-服务器」，否则只留角色名
function Util.ReportName(fullName, showRealm)
    if not fullName then return "?" end
    if showRealm then return fullName end
    if Ambiguate then return Ambiguate(fullName, "short") end
    local dash = fullName:find("-", 1, true)
    if dash then return fullName:sub(1, dash - 1) end
    return fullName
end

-- 职业颜色 r, g, b
function Util.ClassColor(classFile)
    if classFile then
        if C_ClassColor and C_ClassColor.GetClassColor then
            local c = C_ClassColor.GetClassColor(classFile)
            if c then return c.r, c.g, c.b end
        end
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if c then return c.r, c.g, c.b end
    end
    return 0.8, 0.8, 0.8
end

-- 用职业颜色包裹文本
function Util.ColorizeByClass(text, classFile)
    local r, g, b = Util.ClassColor(classFile)
    return format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

-- 按 UTF-8 字符边界截断到 maxBytes 字节以内
function Util.Utf8Truncate(s, maxBytes)
    if not s or #s <= maxBytes then return s end
    local cut = maxBytes
    -- 如果下一个字节是续字节（10xxxxxx），说明 cut 处在字符中间，向前退
    while cut > 0 do
        local nextByte = strbyte(s, cut + 1)
        if not nextByte or nextByte < 0x80 or nextByte >= 0xC0 then break end
        cut = cut - 1
    end
    return strsub(s, 1, cut)
end

-- 聊天消息里不能出现管道符转义，这里把用户输入的 "|" 转义掉
function Util.EscapeChat(s)
    return (s or ""):gsub("|", "||")
end

-- 首领战是否进行中；API 不存在时返回 nil（未知）
function Util.IsEncounterInProgress()
    local fn = (C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress) or IsEncounterInProgress
    if not fn then return nil end
    return fn() and true or false
end

-- 是否处于战斗或首领战中（此时不做聊天发送等敏感操作）
function Util.InCombatOrEncounter()
    return InCombatLockdown() or Util.IsEncounterInProgress() == true
end

-- 在数组中查找满足条件的元素，返回元素与下标
function Util.Find(list, predicate)
    for i, v in ipairs(list) do
        if predicate(v) then return v, i end
    end
    return nil
end
