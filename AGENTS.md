# RaidWipeTracker

魔兽世界正式服插件，用 Lua 编写，没有构建步骤。界面和代码注释使用简体中文。改完把 `RaidWipeTracker` 文件夹放进 `_retail_\Interface\AddOns` 后 `/reload` 验证。

## 目录与加载

- 插件根目录是 `RaidWipeTracker/`。文件夹名、`.toc` 文件名和 `## IconTexture` 里的 `RaidWipeTracker` 必须一致。
- `.toc` 里的文件列表就是加载顺序。新文件要加进 `RaidWipeTracker.toc`，并放在它依赖的文件之后。
- 每个 Lua 文件以 `local addonName, RWT = ...` 开头。逻辑模块用 `RWT:NewModule("Name")`，`ADDON_LOADED` 时调用 `OnInit`。
- 界面基元放在 `RWT.UI.Widgets`。主窗口的页是视图，不是模块：实现 `Create` / `Refresh`，再用 `MainWindow:RegisterView` 注册。
- 数据变化后调用 `RWT:NotifyDataChanged()`。界面监听 `RWT_DATA_CHANGED`，不要在数据层直接刷新控件。

## 数据

- 存档是 SavedVariables `RaidWipeTrackerDB`，运行时为 `RWT.db`。
- 改表结构时把 `RWT.DB_VERSION` 加 1，并在 `Database.migrations` 里添加从上一版升级的函数。迁移必须能套在真实旧存档上，不能假设字段齐全。
- 出厂预设标签只在存档仍是上一版默认列表时替换。用户改过的 `settings.tags` 和 `settings.bossTags` 不要覆盖。
- 统计从 Pull 实时计算，不另存计数缓存。击杀把不计入责任统计。
- 一场开荒是 Session，一把是 Pull。状态用 `RWT.STATUS`，结果用 `RWT.RESULT`。

## 战斗与聊天

- 弹窗和会改界面布局的操作走 `RWT:RunAfterCombat`。战斗中 `InCombatLockdown()` 为真。
- 聊天发送还要避开首领战锁定：`C_ChatInfo.InChatMessagingLockdown`。报告和记录通报共用 `ChatReport` 的队列。
- 聊天正文不要加颜色码，服务器会丢弃整行。人名用纯文本，管道符要转义。单条留在 `RWT.CHAT_MAX_BYTES` 以内。
- 默认只记录 `instanceType == "raid"`。`settings.trackNonRaid` 才包含小队和场景战役。

## 资源与许可

- 游戏内贴图只用 TGA 或 BLP。Logo 路径是 `RWT.LOGO`，文件是 `RaidWipeTracker/Media/logo.tga`。
- `assets/curseforge-icon.png` 只给 CurseForge 用，不要写成 `SetTexture` 的路径。`assets/screenshots/` 是界面截图，不要打进插件压缩包。
- `## Author` 和 `RaidWipeTracker/LICENSE` 里的作者「伐竹取道」保持原样。不要把许可改成 MIT、GPL 或其他开源协议。
- 斜杠命令用 `RWT:RegisterSlash` 注册，不要另建一套 `SlashCmdList`。
