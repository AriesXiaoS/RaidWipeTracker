local addonName, RWT = ...

-- 数据库结构版本。修改 SavedVariables 结构时 +1，并在 Database.migrations 中添加迁移函数。
RWT.DB_VERSION = 5

RWT.RESULT = {
    WIPE = "WIPE",
    KILL = "KILL",
    UNKNOWN = "UNKNOWN", -- 未收到 ENCOUNTER_END（掉线、战斗中重载后首领已重置等）
}

RWT.RESULT_LABEL = {
    WIPE = "灭团",
    KILL = "击杀",
    UNKNOWN = "未知",
}

RWT.STATUS = {
    ACTIVE = "ACTIVE",     -- 战斗进行中
    PENDING = "PENDING",   -- 已结束，待填写
    RECORDED = "RECORDED", -- 已保存
    SKIPPED = "SKIPPED",   -- 已跳过（无责任人）
}

RWT.STATUS_LABEL = {
    ACTIVE = "战斗中",
    PENDING = "待填写",
    RECORDED = "已记录",
    SKIPPED = "已跳过",
}

RWT.ROLE_ORDER = { "TANK", "HEALER", "DAMAGER", "NONE" }

RWT.ROLE_LABEL = {
    TANK = "坦克",
    HEALER = "治疗",
    DAMAGER = "DPS",
    NONE = "未知职责",
}

-- Session 如何被选中（写在 pull.resolveMode 上，供首次灭团窗口给出并入/拆分建议）
RWT.RESOLVE = {
    CURRENT = "CURRENT",
    RESUMED = "RESUMED",
    NEW = "NEW",
}

-- 默认预设 tag；用户可以在设置中增删、排序（settings.tags）
RWT.DEFAULT_TAGS = { "蠢死", "吃地板", "漏断", "站位" }

RWT.MAX_TAG_LETTERS = 40      -- 输入框字符上限
RWT.MAX_TAG_BYTES = 150       -- 保存时的字节上限（迁移来的长原因也能容纳）
RWT.MAX_TAGS_PER_PLAYER = 10
RWT.MAX_PRESET_TAGS = 40
RWT.TAG_COLOR_PRESET = "ffffd100"
RWT.TAG_COLOR_TEMP = "ff66ccff"
RWT.NO_TAG_LABEL = "无 tag"

-- reportChannel / recordChannel: "RAID" = 团队（不在团队时回退到副本/小队），"GUILD"，"SAY" = 普通白字
RWT.DEFAULT_SETTINGS = {
    tags = RWT.DEFAULT_TAGS,
    bossTags = {}, -- encounterID（字符串）-> 该首领专属预设 tag
    minimap = { hide = false, angle = 225 },
    floatPanel = { enabled = false, locked = false },
    reportTopN = 5, -- 3 / 5
    reportChannel = "RAID",
    reportInterval = 0.6, -- 统计报告逐条发送间隔（秒）
    reportShowRealm = false, -- 汇报人名是否带服务器后缀
    recordChat = false, -- 保存记录后按人发到聊天框
    recordChannel = "RAID",
    recordInterval = 0.6,
    autoPopup = true,
    autoOpenStatsOnKill = true,
    resumeWindowHours = 12,
    promptOnFirstWipe = true,
    trackNonRaid = false,
}

RWT.CHAT_MAX_BYTES = 240 -- 聊天消息上限 255 字节，留出余量
RWT.CHAT_INTERVAL_MIN = 0.2
RWT.CHAT_INTERVAL_MAX = 5
RWT.CHAT_INTERVAL_DEFAULT = 0.6
RWT.MAX_REASON_LETTERS = 120

RWT.DEBUG_ENCOUNTER_ID = 999999
