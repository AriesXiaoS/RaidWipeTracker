local addonName, RWT = ...

local Encounter = RWT:NewModule("Encounter")
local Util = RWT.Util
local STATUS, RESULT = RWT.STATUS, RWT.RESULT

-- 调试模式下忽略副本类型检查
Encounter.debugBypass = false

-- 本次加载后亲眼看到开始事件的 Pull。同首领再次开始时，据此区分「重载后的重复事件」和「漏了结束事件的新一把」
local livePull

------------------------------------------------------------
-- 辅助
------------------------------------------------------------

-- 是否在需要记录的副本中（默认只记录团队副本）
function Encounter:IsTrackedInstance()
    if self.debugBypass then return true end
    local _, instanceType = GetInstanceInfo()
    if instanceType == "raid" then return true end
    return RWT.db.settings.trackNonRaid and (instanceType == "party" or instanceType == "scenario")
end

local function GetDifficultyName(difficultyID)
    local name = GetDifficultyInfo and GetDifficultyInfo(difficultyID)
    return Util.SafeString(name, tostring(difficultyID or "?"))
end

-- 从事件参数与当前副本信息构造 Session/Pull 需要的字段
local function BuildEncounterInfo(encounterID, encounterName, difficultyID, groupSize)
    local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    return {
        encounterID = encounterID,
        bossName = Util.SafeString(encounterName, "Encounter " .. tostring(encounterID)),
        difficultyID = difficultyID,
        difficultyName = GetDifficultyName(difficultyID),
        instanceName = Util.SafeString(instanceName, "?"),
        instanceID = instanceID,
        groupSize = groupSize,
    }
end

-- 当前进行中的 Pull
function Encounter:GetActivePull()
    local ref = RWT.db.state.activePull
    if not ref then return nil end
    local session = RWT.Session:Get(ref.sessionID)
    local pull = RWT.Session:GetPull(session, ref.pullNumber)
    if not pull or pull.status ~= STATUS.ACTIVE then
        RWT.db.state.activePull = nil
        return nil
    end
    return session, pull
end

-- 把丢失结束事件的 Pull 标为 UNKNOWN（进入待填写）
local function CloseAsUnknown(session, pull)
    RWT.Session:FinishPull(session, pull, RESULT.UNKNOWN)
    RWT.db.state.activePull = nil
    RWT:Print("Pull #%d 未收到结束事件，已标记为「未知」并进入待填写。", pull.pullNumber)
end

------------------------------------------------------------
-- 事件处理
------------------------------------------------------------

function Encounter:OnEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    if not self:IsTrackedInstance() then return end

    local activeSession, activePull = self:GetActivePull()
    if activePull then
        -- 进行中的 Pull 是重载前留下的：战斗中重载会再收到一次同首领的开始事件
        if activePull.encounterID == encounterID and livePull ~= activePull then
            livePull = activePull
            return
        end
        CloseAsUnknown(activeSession, activePull)
    end

    -- 上一把的窗口还没填完：草稿写回 Pull，保持待填写
    RWT:Fire("RWT_PULL_STARTING")

    local info = BuildEncounterInfo(encounterID, encounterName, difficultyID, groupSize)
    local session, mode = RWT.Session:ResolveForEncounter(info)
    local pull = RWT.Session:NewPull(session, info, RWT.Roster:Snapshot())
    pull.resolveMode = mode
    livePull = pull
    RWT.db.state.activePull = { sessionID = session.sessionID, pullNumber = pull.pullNumber }

    RWT:Print("%s（%s）Pull #%d 开始。", info.bossName, info.difficultyName, pull.pullNumber)
    RWT:NotifyDataChanged()
end

