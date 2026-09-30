local addonName, RWT = ...

local Roster = RWT:NewModule("Roster")
local Util = RWT.Util

local ROLE_RANK = {}
for i, role in ipairs(RWT.ROLE_ORDER) do ROLE_RANK[role] = i end

-- 调试用的假团员（/rwt debug roster 开关）
Roster.fakeMembers = nil

local FAKE_TEMPLATE = {
    { "坦克甲", "WARRIOR", "TANK" }, { "坦克乙", "DEATHKNIGHT", "TANK" },
    { "奶一", "PRIEST", "HEALER" }, { "奶二", "DRUID", "HEALER" }, { "奶三", "EVOKER", "HEALER" },
    { "Mage", "MAGE", "DAMAGER" }, { "猎人", "HUNTER", "DAMAGER" }, { "术士", "WARLOCK", "DAMAGER" },
    { "盗贼", "ROGUE", "DAMAGER" }, { "法师二", "MAGE", "DAMAGER" }, { "萨满", "SHAMAN", "DAMAGER" },
    { "Paladin", "PALADIN", "DAMAGER" }, { "武僧", "MONK", "DAMAGER" }, { "恶魔猎手", "DEMONHUNTER", "DAMAGER" },
    { "Unknown", "PRIEST", "NONE" },
}

function Roster:SetFakeMembers(enabled)
    if not enabled then
        self.fakeMembers = nil
        return
    end
    self.fakeMembers = {}
    for _, t in ipairs(FAKE_TEMPLATE) do
        table.insert(self.fakeMembers, { name = t[1] .. "-测试服", class = t[2], role = t[3] })
    end
end

-- 返回当前队伍的单位 token 列表，以及每个 token 对应的团队序号
local function CollectUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            table.insert(units, { unit = "raid" .. i, raidIndex = i })
        end
    else
        table.insert(units, { unit = "player" })
        if IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do
                table.insert(units, { unit = "party" .. i })
            end
        end
    end
    return units
end

-- 自己的职责：没有分配职责时用当前专精推断
local function GetOwnSpecRole()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getRole = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationRole) or GetSpecializationRole
    if not getSpec or not getRole then return nil end
    local spec = getSpec()
    return spec and getRole(spec) or nil
end

-- 职责兜底链：分配职责 -> 团队框架 combatRole -> 自己的专精 -> "NONE"
function Roster:GetRole(unit, raidIndex)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if not Util.IsSecret(role) and role and ROLE_RANK[role] and role ~= "NONE" then
        return role
    end
    if raidIndex then
        local combatRole = select(12, GetRaidRosterInfo(raidIndex))
        if not Util.IsSecret(combatRole) and combatRole and ROLE_RANK[combatRole] and combatRole ~= "NONE" then
            return combatRole
        end
    end
    if UnitIsUnit(unit, "player") then
        local specRole = GetOwnSpecRole()
        if specRole and ROLE_RANK[specRole] then return specRole end
    end
    return "NONE"
end

local function GetClassFile(unit)
    local classFile = Util.SafeString(UnitClassBase and UnitClassBase(unit), nil)
    return classFile or Util.SafeString(select(2, UnitClass(unit)), nil)
end

-- 按职责、名字排序
function Roster.SortEntries(list)
    table.sort(list, function(a, b)
        local ra, rb = ROLE_RANK[a.role] or 99, ROLE_RANK[b.role] or 99
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return list
end

-- 读一个单位。成功返回条目，失败返回 nil 和原因
local function Diagnose(unit, raidIndex)
    if not UnitExists(unit) then
        return nil, "单位不存在"
    end
    local name, realm = UnitFullName(unit)
    if Util.IsSecret(name) then
        return nil, "名字是 secret"
    end
    if name == UNKNOWNOBJECT then
        return nil, "名字尚未解析"
    end
    name = Util.SafeString(name, nil)
    if not name then
        return nil, "读不到名字"
    end
    local full = Util.NormalizeName(name, realm)
    if not full then
        return nil, "读不到名字"
    end
    return {
        name = full,
        class = GetClassFile(unit),
        role = Roster:GetRole(unit, raidIndex),
        unit = unit,
    }
end

-- 当前团队检查：已识别、未识别分开记。假团员单独返回，不计入已识别
-- { group="raid"|"party"|"solo", expected, recognized={...}, missing={{unit,reason}}, fakes=nil|{{name,class,role,skipped}} }
function Roster:Inspect()
    local recognized, missing, seen = {}, {}, {}
    for _, info in ipairs(CollectUnits()) do
        local entry, reason = Diagnose(info.unit, info.raidIndex)
        if entry then
            seen[entry.name] = true
            table.insert(recognized, entry)
        else
            table.insert(missing, { unit = info.unit, reason = reason })
        end
    end
    Roster.SortEntries(recognized)

    local fakes
    if self.fakeMembers then
        fakes = {}
        for _, m in ipairs(self.fakeMembers) do
            local copy = Util.DeepCopy(m)
            copy.skipped = seen[m.name] and true or false
            table.insert(fakes, copy)
        end
    end

    local group = "solo"
    if IsInRaid() then
        group = "raid"
    elseif IsInGroup() then
        group = "party"
    end

    return {
        group = group,
        expected = #recognized + #missing,
        recognized = recognized,
        missing = missing,
        fakes = fakes,
    }
end

-- 当前团队快照：{ { name="Name-Realm", class="MAGE", role="DAMAGER" }, ... }，按名字去重
function Roster:Snapshot()
    local list, seen = {}, {}
    for _, info in ipairs(CollectUnits()) do
        local name = Util.UnitFullName(info.unit)
        if name and not seen[name] then
            seen[name] = true
            table.insert(list, {
                name = name,
                class = GetClassFile(info.unit),
                role = self:GetRole(info.unit, info.raidIndex),
            })
        end
    end
    if self.fakeMembers then
        for _, m in ipairs(self.fakeMembers) do
            if not seen[m.name] then
                seen[m.name] = true
                table.insert(list, Util.DeepCopy(m))
            end
        end
    end
    return Roster.SortEntries(list)
end

-- 把快照按职责分组：{ TANK = {...}, HEALER = {...}, ... }
function Roster.GroupByRole(list)
    local groups = {}
    for _, role in ipairs(RWT.ROLE_ORDER) do groups[role] = {} end
    for _, entry in ipairs(list) do
        table.insert(groups[ROLE_RANK[entry.role] and entry.role or "NONE"], entry)
    end
    return groups
end

function Roster:OnInit()
    RWT:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        RWT:Fire("RWT_ROSTER_CHANGED")
    end)
end