function Encounter:OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    local session, pull = self:GetActivePull()
    if not pull or pull.encounterID ~= encounterID then return end

    local killed = success == 1 or success == true
    RWT.Session:FinishPull(session, pull, killed and RESULT.KILL or RESULT.WIPE)
    RWT.db.state.activePull = nil
    RWT:NotifyDataChanged()

    local sessionID, pullNumber = session.sessionID, pull.pullNumber
    if killed then
        RWT:Print("%s 击杀！共 %d Pull。", pull.bossName, #session.pulls)
        if RWT.db.settings.autoOpenStatsOnKill then
            RWT:RunAfterCombat(function()
                if RWT.UI.MainWindow then RWT.UI.MainWindow:ShowStats(sessionID, "SESSION") end
            end)
        end
    else
        RWT:Print("Pull #%d 灭团（%s）。", pullNumber, Util.FormatDuration(pull.duration))
        if RWT.db.settings.autoPopup then
            RWT:RunAfterCombat(function()
                -- 脱战前已经开始下一把时不弹旧窗口，该 Pull 保持待填写
                if RWT.db.state.activePull then return end
                if RWT.UI.WipeWindow then RWT.UI.WipeWindow:Open(sessionID, pullNumber) end
            end)
        end
    end
end

-- 兜底对账：有进行中的 Pull 但首领战已不在进行 -> 标为 UNKNOWN
-- allowUnknownApi：IsEncounterInProgress API 不可用时是否仍然关闭（只在登录/切图时允许）
function Encounter:Reconcile(allowUnknownApi)
    local session, pull = self:GetActivePull()
    if not pull then return end
    local inProgress = Util.IsEncounterInProgress()
    if inProgress == true then return end
    if inProgress == nil and not allowUnknownApi then return end
    CloseAsUnknown(session, pull)
    RWT:NotifyDataChanged()
end

-- 进入副本时提示本副本未结束的 Session（每次进入只提示一次）
local lastHintInstanceID
function Encounter:HintUnclosedSessions()
    if not self:IsTrackedInstance() or InCombatLockdown() then return end
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceID == lastHintInstanceID then return end
    lastHintInstanceID = instanceID

    local list = {}
    for _, session in pairs(RWT.db.sessions) do
        if not session.closed and session.instanceID == instanceID then table.insert(list, session) end
    end
    if #list == 0 then return end
    table.sort(list, function(a, b) return (a.lastActivity or 0) > (b.lastActivity or 0) end)
    RWT:Print("本副本有 %d 个未结束的 Session，最近：%s。", #list, RWT.Session.Describe(list[1]))
    RWT:Print("同 Boss 同难度且 %d 小时内会自动续接；首把灭团时可选择并入或拆分。/rwt new 强制新建，/rwt resume 续接最近。",
        RWT.db.settings.resumeWindowHours or 12)
end

function Encounter:OnInit()
    RWT:RegisterEvent("ENCOUNTER_START", function(_, ...) self:OnEncounterStart(...) end)
    RWT:RegisterEvent("ENCOUNTER_END", function(_, ...) self:OnEncounterEnd(...) end)

    RWT:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(3, function()
            self:Reconcile(true)
            self:HintUnclosedSessions()
            RWT:Fire("RWT_WORLD_READY")
        end)
    end)

    RWT:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        C_Timer.After(3, function() self:Reconcile(false) end)
    end)
end

------------------------------------------------------------
-- 调试：不进本模拟完整流程
------------------------------------------------------------

local DEBUG_BOSS = "测试首领"
local DEBUG_DIFFICULTY = 16

function Encounter:DebugStart()
    self.debugBypass = true
    self:OnEncounterStart(RWT.DEBUG_ENCOUNTER_ID, DEBUG_BOSS, DEBUG_DIFFICULTY, GetNumGroupMembers())
end

function Encounter:DebugEnd(success)
    self:OnEncounterEnd(RWT.DEBUG_ENCOUNTER_ID, DEBUG_BOSS, DEBUG_DIFFICULTY, GetNumGroupMembers(), success and 1 or 0)
end

function Encounter:DebugToggleRoster()
    local enable = RWT.Roster.fakeMembers == nil
    RWT.Roster:SetFakeMembers(enable)
    RWT:Print("假团员：%s（只影响之后开始的 Pull 快照）", enable and "开启" or "关闭")
    RWT:NotifyDataChanged()
end

function Encounter:DebugOff()
    self.debugBypass = false
    RWT.Roster:SetFakeMembers(false)
    RWT:Print("调试模式已关闭。")
    RWT:NotifyDataChanged()
end

local DEBUG_HELP = "debug start|wipe|kill|roster|off  模拟首领战（测试用）"

RWT:RegisterSlash("debug", DEBUG_HELP, function(arg)
    arg = (arg or ""):lower()
    if arg == "start" then
        Encounter:DebugStart()
    elseif arg == "wipe" then
        Encounter:DebugEnd(false)
    elseif arg == "kill" then
        Encounter:DebugEnd(true)
    elseif arg == "roster" then
        Encounter:DebugToggleRoster()
    elseif arg == "off" then
        Encounter:DebugOff()
    else
        RWT:Print("/rwt " .. DEBUG_HELP)
    end
end)
